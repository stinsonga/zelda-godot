"""Minimal headless libretro frontend for the pinned Nestopia reference core.

No emulator or ROM is bundled. Definitions follow the public libretro ABI:
https://github.com/libretro/libretro-common/blob/master/include/libretro.h
Callbacks are kept alive for the entire core lifetime. No host audio/video or
persistent SRAM is needed; a fresh process starts with an empty battery save.
"""
import ctypes as C
import hashlib
from pathlib import Path

class Variable(C.Structure):
    _fields_ = [('key', C.c_char_p), ('value', C.c_char_p)]
class Game(C.Structure):
    _fields_ = [('path', C.c_char_p), ('data', C.c_void_p), ('size', C.c_size_t), ('meta', C.c_char_p)]
class SystemInfo(C.Structure):
    _fields_ = [('name', C.c_char_p), ('version', C.c_char_p), ('extensions', C.c_char_p), ('fullpath', C.c_bool), ('block_extract', C.c_bool)]
ENV = C.CFUNCTYPE(C.c_bool, C.c_uint, C.c_void_p)
VIDEO = C.CFUNCTYPE(None, C.c_void_p, C.c_uint, C.c_uint, C.c_size_t)
AUDIO = C.CFUNCTYPE(None, C.c_int16, C.c_int16)
BATCH = C.CFUNCTYPE(C.c_size_t, C.c_void_p, C.c_size_t)
POLL = C.CFUNCTYPE(None)
INPUT = C.CFUNCTYPE(C.c_int16, C.c_uint, C.c_uint, C.c_uint, C.c_uint)
PAD = {'b':0, 'select':2, 'start':3, 'up':4, 'down':5, 'left':6, 'right':7, 'a':8}

class ReferenceCore:
    def __init__(self, library, rom):
        self.library = Path(library).resolve()
        self.lib = C.CDLL(str(self.library))
        self.buttons = set()
        self.variables = {}
        self.directory = str(self.library.parent).encode()
        self.frame = 0
        self.closed = False
        self.loaded = False
        self.callback_error = None
        self.callbacks = [ENV(self.environment), VIDEO(lambda *_: None), AUDIO(lambda *_: None),
                          BATCH(lambda _data, count: count), POLL(lambda: None),
                          INPUT(lambda port, device, index, key: int(port == 0 and device == 1 and key in self.buttons))]
        for name, cb in zip(['environment','video_refresh','audio_sample','audio_sample_batch','input_poll','input_state'], self.callbacks):
            fn = getattr(self.lib, 'retro_set_' + name)
            fn.argtypes = [type(cb)]
            fn.restype = None
            fn(cb)
        self.lib.retro_init.restype = None
        self.lib.retro_init()
        self.lib.retro_get_system_info.argtypes = [C.POINTER(SystemInfo)]
        info = SystemInfo()
        self.lib.retro_get_system_info(C.byref(info))
        self.info = {'name': info.name.decode(), 'version': info.version.decode(),
                     'sha256': hashlib.sha256(self.library.read_bytes()).hexdigest()}
        if self.info['name'] != 'Nestopia':
            self.close()
            raise ValueError('First adapter supports the pinned Nestopia core only')
        data = Path(rom).read_bytes()
        self.rom_buffer = C.create_string_buffer(data)
        game = Game(None, C.cast(self.rom_buffer, C.c_void_p), len(data), None)
        self.lib.retro_load_game.argtypes = [C.POINTER(Game)]
        self.lib.retro_load_game.restype = C.c_bool
        if not self.lib.retro_load_game(C.byref(game)):
            self.close()
            raise ValueError('Reference core rejected ROM')
        self.loaded = True
        self.lib.retro_get_region.restype = C.c_uint
        if self.lib.retro_get_region() != 0:
            self.close()
            raise ValueError('Movement baseline requires NTSC')
        self.lib.retro_get_memory_data.argtypes = [C.c_uint]
        self.lib.retro_get_memory_data.restype = C.c_void_p
        self.lib.retro_get_memory_size.argtypes = [C.c_uint]
        self.lib.retro_get_memory_size.restype = C.c_size_t
        if self.lib.retro_get_memory_size(2) != 2048:
            self.close()
            raise ValueError('Reference core must expose 2 KiB CPU RAM')
        self.ram = (C.c_ubyte * 2048).from_address(self.lib.retro_get_memory_data(2))
        self.lib.retro_serialize_size.restype = C.c_size_t
        for name in ['retro_serialize', 'retro_unserialize']:
            fn = getattr(self.lib, name)
            fn.argtypes = [C.c_void_p, C.c_size_t]
            fn.restype = C.c_bool
        self.lib.retro_run.restype = None

    def environment(self, command, data):
        try:
            if command in (9,31):
                C.cast(data, C.POINTER(C.c_char_p))[0] = self.directory
                return True
            if command == 3:
                C.cast(data, C.POINTER(C.c_bool))[0] = True
                return True
            if command == 10: return True  # Software video is discarded.
            if command == 15:
                var = C.cast(data, C.POINTER(Variable)).contents
                if var.key in self.variables:
                    var.value = self.variables[var.key]
                    return True
                return False
            if command == 16:
                variables = C.cast(data, C.POINTER(Variable))
                index = 0
                while variables[index].key:
                    self.variables[variables[index].key] = variables[index].value.split(b'; ',1)[-1].split(b'|',1)[0]
                    index += 1
                return True
            if command == 17:
                C.cast(data, C.POINTER(C.c_bool))[0] = False
                return True
            return False
        except Exception as error:
            self.callback_error = str(error)
            return False

    def run(self, buttons=(), frames=1):
        self.buttons = {PAD[b] for b in buttons}
        for _ in range(frames):
            self.lib.retro_run()
            self.frame += 1
            if self.callback_error: raise RuntimeError(self.callback_error)

    def save(self):
        size = self.lib.retro_serialize_size()
        if not size or size > 16 * 1024 * 1024: raise ValueError('Invalid core state size')
        data = C.create_string_buffer(size)
        if not self.lib.retro_serialize(data, size): raise ValueError('Core state capture failed')
        return data.raw

    def restore(self, state):
        data = C.create_string_buffer(state)
        if not self.lib.retro_unserialize(data, len(state)): raise ValueError('Core state restore failed')
        self.buttons = set()

    def close(self):
        if self.closed: return
        self.closed = True
        if self.loaded: self.lib.retro_unload_game()
        self.lib.retro_deinit()

    def __enter__(self): return self
    def __exit__(self, *_): self.close()
