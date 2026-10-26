"""The title screen and story scroll (Z_02 mode 0: InitDemo_RunTasks, UpdateMode0Demo),
and the ending (Z_02 mode $13: InitMode13_Full, UpdateMode13WinGame).

The original shows both through the PPU, so they are exported as PPU data: an
index atlas of the demo's pattern tables (Z_01 TransferDemoPatterns over the
common patterns), the nametables built by the title and story transfer buffers,
the palettes, and the demo's tables. The runtime (scripts/nes_screen.gd and
scripts/title_demo.gd) replays the original's per-frame rules on that data.
"""
import json
import struct

from import_caves import ITEM_FRAME_OFFSETS, ITEM_FRAME_TILES, ITEM_ID_TO_SLOT, item_tile

# Pattern blocks: common sprites and background, common misc, then the demo's
# sprite ($0700) and background ($1700) blocks.
DEMO_PATTERNS = [(32895, 1792, 0), (34687, 1792, 0x1000), (36479, 224, 0x1F20),
                 (19892, 2304, 0x0700), (22196, 2080, 0x1700)]
STORY_BUFFER = 107518            # Z_06 StoryTileAttrTransferBuf.
TITLE_BUFFER = 108649            # Z_06 GameTitleTransferBuf.
TITLE_SPRITES = 37102            # Z_02 InitialTitleSprites (28 sprites), followed by DemoLineAttrs.
LINE_ATTRS = TITLE_SPRITES + 112
LEFT_ITEMS = LINE_ATTRS + 175 + 51
RIGHT_ITEMS = LEFT_ITEMS + 22
COLUMN_XS = RIGHT_ITEMS + 18     # DemoItemColumnX1 and X2.
FINAL_TILES = COLUMN_XS + 2      # DemoStoryFinalSpriteTiles, then DemoStoryFinalSpriteAttrs.
TEXT_FIELDS = 37530              # DemoTextFields, followed by DemoLineTextAddrs.
TEXT_ADDRS = TEXT_FIELDS + 531
TEXT_LINES = 29
TITLE_PALETTE = 38126            # TitlePaletteTransferRecord.
STORY_PALETTE = 38223            # StoryPaletteTransferRecord.
GLOW_RECORD = 39003              # TriforcePaletteTransferRecord, then TriforceGlowingColors.
WATERFALL = 39087                # WaterfallWaveTiles, CrestTiles, SpriteXs, WaveSpriteOffsets.
FADE_PALETTES = 39273            # DemoPhase0Subphase1Palettes: 14 palettes of 32.
FADE_DELAYS = FADE_PALETTES + 14 * 32 + 64
FAIRY_SLOT = 0x14
# The ending's tables in bank 2.
PLAY_AREA_ATTRS = 43322          # PlayAreaAttr0TransferBuf.
THANKS_TEXT = 43353              # ThanksText, 38 characters.
THANKS_TEMPLATE = 43405          # ThanksTextboxCharTransferRecTemplate, then ThanksTextboxLineAddrsLo.
FLASH_COLORS = 43551             # EndingFlashColors.
PEACE_TEMPLATE = 43726           # PeaceTextboxCharTransferRecTemplate, PeaceTextboxCharAddrsLo, PeaceText.
PEACE_ADDRS = PEACE_TEMPLATE + 5
PEACE_TEXT = PEACE_ADDRS + 52
LAST_SCREENS = 43968             # CreditsLastScreenList, then CreditsLastVscrollList.
CREDITS_VRAM_HI = 44054          # CreditLineVramAddrsHi, CreditsPagesTextMasks, CreditsTextAddrsLo/Hi.
CREDITS_MASKS = CREDITS_VRAM_HI + 12
CREDITS_ADDRS = CREDITS_MASKS + 12
CREDITS_LINES = 23
CREDITS_ATTRS = 44538
ENDING_PALETTE_SELECTOR = 0x6A   # UpdateMode13WinGame_Sub1's TileBufSelector.
TRANSFER_BUF_ADDRS = 0x1A000
ZELDA_SONG = 0x06


def demo_patterns(prg):
    patterns = bytearray(8192)
    for source, length, target in DEMO_PATTERNS:
        patterns[target:target + length] = prg[source:source + length]
    return patterns


def index_atlas(patterns):
    """Both pattern tables as 128x256 grey levels: pixel value v is stored as v * 85."""
    canvas = bytearray(128 * 256 * 4)
    for tile in range(512):
        pattern = patterns[tile * 16:tile * 16 + 16]
        x0, y0 = tile % 16 * 8, tile // 16 * 8
        for y in range(8):
            for x in range(8):
                value = ((pattern[y] >> (7 - x)) & 1) | (((pattern[y + 8] >> (7 - x)) & 1) << 1)
                offset = ((y0 + y) * 128 + x0 + x) * 4
                canvas[offset:offset + 4] = bytes([value * 85] * 3 + [255])
    return canvas


def apply_records(prg, offset, tables):
    """Z_06 TransferCurTileBuf on two nametables: NT0 ($2000) and NT2 ($2800)."""
    while prg[offset] != 0xFF:
        address = prg[offset] << 8 | prg[offset + 1]
        control = prg[offset + 2]
        count = control & 0x3F or 64
        offset += 3
        for i in range(count):
            value = prg[offset] if control & 0x40 else prg[offset + i]
            target = address + (i * 32 if control & 0x80 else i)
            table = 1 if target & 0x0800 else 0
            tables[table][target & 0x3FF] = value
        offset += 1 if control & 0x40 else count


def blank_tables():
    """TurnOffVideoAndClearArtifacts: tile $24 and zero attributes in both tables."""
    return [bytearray([0x24] * 960 + [0] * 64) for _ in range(2)]


def record_palette(prg, offset):
    assert prg[offset:offset + 3] == bytes([0x3F, 0x00, 0x20])
    return list(prg[offset + 3:offset + 35])


def item_sprites(tile, attr):
    """Z_01 Anim_WriteSpecificItemSprites: (dx, tile, attr) for each 8x16 sprite."""
    if tile == 0xF3 or 0x20 <= tile < 0x62:
        return [[4, tile, attr]]
    if tile < 0x6C:
        return [[0, tile, attr], [7, tile + 2, attr]]
    if tile < 0x7C:
        return [[0, tile, attr], [8, tile, attr ^ 0x40]]
    return [[0, tile, attr], [8, tile + 2, attr]]


def demo_items(prg, ids):
    """Z_07 AnimateItemObject for each story item; flashing slots pick palette 1 or 2 by frame."""
    items = {}
    for item_id in sorted(set(ids)):
        if item_id >= 0x30:
            continue
        if item_id == 0x23:
            # AnimateStationaryFairy: two frames on the red palette row.
            frames = [item_sprites(prg[ITEM_FRAME_TILES + prg[ITEM_FRAME_OFFSETS + FAIRY_SLOT] + frame], 2) for frame in range(2)]
            items[str(item_id)] = {'frames': frames, 'flash': False}
            continue
        tile, attr = item_tile(prg, item_id)
        slot = prg[ITEM_ID_TO_SLOT + item_id]
        items[str(item_id)] = {'frames': [item_sprites(tile, attr)], 'flash': slot in (0x16, 0x19, 0x1A, 0x1B)}
    return items


def text_lines(prg):
    lines = []
    for i in range(TEXT_LINES):
        address = struct.unpack_from('<H', prg, TEXT_ADDRS + i * 2)[0]
        offset = address              # Bank 2 sits at PRG $8000, so CPU and PRG offsets agree.
        column, tiles = prg[offset], []
        offset += 1
        while prg[offset] != 0xFF:
            tiles.append(prg[offset])
            offset += 1
        lines.append([column] + tiles)
    return lines


def export(prg, output, png, colors):
    destination = output / 'title'
    destination.mkdir(parents=True, exist_ok=True)
    png(destination / 'chr.png', 128, 256, index_atlas(demo_patterns(prg)))
    title = blank_tables()
    apply_records(prg, TITLE_BUFFER, title)
    story = blank_tables()
    apply_records(prg, STORY_BUFFER, story)
    left, right = list(prg[LEFT_ITEMS:LEFT_ITEMS + 22]), list(prg[RIGHT_ITEMS:RIGHT_ITEMS + 18])
    # The scroll processes 175 lines; the table is padded with the zeroes that follow it.
    line_attrs = list(prg[LINE_ATTRS:LINE_ATTRS + 176])
    data = {
        'format': 1,
        'colors': [color.hex() for color in colors],
        'title_tables': [list(table) for table in title],
        'story_tables': [list(table) for table in story],
        'title_palette': record_palette(prg, TITLE_PALETTE),
        'story_palette': record_palette(prg, STORY_PALETTE),
        'fade_palettes': [list(prg[FADE_PALETTES + i * 32:FADE_PALETTES + i * 32 + 32]) for i in range(14)],
        'fade_delays': list(prg[FADE_DELAYS:FADE_DELAYS + 14]),
        'glow_address': prg[GLOW_RECORD] << 8 | prg[GLOW_RECORD + 1],
        'glow_record': list(prg[GLOW_RECORD + 3:GLOW_RECORD + 7]),
        'glow_colors': list(prg[GLOW_RECORD + 8:GLOW_RECORD + 16]),
        'title_sprites': list(prg[TITLE_SPRITES:TITLE_SPRITES + 112]),
        'wave_tiles': list(prg[WATERFALL:WATERFALL + 4]),
        'crest_tiles': list(prg[WATERFALL + 4:WATERFALL + 8]),
        'waterfall_xs': list(prg[WATERFALL + 8:WATERFALL + 12]),
        'wave_offsets': list(prg[WATERFALL + 12:WATERFALL + 15]),
        'line_attrs': line_attrs,
        'left_items': left,
        'right_items': right,
        'column_xs': list(prg[COLUMN_XS:COLUMN_XS + 2]),
        'final_tiles': list(prg[FINAL_TILES:FINAL_TILES + 24]),
        'final_attrs': list(prg[FINAL_TILES + 24:FINAL_TILES + 48]),
        'text_lines': text_lines(prg),
        'items': demo_items(prg, left + right),
    }
    (destination / 'title.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
    export_ending(prg, output)
    return data


def palette_records(prg, offset):
    """A palette transfer buffer as [first index, bytes] records."""
    records = []
    while prg[offset] != 0xFF:
        address = prg[offset] << 8 | prg[offset + 1]
        count = prg[offset + 2] & 0x3F
        assert address & 0xFF00 == 0x3F00
        records.append([address - 0x3F00, list(prg[offset + 3:offset + 3 + count])])
        offset += 3 + count
    return records


def credit_lines(prg):
    lines = []
    for i in range(CREDITS_LINES):
        address = prg[CREDITS_ADDRS + i] | prg[CREDITS_ADDRS + CREDITS_LINES + i] << 8
        length, column = prg[address], prg[address + 1]
        lines.append([column] + list(prg[address + 2:address + 2 + length]))
    return lines


def song_frames(prg, request):
    """Frames until the driver's Song byte ($609) clears after a request."""
    from render_audio import Driver
    driver = Driver(prg)
    driver.m[0x600] = request
    for frame in range(1, 3600):
        driver.m[0x15] = frame & 255
        driver.run()
        if driver.m[0x609] == 0:
            return frame
    raise ValueError('Song does not end')


def export_ending(prg, output):
    from import_dungeons import level_info
    info = level_info(prg, 9)
    assert list(info[:3]) == [0x3F, 0x00, 0x20]
    selector = TRANSFER_BUF_ADDRS + ENDING_PALETTE_SELECTOR
    ending_palette = prg[selector] | prg[selector + 1] << 8
    assert list(prg[PLAY_AREA_ATTRS:PLAY_AREA_ATTRS + 2]) == [0x23, 0xD8]
    data = {
        'format': 1,
        'level_palette': list(info[3:35]),
        'play_area_attrs': [prg[PLAY_AREA_ATTRS] << 8 | prg[PLAY_AREA_ATTRS + 1], prg[PLAY_AREA_ATTRS + 2] & 0x3F, prg[PLAY_AREA_ATTRS + 3]],
        'thanks_text': list(prg[THANKS_TEXT:THANKS_TEXT + 38]),
        'thanks_start': prg[THANKS_TEMPLATE] << 8 | prg[THANKS_TEMPLATE + 1],
        'thanks_lines': list(prg[THANKS_TEMPLATE + 5:THANKS_TEMPLATE + 8]),
        'flash_colors': list(prg[FLASH_COLORS:FLASH_COLORS + 4]),
        'peace_high': prg[PEACE_TEMPLATE],
        'peace_addrs': list(prg[PEACE_ADDRS:PEACE_ADDRS + 52]),
        'peace_text': list(prg[PEACE_TEXT:PEACE_TEXT + 53]),
        'ending_palette': palette_records(prg, ending_palette + 0x10000),
        'last_screens': list(prg[LAST_SCREENS:LAST_SCREENS + 2]),
        'last_scrolls': list(prg[LAST_SCREENS + 2:LAST_SCREENS + 4]),
        'credits_pages': list(prg[CREDITS_VRAM_HI:CREDITS_VRAM_HI + 12]),
        'credits_masks': list(prg[CREDITS_MASKS:CREDITS_MASKS + 12]),
        'credits_lines': credit_lines(prg),
        'credits_attrs': list(prg[CREDITS_ATTRS:CREDITS_ATTRS + 24]),
        'zelda_song_frames': song_frames(prg, ZELDA_SONG),
    }
    (output / 'title' / 'ending.json').write_text(json.dumps(data, separators=(',', ':')) + '\n')
    return data
