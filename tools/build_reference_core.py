#!/usr/bin/env python3
"""Build a pinned, unmodified Nestopia libretro core into ignored local storage.

Network access occurs only with --fetch. --source reuses an existing checkout.
The original game and disassembly are never modified.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
COMMIT = '2110d21b7174455ec98948bb474147dea0e3cad0'
UPSTREAM = 'https://github.com/libretro/nestopia.git'

def build(source, output):
    commit = subprocess.check_output(['git','rev-parse','HEAD'], cwd=source, text=True).strip()
    if commit != COMMIT: raise ValueError('Reference checkout does not match pinned commit ' + COMMIT)
    if subprocess.check_output(['git','diff','HEAD','--'], cwd=source): raise ValueError('Reference checkout has modified source files')
    suffix = '.dylib' if platform.system() == 'Darwin' else '.so'
    args = ['make','-C','libretro','-j4']
    if platform.system() == 'Darwin': args += ['platform=osx','MINVERSION=-mmacosx-version-min=11.0']
    elif platform.system() == 'Linux': args += ['platform=unix']
    else: raise ValueError('Build helper supports macOS and Linux')
    subprocess.run(args, cwd=source, check=True)
    output.mkdir(parents=True, exist_ok=True)
    target = output / ('nestopia_libretro' + suffix)
    shutil.copy2(source/'libretro'/target.name, target)
    meta = {'upstream':UPSTREAM, 'commit':commit, 'sha256':hashlib.sha256(target.read_bytes()).hexdigest(), 'library':target.name, 'host':platform.platform()}
    (output/'nestopia.json').write_text(json.dumps(meta, indent=2)+'\n')
    shutil.copy2(source/'COPYING', output/'COPYING.nestopia')
    print('Reference core:', target)
    return target

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--fetch', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT/'reference-inputs/emulator')
    args=parser.parse_args()
    if not args.source and not args.fetch: parser.error('Use --source CHECKOUT or --fetch')
    source=(args.source or args.output/'nestopia-source').resolve()
    if args.fetch and not source.exists():
        subprocess.run(['git','clone',UPSTREAM,str(source)], check=True)
        subprocess.run(['git','checkout','--detach',COMMIT], cwd=source, check=True)
    build(source,args.output.resolve())

if __name__=='__main__': main()
