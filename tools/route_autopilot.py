#!/usr/bin/env python3
"""Find controller input for a new movement case by steering the NES through waypoints.

Routes far from the start cross monster rooms, where fixed frame counts break as
soon as anything shoves Link. This drives the reference emulator frame by frame
instead, then records what it pressed as ordinary segments, so the case it writes
is plain authored input like any other.

Waypoints (a JSON list):
  {"room": "ow_63", "axis": "x", "value": 112, "button": "left"}
      hold the button until Link stands at that grid coordinate in that room
      (grid points are exact: Link always stops on them);
  {"button": "up", "exit": true}
      hold the button until a room change completes (mazes repeat rooms);
  {"idle": 300}
      release everything for that many frames.
While moving, the autopilot presses A (fresh presses only) when a monster is
within reach ahead, if Link has a sword.

It starts after an existing case's setup (--setup-case) or its whole input
(--extend), tries each start delay, and keeps the first run where Link reaches
the last waypoint alive. Example:

  python3 tools/route_autopilot.py --setup-case sword_swings --plan route.json \\
      --id sword_to_somewhere --delays 0,20,40 --append
"""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import movement_trace as m
from reference_libretro import ReferenceCore

FACING = {'right': (1, 0), 'left': (-1, 0), 'down': (0, 1), 'up': (0, -1)}

def segments(inputs):
    out = []
    for buttons in inputs:
        if out and out[-1]['buttons'] == buttons and out[-1]['frames'] < 600: out[-1]['frames'] += 1
        else: out.append({'buttons': list(buttons), 'frames': 1})
    return out

def monster_ahead(snapshot, button):
    fx, fy = FACING[button]
    lx, ly = snapshot['x'], snapshot['y']
    for o in snapshot['objects']:
        if not isinstance(o[0], int): continue
        ahead = (o[2] - lx) * fx + (o[3] - ly) * fy
        across = abs((o[2] - lx) * fy + (o[3] - ly) * fx)
        if 0 < ahead < 28 and across < 12: return True
    return False

def drive(core, plan, delay, limit, sword):
    """Returns (ok, inputs, rooms, reason)."""
    inputs = [[] for _ in range(delay)]
    for _ in range(delay): core.run([])
    rooms, step, idle, exiting = [], 0, 0, False
    while len(inputs) < limit:
        if step >= len(plan): return True, inputs, rooms, ''
        w = plan[step]
        r = m.snapshot(core)
        if r['raw']['mode'] == 0x11: return False, inputs, rooms, 'died'
        if r['phase'] == 'play' and r['room'] not in rooms: rooms.append(r['room'])
        if 'idle' in w:
            if idle >= w['idle']: step, idle = step + 1, 0; continue
            buttons, idle = [], idle + 1
        else:
            if w.get('exit'):
                if r['phase'] == 'transition': exiting = True
                elif exiting: exiting, step = False, step + 1; continue
            elif r['phase'] == 'play' and r['room'] == w['room'] and r[w['axis']] == w['value']:
                step += 1; continue
            buttons = [w['button']]
            if sword and monster_ahead(r, w['button']) and not (inputs and 'a' in inputs[-1]): buttons.append('a')
        core.run(buttons)
        inputs.append(buttons)
    return False, inputs, rooms, 'out of frames'

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--id', required=True, help='ID of the case to write')
    start = parser.add_mutually_exclusive_group()
    start.add_argument('--setup-case', help="start after this case's setup")
    start.add_argument('--extend', help="start after this case's setup and segments")
    parser.add_argument('--delays', default='0,20,40,60,80,100')
    parser.add_argument('--limit', type=int, default=5000, help='frames per attempt')
    parser.add_argument('--append', action='store_true', help='add the case to the scenario file')
    parser.add_argument('--rom', type=Path)
    parser.add_argument('--core', type=Path, default=m.ROOT/'reference-inputs/emulator/nestopia_libretro.dylib')
    args = parser.parse_args()
    suite = m.read_json(m.SCENARIOS)
    if args.id in [c['id'] for c in suite['cases']]: sys.exit('Case ID already exists: ' + args.id)
    base = next((c for c in suite['cases'] if c['id'] in (args.setup_case, args.extend)), None) if (args.setup_case or args.extend) else None
    setup = list(base.get('setup', [])) if base else []
    prefix = [s for s in base['segments']] if args.extend else []
    rom = args.rom or next(iter((m.ROOT/'reference-inputs').glob('*.nes')))
    plan = json.loads(args.plan.read_text())
    with ReferenceCore(args.core, rom) as core:
        for buttons, count in m.BOOT: core.run(buttons, count)
        for buttons in m.setup_frames({'setup': setup}): core.run(buttons)
        for buttons in (m.expand({'segments': prefix}) if prefix else []): core.run(buttons)
        sword = core.ram[0x657] > 0
        checkpoint = core.save()
        for delay in [int(d) for d in args.delays.split(',')]:
            core.restore(checkpoint)
            ok, inputs, rooms, reason = drive(core, plan, delay, args.limit, sword)
            r = m.snapshot(core)
            print(f"delay {delay}: {'reached' if ok else reason} after {len(inputs)} frames at {r['room']} ({r['x']},{r['y']})", file=sys.stderr)
            if ok: break
        else:
            sys.exit('No delay reached the last waypoint')
    visited = [room for room in rooms if room != suite['room']]
    case = {'id': args.id, 'rooms': sorted(set(base.get('rooms', []) if base else []) | set(visited)), 'objects': True}
    if setup: case['setup'] = setup
    case['segments'] = prefix + segments(inputs)
    if args.append:
        suite['cases'].append(case)
        m.validate_suite(suite)
        m.SCENARIOS.write_text(json.dumps(suite, indent=2) + '\n')
        print('Appended', args.id, 'to', m.SCENARIOS, file=sys.stderr)
    else:
        print(json.dumps(case, indent=2))

if __name__ == '__main__': main()
