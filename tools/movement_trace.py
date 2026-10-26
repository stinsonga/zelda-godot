#!/usr/bin/env python3
"""Capture NES movement, replay it through Godot, and report the first mismatch.

`run` exits 1 for measured differences, 2 for invalid/setup failures, 0 for a
complete match. All generated captures default to ignored reference-inputs/.
No frame shifting, tolerance, or expected-failure list hides disagreements.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = ROOT/'tools/movement_scenarios.json'
DEFAULT_OUTPUT = ROOT/'reference-inputs/comparisons/link_movement'
DIRECTIONS = {'right':1, 'left':2, 'down':4, 'up':8}
FIELDS = ('room','x','y','direction')
# Start a fresh file called A, using controller input only. No SRAM/RAM patches.
BOOT = [([],180),(['start'],1),([],180),(['start'],1),([],180),(['a'],1),([],10),
        (['select'],1),([],10),(['select'],1),([],10),(['select'],1),([],10),
        (['start'],1),([],180),(['start'],1),([],360)]

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',',':')).encode()).hexdigest()

def read_json(path):
    return json.loads(Path(path).read_text())

def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2)+'\n')

def output_directory(path):
    path = Path(path).resolve()
    if path == ROOT or (ROOT in path.parents and not any(parent in (ROOT/'reference-inputs', ROOT/'exports') for parent in [path,*path.parents])):
        raise ValueError('Generated traces inside the project must stay in ignored reference-inputs/ or exports/')
    path.mkdir(parents=True, exist_ok=True)
    return path

def expand(scenario):
    frames = []
    for segment in scenario['segments']:
        buttons = segment['buttons']
        count = segment['frames']
        if not isinstance(buttons,list) or len(buttons)>1 or any(b not in DIRECTIONS for b in buttons):
            raise ValueError('First movement adapter accepts zero or one cardinal direction per frame')
        if type(count) is not int or not 1 <= count <= 600:
            raise ValueError('Segment frame count must be 1..600')
        frames.extend([list(buttons) for _ in range(count)])
    if not frames or len(frames)>2400: raise ValueError('Scenario must contain 1..2400 frames')
    return frames

def validate_suite(suite):
    if suite.get('schema') != 1 or suite.get('quest') != 1 or suite.get('room') != 'ow_77':
        raise ValueError('First adapter supports first-quest starting room ow_77 only')
    initial = suite.get('initial',{})
    if initial != {'x':120,'y':77,'direction':8,'fraction':0,'grid_offset':0}:
        raise ValueError('First adapter requires the natural, stationary new-game seed')
    ids=[]
    for case in suite['cases']:
        if not isinstance(case['id'],str) or not case['id'] or case['id'] in ids: raise ValueError('Scenario IDs must be unique and nonempty')
        ids.append(case['id'])
        expand(case)
    if not ids: raise ValueError('No movement scenarios')

def snapshot(core):
    ram = core.ram
    return {'room':f'ow_{ram[0xEB]:02x}', 'x':int(ram[0x70]), 'y':int(ram[0x84])-64,
            'direction':int(ram[0x98]),
            'raw':{'screen_y':int(ram[0x84]), 'fraction':int(ram[0x3A8]), 'grid_offset':int(ram[0x394]),
                   'buttons':int(ram[0xFA]), 'frame_counter':int(ram[0x15]), 'mode':int(ram[0x12]),
                   'submode':int(ram[0x13]), 'level':int(ram[0x10]), 'state':int(ram[0xAC]), 'paused':int(ram[0xE0])}}

def capture_reference(core_path, rom_path, suite, out):
    from import_rom import read_rom, PRG_SHA1
    from reference_libretro import ReferenceCore
    read_rom(rom_path)  # Verified US PRG0 payload; fail before executing it.
    validate_suite(suite)
    with ReferenceCore(core_path,rom_path) as core:
        for buttons, count in BOOT: core.run(buttons,count)
        initial = snapshot(core)
        expected = suite['initial']
        for field in ('x','y','direction'):
            if initial[field] != expected[field]: raise ValueError('Reference bootstrap seed mismatch: '+str(initial))
        if initial['room'] != suite['room'] or initial['raw']['mode'] != 5 or initial['raw']['state'] != 0 or initial['raw']['fraction'] != 0 or initial['raw']['grid_offset'] != 0:
            raise ValueError('Reference did not reach stationary free play: '+str(initial))
        state = core.save()
        (out/'seed.state').write_bytes(state)
        cases=[]
        for scenario in suite['cases']:
            def replay():
                core.restore(state)
                rows=[]
                previous_frame=initial['raw']['frame_counter']
                for frame, buttons in enumerate(expand(scenario),1):
                    core.run(buttons)
                    row=snapshot(core)
                    if row['room'] != suite['room'] or row['raw']['mode'] != 5 or row['raw']['paused'] != 0:
                        raise ValueError(f"{scenario['id']} frame {frame}: reference left the single-room free-play context")
                    mask=sum(DIRECTIONS[b] for b in buttons)
                    if row['raw']['buttons'] != mask:
                        raise ValueError(f"{scenario['id']} frame {frame}: controller/RAM input phase mismatch")
                    if row['raw']['frame_counter'] != (previous_frame+1)%256:
                        raise ValueError(f"{scenario['id']} frame {frame}: NMI frame did not advance once")
                    previous_frame=row['raw']['frame_counter']
                    row.update(frame=frame,buttons=buttons)
                    rows.append(row)
                return rows
            rows=replay()
            if replay()!=rows: raise ValueError('Reference replay is not deterministic: '+scenario['id'])
            cases.append({'id':scenario['id'],'initial':initial,'frames':rows})
        trace={'schema':1,'engine':'nes','suite':suite,'suite_sha256':digest(suite),'rom_prg_sha1':PRG_SHA1,
               'core':core.info,'core_options':{k.decode():v.decode() for k,v in sorted(core.variables.items())},
               'seed_sha256':hashlib.sha256(state).hexdigest(), 'bootstrap_frames':core.frame-sum(len(c['frames'])*2 for c in cases),
               'reference_replay_verified':True,'cases':cases}
        metadata=Path(core_path).parent/'nestopia.json'
        if metadata.exists():
            provenance=read_json(metadata)
            if provenance.get('sha256') != core.info['sha256']: raise ValueError('Core binary does not match its build metadata')
            trace['core_build']=provenance
        write_json(out/'reference.json',trace)
        return trace

def validate_trace(trace, engine):
    if trace.get('schema') != 1 or trace.get('engine') != engine: raise ValueError('Unsupported trace schema or engine')
    suite=trace['suite']
    validate_suite(suite)
    if trace.get('suite_sha256') != digest(suite): raise ValueError('Trace scenario fingerprint does not match')
    if len(trace.get('cases',[])) != len(suite['cases']): raise ValueError('Trace is missing or has extra scenarios')
    for case,scenario in zip(trace['cases'],suite['cases']):
        if case.get('id') != scenario['id']: raise ValueError('Trace scenario order/ID differs')
        inputs=expand(scenario)
        if len(case.get('frames',[])) != len(inputs): raise ValueError('Trace is missing or has extra frames: '+case['id'])
        for frame, (row, buttons) in enumerate(zip(case['frames'],inputs),1):
            if row.get('frame') != frame or row.get('buttons') != buttons: raise ValueError('Trace frame/input phase differs: '+case['id'])
            for field in FIELDS:
                if field not in row or field not in case['initial']: raise ValueError('Trace lacks comparison fields')
            if any(type(row[f]) is not int for f in ('x','y','direction')): raise ValueError('Trace positions/direction must be integers')

def compare(reference, native):
    validate_trace(reference,'nes')
    validate_trace(native,'godot')
    if reference['suite_sha256'] != native['suite_sha256']: raise ValueError('Reference and native scenarios differ')
    if reference['rom_prg_sha1'] != native['rom_prg_sha1']: raise ValueError('Godot content and reference ROM revisions differ')
    results=[]
    for ref,actual in zip(reference['cases'],native['cases']):
        seed_differences=[f for f in FIELDS if ref['initial'][f]!=actual['initial'][f]]
        if seed_differences: raise ValueError('Initial states differ before replay: '+ref['id'])
        differences=[]
        for expected,observed in zip(ref['frames'],actual['frames']):
            fields=[f for f in FIELDS if expected[f]!=observed[f]]
            if fields:
                differences.append({'frame':expected['frame'],'fields':fields,'buttons':expected['buttons'],
                                    'nes':expected,'godot':observed,'delta':{'x':observed['x']-expected['x'],'y':observed['y']-expected['y']}})
        results.append({'id':ref['id'],'frames':len(ref['frames']),'matched':not differences,'different_frames':len(differences),
                        'first_difference':differences[0] if differences else None})
    return {'schema':1,'matched':all(r['matched'] for r in results),'suite_sha256':reference['suite_sha256'],
            'rom_prg_sha1':reference['rom_prg_sha1'],'reference_core':reference['core'],
            'compared_fields':list(FIELDS),'fraction_policy':'NES raw scalar and Godot subposition are diagnostics, not equated', 'cases':results}

def report_text(report):
    lines=[]
    for case in report['cases']:
        lines.append(('PASS' if case['matched'] else 'DIFF')+' '+case['id']+f" ({case['frames']} frames)")
        d=case['first_difference']
        if d:
            lines.append(f"  First difference: frame {d['frame']}, input {d['buttons'] or ['stop']}, fields {d['fields']}")
            for label,key in [('NES','nes'),('Godot','godot')]:
                row=d[key]
                lines.append(f"  {label}: {row['room']} position ({row['x']}, {row['y']}), direction {row['direction']}; diagnostics {row['raw']}")
            lines.append(f"  Delta: {d['delta']}; {case['different_frames']} differing frames")
    return '\n'.join(lines)+'\n'

def capture_native(godot, out):
    result=subprocess.run([str(godot),'--headless','--path',str(ROOT),'--script','res://tools/capture_movement.gd',
                           '--log-file',str(out/'godot.log'),'--','--reference',str(out/'reference.json'),'--output',str(out/'native.json')],
                          capture_output=True,text=True,timeout=120)
    (out/'godot-process.log').write_text(result.stdout+result.stderr)
    if result.returncode or 'SCRIPT ERROR' in result.stdout+result.stderr: raise ValueError('Godot trace capture failed; see '+str(out/'godot-process.log'))
    native=read_json(out/'native.json')
    reference=read_json(out/'reference.json')
    # Godot parses JSON numbers as floats. Restore the authored integer schema
    # only after checking the echoed suite is semantically identical.
    if native['suite'] != reference['suite']: raise ValueError('Godot changed the replay suite')
    native['suite']=reference['suite']
    files=sorted((ROOT/'scripts').glob('*.gd'))+[ROOT/'tools/capture_movement.gd']
    hasher=hashlib.sha256()
    for file in files: hasher.update(file.relative_to(ROOT).as_posix().encode()+b'\0'+file.read_bytes())
    native['godot_source_sha256']=hasher.hexdigest()
    write_json(out/'native.json',native)
    return native

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['run','capture','compare'])
    parser.add_argument('--rom',type=Path)
    parser.add_argument('--core',type=Path,default=ROOT/'reference-inputs/emulator/nestopia_libretro.dylib')
    parser.add_argument('--suite',type=Path,default=SCENARIOS)
    parser.add_argument('--out',type=Path,default=DEFAULT_OUTPUT)
    parser.add_argument('--godot',type=Path,default=Path('/Applications/Godot.app/Contents/MacOS/Godot'))
    args=parser.parse_args()
    try:
        out=output_directory(args.out)
        if args.action in ('run','capture'):
            rom=args.rom
            if rom is None:
                candidates=list((ROOT/'reference-inputs').glob('*.nes'))
                if len(candidates)!=1: raise ValueError('Pass --rom for exactly one verified US PRG0 ROM')
                rom=candidates[0]
            reference=capture_reference(args.core,rom,read_json(args.suite),out)
            if args.action=='capture':
                print('Captured deterministic NES reference:',out/'reference.json')
                return 0
            native=capture_native(args.godot,out)
        else:
            reference,native=read_json(out/'reference.json'),read_json(out/'native.json')
        report=compare(reference,native)
        write_json(out/'report.json',report)
        (out/'report.txt').write_text(report_text(report))
        print(report_text(report),end='')
        return 0 if report['matched'] else 1
    except (ValueError,OSError,KeyError,TypeError,subprocess.SubprocessError) as error:
        print('Movement harness setup/validation error:',error,file=sys.stderr)
        return 2

if __name__=='__main__': sys.exit(main())
