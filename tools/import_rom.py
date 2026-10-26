#!/usr/bin/env python3
"""Import US PRG0 Zelda into editable Godot resources. Python standard library only.

Offsets refer to the 128 KiB PRG payload, excluding the 16-byte iNES header.
See docs/IMPORTING.md for the disassembly routines behind this decoder.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib

from import_dungeons import MONSTERS, export_levels, level_rooms
import import_dungeons
import import_submenu
from import_caves import (TELEPORT_YS, WHIRLWIND_ROOMS, CAVE_LAYOUT, FIRST_CAVE, SHORTCUT_CAVE, SHORTCUT_LAYOUT, cave_resource, cave_room,
                          cave_types, export_item_sprites, export_people, overworld_entrances, portal_lines,
                          secret_resource, SQUARE_FLOOR, SQUARE_STAIRS)

PRG_SHA1 = 'a12d74c73a0481599a5d832361d168f4737bbcf6'
PRG_SIZE = 131072
# Conventional RGB approximation: the NES itself does not store RGB colors.
RGB = '''666666 002a88 1412a7 3b00a4 5c007e 6e0040 6c0600 561d00
333500 0b4800 005200 004f08 00404d 000000 000000 000000
adadad 155fd9 4240ff 7527fe a01acc b71e7b b53120 994e00
6b6d00 388700 0c9300 008f32 007c8d 000000 000000 000000
fffeff 64b0ff 9290ff c676ff f36aff fe6ecc fe8170 ea9e22
bcbe00 88d800 5ce430 45e082 48cdde 4f4f4f 000000 000000
fffeff c0dfff d3d2ff e8c8ff fbc2ff fec4ea feccc5 f7d8a5
e4e594 cfef96 bdf4ab b3f3cc b5ebf2 b8b8b8 000000 000000'''
COLORS = [bytes.fromhex(color) for color in RGB.split()]
WALKABLE = {0x8D, 0x91, 0x9C, 0xAC, 0xAD, 0xCC, 0xD2, 0xD5, 0xDF}
TILE_OBJECTS = dict(zip(range(0xE5, 0xEB), [0xC8, 0xD8, 0xC4, 0xBC, 0xC0, 0xC0]))


def read_rom(path):
    data = Path(path).read_bytes()
    if len(data) < 16 or data[:4] != b'NES\x1a':
        raise ValueError('Not an iNES ROM: missing NES header')
    if data[4:8] != bytes([8, 0, 0x12, 0]):
        raise ValueError('Expected US PRG0 iNES header: 128 KiB PRG, CHR RAM, mapper 1, no trainer')
    if len(data) != PRG_SIZE + 16:
        raise ValueError('ROM has unexpected size or trailing data')
    prg = data[16:]
    if hashlib.sha1(prg).hexdigest() != PRG_SHA1:
        raise ValueError('ROM payload does not match supported US PRG0 revision')
    return prg


def png(path, width, height, pixels):
    def chunk(kind, body):
        return struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body))
    rows = b''.join(b'\0' + pixels[y * width * 4:(y + 1) * width * 4] for y in range(height))
    Path(path).write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def chr_pixels(patterns, tile):
    pattern = patterns[tile * 16:(tile + 1) * 16]
    if len(pattern) != 16:
        raise ValueError('Tile outside pattern memory')
    return [[((pattern[y] >> (7 - x)) & 1) | (((pattern[y + 8] >> (7 - x)) & 1) << 1) for x in range(8)] for y in range(8)]


def blit_tile(canvas, width, x0, y0, patterns, tile, palette, transparent=False):
    for y, row in enumerate(chr_pixels(patterns, tile)):
        for x, value in enumerate(row):
            rgba = COLORS[palette[value] & 63] + bytes([0 if transparent and value == 0 else 255])
            offset = ((y0 + y) * width + x0 + x) * 4
            canvas[offset:offset + 4] = rgba


def square_tiles(prg, index):
    if not 0 <= index < 56:
        raise ValueError(f'Invalid square index {index}')
    if index < 16:
        return list(prg[0x169B4 + index * 4:0x169B4 + index * 4 + 4])
    first = prg[0x1697C + index]
    first = TILE_OBJECTS.get(first, first)
    return list(range(first, first + 4))


def decode_room(prg, room_id):
    layout_id = prg[99328 + 3 * 128 + room_id] & 0x7F
    descriptors = prg[87064 + layout_id * 16:87064 + layout_id * 16 + 16]
    return decode_columns(prg, descriptors)


def decode_columns(prg, descriptors):
    grid = [[0] * 16 for _ in range(11)]
    for x, descriptor in enumerate(descriptors):
        table = descriptor >> 4
        address = struct.unpack_from('<H', prg, 0x19D0F + table * 2)[0]
        offset = 5 * 0x4000 + address - 0x8000
        column = descriptor & 15
        # Bit 7 identifies the first descriptor of each compressed column.
        for _ in range(1024):
            if prg[offset] & 0x80:
                if column == 0:
                    break
                column -= 1
            offset += 1
        else:
            raise ValueError('Column start not found')
        rows = []
        while len(rows) < 11:
            value = prg[offset]
            rows.extend([value & 0x3F] * (2 if value & 0x40 else 1))
            offset += 1
        if len(rows) != 11:
            raise ValueError('Column expands past room height')
        for y, value in enumerate(rows):
            square_tiles(prg, value)  # Validate before emitting any resources.
            grid[y][x] = value
    return grid


def array(values):
    return ', '.join(map(str, values))


def export_cave(prg, patterns, palettes, output):
    """Original starting cave and the sprites used by its native game logic."""
    cave_palettes = [row[:] for row in palettes]
    cave_palettes[2] = [0x0F, 0x30, 0x00, 0x12]
    cave_palettes[3] = [0x0F, 0x07, 0x0F, 0x17]
    atlas = bytearray(256 * 256 * 4)
    for palette in range(4):
        for index in range(56):
            slot = palette * 64 + index
            for part, tile in enumerate(square_tiles(prg, index)):
                blit_tile(atlas, 256, slot % 16 * 16 + part // 2 * 8,
                          slot // 16 * 16 + part % 2 * 8,
                          patterns[0x1000:], tile, cave_palettes[palette])
    png(output / 'cave_tiles.png', 256, 256, atlas)

    def sprite(name, tile, palette, mirrored=False, narrow=False, flip_x=False, flip_y=False, right_override=None):
        canvas = bytearray(16 * 16 * 4)
        for part in range(2 if narrow else 4):
            column, row = part // 2, part % 2
            actual = tile + part if not mirrored else tile + row
            if column == 1 and right_override is not None:
                actual = right_override + row
            block = bytearray(8 * 8 * 4)
            blit_tile(block, 8, 0, 0, patterns, actual, palettes[palette], transparent=True)
            for y in range(8):
                for x in range(8):
                    source_x = 7 - x if mirrored and column == 1 else x
                    dest_x = column * 8 + x + (4 if narrow else 0)
                    dest_y = row * 8 + y
                    if flip_x: dest_x = 15 - dest_x
                    if flip_y: dest_y = 15 - dest_y
                    dst = (dest_y * 16 + dest_x) * 4
                    src = (y * 8 + source_x) * 4
                    canvas[dst:dst + 4] = block[src:src + 4]
        png(output / (name + '.png'), 16, 16, canvas)

    animations = prg[0x6E04:0x6E83]
    old_man = prg[0x6E83 + animations[0x6B]]
    fire = prg[0x6E83 + animations[0x41]]
    sprite('old_man', old_man, 6, mirrored=True)
    sprite('fire_0', fire, 6)
    sprite('fire_1', fire, 6, flip_x=True)
    sprite('wooden_sword', 0x20, 4, narrow=True)
    sprite('sword_up', 0x20, 4, narrow=True)
    sprite('sword_down', 0x20, 4, narrow=True, flip_y=True)
    sprite('sword_right', 0x82, 4)
    sprite('sword_left', 0x82, 4, flip_x=True)
    for name, frame, flip in [('attack_right', 4, False), ('attack_left', 4, True),
                               ('attack_down', 6, False), ('attack_up', 7, False)]:
        sprite(name, prg[0x6E83 + frame], 4, flip_x=flip)
        for palette in range(1, 4):
            sprite(f'{name}_clock_{palette}', prg[0x6E83 + frame], 4 + palette, flip_x=flip)
    # Item slot $21: lifting pose, with the narrow-item one-arm substitution.
    lift_tile = prg[0x714C + prg[0x7127 + 0x21]]
    sprite('lift', lift_tile, 4, mirrored=True, right_override=0x08)

    return {'cave': cave_layout(prg, CAVE_LAYOUT), 'shortcut': cave_layout(prg, SHORTCUT_LAYOUT)}


def cave_layout(prg, descriptors):
    """Cave interiors share overworld squares, drawn with the cave palette atlas."""
    layout = decode_columns(prg, prg[descriptors:descriptors + 16])
    indices, collision, coarse = [], [0] * 704, []
    outer = prg[99328 + 0x44] & 3
    inner = prg[99328 + 128 + 0x44] & 3
    for y, row in enumerate(layout):
        line = ''
        for x, index in enumerate(row):
            palette = inner if 2 <= x < 14 and 2 <= y < 9 else outer
            indices.append(palette * 64 + index)
            blocked = []
            for part, tile in enumerate(square_tiles(prg, index)):
                value = int(tile >= 0x89 and tile not in WALKABLE)
                collision[(y * 2 + part % 2) * 32 + x * 2 + part // 2] = value
                blocked.append(value)
            line += '#' if all(blocked) else '.'
        coarse.append(line)
    return indices, collision, coarse


def export_combat_sprites(prg, patterns, palettes, output):
    names = []
    animations = prg[0x6E04:0x6E83]
    for name, enemy_type in [('red_octorok', 7), ('blue_octorok', 9)]:
        base = animations[enemy_type + 1]
        for direction in ['right', 'left', 'down', 'up']:
            for pose in range(2):
                frame = base + pose * 3 + {'left': 0, 'right': 0, 'up': 1, 'down': 2}[direction]
                tile = prg[0x6E83 + frame]
                palette = 4 + (prg[0x6F4F + frame] & 3)
                canvas = bytearray(16 * 16 * 4)
                vertical = direction in ('up', 'down')
                for part in range(4):
                    column, row = part // 2, part % 2
                    actual = tile + (row if vertical else part)
                    block = bytearray(8 * 8 * 4)
                    blit_tile(block, 8, 0, 0, patterns, actual, palettes[palette], transparent=True)
                    for y in range(8):
                        for x in range(8):
                            source_x = 7 - x if vertical and column == 1 else x
                            dest_x = column * 8 + x
                            if direction == 'right': dest_x = 15 - dest_x
                            dst = ((row * 8 + y) * 16 + dest_x) * 4
                            src = (y * 8 + source_x) * 4
                            canvas[dst:dst + 4] = block[src:src + 4]
                key = f'{name}_{direction}_{pose}'
                png(output / (key + '.png'), 16, 16, canvas)
                names.append(key)
    # $53 is half-width (ObjectTypeToAttributes bit 1), drawn at X + 4.
    frame = animations[0x54]
    tile = prg[0x6E83 + frame]
    canvas = bytearray(16 * 16 * 4)
    for row in range(2):
        blit_tile(canvas, 16, 4, row * 8, patterns, tile + row, palettes[4], transparent=True)
    png(output / 'rock.png', 16, 16, canvas)
    names.append('rock')
    # Rupee $18 maps to slot $16, tile $32. Heart $22 maps to slot $19,
    # tile $F3: odd 8x16 sprite indices select the background pattern bank.
    for name, tile in [('heart', 0xF3), ('rupee', 0x32)]:
        for pose in range(2):
            canvas = bytearray(16 * 16 * 4)
            bank = patterns[0x1000:] if tile & 1 else patterns
            for row in range(2):
                blit_tile(canvas, 16, 4, row * 8, bank, (tile & 0xFE) + row,
                          palettes[5 + pose], transparent=True)
            key = f'{name}_{pose}'
            png(output / (key + '.png'), 16, 16, canvas)
            names.append(key)
    return names


def export_beam_sprites(prg, patterns, palettes, output):
    names = []
    def render(key, tile, palette, flip_x=False, flip_y=False, narrow=False, mirrored=False):
        canvas = bytearray(16 * 16 * 4)
        bank = patterns[0x1000:] if tile & 1 else patterns
        top = tile & 0xFE
        for column in range(1 if narrow else 2):
            for row in range(2):
                block = bytearray(8 * 8 * 4)
                blit_tile(block, 8, 0, 0, bank, top + (0 if mirrored else column * 2) + row, palettes[4 + palette], transparent=True)
                for y in range(8):
                    for x in range(8):
                        dx, dy = column * 8 + x + (4 if narrow else 0), row * 8 + y
                        if flip_x: dx = 15 - dx
                        if flip_y: dy = 15 - dy
                        dst, src = (dy * 16 + dx) * 4, (y * 8 + (7 - x if mirrored and column == 1 else x)) * 4
                        canvas[dst:dst + 4] = block[src:src + 4]
        png(output / (key + '.png'), 16, 16, canvas)
        names.append(key)
    for palette in range(4):
        for direction in ('up', 'down', 'left', 'right'):
            horizontal = direction in ('left', 'right')
            offset = prg[0x7127 + 0x22] + int(horizontal)
            tile = prg[0x714C + offset]
            render(f'beam_{direction}_{palette}', tile, palette,
                   flip_x=direction == 'left', flip_y=direction == 'down', narrow=not horizontal)
            magic_tile = prg[0x714C + prg[0x7127 + 0x23] + int(horizontal)]
            render(f'magic_wave_{direction}_{palette}', magic_tile, palette,
                   flip_x=direction == 'left', flip_y=direction == 'down', mirrored=not horizontal)

        tile = prg[0x714C + prg[0x7127 + 0x23] + 2]
        for corner in range(4):
            render(f'beam_burst_{corner}_{palette}', tile, palette,
                   flip_x=corner in (2, 3), flip_y=corner in (1, 2), narrow=True)
    return names


def export_source_enemies(prg, patterns, palettes, output):
    (output / 'enemies').mkdir(exist_ok=True)
    for name, kind in [('red_octorok', 7), ('fast_red_octorok', 8), ('blue_octorok', 9), ('fast_blue_octorok', 10)]:
        (output / 'enemies' / (name + '.tres')).write_text(f'''[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/enemy_definition.gd" id="1"]
[resource]
script = ExtResource("1")
id = &"{name}"
title = "{name.replace('_', ' ').title()}"
behavior = "nes_octorok"
nes_type = {kind}
health = {2 if kind >= 9 else 1}
speed_subpixels = {256 if kind in (8, 10) else 128}
sprite = &"{'blue_octorok' if kind >= 9 else 'red_octorok'}"
turn_chance = {160 if kind >= 9 else 112}
''')
    names = []
    for name, tile in [('spawn_cloud_0', 0x70), ('spawn_cloud_1', 0x72), ('spawn_cloud_2', 0x74), ('death_spark_0', 0x64), ('death_spark_1', 0x62)]:
        canvas = bytearray(16 * 16 * 4)
        for row in range(2):
            block = bytearray(8 * 8 * 4)
            blit_tile(block, 8, 0, 0, patterns, tile + row, palettes[5], transparent=True)
            for y in range(8):
                for x in range(8):
                    for column in range(2):
                        src = (y * 8 + (7 - x if column else x)) * 4
                        dst = ((row * 8 + y) * 16 + column * 8 + x) * 4
                        canvas[dst:dst + 4] = block[src:src + 4]
        png(output / (name + '.png'), 16, 16, canvas)
        names.append(name)
    return names


# Semantic IDs and native behaviors; numeric game tables are read only from ROM.
ENEMY_TYPES = {
    1: ('blue_lynel','walker'), 2: ('red_lynel','walker'),
    3: ('blue_moblin','walker'), 4: ('red_moblin','walker'),
    7: ('red_octorok','nes_octorok'), 8: ('fast_red_octorok','nes_octorok'),
    9: ('blue_octorok','nes_octorok'), 10: ('fast_blue_octorok','nes_octorok'),
    13: ('blue_tektite','jumper'), 14: ('red_tektite','jumper'),
    15: ('blue_leever','burrower'), 16: ('red_leever','burrower'),
    26: ('peahat','flyer'),
    # Never in an encounter list: Z_04 CheckZora raises it in rooms flagged in attribute A.
    0x11: ('zora','zora'),
    # Woken from statue squares by Z_01 CheckPassiveTileObjects.
    0x1E: ('armos','walker'),
}
# Z_04 InitArmosOrFlyingGhini: rooms whose Armos at ($X, $80) hides stairs, or in
# room $24 the power bracelet.
SECRET_ARMOS = {0x24: 0xE0, 0x0B: 0xB0, 0x1C: 0xB0, 0x22: 0x30, 0x34: 0x40, 0x3D: 0x90, 0x4E: 0xA0}
BRACELET_ROOM = 0x24


def room_enemy_types(prg, room_id):
    attr_c, attr_d = prg[99328 + 256 + room_id], prg[99328 + 384 + room_id]
    template = (attr_c & 63) | ((attr_d >> 7) << 6)
    count = prg[103168 + 36 + (attr_c >> 6)]
    if template == 0: return []
    if template < 0x62: return [template] * (1 if template >= 0x32 else count)
    pointer_offset = 83775 + (template - 0x62) * 2
    address = int.from_bytes(prg[pointer_offset:pointer_offset + 2], 'little')
    offset = 0x14000 + address - 0x8000
    if not 0x14000 <= offset < 0x18000 or offset + count > 0x18000:
        raise ValueError('Invalid enemy list pointer')
    return list(prg[offset:offset + count])


def enemy_resources(prg, room_id, collision, spawn):
    types = room_enemy_types(prg, room_id)
    # Never silently reinterpret unsupported monsters as another family.
    if not types or any(kind not in ENEMY_TYPES for kind in types): return '', '', '', 0
    ext = '[ext_resource type="Script" path="res://scripts/enemy_spawn.gd" id="enemy_spawn"]\n'
    for kind in sorted(set(types)):
        name = ENEMY_TYPES[kind][0]
        ext += f'[ext_resource type="Resource" path="res://imported/enemies/{name}.tres" id="enemy_def_{kind}"]\n'
    sub = ''
    for i,kind in enumerate(types):
        delay = 32 + i * 16 if kind in (7,8,9,10) else i + 1
        sub += f'''[sub_resource type="Resource" id="enemy_{i}"]
script = ExtResource("enemy_spawn")
id = &"slot_{i}"
enemy = ExtResource("enemy_def_{kind}")
position = Vector2i({spawn[0]}, {spawn[1]})
facing = Vector2i(0, 0)
seed_value = {room_id * 31 + i + 1}
spawn_ticks = {delay}
'''
    field = 'enemies = Array[Resource]([' + ', '.join(f'SubResource("enemy_{i}")' for i in range(len(types))) + '])'
    return ext, sub, field, len(types)


def loot_group(prg, kind):
    for group,(start,count) in enumerate(((0x13022,6),(0x13028,9),(0x13031,9))):
        if kind in prg[start:start+count]: return group
    return 3


def export_overworld_enemies(prg, patterns, palettes, output):
    names = []
    def render(key, frame, mirrored=False, flip_x=False, narrow=False, palette_override=None, flip_y=False):
        tile = prg[0x6E83 + frame]
        attr = prg[0x6F4F + frame]
        palette = palettes[4 + (attr & 3) if palette_override is None else palette_override]
        tile_base = tile & 0xFE
        bank = patterns[0x1000:] if tile & 1 else patterns
        canvas = bytearray(16 * 16 * 4)
        for column in range(1 if narrow else 2):
            for row in range(2):
                block = bytearray(8 * 8 * 4)
                blit_tile(block,8,0,0,bank,tile_base + row + (0 if mirrored else column*2),palette,True)
                for y in range(8):
                    for x in range(8):
                        sx = 7-x if mirrored and column == 1 else x
                        dx,dy = column*8+x+(4 if narrow else 0),row*8+y
                        if flip_x: dx = 15-dx
                        if bool(attr & 128) != flip_y: dy = 15-dy
                        canvas[(dy*16+dx)*4:(dy*16+dx)*4+4] = block[(y*8+sx)*4:(y*8+sx)*4+4]
        png(output/(key+'.png'),16,16,canvas)
        names.append(key)
    for kind,(name,behavior) in ENEMY_TYPES.items():
        pair = prg[0x1FB4E + kind//2]
        hp = pair & 15 if kind & 1 else pair >> 4
        raw_damage = prg[0x72BA + kind]
        damage = (raw_damage & 15)*2 + (1 if raw_damage & 240 else 0)
        fields = {'id':f'&"{name}"', 'title':json.dumps(name.replace('_',' ').title()), 'behavior':json.dumps(behavior),
                  'nes_type':kind,'health':hp, 'contact_damage':damage,'sprite':f'&"{name}"'}
        if behavior == 'nes_octorok':
            fields.update(sprite=f'&"{"blue_octorok" if kind >= 9 else "red_octorok"}"',
                          speed_subpixels=256 if kind in (8,10) else 128,turn_chance=160 if kind>=9 else 112)
        elif kind == 0x1E:
            # UpdateArmos runs UpdateGoriya; it fades in $3F frames, then moves at
            # q-speed $20 or $60. It dies as the dead dummy: no drop, no kill count.
            fields.update(speed_subpixels=128, turn_chance=0x80, targeting='"dominant_axis"', shooting_enabled='false',
                          spawn_cloud='false', drops_rewards='false', advances_kill_cycle='false', counts_for_clear='false',
                          counts_for_persistence='false', sprite_style='"front_back"', wake_ticks=0x3F,
                          wake_speeds='PackedInt32Array(128, 384)')
        elif behavior == 'walker':
            fields.update(turn_chance=160, projectile_kind=json.dumps('sword' if kind in (1,2) else 'arrow'),
                          projectile_speed_subpixels=768 if kind in (1,2) else 512,
                          projectile_damage=2 if kind in (1,2) else 1,
                          projectile_blockable='false' if kind in (1,2) else 'true',
                          targeting=json.dumps('dominant_axis' if kind in (1,2) else 'aligned'))
        else:
            fields['shooting_enabled'] = 'false'
            # Z_04 InitPeahat: no spawn cloud.
            if behavior == 'flyer': fields['spawn_cloud'] = 'false'
            if behavior == 'jumper':
                red = kind == 14
                fields.update(speed_subpixels=256,jump_velocity_subpixels=-1024 if red else -768,
                              jump_horizontal_acceleration=prg[0x108D5 + (11 if red else 0)+1],
                              jump_up_acceleration=prg[0x108D5 + (11 if red else 0)+9],
                              jump_down_acceleration=prg[0x108D5 + (11 if red else 0)+5],
                              jump_wait_style=json.dumps('red' if red else 'blue'))
            elif behavior == 'zora':
                # UpdateZora runs UpdateBurrower on the Blue Leever tables; its $55
                # fireball can be blocked by the magical shield.
                raw = prg[0x72BA + 0x55]
                fields.update(spawn_cloud='false', counts_for_clear='false', counts_for_persistence='false',
                              projectile_kind='"fireball"', projectile_damage=(raw & 15) * 2 + (1 if raw & 240 else 0))
                for field, offset in [('burrow_times', 6), ('burrow_animation_ticks', 12)]:
                    fields[field] = 'PackedInt32Array(' + array(list(prg[0x10a53 + offset:0x10a53 + offset + 6])) + ')'
            elif behavior == 'burrower':
                red = kind == 16
                # Locate state tables through fixed verified-ROM offsets below.
                base = 0x10af7 if red else 0x10a53
                fields.update(burrow_style=json.dumps('ambush' if red else 'roam'))
                # Exact addresses are supplied by the verified source table search.
                for field,offset,scale in [('burrow_speeds',0,4),('burrow_times',6,1),('burrow_animation_ticks',12,1)]:
                    values = [v*scale for v in prg[base+offset:base+offset+6]]
                    fields[field] = 'PackedInt32Array('+array(values)+')'
                fields['turn_chance'] = 160
        text = '[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]\n[ext_resource type="Script" path="res://scripts/enemy_definition.gd" id="1"]\n[resource]\nscript = ExtResource("1")\n'
        (output/'enemies'/(name+'.tres')).write_text(text+'\n'.join(f'{key} = {value}' for key,value in fields.items())+'\n')
        if behavior == 'nes_octorok': continue
        base = prg[0x6E04 + kind + 1]
        if kind == 0x1E:
            # DrawArmosAndCheckCollisions: front and back, two animation sets.
            for frame in range(4): render(f'{name}_{frame}', base + frame)
        elif behavior == 'walker':
            for direction in ('up','down','left','right'):
                for pose in range(2):
                    frame = base + (3 if direction=='up' else 2 if direction=='down' else pose)
                    render(f'{name}_{direction}_{pose}',frame,flip_x=(pose==1 if direction in ('up','down') else direction=='left'))
        else:
            for frame in range(10 if behavior in ('burrower', 'zora') else 2): render(f'{name}_{frame}',base+frame,mirrored=True)
    # Arrow item uses the weapon-image heap rather than the object animation heap.
    for direction in ('up','down','left','right'):
        tile = prg[0x714C + prg[0x7127+2] + int(direction in ('left','right'))]
        canvas = bytearray(16*16*4)
        narrow = direction in ('up','down')
        bank = patterns[0x1000:] if tile & 1 else patterns
        for col in range(1 if narrow else 2):
            for row in range(2):
                block = bytearray(8*8*4)
                blit_tile(block,8,0,0,bank,(tile&254)+col*2+row,palettes[6],True)
                for y in range(8):
                    for x in range(8):
                        dx,dy = col*8+x+(4 if narrow else 0),row*8+y
                        if direction=='left': dx=15-dx
                        if direction=='down': dy=15-dy
                        canvas[(dy*16+dx)*4:(dy*16+dx)*4+4]=block[(y*8+x)*4:(y*8+x)*4+4]
        key='monster_arrow_'+direction
        png(output/(key+'.png'),16,16,canvas);names.append(key)
    return names


def import_rom(prg, output):
    output = Path(output)
    # Decode everything before touching output, to fail early on unsupported data.
    layouts = [decode_room(prg, i) for i in range(128)]
    output.mkdir(parents=True, exist_ok=True)
    (output / 'rooms').mkdir(exist_ok=True)
    patterns = bytearray(8192)
    for source, length, target in [(32895, 1792, 0), (34687, 1792, 0x1000),
                                    (36479, 224, 0x1F20), (19892, 2304, 0x0700),
                                    (51515, 2080, 0x1700),
                                    (53595, 1824, 0x08E0)]:
        patterns[target:target + length] = prg[source:source + length]
    palettes = [list(prg[103168 + 3 + p * 4:103168 + 7 + p * 4]) for p in range(8)]
    atlas = bytearray(256 * 256 * 4)
    for palette in range(4):
        for index in range(56):
            slot = palette * 64 + index
            for part, tile in enumerate(square_tiles(prg, index)):
                blit_tile(atlas, 256, slot % 16 * 16 + part // 2 * 8,
                          slot // 16 * 16 + part % 2 * 8,
                          patterns[0x1000:], tile, palettes[palette])
    png(output / 'overworld_tiles.png', 256, 256, atlas)
    # Eight explicit directional frames: right, left, down, up, two poses each.
    for player_palette in range(4):
        player = bytearray(128 * 16 * 4)
        for direction in range(4):
            for pose in range(2):
                frame = pose if direction < 2 else direction
                tile = prg[0x6E83 + frame]
                sprite = bytearray(16 * 16 * 4)
                for part in range(4):
                    actual = tile + part
                    if direction == 2 and part == 0:
                        actual += 0x50  # Original small-shield substitution, Z_07.
                    blit_tile(sprite, 16, part // 2 * 8, part % 2 * 8,
                              patterns, actual, palettes[4 + player_palette], transparent=True)
                flip = direction == 1 or (direction >= 2 and pose == 1)
                for y in range(16):
                    for x in range(16):
                        src = (y * 16 + (15 - x if flip else x)) * 4
                        dst = (y * 128 + (direction * 2 + pose) * 16 + x) * 4
                        player[dst:dst + 4] = sprite[src:src + 4]
        png(output / ('player.png' if player_palette == 0 else f'clock_player_{player_palette}.png'), 128, 16, player)
    glyphs = bytearray(128 * 128 * 4)
    for tile in range(256):
        blit_tile(glyphs, 128, tile % 16 * 8, tile // 16 * 8,
                  patterns[0x1000:], tile, [0x0F, 0x30, 0x30, 0x30], transparent=True)
    png(output / 'hud_tiles.png', 128, 128, glyphs)
    # HUD heart tiles use palette indices 1 and 3 to distinguish filled and
    # missing health. A monochrome text mask destroys that distinction.
    hearts = bytearray(24 * 8 * 4)
    for frame, tile in enumerate((0xF2, 0x65, 0x66)):
        blit_tile(hearts, 24, frame * 8, 0, patterns[0x1000:], tile, palettes[1], transparent=True)
    png(output / 'hud_hearts.png', 24, 8, hearts)
    cave_layouts = export_cave(prg, patterns, palettes, output)
    combat_names = export_combat_sprites(prg, patterns, palettes, output)
    people, person_tiles = export_people(prg, patterns, palettes, output, png, blit_tile)
    combat_names += people + export_item_sprites(prg, patterns, palettes, output, png, blit_tile)
    caves = cave_types(prg)
    (output / 'caves').mkdir(exist_ok=True)
    for cave in caves:
        cave['person_tile'] = person_tiles[cave['type']]
        (output / 'caves' / f'{cave["id"]}.tres').write_text(cave_resource(cave), encoding='utf-8')
    entrances = overworld_entrances(prg, layouts, square_tiles)
    cellar = list(prg[103168 + 52:103168 + 56])
    cave_rooms, cave_ids, unreachable = [], [], []
    # Each level's entrance: the first-quest room with an entrance square or secret,
    # else (level 7's recorder pond) the room whose secret is not second-quest only.
    level_entrances = {}
    for room_id in range(128):
        entrance = entrances[room_id]
        level = entrance['destination']
        if not 1 <= level <= 9: continue
        places = [e['mouth'] for e in entrance['visible']] + ([entrance['secret']['kind'] == 'wall'] if entrance['secret'] else [])
        second_quest = prg[99328 + 640 + room_id] >> 6 == 2
        if places or (level not in level_entrances and not second_quest):
            level_entrances[level] = (f'ow_{room_id:02x}', entrance['exit'], 16 if places and places[0] else 0)
    level_room_ids, level_starts, dungeon_sprites, dungeon_coverage = export_levels(prg, output, png, blit_tile, level_entrances)
    combat_names += dungeon_sprites
    combat_names += export_beam_sprites(prg, patterns, palettes, output)
    combat_names += export_source_enemies(prg, patterns, palettes, output)
    combat_names += export_overworld_enemies(prg, patterns, palettes, output)
    # The pause submenu uses the overworld or the current level's background patterns.
    uw_patterns = bytearray(8192)
    for source, length, target in [(32895, 1792, 0), (34687, 1792, 0x1000), (36479, 224, 0x1F20), (49435, 0x820, 0x1700)]:
        uw_patterns[target:target + length] = prg[source:source + length]
    combat_names += import_submenu.export(prg, output, patterns, uw_patterns, palettes,
                                          {level: import_dungeons.level_info(prg, level) for level in range(1, 10)}, png, blit_tile)
    start_id = prg[103168 + 47]
    start_y = prg[103168 + 40] - 64
    for room_id, layout in enumerate(layouts):
        inner = prg[99328 + 128 + room_id] & 3
        outer = prg[99328 + room_id] & 3
        indices, collision = [], [0] * (32 * 22)
        ladder_water = [0] * 704
        coarse = []
        for y, row in enumerate(layout):
            line = ''
            for x, index in enumerate(row):
                palette = inner if 2 <= x < 14 and 2 <= y < 9 else outer
                indices.append(palette * 64 + index)
                parts = square_tiles(prg, index)
                solid = []
                for part, tile in enumerate(parts):
                    blocked = int(tile >= 0x89 and tile not in WALKABLE)
                    collision[(y * 2 + part % 2) * 32 + x * 2 + part // 2] = blocked
                    ladder_water[(y * 2 + part % 2) * 32 + x * 2 + part // 2] = int(0x8D <= tile < 0x99)
                    solid.append(blocked)
                line += '#' if all(solid) else '.'
            coarse.append(line)
        exits = {}
        for edge, delta, allowed in [('left', -1, room_id % 16 > 0), ('right', 1, room_id % 16 < 15),
                                     ('up', -16, room_id >= 16), ('down', 16, room_id < 112)]:
            if allowed:
                exits[edge] = f'ow_{room_id + delta:02x}'
        # Default spawns are only used by reset; choose a walkable square.
        spawn = (120, start_y) if room_id == start_id else next(
            ((x * 16, y * 16 - 3) for y in range(1, 10) for x in range(1, 15)
             if all(collision[(y * 2 + dy) * 32 + x * 2 + dx] == 0 for dy in range(2) for dx in range(2))), (120, 77))
        edge_cells = []
        for y in range(11):
            for x in range(16):
                if (x in (0, 15) or y in (0, 10)) and square_tiles(prg, layout[y][x])[0] < 0x84:
                    edge_cells.append((y + 4) * 16 + x)
        entrance = entrances[room_id]
        palette_for = lambda x, y: inner if 2 <= x < 14 and 2 <= y < 9 else outer
        portal_lines_out, portal_ids, secret_lines = [], [], []
        if entrance['secret']:
            secret_lines = ['[sub_resource type="Resource" id="secret"]'] + secret_resource(
                prg, entrance, layout, palette_for, square_tiles, WALKABLE)
        # Z_05 HandleWarpOW: caves from attribute B $40 up; levels below are future work.
        places = [(e['cell'], e['mouth'], False) for e in entrance['visible']]
        if entrance['secret']:
            places.append((entrance['secret']['reveal'], entrance['secret']['kind'] == 'wall', True))
        # Statues and the Armos secret of this room.
        armos_cells = [(x, y) for y, row in enumerate(layout) for x, index in enumerate(row) if 0xC0 <= square_tiles(prg, index)[0] <= 0xC3]
        armos_secret = None
        if room_id in SECRET_ARMOS and (SECRET_ARMOS[room_id] // 16, 4) in armos_cells:
            armos_secret = (SECRET_ARMOS[room_id] // 16, 4)
            item = room_id == BRACELET_ROOM
            square = SQUARE_FLOOR if item else SQUARE_STAIRS
            secret_lines = ['[sub_resource type="Resource" id="secret"]', 'script = ExtResource("secret")', 'trigger = "armos"',
                            f'cell = Vector2i({armos_secret[0]}, {armos_secret[1]})', f'reveal_cell = Vector2i({armos_secret[0]}, {armos_secret[1]})',
                            f'reveal_tile = {palette_for(*armos_secret) * 64 + square}', f'floor_tile = {palette_for(*armos_secret) * 64 + SQUARE_FLOOR}',
                            f'reveal_kind = "{"item" if item else "entrance"}"', 'persistent = false']
            if not item and entrance['destination'] >= FIRST_CAVE and not places:
                places.append((armos_secret, False, True))
            elif not item and 1 <= entrance['destination'] <= 9:
                # A second, Armos-hidden way into the level.
                portal_lines_out += ['[sub_resource type="Resource" id="armos_stairs"]'] + portal_lines(
                    (armos_secret[0] * 16, armos_secret[1] * 16 - 3, 1, 1), level_starts[entrance['destination']], (120, 157), (0, -1), walk=16, requires_secret=True)
                portal_ids.append('SubResource("armos_stairs")')
        if 1 <= entrance['destination'] <= 9 and places:
            # Level 6's entrance is two squares wide; CheckWarps then accepts X multiples of 8.
            cells = sorted(place[0] for place in places)
            cell, hidden = cells[0], places[0][2]
            width = 1 + (cells[-1][0] - cells[0][0]) * 16
            portal_lines_out += ['[sub_resource type="Resource" id="entrance"]'] + portal_lines(
                (cell[0] * 16, cell[1] * 16 - 3, width, 1), level_starts[entrance['destination']], (120, 157), (0, -1), walk=16, requires_secret=hidden)
            portal_ids.append('SubResource("entrance")')
        if len(places) > 1 and entrance['destination'] >= FIRST_CAVE:
            raise ValueError(f'Overworld room {room_id:02X} has {len(places)} cave entrances')
        if entrance['destination'] >= FIRST_CAVE and not places:
            # Second-quest, Armos, and recorder entrances are not imported yet.
            unreachable.append(f'ow_{room_id:02x}')
        elif entrance['destination'] >= FIRST_CAVE:
            cell, mouth, hidden = places[0]
            cave_ids.append(f'cave_{room_id:02x}')
            cave_rooms.append(cave_room(room_id, entrance['destination'], dict(entrance, mouth=mouth), cellar, entrances, cave_layouts))
            # CheckWarps: grid-aligned X, Y = 16n + $0D, standing on the entrance square.
            portal_lines_out += ['[sub_resource type="Resource" id="entrance"]'] + portal_lines(
                (cell[0] * 16, cell[1] * 16 - 3, 1, 1), f'cave_{room_id:02x}', (112, 157), (0, -1), walk=48, requires_secret=hidden)
            portal_ids.append('SubResource("entrance")')
        portal_resources = ''
        if portal_lines_out or secret_lines:
            portal_resources = '[ext_resource type="Script" path="res://scripts/portal_definition.gd" id="portal"]\n'
            portal_resources += '[ext_resource type="Script" path="res://scripts/secret_definition.gd" id="secret"]\n'
            portal_resources += '\n'.join(portal_lines_out + secret_lines) + '\n'
        portal_field = ('portals = Array[Resource]([' + ', '.join(portal_ids) + '])\n') if portal_ids else ''
        if secret_lines: portal_field += 'secret = SubResource("secret")\n'
        enemy_ext, enemy_sub, enemy_field, enemy_count = enemy_resources(prg, room_id, collision, spawn)
        portal_resources = enemy_ext + portal_resources + enemy_sub
        if room_id in (0x3F, 0x55):
            dock_x = 128 if room_id == 0x55 else 96
            portal_resources = '[ext_resource type="Script" path="res://scripts/raft_route.gd" id="raft_route"]\n' + portal_resources
            portal_resources += '\n'.join(['[sub_resource type="Resource" id="dock_route"]', 'script = ExtResource("raft_route")',
                f'dock_position = Vector2i({dock_x}, 61)', f'edge_position = Vector2i({dock_x}, -3)',
                f'landing_position = Vector2i({dock_x}, 63)']) + '\n'
            portal_field += 'raft_route = SubResource("dock_route")\n'
        # Z_04 CheckZora: attribute A bit 3.
        zora = bool(prg[99328 + room_id] & 0x08)
        if zora: portal_resources = '[ext_resource type="Resource" path="res://imported/enemies/zora.tres" id="zora"]\n' + portal_resources
        armos_field = ''
        if armos_cells:
            portal_resources = '[ext_resource type="Resource" path="res://imported/enemies/armos.tres" id="armos"]\n' + portal_resources
            armos_field = ('armos = ExtResource("armos")\n' + 'armos_cells = PackedVector2Array(' + ', '.join(f'{x}, {y}' for x, y in armos_cells) + ')\n'
                           + 'armos_floor_tiles = PackedInt32Array(' + ', '.join(str(palette_for(x, y) * 64 + SQUARE_FLOOR) for x, y in armos_cells) + ')\n')
        if room_id == BRACELET_ROOM and armos_secret:
            portal_resources = ('[ext_resource type="Script" path="res://scripts/pickup_definition.gd" id="pickup_script"]\n'
                                '[ext_resource type="Resource" path="res://content/items/power_bracelet.tres" id="bracelet"]\n') + portal_resources
            portal_resources += '\n'.join(['[sub_resource type="Resource" id="bracelet_pickup"]', 'script = ExtResource("pickup_script")', 'id = &"item"',
                                            'item = ExtResource("bracelet")', f'position = Vector2i({SECRET_ARMOS[room_id]}, {0x80 - 64 - 3})',
                                            'tolerance = Vector2i(8, 8)', 'lift_ticks = 0', 'requires_secret = true']) + '\n'
            armos_field += 'pickups = Array[Resource]([SubResource("bracelet_pickup")])\n'
        steps = 3 + portal_resources.count('[ext_resource') + portal_resources.count('[sub_resource')
        text = f'''[gd_resource type="Resource" script_class="RoomDefinition" load_steps={steps} format=3]
[ext_resource type="Script" path="res://scripts/room_definition.gd" id="1"]
[ext_resource type="Texture2D" path="res://imported/overworld_tiles.png" id="2"]
{portal_resources}[resource]
script = ExtResource("1")
id = &"ow_{room_id:02x}"
enemy_persistence = "overworld"
source_spawn_lists = true
source_edge_spawns = {str(bool(prg[99328 + 640 + room_id] & 8)).lower()}
source_edge_cells = PackedByteArray({array(edge_cells)})
title = "Overworld {room_id:02X}"
map_room_id = {room_id}
{portal_field}
{enemy_field}
tiles = {json.dumps(chr(10).join(coarse))}
exits = Dictionary[String, String]({json.dumps(exits)})
spawn = Vector2i({spawn[0]}, {spawn[1]})
movement_bounds = Rect2i(0, -3, 241, 161)
grid_origin = Vector2i(0, 5)
tile_atlas = ExtResource("2")
tile_indices = PackedInt32Array({array(indices)})
collision_tiles = PackedByteArray({array(collision)})
ladder_allowed = {str(room_id in (0x17, 0x18, 0x19, 0x27, 0x4F, 0x5F)).lower()}
ladder_water = PackedByteArray({array(ladder_water)})
{'zora = ExtResource("zora")' if zora else ''}
{armos_field}
'''
        (output / 'rooms' / f'ow_{room_id:02x}.tres').write_text(text)
    for name, text in zip(cave_ids, cave_rooms):
        (output / 'rooms' / f'{name}.tres').write_text(text)
    # The single sword cave became cave_77; never leave a stale room behind.
    if (output / 'rooms' / 'sword_cave.tres').exists():
        (output / 'rooms' / 'sword_cave.tres').unlink()
    names = ['fire_0', 'fire_1', 'wooden_sword', 'sword_up', 'sword_down', 'sword_right', 'sword_left', 'attack_right', 'attack_left', 'attack_down', 'attack_up', 'lift'] + combat_names
    names += [f'clock_player_{i}' for i in range(1,4)] + [f'attack_{direction}_clock_{i}' for direction in ('up','down','left','right') for i in range(1,4)]
    theme = [f'[gd_resource type="Resource" script_class="VisualTheme" load_steps={5 + len(names)} format=3]',
             '[ext_resource type="Script" path="res://scripts/visual_theme.gd" id="1"]',
             '[ext_resource type="Texture2D" path="res://imported/player.png" id="2"]',
             '[ext_resource type="Texture2D" path="res://imported/hud_tiles.png" id="3"]',
             '[ext_resource type="Texture2D" path="res://imported/hud_hearts.png" id="hearts"]']
    for name in names:
        theme.append(f'[ext_resource type="Texture2D" path="res://imported/{name}.png" id="{name}"]')
    theme += ['[resource]', 'script = ExtResource("1")', 'player_sheet = ExtResource("2")', 'hud_tiles = ExtResource("3")', 'hud_hearts = ExtResource("hearts")',
              'sprites = Dictionary[StringName, Texture2D]({' + ', '.join(f'&"{name}": ExtResource("{name}")' for name in names) + '})']
    (output / 'theme.tres').write_text('\n'.join(theme) + '\n')
    catalog = [f'[gd_resource type="Resource" script_class="WorldDefinition" load_steps={141 + len(cave_ids) + len(level_room_ids)} format=3]',
               '[ext_resource type="Script" path="res://scripts/world_definition.gd" id="script"]',
               '[ext_resource type="Resource" path="res://imported/theme.tres" id="theme"]',
               '[ext_resource type="Resource" path="res://imported/submenu.tres" id="submenu"]']
    for i in range(128):
        catalog.append(f'[ext_resource type="Resource" path="res://imported/rooms/ow_{i:02x}.tres" id="r{i}"]')
    for name in cave_ids + level_room_ids:
        catalog.append(f'[ext_resource type="Resource" path="res://imported/rooms/{name}.tres" id="{name}"]')
    catalog += [
        '[ext_resource type="Script" path="res://scripts/loot_table.gd" id="loot_script"]',
        '[ext_resource type="Resource" path="res://content/items/heart.tres" id="heart"]',
        '[ext_resource type="Resource" path="res://content/items/rupee.tres" id="rupee"]',
        '[ext_resource type="Resource" path="res://content/items/five_rupees.tres" id="five_rupees"]',
        '[ext_resource type="Resource" path="res://content/items/bomb_drop.tres" id="bomb_drop"]',
        '[ext_resource type="Resource" path="res://content/items/clock.tres" id="clock"]',
        '[ext_resource type="Resource" path="res://content/items/fairy.tres" id="fairy"]']
    # Original group rates and kill-cycle rows remain generated local data.
    # All original drop IDs now have native behavior resources.
    supported = {0x22: 'heart', 0x18: 'rupee', 0x0F: 'five_rupees', 0x00: 'bomb_drop', 0x21: 'clock', 0x23: 'fairy'}
    for name, group in [(f'loot_{group}', group) for group in range(4)]:
        row = prg[0x13042 + group * 10:0x13042 + group * 10 + 10]
        entries = [f'ExtResource("{supported[value]}")' if value in supported else 'null' for value in row]
        catalog += [f'[sub_resource type="Resource" id="{name}"]', 'script = ExtResource("loot_script")',
                    f'chance = {prg[0x1303E + group]}', 'entries = Array[Resource]([' + ', '.join(entries) + '])']
    catalog += ['[resource]', 'script = ExtResource("script")', 'id = &"original_quest_1"', 'submenu = ExtResource("submenu")', f'start_room = &"ow_{start_id:02x}"',
                'visual_theme = ExtResource("theme")',
                'spawn_lists = Array[PackedByteArray]([' + ', '.join('PackedByteArray(' + array(prg[0x1464E + i * 9:0x1464E + i * 9 + 9]) + ')' for i in range(4)) + '])',
                'loot_tables = Dictionary[StringName, Resource]({' + ', '.join(f'&"{name}": SubResource("loot_{loot_group(prg,kind)}")' for kind,(name,_) in list(ENEMY_TYPES.items()) + list(MONSTERS.items())) + '})',
                'legacy_ids = Dictionary[String, String]({"sword_cave": "cave_77", "sword_cave/sword_gift": "cave_77/taken"})',
                'whirlwinds = [' + ', '.join(f'{{"room": "ow_{prg[WHIRLWIND_ROOMS + i] + 1:02x}", "y": {prg[TELEPORT_YS + i]}}}' for i in range(8)) + ']',
                'rooms = Array[Resource]([' + ', '.join([f'ExtResource("r{i}")' for i in range(128)] + [f'ExtResource("{name}")' for name in cave_ids + level_room_ids]) + '])']
    (output / 'world.tres').write_text('\n'.join(catalog) + '\n')
    (output / 'manifest.json').write_text(json.dumps({
        'format_version': 1, 'revision': 'US PRG0', 'prg_sha1': PRG_SHA1,
        'enemy_coverage': {
            'supported_types': [name for name,_ in ENEMY_TYPES.values()],
            'encounters': sum(bool(types := room_enemy_types(prg,i)) and all(t in ENEMY_TYPES for t in types) for i in range(128)),
            'dungeon_rooms_with_monsters': dungeon_coverage['rooms'], 'dungeon_rooms_populated': dungeon_coverage['populated'],
            'mixed_encounters': sum(bool(types := room_enemy_types(prg,i)) and len(set(types)) > 1 and all(t in ENEMY_TYPES for t in types) for i in range(128))},
        'rooms': 128 + len(cave_ids) + len(level_room_ids), 'dungeon_rooms': len(level_room_ids), 'caves': len(cave_ids), 'caves_without_first_quest_entrance': unreachable, 'start_room': f'ow_{start_id:02x}', 'start_position': [120, start_y],
        'limitations': ['First-quest terrain; Ghini, boulders, pond fairies, and the Lost Woods/Hills remain unimplemented.',
                        'First-quest dungeon encounters are imported; Zora and Armos are in.',
                        'RGB colors approximate NES output.']}, indent=2) + '\n')
    from render_audio import export_audio
    export_audio(prg, output / 'audio')
    print(f'Imported 128 overworld rooms, {len(cave_ids)} caves, terrain, player, item, and common overworld enemy sprites into {output}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rom', type=Path)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'imported',
                        help='Output res://imported directory of the destination Godot project')
    args = parser.parse_args()
    try:
        import_rom(read_rom(args.rom), args.output)
    except (OSError, ValueError) as exc:
        parser.exit(1, f'Import failed: {exc}\n')


if __name__ == '__main__':
    main()
