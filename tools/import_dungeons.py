"""First-quest dungeon levels: rooms, cellars, doors, items, and entrances.

Room tile maps come from running the original layout routines (Z_05
LayOutRoom's underworld branch, LayoutCellarAndAdvanceSubmode, and
FillPlayAreaAttrs) on nes_cpu, so walls, doors, and floors match the game.
See docs/DUNGEONS.md for the routines behind each table.
"""
import json

from nes_cpu import Cpu

LEVEL_BLOCKS = {1: 0x18700, 7: 0x18A00}   # Levels 1-6 and 7-9 share a 128-room grid.
LEVEL_INFO = 0x19300
LEVEL_INFO_STRIDE = 0xFC
COMMON_CODE = (0x6500, 0x6C90, 0x1270)    # Bank 1 code copied to $6C90 at reset.
COMMON_DATA_POINTER = 0x18028
LAYOUT_UW = 0xA8CB                        # LayOutRoom after its overworld branch.
FILL_ATTRS = 0x83D7                       # FillPlayAreaAttrs, A = room ID.
PATCH_CELLAR = 0xAB30                     # PatchColumnDirectoryForCellar.
LAYOUT_CELLAR = 0xAB62                    # LayoutCellarAndAdvanceSubmode.
CUR_LEVEL, ROOM_ID, OPENED_DOORS = 0x10, 0xEB, 0xEE
PLAY_AREA_TILES = 0x530                   # SRAM offset of $6530, column-major, 22 rows.
PLAY_AREA_ATTRS = 0x530                   # RAM $0530.
FIRST_UNWALKABLE = 0x78                   # ObjectRoomBoundsUW.
STAIRS = range(0x70, 0x74)
DIRECTIONS = {'up': (-16, 0, 5, (0, -1)), 'down': (16, 0, 2, (0, 1)),
              'left': (-1, 128, 5, (-1, 0)), 'right': (1, 128, 2, (1, 0))}
DOOR_KINDS = ['open', 'wall', 'false', 'false', 'bombable', 'key', 'key', 'shutter']
# Door lanes: cells cleared to the room edge so Link can walk out, as CheckDoorway does.
DOOR_LANES = {'up': [(x, y) for x in (15, 16) for y in range(0, 4)],
              'down': [(x, y) for x in (15, 16) for y in range(18, 22)],
              'left': [(x, y) for x in range(0, 4) for y in (10, 11)],
              'right': [(x, y) for x in range(28, 32) for y in (10, 11)]}
# Door regions in eight-pixel tiles, used to diff closed and open layouts.
DOOR_REGIONS = {'up': (13, 0, 6, 5), 'down': (13, 17, 6, 5), 'left': (0, 8, 5, 6), 'right': (27, 8, 5, 6)}
# Z_07 BombableWallHotspots in play-area coordinates; Link's doorway coordinates.
BOMB_HOTSPOTS = {'up': (120, 29), 'down': (120, 125), 'left': (32, 77), 'right': (208, 77)}
ITEMS = {0x00: 'bombs', 0x05: 'recorder', 0x07: 'red_candle', 0x09: 'silver_arrows', 0x0A: 'bow',
         0x0B: 'magic_key', 0x0C: 'raft', 0x0D: 'ladder', 0x0E: 'triforce_of_power', 0x0F: 'five_rupees', 0x10: 'magic_rod', 0x11: 'book',
         0x13: 'red_ring', 0x14: 'power_bracelet', 0x16: 'compass', 0x17: 'map', 0x19: 'key',
         0x1A: 'heart_container', 0x1B: 'triforce', 0x1D: 'boomerang', 0x1E: 'magical_boomerang'}
NO_ITEM = 0x03


def level_info(prg, level):
    return prg[LEVEL_INFO + LEVEL_INFO_STRIDE * level:LEVEL_INFO + LEVEL_INFO_STRIDE * level + 256]


def level_block(prg, level):
    start = LEVEL_BLOCKS[1 if level <= 6 else 7]
    return prg[start:start + 768]


def door_kind(block, room, direction):
    _, attr, shift, _ = DIRECTIONS[direction]
    return DOOR_KINDS[(block[attr + room] >> shift) & 7]


def neighbor(room, direction):
    step = DIRECTIONS[direction][0]
    target = room + step
    if direction in ('left', 'right') and target // 16 != room // 16: return None
    return target if 0 <= target < 128 else None


class Layouts:
    """Runs the original layout code for one level."""
    def __init__(self, prg, level):
        self.prg = prg
        self.level = level
        self.info = level_info(prg, level)
        self.block = level_block(prg, level)

    def cpu(self):
        cpu = Cpu(self.prg, 5)
        source, target, size = COMMON_CODE
        cpu.sram[target - 0x6000:target - 0x6000 + size] = self.prg[source:source + size]
        data = (self.prg[COMMON_DATA_POINTER] | self.prg[COMMON_DATA_POINTER + 1] << 8) - 0x8000 + 0x18000
        cpu.sram[0x7F0:0x87E] = self.prg[data:data + 0x8E]
        cpu.sram[0x87E:0x87E + 768] = self.block
        cpu.sram[0xB7E:0xB7E + 256] = self.info
        cpu.write(CUR_LEVEL, self.level)
        return cpu

    def room(self, room, opened=0):
        cpu = self.cpu()
        cpu.write(ROOM_ID, room)
        cpu.write(OPENED_DOORS, opened)
        cpu.call(LAYOUT_UW)
        tiles = bytes(cpu.sram[PLAY_AREA_TILES:PLAY_AREA_TILES + 704])
        cpu.a = room
        cpu.call(FILL_ATTRS)
        return tiles, bytes(cpu.ram[PLAY_AREA_ATTRS:PLAY_AREA_ATTRS + 48])

    def cellar(self, room):
        cpu = self.cpu()
        cpu.write(ROOM_ID, room)
        cpu.call(PATCH_CELLAR)
        cpu.call(LAYOUT_CELLAR)
        # Z_06 CellarAttrsTransferBuf fills every attribute with $AA.
        return bytes(cpu.sram[PLAY_AREA_TILES:PLAY_AREA_TILES + 704]), bytes([0xAA] * 48)


def tile_at(tiles, x, y):
    return tiles[x * 22 + y]


def palette_at(attrs, x, y):
    """Attribute quadrant for the 16-pixel cell at tile (x, y); play area starts on a 32-pixel row."""
    value = attrs[(y // 4) * 8 + x // 4]
    return (value >> (((y // 2) & 1) * 4 + ((x // 2) & 1) * 2)) & 3


def collision(tiles):
    return [int(tile_at(tiles, x, y) >= FIRST_UNWALKABLE) for y in range(22) for x in range(32)]


def level_rooms(prg, level):
    """Rooms reachable from the start room through doors and cellar stairs."""
    layouts = Layouts(prg, level)
    block, info = layouts.block, layouts.info
    start = info[0x2F]
    cellars = [room for room in info[0x34:0x3E] if room != 0xFF]
    links = {}
    for cellar in cellars:
        for room in (block[cellar], block[128 + cellar]):
            links.setdefault(room, set()).add(cellar)
    seen, pending = set(), [start]
    while pending:
        room = pending.pop()
        if room in seen: continue
        seen.add(room)
        if room in cellars:
            pending += [block[room], block[128 + room]]
            continue
        pending += list(links.get(room, ()))
        for direction in DIRECTIONS:
            if door_kind(block, room, direction) == 'wall' or (room == start and direction == 'down'): continue
            target = neighbor(room, direction)
            if target is not None: pending.append(target)
    return start, sorted(r for r in seen if r not in cellars), sorted(r for r in seen if r in cellars)


def room_id(level, room):
    return f'l{level}_{room:02x}'


def cellar_id(level, room):
    return f'l{level}_c{room:02x}'


def item_position(info, attr_f):
    """Z_01 GetShortcutOrItemXYForRoom, converted to play-area pixels."""
    value = info[0x29 + ((attr_f >> 4) & 3)]
    return value & 0xF0, (value & 0x0F) * 16 - 64


class Atlas:
    """Unique 16-pixel cells (four tiles and a palette) for one level."""
    def __init__(self):
        self.cells = {}

    def index(self, tiles, attrs, cx, cy):
        x, y = cx * 2, cy * 2
        key = (tile_at(tiles, x, y), tile_at(tiles, x, y + 1), tile_at(tiles, x + 1, y), tile_at(tiles, x + 1, y + 1), palette_at(attrs, x, y))
        return self.cells.setdefault(key, len(self.cells))

    def square(self, first, palette):
        return self.cells.setdefault((first, first + 1, first + 2, first + 3, palette), len(self.cells))

    def write(self, path, patterns, palettes, png, blit_tile):
        rows = max(1, (len(self.cells) + 15) // 16)
        canvas = bytearray(256 * rows * 16 * 4)
        for (t0, t1, t2, t3, palette), index in self.cells.items():
            x0, y0 = index % 16 * 16, index // 16 * 16
            for tile, dx, dy in ((t0, 0, 0), (t1, 0, 8), (t2, 8, 0), (t3, 8, 8)):
                blit_tile(canvas, 256, x0 + dx, y0 + dy, patterns, tile, palettes[palette])
        png(path, 256, rows * 16, canvas)


def mask(collision, cx, cy):
    """Four eight-pixel parts of a 16-pixel cell, column-major, bit set when blocked."""
    parts = [collision[(cy * 2 + part % 2) * 32 + cx * 2 + part // 2] for part in range(4)]
    return sum(bit << part for part, bit in enumerate(parts))


def spawn_point(blocked):
    """A walkable grid position, preferring the bottom centre, for resets and loads."""
    rows = range(141, 12, -16)
    columns = sorted(range(32, 224, 16), key=lambda x: abs(x - 120))
    for y in rows:
        for x in columns:
            if not any(blocked[((y + 11) // 8) * 32 + (x + dx) // 8] for dx in (0, 8)): return x, y
    return 120, 141


def cell_lines(values):
    return ', '.join(map(str, values))


def door_resource(name, direction, kind, closed, opened, atlas, closed_attrs, open_attrs):
    """Cells that change when the door is passable: open layout, plus the cleared lane."""
    source_tiles, source_attrs = (closed if kind == 'false' else opened), (closed_attrs if kind == 'false' else open_attrs)
    passable = collision(source_tiles)
    for x, y in DOOR_LANES[direction]: passable[y * 32 + x] = 0
    base = collision(closed)
    x0, y0, w, h = DOOR_REGIONS[direction]
    cells, tiles, masks = [], [], []
    for cy in range(y0 // 2, (y0 + h + 1) // 2):
        for cx in range(x0 // 2, (x0 + w + 1) // 2):
            open_index = atlas.index(source_tiles, source_attrs, cx, cy)
            if open_index == atlas.index(closed, closed_attrs, cx, cy) and mask(passable, cx, cy) == mask(base, cx, cy): continue
            cells.append(cy * 16 + cx)
            tiles.append(open_index)
            masks.append(mask(passable, cx, cy))
    vector = DIRECTIONS[direction][3]
    return [f'[sub_resource type="Resource" id="{name}"]', 'script = ExtResource("door")',
            f'direction = Vector2i({vector[0]}, {vector[1]})', f'kind = "{kind}"',
            f'cells = PackedInt32Array({cell_lines(cells)})', f'open_tiles = PackedInt32Array({cell_lines(tiles)})',
            f'open_collision = PackedInt32Array({cell_lines(masks)})']


def portal(name, area, target, position, facing, walk=0, direction=(0, 0), rise=0):
    lines = [f'[sub_resource type="Resource" id="{name}"]', 'script = ExtResource("portal")',
             f'area = Rect2i({area[0]}, {area[1]}, {area[2]}, {area[3]})', f'required_direction = Vector2i({direction[0]}, {direction[1]})',
             f'target_room = &"{target}"', f'target_position = Vector2i({position[0]}, {position[1]})',
             f'target_facing = Vector2i({facing[0]}, {facing[1]})', f'entry_walk_pixels = {walk}']
    if rise: lines.append(f'exit_rise_pixels = {rise}')
    return lines


def resource(lines):
    steps = sum(line.startswith(('[ext_resource', '[sub_resource')) for line in lines) + 1
    return '\n'.join([f'[gd_resource type="Resource" script_class="RoomDefinition" load_steps={steps} format=3]'] + lines) + '\n'


def export_levels(prg, output, png, blit_tile, entrances):
    """Writes imported/levels/*.png and imported/rooms/l*.tres. Returns room IDs and per-level start rooms.

    entrances maps level number to the overworld room ID, exit position, and rise of its entrance.
    """
    patterns = bytearray(8192)
    for source, length, target in [(34687, 1792, 0x1000), (36479, 224, 0x1F20), (49435, 0x820, 0x1700)]:
        patterns[target:target + length] = prg[source:source + length]
    (output / 'levels').mkdir(exist_ok=True)
    rooms_written, starts, missing_items = [], {}, set()
    for level in range(1, 10):
        layouts = Layouts(prg, level)
        block, info = layouts.block, layouts.info
        start, rooms, cellars = level_rooms(prg, level)
        starts[level] = room_id(level, start)
        palettes = [list(info[3 + p * 4:7 + p * 4]) for p in range(4)]
        atlas = Atlas()
        music = 'level_9' if level == 9 else 'dungeon'
        cellar_of = {}
        for cellar in cellars:
            for side, room in enumerate((block[cellar], block[128 + cellar])):
                cellar_of.setdefault(room, (cellar, side))
        texts = {}
        for room in rooms:
            closed, closed_attrs = layouts.room(room)
            opened, open_attrs = layouts.room(room, 0x0F)
            ext = ['[ext_resource type="Script" path="res://scripts/room_definition.gd" id="room"]',
                   '[ext_resource type="Script" path="res://scripts/door_definition.gd" id="door"]',
                   '[ext_resource type="Script" path="res://scripts/portal_definition.gd" id="portal"]',
                   '[ext_resource type="Script" path="res://scripts/pickup_definition.gd" id="pickup"]',
                   '[ext_resource type="Script" path="res://scripts/secret_definition.gd" id="secret"]',
                   f'[ext_resource type="Texture2D" path="res://imported/levels/level_{level}.png" id="atlas"]']
            subs, doors, portals, exits, fields = [], [], [], {}, []
            base = collision(closed)
            for direction in DIRECTIONS:
                kind = door_kind(block, room, direction)
                if kind == 'wall': continue
                if kind == 'open':
                    for x, y in DOOR_LANES[direction]: base[y * 32 + x] = 0
                subs += door_resource(f'door_{direction}', direction, kind, closed, opened, atlas, closed_attrs, open_attrs)
                doors.append(f'SubResource("door_{direction}")')
                target = neighbor(room, direction)
                if room == start and direction == 'down':
                    over, exit_position, rise = entrances[level]
                    subs += portal('exit', (104, 157, 32, 1), over, exit_position, (0, 1), direction=(0, 1), rise=rise)
                    portals.append('SubResource("exit")')
                elif target in rooms:
                    exits[direction] = room_id(level, target)
            # Stairs squares (tile $70) and push-block stairs lead into cellars.
            stairs = [(x // 2, y // 2) for x in range(0, 32, 2) for y in range(0, 22, 2) if tile_at(closed, x, y) == 0x70]
            attr_f = block[640 + room]
            trigger = attr_f & 7
            if block[384 + room] & 0x40:
                column = next((x for x in range(4, 26, 2) if tile_at(closed, x, 10) == 0xB0), 4)
                cell = (column // 2, 5)
                reveal = (13, 2) if trigger == 5 else cell
                subs += ['[sub_resource type="Resource" id="block"]', 'script = ExtResource("secret")', 'trigger = "block"',
                         f'cell = Vector2i({cell[0]}, {cell[1]})', f'reveal_cell = Vector2i({reveal[0]}, {reveal[1]})',
                         f'reveal_tile = {atlas.square(0x70, palette_at(closed_attrs, 26, 4)) if trigger == 5 else -1}',
                         f'floor_tile = {atlas.square(0x74, palette_at(closed_attrs, cell[0] * 2, 10))}',
                         f'object_tile = {atlas.square(0xB0, palette_at(closed_attrs, cell[0] * 2, 10))}',
                         f'reveal_kind = "{"stairs" if trigger == 5 else "shutters"}"', 'persistent = false']
                fields.append('secret = SubResource("block")')
                if trigger == 5: stairs.append(reveal)
            if room in cellar_of and stairs:
                cellar, side = cellar_of[room]
                cell = stairs[0]
                subs += portal('stairs', (cell[0] * 16, cell[1] * 16 - 3, 1, 1), cellar_id(level, cellar),
                               (0x30 if side == 0 else 0xC0, 1), (0, 1), walk=28)
                if trigger == 5 and block[384 + room] & 0x40: subs.append('requires_secret = true')
                portals.append('SubResource("stairs")')
            item = block[512 + room] & 0x1F
            if item != NO_ITEM:
                name = ITEMS.get(item)
                if name is None: missing_items.add(item)
                else:
                    x, y = item_position(info, attr_f)
                    # Z_01 TryTakeItem: |Link X - X| < 9 and |Link Y + 3 - Y| < 9.
                    ext.append(f'[ext_resource type="Resource" path="res://content/items/{name}.tres" id="item"]')
                    subs += ['[sub_resource type="Resource" id="room_item"]', 'script = ExtResource("pickup")', 'id = &"item"',
                             'item = ExtResource("item")', f'position = Vector2i({x}, {y - 3})', 'tolerance = Vector2i(8, 8)', 'lift_ticks = 0',
                             f'requires_clear = {str(trigger in (3, 7)).lower()}']
                    fields.append('pickups = Array[Resource]([SubResource("room_item")])')
            indices = [atlas.index(closed, closed_attrs, cx, cy) for cy in range(11) for cx in range(16)]
            fields += [f'dungeon_level = {level}', f'map_room_id = {room}', f'shutter_trigger = {trigger}',
                       f'doors = Array[Resource]([{", ".join(doors)}])', f'portals = Array[Resource]([{", ".join(portals)}])']
            text = resource(ext + subs + ['[resource]', 'script = ExtResource("room")', f'id = &"{room_id(level, room)}"',
                f'title = "Level {level} room {room:02X}"', f'music = &"{music}"', 'enemy_persistence = "reset"',
                f'tiles = {json.dumps(chr(10).join("." * 16 for _ in range(11)))}', f'exits = Dictionary[String, String]({json.dumps(exits)})',
                f'spawn = Vector2i({spawn_point(base)[0]}, {spawn_point(base)[1]})', 'movement_bounds = Rect2i(0, -3, 241, 161)', 'grid_origin = Vector2i(0, 5)',
                'tile_atlas = ExtResource("atlas")', f'tile_indices = PackedInt32Array({cell_lines(indices)})',
                f'collision_tiles = PackedByteArray({cell_lines(base)})'] + fields)
            texts[room_id(level, room)] = text
        for cellar in cellars:
            tiles, attrs = layouts.cellar(cellar)
            ext = ['[ext_resource type="Script" path="res://scripts/room_definition.gd" id="room"]',
                   '[ext_resource type="Script" path="res://scripts/portal_definition.gd" id="portal"]',
                   '[ext_resource type="Script" path="res://scripts/pickup_definition.gd" id="pickup"]',
                   f'[ext_resource type="Texture2D" path="res://imported/levels/level_{level}.png" id="atlas"]']
            subs, portals, fields = [], [], []
            # Z_05: leaving above Y $40, X < $80 uses attribute A, else B; arrive at attribute C.
            arrive = block[256 + cellar]
            for side, x in enumerate((0x30, 0xC0)):
                target = block[128 * side + cellar]
                if target not in rooms or tile_at(tiles, x // 8, 0) >= FIRST_UNWALKABLE: continue
                subs += portal(f'ladder_{side}', (x, -3, 1, 3), room_id(level, target),
                               (arrive & 0xF0, ((arrive & 0x0F) << 4 | 0x0D) - 64), (0, 1), direction=(0, -1))
                portals.append(f'SubResource("ladder_{side}")')
            item = block[512 + cellar] & 0x1F
            if item != NO_ITEM and ITEMS.get(item):
                x, y = item_position(info, block[640 + cellar])
                ext.append(f'[ext_resource type="Resource" path="res://content/items/{ITEMS[item]}.tres" id="item"]')
                subs += ['[sub_resource type="Resource" id="cellar_item"]', 'script = ExtResource("pickup")', 'id = &"item"',
                         'item = ExtResource("item")', f'position = Vector2i({x}, {y - 3})', 'tolerance = Vector2i(8, 8)']
                fields.append('pickups = Array[Resource]([SubResource("cellar_item")])')
            elif item != NO_ITEM: missing_items.add(item)
            indices = [atlas.index(tiles, attrs, cx, cy) for cy in range(11) for cx in range(16)]
            texts[cellar_id(level, cellar)] = resource(ext + subs + ['[resource]', 'script = ExtResource("room")',
                f'id = &"{cellar_id(level, cellar)}"', f'title = "Level {level} cellar {cellar:02X}"', f'music = &"{music}"',
                f'history_id = &"{room_id(level, block[cellar])}"', 'enemy_persistence = "reset"', f'dungeon_level = {level}',
                f'tiles = {json.dumps(chr(10).join("." * 16 for _ in range(11)))}', 'spawn = Vector2i(48, 29)',
                'movement_bounds = Rect2i(0, -3, 241, 161)', 'grid_origin = Vector2i(0, 5)', 'tile_atlas = ExtResource("atlas")',
                f'tile_indices = PackedInt32Array({cell_lines(indices)})', f'collision_tiles = PackedByteArray({cell_lines(collision(tiles))})',
                f'portals = Array[Resource]([{", ".join(portals)}])'] + fields)
        atlas.write(output / 'levels' / f'level_{level}.png', patterns[0x1000:], palettes, png, blit_tile)
        for name, text in texts.items():
            (output / 'rooms' / f'{name}.tres').write_text(text)
            rooms_written.append(name)
    if missing_items:
        raise ValueError('Dungeons hold unsupported items: ' + ', '.join(f'${item:02X}' for item in sorted(missing_items)))
    return rooms_written, starts
