"""Overworld caves, cave residents, item sprites, and overworld secrets.

See docs/CAVES_AND_SECRETS.md for the routines behind these tables:
Z_01 InitCave and UpdateCavePerson, Z_05 HandleWarpOW and CheckTileObject,
Z_04 UpdateRockWall, UpdateTree, and UpdateRockOrGravestone.
"""
import json
import struct

OW_ATTRS = 99328          # Overworld level block attributes A-F, 128 bytes each.
LEVEL_INFO = 103168       # Overworld level info.
PERSON_TEXT_ADDRS = 0x4000
TEXT_SELECTORS = 0x45A2   # OverworldPersonTextSelectors, one per cave type.
HINT_SELECTORS = 0x493B   # HintCaveTextSelectors0 and 1.
PRIMARY_SQUARES = 0x1697C
ITEM_ID_TO_SLOT = 0x6B14
ITEM_ID_TO_DESCRIPTOR = 0x6B38
ITEM_SLOT_PALETTES = 0x6B5C
ITEM_FRAME_OFFSETS = 0x7127
ITEM_FRAME_TILES = 0x714C
CAVE_LAYOUT = 89000
SHORTCUT_LAYOUT = 89016
FIRST_CAVE = 0x10
SHORTCUT_CAVE = 0x14
NO_ITEM = 0x3F
SQUARE_CAVE = 0x0C
# LayoutRoomOrCaveOW writes square $10 with primary $70; square 18 has that primary.
SQUARE_STAIRS = 18
SQUARE_FLOOR = 0x0E
# ROM item IDs supported by native content definitions under content/items.
ITEMS = {0x00: 'bombs', 0x01: 'wooden_sword', 0x02: 'white_sword', 0x03: 'magical_sword',
         0x04: 'bait', 0x06: 'blue_candle', 0x08: 'arrows', 0x0F: 'five_rupees',
         0x12: 'blue_ring', 0x15: 'letter', 0x18: 'rupee', 0x19: 'key',
         0x1A: 'heart_container', 0x1C: 'magic_shield', 0x1F: 'blue_potion',
         0x20: 'red_potion', 0x22: 'heart'}
# Sprites that already exist as two-frame drop animations.
ANIMATED_ITEMS = {'rupee', 'five_rupees', 'heart'}
TEXT_CHARS = {0x24: ' ', 0x25: ' ', 0x28: ',', 0x29: '.', 0x2A: "'", 0x2C: '!',
              0x2D: '"', 0x2E: '?', 0x2F: '-'}
SECRET_KINDS = {0xE5: 'rock', 0xE6: 'wall', 0xE7: 'tree', 0xE8: 'grave'}


def person_text(prg, selector):
    """Z_01 UpdatePersonState_Textbox: high bits end a line or the message."""
    address = struct.unpack_from('<H', prg, PERSON_TEXT_ADDRS + selector)[0] - 0x8000 + 0x4000
    text = ''
    for offset in range(256):
        byte = prg[address + offset]
        code = byte & 0x3F
        if code < 10: text += chr(48 + code)
        elif code < 36: text += chr(55 + code)
        elif code in TEXT_CHARS: text += TEXT_CHARS[code]
        else: raise ValueError(f'Unsupported text character ${code:02X}')
        if byte & 0xC0 == 0xC0: return text
        if byte & 0xC0: text += '\n'
    raise ValueError('Unterminated person text')


def cave_types(prg):
    """InitCave: three wares and prices per type, flags split across their high bits."""
    caves = []
    for index in range(20):
        kind = 0x6A + index
        selector = prg[TEXT_SELECTORS + index]
        wares = prg[OW_ATTRS + 512 + index * 3:OW_ATTRS + 512 + index * 3 + 3]
        prices = prg[OW_ATTRS + 572 + index * 3:OW_ATTRS + 572 + index * 3 + 3]
        flags = ((selector >> 6) & 1) | ((selector >> 6) & 2)
        flags |= (wares[2] & 0xC0) >> 4 | (wares[1] & 0xC0) >> 2 | (wares[0] & 0xC0)
        hints = None
        if flags & 0x10:
            base = 0 if kind == 0x75 else 3
            hints = [person_text(prg, prg[HINT_SELECTORS + base + i]) for i in range(3)]
        items = []
        for i, ware in enumerate(wares):
            item = ware & 0x3F
            if item == NO_ITEM:
                items.append(None)
                continue
            if item not in ITEMS:
                raise ValueError(f'Cave ${kind:02X} sells unsupported item ${item:02X}')
            items.append({'item': ITEMS[item], 'price': prices[i], 'hint': hints[i] if hints else ''})
        caves.append({'type': kind, 'id': f'cave_{kind:02x}', 'text': person_text(prg, selector & 0x3F), 'wares': items,
                      'choose': bool(flags & 1), 'pay': bool(flags & 2), 'show_items': bool(flags & 4),
                      'show_prices': bool(flags & 8), 'hint': bool(flags & 0x10),
                      'money_game': bool(flags & 0x20) and kind < 0x7B, 'gift_money': kind >= 0x7B,
                      'heart_requirement': (5 if kind == 0x6C else 12) if flags & 0x40 else 0,
                      'negative_prices': bool(flags & 0x80),
                      'remember': kind < 0x6E or kind in (0x71, 0x72) or kind >= 0x7B,
                      'door_charge': 20 if kind == 0x71 else 0, 'requires_letter': kind == 0x74})
    return caves


def cave_resource(cave):
    ext = ['[ext_resource type="Script" path="res://scripts/cave_definition.gd" id="cave"]',
           '[ext_resource type="Script" path="res://scripts/cave_ware.gd" id="ware"]']
    subs, wares = [], []
    for name in sorted({ware['item'] for ware in cave['wares'] if ware}):
        ext.append(f'[ext_resource type="Resource" path="res://content/items/{name}.tres" id="{name}"]')
    for i, ware in enumerate(cave['wares']):
        if ware is None:
            wares.append('null')
            continue
        subs += [f'[sub_resource type="Resource" id="ware_{i}"]', 'script = ExtResource("ware")',
                 f'item = ExtResource("{ware["item"]}")', f'price = {ware["price"]}', f'hint = {json.dumps(ware["hint"], ensure_ascii=False)}']
        wares.append(f'SubResource("ware_{i}")')
    sprite = {0x98: 'old_man', 0x9A: 'old_woman', 0x9C: 'merchant', 0xF8: 'cave_moblin'}[cave['person_tile']]
    fields = [f'id = &"{cave["id"]}"', f'person_sprite = &"{sprite}"', f'text = {json.dumps(cave["text"], ensure_ascii=False)}',
              'wares = Array[Resource]([' + ', '.join(wares) + '])']
    for key in ('choose', 'pay', 'show_items', 'show_prices', 'negative_prices', 'hint', 'money_game', 'remember', 'gift_money', 'requires_letter'):
        fields.append(f'{key} = {str(cave[key]).lower()}')
    fields += [f'heart_requirement = {cave["heart_requirement"]}', f'door_charge = {cave["door_charge"]}']
    return resource_text('CaveDefinition', ext + subs + ['[resource]', 'script = ExtResource("cave")'] + fields)


def resource_text(script_class, lines):
    steps = sum(line.startswith(('[ext_resource', '[sub_resource')) for line in lines) + 1
    return '\n'.join([f'[gd_resource type="Resource" script_class="{script_class}" load_steps={steps} format=3]'] + lines) + '\n'


def render_item(prg, patterns, palettes, tile, attr, blit_tile):
    """Z_01 Anim_WriteSpecificItemSprites: narrow, slim, mirrored, or flippable pairs."""
    canvas = bytearray(16 * 16 * 4)
    bank = patterns[0x1000:] if tile & 1 else patterns
    base = tile & 0xFE
    palette = palettes[4 + (attr & 3)]
    narrow = tile == 0xF3 or 0x20 <= tile < 0x62
    columns = [(4, base, False)] if narrow else [(0, base, False), (7 if tile < 0x6C else 8, base if 0x6C <= tile < 0x7C else base + 2, 0x6C <= tile < 0x7C)]
    for x0, top, mirrored in columns:
        for row in range(2):
            block = bytearray(8 * 8 * 4)
            blit_tile(block, 8, 0, 0, bank, top + row, palette, transparent=True)
            for y in range(8):
                for x in range(8):
                    source = (y * 8 + (7 - x if mirrored else x)) * 4
                    if block[source + 3] == 0: continue
                    target = ((row * 8 + y) * 16 + x0 + x) * 4
                    canvas[target:target + 4] = block[source:source + 4]
    return canvas


def item_tile(prg, item_id, frame=0):
    """Z_07 DrawItemBySlot: palette by slot, plus grade for color-varying slots."""
    slot = prg[ITEM_ID_TO_SLOT + item_id]
    value = prg[ITEM_ID_TO_DESCRIPTOR + item_id] & 0x0F
    attr = prg[ITEM_SLOT_PALETTES + slot]
    if slot in (0x16, 0x19, 0x1A, 0x1B):
        attr = 1
    elif slot in (0x00, 0x02, 0x04, 0x07, 0x0B):
        attr = (attr + value) & 0xFF
        if slot == 0 and attr == 2:
            slot = 0x20
    return prg[ITEM_FRAME_TILES + prg[ITEM_FRAME_OFFSETS + slot] + frame], attr


def export_item_sprites(prg, patterns, palettes, output, png, blit_tile):
    names = []
    def write(name, tile, attr, flip_x=False, flip_y=False):
        canvas = render_item(prg, patterns, palettes, tile, attr, blit_tile)
        if flip_x or flip_y:
            flipped = bytearray(len(canvas))
            for y in range(16):
                for x in range(16):
                    sx, sy = (15 - x if flip_x else x), (15 - y if flip_y else y)
                    flipped[(y * 16 + x) * 4:(y * 16 + x) * 4 + 4] = canvas[(sy * 16 + sx) * 4:(sy * 16 + sx) * 4 + 4]
            canvas = flipped
        png(output / f'{name}.png', 16, 16, canvas)
        names.append(name)
    for item_id, name in ITEMS.items():
        if name in ANIMATED_ITEMS or name == 'wooden_sword': continue
        write(name, *item_tile(prg, item_id))
    # Bomb smoke uses item slot 1 frames 1 and 2 with the blue palette row.
    for frame in (1, 2):
        write(f'bomb_cloud_{frame}', prg[ITEM_FRAME_TILES + prg[ITEM_FRAME_OFFSETS + 1] + frame], 1)
    # Held swords: grade palettes on the wooden sword's vertical and side tiles.
    for name, attr in (('white_sword', 1), ('magical_sword', 2)):
        write(f'{name}_up', 0x20, attr)
        write(f'{name}_down', 0x20, attr, flip_y=True)
        write(f'{name}_right', 0x82, attr)
        write(f'{name}_left', 0x82, attr, flip_x=True)
    return names


def export_people(prg, patterns, palettes, output, png, blit_tile):
    """Cave residents: object type $6A + cave index, animation table index type + 1."""
    animations = prg[0x6E04:0x6E83]
    names, tiles = [], {}
    for kind in range(0x6A, 0x7E):
        frame = animations[kind + 1]
        tile, attr = prg[0x6E83 + frame], prg[0x6F4F + frame] & 3
        tiles[kind] = tile
        name = {0x98: 'old_man', 0x9A: 'old_woman', 0x9C: 'merchant', 0xF8: 'cave_moblin'}[tile]
        if name in names: continue
        canvas = bytearray(16 * 16 * 4)
        bank = patterns[0x1000:] if tile & 1 else patterns
        mirrored = kind < 0x7B
        for column in range(2):
            for row in range(2):
                block = bytearray(8 * 8 * 4)
                top = (tile & 0xFE) + (0 if mirrored else column * 2)
                blit_tile(block, 8, 0, 0, bank, top + row, palettes[4 + attr], transparent=True)
                for y in range(8):
                    for x in range(8):
                        source = (y * 8 + (7 - x if mirrored and column else x)) * 4
                        target = ((row * 8 + y) * 16 + column * 8 + x) * 4
                        canvas[target:target + 4] = block[source:source + 4]
        png(output / f'{name}.png', 16, 16, canvas)
        names.append(name)
    return names, tiles


def overworld_entrances(prg, layouts, square_tiles):
    """Per room: destination, visible entrances, the tile-object secret, and exit."""
    primary = prg[PRIMARY_SQUARES:PRIMARY_SQUARES + 56]
    positions = prg[LEVEL_INFO + 0x29:LEVEL_INFO + 0x2D]
    rooms = {}
    for room_id, layout in enumerate(layouts):
        destination = prg[OW_ATTRS + 128 + room_id] >> 2
        attr_f = prg[OW_ATTRS + 640 + room_id]
        visible, secret = [], None
        for y, row in enumerate(layout):
            for x, square in enumerate(row):
                tile = square_tiles(prg, square)[1]
                if tile in (0x24, 0x88) or 0x70 <= tile <= 0x73:
                    visible.append({'cell': (x, y), 'mouth': tile == 0x24})
                kind = SECRET_KINDS.get(primary[square])
                # IsQuestSecretMismatch: quest-secret value 2 is second quest only.
                if kind and attr_f >> 6 != 2:
                    secret = {'kind': kind, 'cell': (x, y), 'square': square}
        if secret and secret['kind'] in ('rock', 'grave'):
            position = positions[(attr_f >> 4) & 3]
            cell = ((position & 0xF0) // 16, (position & 0x0F) - 4)
            secret['reveal'] = cell
            # Z_05 CheckShortcut: stairs return on later visits unless a gravestone stands there.
            secret['persistent'] = square_tiles(prg, layout[cell[1]][cell[0]])[0] != 0xBC
        elif secret:
            secret['reveal'] = secret['cell']
            secret['persistent'] = True
        rooms[room_id] = {'destination': destination, 'visible': visible, 'secret': secret,
                          'exit': (prg[OW_ATTRS + room_id] & 0xF0, (attr_f & 7) * 16 + 13)}
    return rooms


def secret_resource(prg, entrance, layout, palette_for, square_tiles, walkable):
    """A SecretDefinition sub-resource body for an overworld room."""
    secret = entrance['secret']
    trigger = {'wall': 'bomb', 'tree': 'fire', 'grave': 'push', 'rock': 'bracelet_push'}[secret['kind']]
    reveal_square = SQUARE_CAVE if secret['kind'] == 'wall' else SQUARE_STAIRS
    def collision(square):
        return [int(tile >= 0x89 and tile not in walkable) for tile in square_tiles(prg, square)]
    cell, reveal = secret['cell'], secret['reveal']
    lines = ['script = ExtResource("secret")', f'trigger = "{trigger}"',
             f'cell = Vector2i({cell[0]}, {cell[1]})', f'reveal_cell = Vector2i({reveal[0]}, {reveal[1]})',
             f'reveal_tile = {palette_for(*reveal) * 64 + reveal_square}',
             f'reveal_collision = PackedByteArray({", ".join(map(str, collision(reveal_square)))})',
             f'persistent = {str(secret["persistent"]).lower()}']
    if trigger in ('push', 'bracelet_push'):
        lines += [f'floor_tile = {palette_for(*cell) * 64 + SQUARE_FLOOR}',
                  f'object_tile = {palette_for(*cell) * 64 + secret["square"]}',
                  f'object_collision = PackedByteArray({", ".join(map(str, collision(secret["square"])))})']
    return lines


def portal_lines(area, target, position, facing, walk=0, direction=(0, 0), rise=0, requires_secret=False):
    lines = ['script = ExtResource("portal")', f'area = Rect2i({area[0]}, {area[1]}, {area[2]}, {area[3]})',
             f'required_direction = Vector2i({direction[0]}, {direction[1]})', f'target_room = &"{target}"',
             f'target_position = Vector2i({position[0]}, {position[1]})', f'target_facing = Vector2i({facing[0]}, {facing[1]})',
             f'entry_walk_pixels = {walk}']
    if rise: lines.append(f'exit_rise_pixels = {rise}')
    if requires_secret: lines.append('requires_secret = true')
    return lines


def cave_room(room_id, cave_index, entrance, cellar, rooms, layouts):
    """One interior per overworld entrance, so taken state is per room as in the original."""
    shortcut = cave_index == SHORTCUT_CAVE
    layout = layouts['shortcut' if shortcut else 'cave']
    mouth = entrance['mouth']
    exit_x, exit_y = entrance['exit']
    subs = ['[sub_resource type="Resource" id="exit"]'] + portal_lines(
        (104, 157, 32, 1), f'ow_{room_id:02x}', (exit_x, exit_y), (0, 1), direction=(0, 1), rise=16 if mouth else 0)
    portals = ['SubResource("exit")']
    if shortcut:
        # Z_05 mode $C: stairs n of 3 lead n rooms further around the cellar list.
        index = cellar.index(room_id)
        for n, x in enumerate((80, 128, 176), start=1):
            target = cellar[(index + n) & 3]
            subs += [f'[sub_resource type="Resource" id="stairs_{n}"]'] + portal_lines(
                (x, 93, 1, 1), f'ow_{target:02x}', rooms[target]['exit'], (0, 1))
            portals.append(f'SubResource("stairs_{n}")')
    for name, x in (('fire_left', 72), ('fire_right', 168)):
        subs += [f'[sub_resource type="Resource" id="{name}"]', 'script = ExtResource("decoration")',
                 f'position = Vector2i({x}, 64)', 'sprite = &"fire"', 'frames = 2', 'frame_ticks = 6',
                 f'blocking_area = Rect2i({x}, 64, 16, 16)']
    indices, collision, coarse = layout
    cave_type = 0x6A + cave_index - FIRST_CAVE
    return resource_text('RoomDefinition', [
        '[ext_resource type="Script" path="res://scripts/room_definition.gd" id="room"]',
        '[ext_resource type="Texture2D" path="res://imported/cave_tiles.png" id="atlas"]',
        '[ext_resource type="Script" path="res://scripts/portal_definition.gd" id="portal"]',
        '[ext_resource type="Script" path="res://scripts/decoration_definition.gd" id="decoration"]',
        f'[ext_resource type="Resource" path="res://imported/caves/cave_{cave_type:02x}.tres" id="cave"]']
        + subs + ['[resource]', 'script = ExtResource("room")', f'id = &"cave_{room_id:02x}"', 'music = &"cave"',
                  f'history_id = &"ow_{room_id:02x}"', f'title = "Cave {room_id:02X}"', f'map_room_id = {room_id}',
                  f'tiles = {json.dumps(chr(10).join(coarse))}', 'spawn = Vector2i(112, 109)',
                  'movement_bounds = Rect2i(0, -3, 241, 161)', 'grid_origin = Vector2i(0, 5)',
                  'tile_atlas = ExtResource("atlas")', f'tile_indices = PackedInt32Array({", ".join(map(str, indices))})',
                  f'collision_tiles = PackedByteArray({", ".join(map(str, collision))})',
                  'portals = Array[Resource]([' + ', '.join(portals) + '])',
                  'decorations = Array[Resource]([SubResource("fire_left"), SubResource("fire_right")])',
                  'cave = ExtResource("cave")'])
