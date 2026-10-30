"""The pause submenu (Z_05 UpdateMenu and its Submenu_* routines).

Backdrops are built the way the original builds NT2: the static transfer
buffers named by SubmenuTransferBufSelectorsOW/UW are applied to a blank
nametable, which is cropped to the 22 rows shown while the menu is open (NT2
rows 8-29). Pieces that change with the game (Triforce tiles, sheet-map marks)
are exported as tile atlases plus a layout resource; the runtime reapplies the
original rules (UpdateMenuStartOW, Submenu_WriteScanningMapRoomMark).
"""
import struct

TRANSFER_BUF_ADDRS = 0x1A000       # Z_06 TransferBufAddrs; bank 6 data sits at CPU address + $10000.
TRIFORCE_TEMPLATES = 0x19D2F       # Z_06 TriforceRow0-3TransferBuf, then TriforceTextTransferBuf (copied to RAM).
TRIFORCE_TABLES = 0x14152          # Z_05 TriforceTransferBufOffsets, Replacements, Tiles: 24 bytes each.
LEVEL_INFO_ROTATION = 0x2D         # LevelInfo_SubmenuMapRotation, relative to the level info block.
LEVEL_INFO_MASK = 0x3F             # LevelInfo_SubmenuMapMask, 16 bytes.
LEVEL_INFO_STATUS_OFFSET = 0x2E    # LevelInfo_StatusBarMapXOffset.
LEVEL_INFO_STATUS_MAP = 0x4F       # LevelInfo_StatusBarMapTransferBuf.


def status_map_cells(info):
    """Decodes a PPU transfer buffer (address, count with $80 vertical and $40
    repeat, then tiles) into (column, row, tile) cells of nametable $2000."""
    cells, i = [], LEVEL_INFO_STATUS_MAP
    while info[i] != 0xFF:
        address, flags = (info[i] << 8 | info[i + 1]) - 0x2000, info[i + 2]
        count, vertical, repeat = flags & 0x3F, flags & 0x80, flags & 0x40
        tiles = [info[i + 3]] * count if repeat else list(info[i + 3:i + 3 + count])
        for k, tile in enumerate(tiles):
            cells.append((address % 32 + (0 if vertical else k), address // 32 + (k if vertical else 0), tile))
        i += 3 + (1 if repeat else count)
    return cells
STATIC_OW = (0x48, 0x4A, 0x4C, 0x30, 0x32, 0x34, 0x38, 0x3A, 0x3C, 0x50, 0x5A)
STATIC_UW = (0x48, 0x4A, 0x4C, 0x30, 0x32, 0x34, 0x38, 0x3A, 0x3C, 0x40, 0x42)
FIRST_ROW = 8                      # NT2 row at the top of the open menu.
MAP_ROW, MAP_COLUMN = 13, 12       # Sheet map: NT2 rows $D-$14 (as menu rows), columns $C-$1B.
BLANK_MAP = 0xF5
CURSOR_TILE = 0x1E
MARKER_TILE = 0x3E


def buffer_at(prg, selector):
    address = struct.unpack_from('<H', prg, TRANSFER_BUF_ADDRS + selector)[0]
    return address + 0x10000


def apply_records(prg, offset, tiles, attrs):
    """Z_06 TransferCurTileBuf records: address, count (bit 7 vertical, bit 6 repeat), bytes."""
    while prg[offset] != 0xFF:
        address = prg[offset] << 8 | prg[offset + 1]
        control = prg[offset + 2]
        count = control & 0x3F or 64
        offset += 3
        for i in range(count):
            value = prg[offset] if control & 0x40 else prg[offset + i]
            target = address + (i * 32 if control & 0x80 else i)
            relative = target - 0x2800
            if 0 <= relative < 0x3C0: tiles[relative] = value
            elif 0x3C0 <= relative < 0x400: attrs[relative - 0x3C0] = value
        offset += 1 if control & 0x40 else count


def triforce_rows(prg):
    """The four RAM row buffers, their ROM template offsets, and the label's offset."""
    rows, starts, offset = [], [], TRIFORCE_TEMPLATES
    for _ in range(4):
        length = 3 + (prg[offset + 2] & 0x3F) + 1
        rows.append(bytearray(prg[offset:offset + length]))
        starts.append(offset)
        offset += length
    return rows, starts, offset


def triforce_slots(prg):
    """Each of the 24 tile slots: menu-local pixel, empty tile, and owned tile."""
    rows, _, _ = triforce_rows(prg)
    places = []
    for row in rows:
        address = row[0] << 8 | row[1]
        for i in range(row[2] & 0x3F): places.append(address + i)
    # Map a byte index in the concatenation (starting at Row0 + 4) to a PPU address.
    index_to_address, cursor, place = {}, 0, 0
    for row in rows:
        for i in range(len(row)):
            if 3 <= i < len(row) - 1:
                index_to_address[cursor + i] = places[place]
                place += 1
        cursor += len(row)
    offsets = prg[TRIFORCE_TABLES:TRIFORCE_TABLES + 24]
    full = prg[TRIFORCE_TABLES + 24:TRIFORCE_TABLES + 48]
    empty = prg[TRIFORCE_TABLES + 48:TRIFORCE_TABLES + 72]
    slots = []
    for slot in range(24):
        address = index_to_address[4 + offsets[slot]]
        relative = address - 0x2800
        slots.append(((relative % 32) * 8, (relative // 32 - FIRST_ROW) * 8, empty[slot], full[slot]))
    return slots


def render(prg, tiles, attrs, patterns, palettes, blit_tile, png, path):
    canvas = bytearray(256 * 176 * 4)
    for row in range(FIRST_ROW, 30):
        for column in range(32):
            attr = attrs[(row // 4) * 8 + column // 4]
            palette = (attr >> (((row % 4) // 2) * 4 + ((column % 4) // 2) * 2)) & 3
            blit_tile(canvas, 256, column * 8, (row - FIRST_ROW) * 8, patterns[0x1000:], tiles[row * 32 + column], palettes[palette])
    png(path, 256, 176, canvas)


def tile_atlas(patterns, palette, blit_tile, png, path):
    canvas = bytearray(128 * 128 * 4)
    for tile in range(256):
        blit_tile(canvas, 128, tile % 16 * 8, tile // 16 * 8, patterns[0x1000:], tile, palette)
    png(path, 128, 128, canvas)


def sprite(patterns, tile, palette, blit_tile, png, path, flip_x=False):
    """One 8x16 sprite (tile pair) in an 8x16 image."""
    canvas = bytearray(8 * 16 * 4)
    bank = patterns[0x1000:] if tile & 1 else patterns
    for half in range(2): blit_tile(canvas, 8, 0, half * 8, bank, (tile & 0xFE) + half, palette, True)
    if flip_x:
        flipped = bytearray(len(canvas))
        for y in range(16):
            for x in range(8): flipped[(y * 8 + x) * 4:(y * 8 + x) * 4 + 4] = canvas[(y * 8 + 7 - x) * 4:(y * 8 + 7 - x) * 4 + 4]
        canvas = flipped
    png(path, 8, 16, canvas)


def export(prg, output, ow_patterns, uw_patterns, ow_palettes, level_infos, png, blit_tile):
    """Writes backdrops, tile atlases, sprites, and imported/submenu.tres."""
    names = []
    # Overworld: static boxes and text, the empty Triforce, and its label.
    tiles, attrs = bytearray([0x24] * 0x3C0), bytearray(64)
    for selector in STATIC_OW: apply_records(prg, buffer_at(prg, selector), tiles, attrs)
    _, starts, text = triforce_rows(prg)
    for start in starts: apply_records(prg, start, tiles, attrs)
    apply_records(prg, text, tiles, attrs)
    slots = triforce_slots(prg)
    for x, y, empty, _ in slots: tiles[(y // 8 + FIRST_ROW) * 32 + x // 8] = empty
    render(prg, tiles, attrs, ow_patterns, ow_palettes, blit_tile, png, output / 'submenu_ow.png')
    tile_atlas(ow_patterns, ow_palettes[1], blit_tile, png, output / 'submenu_ow_tiles.png')
    names += ['submenu_ow', 'submenu_ow_tiles']
    for level in range(1, 10):
        info = level_infos[level]
        palettes = [list(info[3 + p * 4:7 + p * 4]) for p in range(8)]
        tiles, attrs = bytearray([0x24] * 0x3C0), bytearray(64)
        for selector in STATIC_UW: apply_records(prg, buffer_at(prg, selector), tiles, attrs)
        for row in range(8):
            for column in range(16): tiles[(MAP_ROW + row + FIRST_ROW) * 32 + MAP_COLUMN + column] = BLANK_MAP
        render(prg, tiles, attrs, uw_patterns, palettes, blit_tile, png, output / f'submenu_l{level}.png')
        tile_atlas(uw_patterns, palettes[1], blit_tile, png, output / f'submenu_l{level}_tiles.png')
        names += [f'submenu_l{level}', f'submenu_l{level}_tiles']
    # UpdateSubmenuSelection: the cursor flashes between sprite rows 5 and 6;
    # the room marker is tile $3E in row 4.
    for index, palette in enumerate((5, 6)):
        sprite(ow_patterns, CURSOR_TILE, ow_palettes[palette], blit_tile, png, output / f'submenu_cursor_{index}.png')
        sprite(ow_patterns, CURSOR_TILE, ow_palettes[palette], blit_tile, png, output / f'submenu_cursor_{index}_right.png', flip_x=True)
    sprite(ow_patterns, MARKER_TILE, ow_palettes[4], blit_tile, png, output / 'submenu_marker.png')
    names += ['submenu_cursor_0', 'submenu_cursor_1', 'submenu_cursor_0_right', 'submenu_cursor_1_right', 'submenu_marker']
    write_layout(prg, output / 'submenu.tres', level_infos)
    return names


def write_layout(prg, path, level_infos):
    """The SubmenuLayout: Triforce slots, and each level's map rotation and mask.
    The second quest writes its own, since its level info replaces the maps."""
    slots = triforce_slots(prg)
    rotations = [level_infos[level][LEVEL_INFO_ROTATION] for level in range(1, 10)]
    masks = [list(level_infos[level][LEVEL_INFO_MASK:LEVEL_INFO_MASK + 16]) for level in range(1, 10)]
    lines = ['[gd_resource type="Resource" script_class="SubmenuLayout" load_steps=2 format=3]',
             '[ext_resource type="Script" path="res://scripts/submenu_layout.gd" id="1"]', '[resource]', 'script = ExtResource("1")',
             'triforce_positions = PackedVector2Array(' + ', '.join(f'{x}, {y}' for x, y, _, _ in slots) + ')',
             'triforce_empty = PackedByteArray(' + ', '.join(str(e) for _, _, e, _ in slots) + ')',
             'triforce_full = PackedByteArray(' + ', '.join(str(f) for _, _, _, f in slots) + ')',
             'map_rotations = PackedByteArray(' + ', '.join(str(r) for r in rotations) + ')',
             'map_masks = PackedByteArray(' + ', '.join(str(b) for mask in masks for b in mask) + ')',
             'status_map_tiles = PackedInt32Array(' + ', '.join(str(v) for level in range(1, 10) for cell in status_map_cells(level_infos[level]) for v in (level, *cell)) + ')',
             'status_map_offsets = PackedByteArray(' + ', '.join(str(level_infos[level][LEVEL_INFO_STATUS_OFFSET]) for level in range(1, 10)) + ')']
    path.write_text('\n'.join(lines) + '\n')
