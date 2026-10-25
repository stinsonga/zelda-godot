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
    write_monsters(prg, output)
    rooms_written, starts, missing_items, sprite_names, coverage = [], {}, set(), [], {'rooms': 0, 'populated': 0, 'unsupported': 0}
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
        kinds = {0x1B} if cellars else set()
        for room in rooms:
            types = monster_types(prg, block, info, room)
            if types and all(kind in MONSTERS for kind in types): kinds.update(types)
        if 0x13 in kinds: kinds.add(0x14)
        sprite_names += monster_sprites(prg, level, kinds, output, png, blit_tile)
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
            types = monster_types(prg, block, info, room)
            coverage['rooms'] += bool(types)
            persistence = 'reset'
            if types and all(kind in MONSTERS for kind in types):
                # Z_05 AssignObjSpawnPositions uses the same spawn lists as the overworld.
                enemy_ext, enemy_subs, enemy_field = enemy_lines(level, types, room=room)
                ext += enemy_ext
                subs += enemy_subs
                fields += [enemy_field, 'source_spawn_lists = true']
                # InitMoldorm/InitLamnola: RoomObjCount 8, the most kills a room remembers.
                if {0x41, 0x3A, 0x3B} & set(types): fields.append('persistence_enemy_count = 8')
                persistence = 'overworld'
                coverage['populated'] += 1
            elif types: coverage['unsupported'] += 1
            indices = [atlas.index(closed, closed_attrs, cx, cy) for cy in range(11) for cx in range(16)]
            fields += [f'dungeon_level = {level}', f'enemy_persistence = "{persistence}"', f'map_room_id = {room}', f'shutter_trigger = {trigger}',
                       f'doors = Array[Resource]([{", ".join(doors)}])', f'portals = Array[Resource]([{", ".join(portals)}])']
            text = resource(ext + subs + ['[resource]', 'script = ExtResource("room")', f'id = &"{room_id(level, room)}"',
                f'title = "Level {level} room {room:02X}"', f'music = &"{music}"',
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
            # Z_05 AssignObjSpawnPositions: every cellar holds four blue Keese.
            enemy_ext, enemy_subs, enemy_field = enemy_lines(level, [0x1B] * 4, [(x, y - 64) for x, y in CELLAR_KEESE], cellar)
            ext += enemy_ext
            subs += enemy_subs
            fields.append(enemy_field)
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
    return rooms_written, starts, sprite_names, coverage


# Dungeon monster types (Z_07 UpdateObject_JumpTable) with their native behavior.
MONSTERS = {0x3E: ('ganon', 'ganon'), 0x37: ('zelda', 'zelda'), 0x3F: ('guard_fire', 'guard_fire'), 0x47: ('patra_1', 'patra'), 0x48: ('patra_2', 'patra'), 0x41: ('moldorm', 'moldorm'), 0x3A: ('red_lanmola', 'moldorm'), 0x3B: ('blue_lanmola', 'moldorm'), 0x42: ('gleeok_1', 'gleeok'), 0x43: ('gleeok_2', 'gleeok'), 0x44: ('gleeok_3', 'gleeok'), 0x45: ('gleeok_4', 'gleeok'), 0x3C: ('manhandla', 'manhandla'), 0x05: ('blue_goriya', 'walker'), 0x06: ('red_goriya', 'walker'), 0x13: ('zol', 'gel'),
            0x14: ('child_gel', 'gel'), 0x15: ('gel', 'gel'), 0x1B: ('blue_keese', 'flyer'),
            0x1C: ('red_keese', 'flyer'), 0x1D: ('black_keese', 'flyer'), 0x28: ('rope', 'rope'),
            0x2A: ('stalfos', 'walker'), 0x0B: ('red_darknut', 'walker'), 0x0C: ('blue_darknut', 'walker'),
            0x12: ('vire', 'walker'), 0x16: ('pols_voice', 'pols_voice'), 0x17: ('like_like', 'walker'),
            0x27: ('wallmaster', 'wallmaster'), 0x2B: ('bubble', 'walker'), 0x2C: ('blue_bubble', 'walker'),
            0x2D: ('red_bubble', 'walker'), 0x30: ('gibdo', 'walker'), 0x49: ('trap', 'trap'),
            0x23: ('blue_wizzrobe', 'blue_wizzrobe'), 0x24: ('red_wizzrobe', 'red_wizzrobe'),
            0x3D: ('aquamentus', 'aquamentus'), 0x31: ('dodongo', 'dodongo'), 0x32: ('dodongo', 'dodongo'),
            0x33: ('blue_gohma', 'gohma'), 0x34: ('red_gohma', 'gohma'), 0x38: ('digdogger', 'digdogger'),
            0x39: ('lone_digdogger', 'digdogger'), 0x18: ('little_digdogger', 'digdogger')}
# Z_04 DodongoFrameImages / DodongoFrameImagesBloated: right, left, down, -, up for pose A, then B.
DODONGO_IMAGES = [0x00, 0x01, 0x06, None, 0x08, 0x02, 0x03, 0x06, None, 0x08]
DODONGO_BLOATED = [0x04, 0x05, 0x07, None, 0x09]
# Bosses that start at fixed spots rather than spawn lists (Z_04 InitAquamentus).
# Gohma's position is its middle part; ours is the left leg, 16 pixels earlier.
# InitLamnola starts every segment at ($40, $8D); InitPatra at ($80, $70).
FIXED_POSITIONS = {0x37:(0x78,0x88), 0x47:(0x80,0x70), 0x48:(0x80,0x70), 0x3A:(0x40,0x8D), 0x3B:(0x40,0x8D), 0x41:(0x80,0x70),0x42:(0x74,0x57), 0x43:(0x74,0x57), 0x44:(0x74,0x57), 0x45:(0x74,0x57),0x3D: (0xB0, 0x80), 0x33: (0x70, 0x70), 0x34: (0x70, 0x70)}
AQUAMENTUS_TILES = 0x11834          # Two frames of six 8x16 sprites.
AQUAMENTUS_PALETTE = 0x1A28E        # AquamentusPaletteRow7TransferBuf.
ORANGE_BOSS_PALETTE = 0x1A296       # OrangeBossPaletteRow7TransferBuf (Dodongo, Gohma).
# Z_01 TrapXs/TrapYs: $49 makes six traps, $4A the first four.
TRAPS = [(0x20, 0x5D), (0x20, 0xBD), (0xD0, 0x5D), (0xD0, 0xBD), (0x40, 0x8D), (0xB0, 0x8D)]
SWORD_ONLY = 'PackedStringArray("boomerang", "arrow", "bomb", "fire", "magic")'
PATRA_MANEUVER_TIMES = 0x12B64     # Z_04 PatraManeuverTimes; only the first is ever used.
# Z_04 rotation bit tables, overlapping: child 1 cosine (Y) bits at +0, child 2
# bits at +1, child 1 sine (X) bits at +2; each indexed by the maneuver.
PATRA_BITS = 0x12BD6
# Z_04 Ganon tables and palettes.
GANON_FRAME_IMAGES = 0x12E91       # GanonFrameImages: 6 poses x 4 parts.
GANON_BURST = 0x12D95              # GanonBurstDirs (8), SpriteAttrs (10), Tiles (10).
GANON_START_XS = 0x12D2D           # GanonStartXs: $30, $B0.
GANON_PALETTE = 0x1A202            # GanonPaletteRow7TransferBuf (blue).
GANON_COLOR_SETS = 0x61C5          # GanonColorSets: brown, blue, triforce.
GUARD_FIRES = 0x128C0              # GuardFireXs (5), GuardFireYs (5); slot 1 becomes Zelda.
GUARD_FIRE_SPOTS = [(0x78, 0x88), (0x60, 0xB5), (0x70, 0x9D), (0x80, 0x9D), (0x90, 0xB5)]
EVERYTHING = '"sword", "beam", "boomerang", "arrow", "bomb", "fire", "magic"'
OBJECT_LISTS = 83775            # ObjListAddrs pointer table, bank 5.
CELLAR_KEESE = [(0x20, 0x9D), (0x60, 0x5D), (0x90, 0x7D), (0xD0, 0x9D)]   # Z_05 CellarKeeseXs/Ys
# Z_03 LevelPatternBlockSrcAddrs: level-group sprite blocks, loaded at $09E0.
LEVEL_SPRITES = {1: 56763, 2: 56763, 7: 56763, 3: 55419, 5: 55419, 8: 55419, 4: 55963, 6: 55963, 9: 55963}
UW_COMMON_SPRITES = 56507       # PatternBlockUWSP, $100 bytes at $08E0.
# Z_03 BossPatternBlockSrcAddrs, loaded at $0C00.
BOSS_SPRITES = {1: 57307, 2: 57307, 5: 57307, 7: 57307, 3: 58331, 4: 58331, 6: 58331, 8: 58331, 9: 59355}


def monster_types(prg, block, info, room):
    """Z_05 object templates: one type with a count, or a mixed list from ObjListAddrs."""
    attr_c, attr_d = block[256 + room], block[384 + room]
    template = (attr_c & 63) | ((attr_d >> 7) << 6)
    count = info[36 + (attr_c >> 6)]
    if template == 0: return []
    if template in (0x49, 0x4A): return [0x49] * (6 if template == 0x49 else 4)
    # InitZelda: Zelda in slot 1 and four guard fires.
    if template == 0x37: return [0x37] + [0x3F] * 4
    if template < 0x62: return [template] * (1 if template >= 0x32 else count)
    address = prg[OBJECT_LISTS + (template - 0x62) * 2] | prg[OBJECT_LISTS + (template - 0x62) * 2 + 1] << 8
    offset = 0x14000 + address - 0x8000
    types = []
    for kind in prg[offset:offset + count]:
        # Type 0 is an empty slot; trap generators in lists still make their traps.
        if kind in (0x49, 0x4A): types += [0x49] * (6 if kind == 0x49 else 4)
        elif kind: types.append(kind)
    return types


def monster_definition(prg, kind):
    name, behavior = MONSTERS[kind]
    pair = prg[0x1FB4E + kind // 2]
    health = max(1, pair & 15 if kind & 1 else pair >> 4)   # HP 0 dies to any hit.
    raw = prg[0x72BA + kind]
    fields = {'id': f'&"{name}"', 'title': json.dumps(name.replace('_', ' ').title()), 'behavior': json.dumps(behavior),
              'nes_type': kind, 'health': health, 'fragile': str((pair & 15 if kind & 1 else pair >> 4) == 0).lower(), 'contact_damage': (raw & 15) * 2 + (1 if raw & 240 else 0), 'sprite': f'&"{name}"'}
    if name in ('blue_goriya', 'red_goriya'):
        # Z_04 UpdateGoriya: dominant-axis aim within $51, boomerangs at 2.5 pixels a frame.
        fields.update(speed_subpixels=128, turn_chance=0x80, targeting='"dominant_axis"', projectile_kind='"boomerang"',
                      projectile_damage=1, projectile_blockable='true')
        if name == 'red_goriya': fields['shoot_random_values'] = 'PackedInt32Array(35, 119)'
    elif name == 'stalfos':
        # Z_04 UpdateStalfos: turn rate $80, q-speed $20; first-quest Stalfos never shoot.
        fields.update(speed_subpixels=128, turn_chance=0x80, shooting_enabled='false', sprite_style='"frames"', animation_frame_ticks=8)
    elif behavior == 'gel':
        # Z_04 UpdateNormalZolOrGel: turn rate $20; Zol q-speed $18, Gel $40; ZolGelDelays.
        zol = name == 'zol'
        fields.update(speed_subpixels=96 if zol else 256, turn_chance=0x20, shooting_enabled='false', sprite_style='"frames"',
                      animation_frame_ticks=8 if zol else 2, hop_delays='PackedInt32Array(24, 40, 56, 72)' if zol else 'PackedInt32Array(8, 24, 40, 56)')
    elif behavior == 'flyer':
        # Z_04 InitBlueKeese / InitRedOrBlackKeese and Flyer_KeeseDecideState.
        fields.update(flight_max_speed=0xC0, flight_initial_speed=0x1F if name == 'blue_keese' else 0x7F, flight_random_start='true',
                      flight_vulnerable_resting_only='false', flight_chase_threshold=0xA0, flight_rest_min=0x40, flight_rest_random_mask=0x3F)
    elif behavior == 'rope':
        fields.update(speed_subpixels=128, shooting_enabled='false')
    elif name in ('red_darknut', 'blue_darknut'):
        # Z_04 InitDarknut: mask $F6 leaves only sword and bomb; q-speed $20 red, $28 blue.
        fields.update(speed_subpixels=128 if name == 'red_darknut' else 160, turn_chance=0x80, shooting_enabled='false', front_shield='true', stunnable='false',
                      invincible_to='PackedStringArray("boomerang", "arrow", "fire", "magic")')
    elif name in ('gibdo', 'like_like', 'vire'):
        # UpdateGibdo, UpdateLikeLike, UpdateVireState0: turn rate $80 at the default q-speed $20.
        fields.update(speed_subpixels=128, turn_chance=0x80, shooting_enabled='false', sprite_style='"frames"', animation_frame_ticks=8)
        if name == 'like_like': fields['contact_effect'] = '"capture"'
        if name == 'vire':
            fields.update(hops='true', sprite_style='"directional"')
    elif 'bubble' in name:
        # UpdateBubble: turn rate $40, InitBubble q-speed $40; harmless, unkillable, uncounted.
        effect = {'bubble': 'block_sword', 'blue_bubble': 'restore_sword', 'red_bubble': 'curse_sword'}[name]
        fields.update(speed_subpixels=256, turn_chance=0x40, shooting_enabled='false', sprite_style='"frames"', animation_frame_ticks=1,
                      contact_effect=f'"{effect}"', contact_damage=0, counts_for_clear='false', invincible_to=f'PackedStringArray({EVERYTHING})')
    elif name == 'pols_voice':
        # UpdatePolsVoice sets mask $FE: only the sword hurts it here.
        fields.update(invincible_to='PackedStringArray("boomerang", "bomb", "fire", "magic")', sprite_style='"frames"', animation_frame_ticks=8,
                      arrow_kills='true')
    elif name == 'wallmaster':
        fields.update(contact_effect='"capture"', spawn_cloud='false', sprite_style='"frames"', animation_frame_ticks=8)
    elif 'wizzrobe' in name:
        # Wizzrobe_DrawAndCheckCollisions: mask $F6; magic shots $58 (blue) and $59 (red).
        shot = 0x58 if name == 'blue_wizzrobe' else 0x59
        raw = prg[0x72BA + shot]
        fields.update(invincible_to='PackedStringArray("boomerang", "arrow", "fire", "magic")', spawn_cloud='false',
                      projectile_kind='"magic"', projectile_speed_subpixels=768, projectile_blockable='false',
                      projectile_damage=(raw & 15) * 2 + (1 if raw & 240 else 0), shooting_enabled='true')
    elif behavior == 'moldorm':
        fields.update(spawn_cloud='false',stunnable='false',shooting_enabled='false',drops_rewards='false',
                      advances_kill_cycle='false',speed_subpixels=128)
        if 'lanmola' in name:
            # InitLamnola: speed is the type minus $39; segments revive at HP $20.
            fields.update(chain_style='"lanmola"', chain_speed=kind - 0x39)
    elif behavior == 'patra':
        # InitPatra: mask $FE (sword only), speed $1F up to $40; Flyer_PatraDecideState
        # chases on random >= $40 for 8 turns. Patra $47 has children $25, $48 has $26.
        fields.update(sprite='&"patra"', stunnable='false', invincible_to=SWORD_ONLY, flight_initial_speed=0x1F,
                      flight_max_speed=0x40, flight_chase_threshold=0x40, flight_turn_count=8, flight_turn_ticks=16,
                      flight_vulnerable_resting_only='false', patra_maneuver_ticks=prg[PATRA_MANEUVER_TIMES])
    elif name == 'ganon':
        # InitGanon: mask $FA (sword and arrow); fireballs $56 cannot be blocked.
        raw = prg[0x72BA + 0x56]
        xs = prg[GANON_START_XS:GANON_START_XS + 2]
        fields.update(size='Vector2i(32, 32)', collision_size='Vector2i(16, 16)', collision_offset='Vector2i(8, 8)',
                      spawn_cloud='false', stunnable='false', drops_rewards='false', advances_kill_cycle='false',
                      invincible_to='PackedStringArray("beam", "boomerang", "bomb", "fire", "magic")', projectile_kind='"fireball"',
                      projectile_blockable='false', projectile_magic_blockable='false', projectile_damage=(raw & 15) * 2 + bool(raw & 240),
                      ganon_spots=f'PackedVector2Array({xs[0]}, {0xA0 - 64}, {xs[1]}, {0xA0 - 64})')
    elif name == 'zelda':
        fields.update(spawn_cloud='false', stunnable='false', contact_damage=0, counts_for_clear='false', counts_for_persistence='false',
                      drops_rewards='false', advances_kill_cycle='false', invincible_to=f'PackedStringArray({EVERYTHING})')
    elif name == 'guard_fire':
        fields.update(spawn_cloud='false', stunnable='false', counts_for_clear='false', counts_for_persistence='false', shooting_enabled='false')
    elif behavior == 'gleeok':
        raw = prg[0x72BA+0x56]
        fields.update(size='Vector2i(24,32)', collision_size='Vector2i(16,16)', collision_offset='Vector2i(8,24)',
                      spawn_cloud='false', stunnable='false', invincible_to=f'PackedStringArray({EVERYTHING})',
                      gleeok_neck_count=kind-0x41, projectile_kind='"fireball"', projectile_blockable='false',
                      projectile_magic_blockable='false', projectile_damage=(raw&15)*2+bool(raw&240))
    elif name == 'manhandla':
        raw = prg[0x72BA + 0x56]
        fields.update(spawn_cloud='false', stunnable='false', sprite_style='"frames"',
                      invincible_to=f'PackedStringArray({EVERYTHING})', projectile_kind='"fireball"',
                      projectile_blockable='false', projectile_magic_blockable='false', projectile_damage=(raw & 15)*2+bool(raw & 240))
    elif name == 'aquamentus':
        # InitAquamentus: mask $E2 (immune to boomerang and fire); fireballs are type $55.
        raw = prg[0x72BA + 0x55]
        fields.update(size='Vector2i(24, 32)', invincible_to='PackedStringArray("boomerang", "fire")', projectile_kind='"fireball"',
                      projectile_damage=(raw & 15) * 2 + (1 if raw & 240 else 0), sprite_style='"frames"', animation_frame_ticks=16)
    elif name == 'dodongo':
        # Dodongo_CheckCollisionsStandardSize: mask $FF until stunned; then any sword hit kills.
        fields.update(health=1, speed_subpixels=128, turn_chance=0x20, shooting_enabled='false', wide_when_horizontal='true',
                      invincible_to='PackedStringArray("beam", "boomerang", "arrow", "bomb", "fire", "magic")', stunnable='false')
    elif 'gohma' in name:
        # InitGohma: mask $FB, arrows only, and only into the open eye; fireballs $56.
        raw = prg[0x72BA + 0x56]
        fields.update(size='Vector2i(48, 16)', invincible_to='PackedStringArray("sword", "beam", "boomerang", "bomb", "fire", "magic")',
                      projectile_kind='"fireball"', projectile_damage=(raw & 15) * 2 + (1 if raw & 240 else 0), stunnable='false',
                      spawn_cloud='false')
    elif 'digdogger' in name:
        # Big Digdoggers cannot be hurt; the recorder splits them (InitDigdogger1/2: 3 or 1 child).
        if name == 'little_digdogger':
            fields.update(spawn_cloud='false')
        else:
            fields.update(size='Vector2i(32, 32)', split_count=3 if name == 'digdogger' else 1, stunnable='false',
                          invincible_to=f'PackedStringArray({EVERYTHING})')
    elif name == 'trap':
        fields.update(invincible_to=f'PackedStringArray({EVERYTHING})', counts_for_clear='false', spawn_cloud='false', sprite_style='"frames"',
                      contact_damage=max(1, fields['contact_damage']))
    return name, fields


def write_monsters(prg, output):
    (output / 'enemies').mkdir(exist_ok=True)
    for kind in MONSTERS:
        name, fields = monster_definition(prg, kind)
        ext = ['[ext_resource type="Script" path="res://scripts/enemy_definition.gd" id="1"]']
        if fields['behavior'] == '"moldorm"':
            segment=fields.copy()
            segment_name=f'{name}_segment'
            segment.update(id=f'&"{segment_name}"',title=json.dumps(segment_name.replace('_',' ').title()),behavior='"moldorm_segment"',counts_for_persistence='false')
            header='[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]\n'+ext[0]+'\n[resource]\nscript = ExtResource("1")\n'
            (output/'enemies'/f'{segment_name}.tres').write_text(header+'\n'.join(f'{key} = {value}' for key,value in segment.items())+'\n')
            ext.append(f'[ext_resource type="Resource" path="res://imported/enemies/{segment_name}.tres" id="segment"]')
            fields['moldorm_segment']='ExtResource("segment")'
        if fields['behavior'] == '"gleeok"':
            head = fields.copy()
            for key in ['size','collision_size','collision_offset','gleeok_neck_count']: head.pop(key,None)
            head.update(id='&"gleeok_head"', title='"Gleeok head"',behavior='"gleeok_head"', nes_type=0x46,
                        health=10, sprite='&"gleeok_head"', counts_for_clear='false',counts_for_persistence='false',
                        advances_kill_cycle='false',loot_table='null', flight_initial_speed=0xBF,flight_max_speed=0xE0,
                        invincible_to='PackedStringArray("boomerang","arrow","bomb","fire","magic")')
            header = '[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]\n'+ext[0]+'\n[resource]\nscript = ExtResource("1")\n'
            (output/'enemies'/'gleeok_head.tres').write_text(header+'\n'.join(f'{key} = {value}' for key,value in head.items())+'\n')
            ext.append('[ext_resource type="Resource" path="res://imported/enemies/gleeok_head.tres" id="head"]')
            fields['gleeok_head'] = 'ExtResource("head")'
        if name == 'manhandla':
            hand = fields.copy()
            hand.update(id='&"manhandla_hand"', title='"Manhandla hand"', counts_for_clear='false', advances_kill_cycle='false',
                        loot_table='null', counts_for_persistence='false', invincible_to='PackedStringArray("boomerang", "fire")')
            header = '[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]\n'+ext[0]+'\n[resource]\nscript = ExtResource("1")\n'
            (output/'enemies'/'manhandla_hand.tres').write_text(header+'\n'.join(f'{key} = {value}' for key,value in hand.items())+'\n')
            ext.append('[ext_resource type="Resource" path="res://imported/enemies/manhandla_hand.tres" id="hand"]')
            fields['boss_hand'] = 'ExtResource("hand")'
        if fields['behavior'] == '"patra"':
            child_kind = 0x25 if kind == 0x47 else 0x26
            child_name = f'{name}_child'
            pair = prg[0x1FB4E + child_kind // 2]
            raw = prg[0x72BA + child_kind]
            # UpdatePatraChild: $25 orbits $2C above at angle step $70, $26 $18 at $60.
            first = child_kind == 0x25
            bits = lambda start: f'PackedInt32Array({prg[PATRA_BITS + start]}, {prg[PATRA_BITS + start + 1]})'
            child = {'id': f'&"{child_name}"', 'title': json.dumps(child_name.replace('_', ' ').title()), 'behavior': '"patra_child"',
                     'nes_type': child_kind, 'health': max(1, pair & 15 if child_kind & 1 else pair >> 4),
                     'contact_damage': (raw & 15) * 2 + (1 if raw & 240 else 0), 'sprite': '&"patra_child"', 'spawn_cloud': 'false',
                     'stunnable': 'false', 'counts_for_persistence': 'false', 'invincible_to': SWORD_ONLY,
                     'orbit_radius': 0x2C if first else 0x18, 'orbit_angle_step': 0x70 if first else 0x60,
                     'orbit_x_bits': bits(2 if first else 1), 'orbit_y_bits': bits(0 if first else 1)}
            header = '[gd_resource type="Resource" script_class="EnemyDefinition" load_steps=2 format=3]\n'+ext[0]+'\n[resource]\nscript = ExtResource("1")\n'
            (output/'enemies'/f'{child_name}.tres').write_text(header+'\n'.join(f'{key} = {value}' for key,value in child.items())+'\n')
            ext.append(f'[ext_resource type="Resource" path="res://imported/enemies/{child_name}.tres" id="child"]')
            fields['patra_child'] = 'ExtResource("child")'
        if name == 'zol':
            ext.append('[ext_resource type="Resource" path="res://imported/enemies/child_gel.tres" id="gel"]')
            fields['splits_into'] = 'ExtResource("gel")'
        if name == 'vire':
            ext.append('[ext_resource type="Resource" path="res://imported/enemies/red_keese.tres" id="keese"]')
            fields['splits_into'] = 'ExtResource("keese")'
        if name in ('digdogger', 'lone_digdogger'):
            ext.append('[ext_resource type="Resource" path="res://imported/enemies/little_digdogger.tres" id="little"]')
            fields['splits_into'] = 'ExtResource("little")'
        text = [f'[gd_resource type="Resource" script_class="EnemyDefinition" load_steps={len(ext) + 1} format=3]'] + ext
        text += ['[resource]', 'script = ExtResource("1")'] + [f'{key} = {value}' for key, value in fields.items()]
        (output / 'enemies' / f'{name}.tres').write_text('\n'.join(text) + '\n')


def sprite_piece(patterns, tile, row, blit_tile, mirrored=False, flip_x=False, flip_y=False, narrow=False):
    """One 16x16 RGBA sprite pair (or a single 8x16 sprite when narrow), as the PPU draws it."""
    bank = patterns[0x1000:] if tile & 1 else patterns
    canvas = bytearray(16 * 16 * 4)
    for column in range(1 if narrow else 2):
        for part in range(2):
            piece = bytearray(8 * 8 * 4)
            blit_tile(piece, 8, 0, 0, bank, (tile & 0xFE) + part + (0 if mirrored or narrow else column * 2), row, True)
            for y in range(8):
                for x in range(8):
                    sx = 7 - x if mirrored and column == 1 else x
                    dx, dy = column * 8 + x, part * 8 + y
                    if flip_x: dx = (7 if narrow else 15) - dx
                    if flip_y: dy = 15 - dy
                    canvas[(dy * 16 + dx) * 4:(dy * 16 + dx) * 4 + 4] = piece[(y * 8 + sx) * 4:(y * 8 + sx) * 4 + 4]
    return canvas


def ganon_sprites(prg, level, patterns, palettes, output, png, blit_tile, names):
    """Ganon_DrawBody, Ganon_DrawAshes, Ganon_DrawCloud, Ganon_DrawBurst."""
    base = prg[0x6E04 + 0x3F]
    sets = prg[GANON_COLOR_SETS:GANON_COLOR_SETS + 9]
    rows = {'brown': [0x0F] + list(sets[0:3]), 'blue': list(prg[GANON_PALETTE + 3:GANON_PALETTE + 7]), 'triforce': [0x0F] + list(sets[6:9])}

    def save(key, width, canvas):
        png(output / f'{key}.png', width, width, canvas)
        names.append(key)

    for colors, row in rows.items():
        if colors == 'triforce': continue
        for pose in range(6):
            canvas = bytearray(32 * 32 * 4)
            for part in range(4):
                image = prg[GANON_FRAME_IMAGES + pose * 4 + part]
                piece = sprite_piece(patterns, prg[0x6E83 + base + image], row, blit_tile, flip_x=part & 1 == 1)
                ox, oy = (part & 1) * 16, (part >> 1) * 16
                for y in range(16):
                    canvas[((oy + y) * 32 + ox) * 4:((oy + y) * 32 + ox + 16) * 4] = piece[y * 64:(y + 1) * 64]
            save(f'l{level}_ganon_{colors}_{pose}', 32, canvas)
    save(f'l{level}_ganon_ashes', 16, sprite_piece(patterns, prg[0x6E83 + base + 0x0B], rows['triforce'], blit_tile))
    for index, image in enumerate((0x0C, 0x0D)):
        save(f'l{level}_ganon_cloud_{index}', 16, sprite_piece(patterns, prg[0x6E83 + base + image], rows['triforce'], blit_tile, mirrored=True))
    # Rays use the slot-indexed tiles and flips; the frame counter picks the palette row.
    for ray in range(8):
        attr, tile = prg[GANON_BURST + 8 + 2 + ray], prg[GANON_BURST + 18 + 2 + ray]
        for palette in range(4):
            row = rows['triforce'] if palette == 3 else palettes[4 + palette]
            save(f'l{level}_ganon_ray_{ray}_{palette}', 16, sprite_piece(patterns, tile, row, blit_tile, flip_x=bool(attr & 0x40), flip_y=bool(attr & 0x80), narrow=True))


def monster_sprites(prg, level, kinds, output, png, blit_tile):
    """Per-level sprites: level-group pattern blocks and the level's sprite palettes."""
    patterns = bytearray(8192)
    for source, length, target in [(32895, 1792, 0), (19892, 2304, 0x0700), (UW_COMMON_SPRITES, 0x100, 0x08E0),
                                    (LEVEL_SPRITES[level], 0x220, 0x09E0), (BOSS_SPRITES[level], 0x400, 0x0C00)]:
        patterns[target:target + length] = prg[source:source + length]
    info = level_info(prg, level)
    palettes = [list(info[3 + p * 4:7 + p * 4]) for p in range(8)]
    names = []

    def render(key, frame, mirrored=False, flip_x=False, narrow=False, palette=None):
        tile, attr = prg[0x6E83 + frame], prg[0x6F4F + frame]
        row = palettes[4 + ((attr if palette is None else palette) & 3)]
        bank = patterns[0x1000:] if tile & 1 else patterns
        canvas = bytearray(16 * 16 * 4)
        for column in range(1 if narrow else 2):
            for part in range(2):
                piece = bytearray(8 * 8 * 4)
                blit_tile(piece, 8, 0, 0, bank, (tile & 0xFE) + part + (0 if mirrored else column * 2), row, True)
                for y in range(8):
                    for x in range(8):
                        sx = 7 - x if mirrored and column == 1 else x
                        dx, dy = column * 8 + x + (4 if narrow else 0), part * 8 + y
                        if flip_x: dx = 15 - dx
                        canvas[(dy * 16 + dx) * 4:(dy * 16 + dx) * 4 + 4] = piece[(y * 8 + sx) * 4:(y * 8 + sx) * 4 + 4]
        png(output / f'{key}.png', 16, 16, canvas)
        names.append(key)

    for kind, name in ((0x3A, 'red_lanmola'), (0x3B, 'blue_lanmola')):
        if kind not in kinds: continue
        # UpdateLamnola: narrow 8x16 sprites, head $9E and body $A0; attributes are speed XOR 3.
        row = palettes[4 + ((kind - 0x39) ^ 3)]
        for part, tile in (('head', 0x9E), ('body', 0xA0)):
            canvas = bytearray(16 * 16 * 4)
            bank = patterns[0x1000:] if tile & 1 else patterns
            for half in range(2): blit_tile(canvas, 16, 4, half * 8, bank, (tile & 0xFE) + half, row, True)
            png(output / f'l{level}_{name}_{part}.png', 16, 16, canvas)
            names.append(f'l{level}_{name}_{part}')
        kinds = kinds - {kind}
    if 0x3E in kinds:
        ganon_sprites(prg, level, patterns, palettes, output, png, blit_tile, names)
        kinds = kinds - {0x3E}
    if 0x37 in kinds:
        # Person_Draw: frame 0, mirrored, table attribute.
        render(f'l{level}_zelda', prg[0x6E04 + 0x38], mirrored=True)
        # UpdateGuardFire: frame 0, flipped on alternate poses.
        for pose in range(2): render(f'l{level}_guard_fire_{pose}', prg[0x6E04 + 0x40], flip_x=pose == 1)
        kinds = kinds - {0x37, 0x3F}
    if kinds & {0x47, 0x48}:
        # UpdatePatra: frame 0, not mirrored, flipped horizontally every other pose.
        base = prg[0x6E04 + 0x48]
        for pose in range(2): render(f'l{level}_patra_{pose}', base, flip_x=pose == 1)
        # PatraChild_Draw: half-width (attribute $C3), red row 6, tiles alternating.
        base = prg[0x6E04 + 0x26]
        for pose in range(2):
            tile = prg[0x6E83 + base + pose]
            canvas = bytearray(16 * 16 * 4)
            bank = patterns[0x1000:] if tile & 1 else patterns
            for half in range(2): blit_tile(canvas, 16, 0, half * 8, bank, (tile & 0xFE) + half, palettes[6], True)
            png(output / f'l{level}_patra_child_{pose}.png', 16, 16, canvas)
            names.append(f'l{level}_patra_child_{pose}')
        kinds = kinds - {0x47, 0x48}
    if 0x41 in kinds:
        # UpdateMoldorm draws one normal, red-palette 8x16 sprite at tile $44.
        canvas=bytearray(16*16*4)
        for half in range(2):blit_tile(canvas,16,0,half*8,patterns,0x44+half,palettes[6],True)
        key=f'l{level}_moldorm'
        png(output/f'{key}.png',16,16,canvas);names.append(key)
        kinds=kinds-{0x41}
    if kinds & {0x42,0x43,0x44,0x45}:
        row = palettes[7]
        # GleeokBodyTiles0..2 and GleeokBodyBaseTileOffsets, in the verified ROM.
        for frame in range(4):
            offset = prg[0x1281B+frame]
            canvas = bytearray(24*32*4)
            for part in range(6):
                tile = prg[0x12809+offset+part]
                for half in range(2): blit_tile(canvas,24,(part%3)*8,(part//3)*16+half*8,patterns,(tile&254)+half,row,True)
            key = f'l{level}_gleeok_body_{frame}'
            png(output/f'{key}.png',24,32,canvas);names.append(key)
        for name,tile in [('neck',0xDA),('head',0xDC)]:
            canvas = bytearray(16*16*4)
            for half in range(2): blit_tile(canvas,16,0,half*8,patterns,tile+half,row,True)
            key=f'l{level}_gleeok_{name}'
            png(output/f'{key}.png',16,16,canvas);names.append(key)
        base=prg[0x6E04+0x47]
        for pose in range(2): render(f'l{level}_gleeok_flying_{pose}',base+pose,mirrored=True)
        kinds=kinds-{0x42,0x43,0x44,0x45}
    if 0x3C in kinds:
        base = prg[0x6E04+0x3D]
        for part,offset in [('up',0),('down',0),('left',2),('right',2),('body',4)]:
            for pose in range(2):
                key = f'l{level}_manhandla_{part}_{pose}'
                render(key,base+offset+pose,mirrored=part not in ('left','right'),flip_x=part=='right',palette=1)
                if part == 'down':
                    # NES vertical flip applies to each complete 8x16 sprite.
                    # Redraw the vertically flipped, mirrored pair.
                    tile = prg[0x6E83+base+offset+pose]
                    canvas = bytearray(16*16*4)
                    for col in range(2):
                        for row_index in range(2):
                            block = bytearray(8*8*4)
                            blit_tile(block,8,0,0,patterns,tile+row_index,palettes[5],True)
                            for y in range(8):
                                for x in range(8):
                                    src=(y*8+(7-x if col else x))*4
                                    dst=((15-row_index*8-y)*16+col*8+x)*4
                                    canvas[dst:dst+4]=block[src:src+4]
                    png(output/f'{key}.png',16,16,canvas)
        kinds = kinds-{0x3C}
    if 0x3D in kinds:
        # Aquamentus_Draw: six 8x16 sprites, AquamentusTiles frames, its own palette row.
        row = list(prg[AQUAMENTUS_PALETTE + 3:AQUAMENTUS_PALETTE + 7])
        for frame in range(2):
            canvas = bytearray(24 * 32 * 4)
            for part in range(6):
                tile = prg[AQUAMENTUS_TILES + frame * 6 + part]
                bank = patterns[0x1000:] if tile & 1 else patterns
                for half in range(2):
                    blit_tile(canvas, 24, (part % 3) * 8, (part // 3) * 16 + half * 8, bank, (tile & 0xFE) + half, row, True)
            png(output / f'l{level}_aquamentus_{frame}.png', 24, 32, canvas)
            names.append(f'l{level}_aquamentus_{frame}')
        # Fireballs ($55) flash between the red and blue rows.
        tile = prg[0x6E83 + prg[0x6E04 + 0x55 + 1]]
        for frame, palette in enumerate((6, 5)):
            canvas = bytearray(16 * 16 * 4)
            bank = patterns[0x1000:] if tile & 1 else patterns
            for half in range(2):
                blit_tile(canvas, 16, 4, half * 8, bank, (tile & 0xFE) + half, palettes[palette], True)
            png(output / f'fireball_{frame}.png', 16, 16, canvas)
            if f'fireball_{frame}' not in names: names.append(f'fireball_{frame}')
        kinds = kinds - {0x3D}
    if kinds & {0x31, 0x32}:
        base = prg[0x6E04 + 0x31 + 1]
        # The level palette row, which boss rooms load from OrangeBossPaletteRow7TransferBuf.
        row = list(prg[ORANGE_BOSS_PALETTE + 3:ORANGE_BOSS_PALETTE + 7])

        def image(index, mirrored):
            tile = prg[0x6E83 + base + index]
            bank = patterns[0x1000:] if tile & 1 else patterns
            canvas = bytearray(16 * 16 * 4)
            for column in range(2):
                for half in range(2):
                    piece = bytearray(8 * 8 * 4)
                    blit_tile(piece, 8, 0, 0, bank, (tile & 0xFE) + half + (0 if mirrored else column * 2), row, True)
                    for y in range(8):
                        for x in range(8):
                            sx = 7 - x if mirrored and column == 1 else x
                            canvas[((half * 8 + y) * 16 + column * 8 + x) * 4:((half * 8 + y) * 16 + column * 8 + x) * 4 + 4] = piece[(y * 8 + sx) * 4:(y * 8 + sx) * 4 + 4]
            return canvas

        def flip(canvas, width, height):
            out = bytearray(len(canvas))
            for y in range(height):
                for x in range(width):
                    out[(y * width + x) * 4:(y * width + x) * 4 + 4] = canvas[(y * width + width - 1 - x) * 4:(y * width + width - 1 - x) * 4 + 4]
            return out

        def wide(first):
            left, right = image(first, False), image(first ^ 1, False)
            canvas = bytearray(32 * 16 * 4)
            for y in range(16):
                canvas[y * 128:y * 128 + 64] = left[y * 64:y * 64 + 64]
                canvas[y * 128 + 64:y * 128 + 128] = right[y * 64:y * 64 + 64]
            return canvas

        def save(key, canvas, width):
            png(output / f'l{level}_{key}.png', width, 16, canvas)
            names.append(f'l{level}_{key}')

        for pose in range(2):
            right = wide(DODONGO_IMAGES[pose * 5])
            save(f'dodongo_right_{pose}', right, 32)
            save(f'dodongo_left_{pose}', flip(right, 32, 16), 32)
            for direction, slot in (('down', 2), ('up', 4)):
                canvas = image(DODONGO_IMAGES[pose * 5 + slot], False)
                save(f'dodongo_{direction}_{pose}', flip(canvas, 16, 16) if pose else canvas, 16)
        bloated = wide(DODONGO_BLOATED[0])
        save('dodongo_bloated_right', bloated, 32)
        save('dodongo_bloated_left', flip(bloated, 32, 16), 32)
        save('dodongo_bloated_down', image(DODONGO_BLOATED[2], True), 16)
        save('dodongo_bloated_up', image(DODONGO_BLOATED[4], True), 16)
        kinds = kinds - {0x31, 0x32}
    if kinds & {0x33, 0x34}:
        # Gohma_AnimateAndDraw: eye image 0-3 in the middle, leg images 4-5 at -16 and +16.
        base = prg[0x6E04 + 0x33 + 1]
        for kind, prefix in ((0x33, 'blue_gohma'), (0x34, 'red_gohma')):
            if kind not in kinds: continue
            row = palettes[4 + kind - 0x32]   # Gohma_SetSpriteAttributes: type - $32.
            for eye in range(4):
                for pose in range(2):
                    canvas = bytearray(48 * 16 * 4)
                    parts = [(4 + ((pose + 1) & 1), 0, False, True), (eye, 16, True, False), (4 + (pose & 1), 32, False, False)]
                    for index, x0, mirrored, flipped in parts:
                        tile = prg[0x6E83 + base + index]
                        bank = patterns[0x1000:] if tile & 1 else patterns
                        for column in range(2):
                            for half in range(2):
                                piece = bytearray(8 * 8 * 4)
                                blit_tile(piece, 8, 0, 0, bank, (tile & 0xFE) + half + (0 if mirrored else column * 2), row, True)
                                for y in range(8):
                                    for x in range(8):
                                        sx = 7 - x if mirrored and column == 1 else x
                                        dx = column * 8 + x
                                        if flipped: dx = 15 - dx
                                        offset = ((half * 8 + y) * 48 + x0 + dx) * 4
                                        if piece[(y * 8 + sx) * 4 + 3]: canvas[offset:offset + 4] = piece[(y * 8 + sx) * 4:(y * 8 + sx) * 4 + 4]
                    png(output / f'l{level}_{prefix}_{eye}_{pose}.png', 48, 16, canvas)
                    names.append(f'l{level}_{prefix}_{eye}_{pose}')
        kinds = kinds - {0x33, 0x34}
    if kinds & {0x38, 0x39, 0x18}:
        # Digdogger_Draw: one image in four flipped quarters, the little face drawn over its middle.
        row = list(prg[ORANGE_BOSS_PALETTE + 3:ORANGE_BOSS_PALETTE + 7])
        def blit16(canvas, width, x0, y0, tile, flip_x, flip_y):
            bank = patterns[0x1000:] if tile & 1 else patterns
            for column in range(2):
                for half in range(2):
                    piece = bytearray(8 * 8 * 4)
                    blit_tile(piece, 8, 0, 0, bank, (tile & 0xFE) + half + column * 2, row, True)
                    for y in range(8):
                        for x in range(8):
                            dx, dy = column * 8 + x, half * 8 + y
                            if flip_x: dx = 15 - dx
                            if flip_y: dy = 15 - dy
                            if piece[(y * 8 + x) * 4 + 3]:
                                offset = ((y0 + dy) * width + x0 + dx) * 4
                                canvas[offset:offset + 4] = piece[(y * 8 + x) * 4:(y * 8 + x) * 4 + 4]
        big = prg[0x6E83 + prg[0x6E04 + 0x38 + 1]]
        little = prg[0x6E04 + 0x18 + 1]
        for pose in range(2):
            face = prg[0x6E83 + little + pose]
            canvas = bytearray(32 * 32 * 4)
            for part, (x0, y0) in enumerate(((0, 0), (16, 0), (0, 16), (16, 16))):
                blit16(canvas, 32, x0, y0, big, part & 1 == 1, part >= 2)
            blit16(canvas, 32, 8, 8, face, False, False)
            for name in ('digdogger', 'lone_digdogger'):
                png(output / f'l{level}_{name}_{pose}.png', 32, 32, canvas)
                names.append(f'l{level}_{name}_{pose}')
            small = bytearray(16 * 16 * 4)
            blit16(small, 16, 0, 0, face, False, False)
            png(output / f'l{level}_little_digdogger_{pose}.png', 16, 16, small)
            names.append(f'l{level}_little_digdogger_{pose}')
        kinds = kinds - {0x38, 0x39, 0x18}
    for kind in sorted(kinds):
        name, behavior = MONSTERS[kind]
        base = prg[0x6E04 + kind + 1]
        prefix = f'l{level}_{name}'
        if 'wizzrobe' in name:
            # Wizzrobe_DrawAndCheckCollisions: up uses frames 2 and 3; left flips.
            for direction in ('up', 'down', 'left', 'right'):
                for pose in range(2):
                    render(f'{prefix}_{direction}_{pose}', base + (2 if direction == 'up' else 0) + pose, flip_x=direction == 'left')
        elif name in ('blue_goriya', 'red_goriya'):
            for direction in ('up', 'down', 'left', 'right'):
                for pose in range(2):
                    frame = base + (3 if direction == 'up' else 2 if direction == 'down' else pose)
                    render(f'{prefix}_{direction}_{pose}', frame, flip_x=(pose == 1 if direction in ('up', 'down') else direction == 'left'))
        elif name == 'stalfos':
            # AnimateAndDrawCommonObject: one image, flipped every eight frames.
            render(f'{prefix}_0', base, mirrored=True)
            render(f'{prefix}_1', base, mirrored=True, flip_x=True)
        elif behavior == 'gel' and name != 'zol':
            for pose in range(2): render(f'{prefix}_{pose}', base + pose, narrow=True, palette=3)
        elif name in ('red_darknut', 'blue_darknut'):
            # UpdateDarknut: base + 0 sideways, 1 down, 2 up; +3 for the second pose; up flips it.
            for pose in range(2):
                for direction, step in (('right', 0), ('left', 0), ('down', 1), ('up', 2)):
                    render(f'{prefix}_{direction}_{pose}', base + step + 3 * pose, flip_x=direction == 'left' or (direction == 'up' and pose == 1))
        elif name == 'vire':
            # DrawVire: up uses frames 2 and 3, otherwise 0 and 1.
            for pose in range(2):
                for direction in ('up', 'down', 'left', 'right'):
                    render(f'{prefix}_{direction}_{pose}', base + (2 if direction == 'up' else 0) + pose, mirrored=True)
        elif name in ('gibdo', 'trap') or 'bubble' in name:
            # One image, flipped by the animation counter; bubbles also alternate palettes.
            palettes_for = {'bubble': (1, 2), 'blue_bubble': (1, 1), 'red_bubble': (2, 2)}.get(name, (None, None))
            render(f'{prefix}_0', base, palette=palettes_for[0])
            render(f'{prefix}_1', base, flip_x=name != 'trap', palette=palettes_for[1])
        elif behavior == 'rope':
            for pose in range(2):
                for direction in ('up', 'down', 'right', 'left'):
                    render(f'{prefix}_{direction}_{pose}', base + pose, flip_x=direction == 'left')
        else:
            for pose in range(2): render(f'{prefix}_{pose}', base + pose, mirrored=True)
    return names


def enemy_lines(level, types, positions=None, room=0):
    """EnemySpawn sub-resources; source spawn lists place them unless positions are given."""
    ext = ['[ext_resource type="Script" path="res://scripts/enemy_spawn.gd" id="enemy_spawn"]']
    for kind in sorted(set(types)):
        ext.append(f'[ext_resource type="Resource" path="res://imported/enemies/{MONSTERS[kind][0]}.tres" id="enemy_{kind}"]')
    subs = []
    trap = 0
    fire = 0
    for i, kind in enumerate(types):
        x, y = positions[i] if positions else (120, 77)
        if kind == 0x49:
            x, y = TRAPS[trap][0], TRAPS[trap][1] - 64
            trap += 1
        elif kind == 0x3F:
            fire += 1
            x, y = GUARD_FIRE_SPOTS[fire][0], GUARD_FIRE_SPOTS[fire][1] - 64
        elif kind in FIXED_POSITIONS:
            x, y = FIXED_POSITIONS[kind][0], FIXED_POSITIONS[kind][1] - 64
        subs += [f'[sub_resource type="Resource" id="enemy_{i}"]', 'script = ExtResource("enemy_spawn")', f'id = &"slot_{i}"',
                 f'enemy = ExtResource("enemy_{kind}")', f'position = Vector2i({x}, {y})', 'facing = Vector2i(0, 0)',
                 f'seed_value = {level * 977 + room * 31 + i + 1}', f'spawn_ticks = {i + 1}']
    return ext, subs, 'enemies = Array[Resource]([' + ', '.join(f'SubResource("enemy_{i}")' for i in range(len(types))) + '])'
