#!/usr/bin/env python3
"""User-facing, staged ROM import for the game and standalone editor.

Python standard library only. The ROM is read, never copied or modified.
Generated libraries, catalogs, jobs, logs and previous imports stay ignored.
"""
import argparse
from contextlib import redirect_stdout, redirect_stderr, contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import traceback
import uuid

from import_rom import PRG_SHA1, read_rom, import_rom

ROOT = Path(__file__).resolve().parents[1]


def atomic_json(path, data):
    path = Path(path)
    temp = path.with_name(path.name + '.tmp')
    temp.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
    temp.replace(path)


def category(path):
    if path.parts[0] == 'levels' or path.name in ('overworld_tiles.png', 'cave_tiles.png'):
        return 'tiles'
    if path.parts[0] == 'title' or path.stem.startswith(('hud_', 'submenu_')):
        return 'interface'
    return 'sprites'


def build_catalog(folder):
    """Index PNGs without executing Godot resources or requiring image packages."""
    folder = Path(folder)
    entries = []
    for path in sorted(folder.rglob('*.png')):
        if path.is_symlink():
            raise ValueError('Generated image must not be a symlink: ' + str(path))
        with path.open('rb') as file:
            header = file.read(24)
        if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
            raise ValueError('Invalid generated PNG: ' + str(path))
        width, height = struct.unpack('>II', header[16:24])
        if not 1 <= width <= 4096 or not 1 <= height <= 4096:
            raise ValueError('Invalid generated PNG dimensions: ' + str(path))
        relative = path.relative_to(folder)
        entries.append({'id': 'rom/us_prg0/' + relative.with_suffix('').as_posix(),
                        'name': relative.stem.replace('_', ' '), 'path': relative.as_posix(),
                        'category': category(relative), 'width': width, 'height': height})
    if not entries:
        raise ValueError('Import produced no PNG assets')
    catalog = {'format_version': 1, 'source': {'revision': 'US PRG0', 'prg_sha1': PRG_SHA1},
               'entries': entries}
    atomic_json(folder / 'editor_catalog.json', catalog)
    return catalog


@contextmanager
def import_lock(jobs, job):
    lock = jobs / 'import.lock'
    try:
        lock.mkdir()
    except FileExistsError:
        raise ValueError('Another import owns ' + str(lock) + '. If it was interrupted, check owner.json and restore any previous-import before removing the stale lock.') from None
    try:
        atomic_json(lock / 'owner.json', {'pid': os.getpid(), 'job': str(job)})
        yield
    finally:
        (lock / 'owner.json').unlink(missing_ok=True)
        lock.rmdir()


def activate(staging, target, backup):
    """Same-filesystem replacement with rollback if the new library cannot move."""
    had_previous = target.exists()
    if had_previous:
        target.rename(backup)
    try:
        staging.rename(target)
    except BaseException:
        if had_previous:
            backup.rename(target)
        raise


def run(rom, project=ROOT, job_dir=None, validate_only=False, godot=None):
    project = Path(project).resolve()
    if not (project / 'project.godot').is_file() or not (project / 'scripts/room_definition.gd').is_file():
        raise ValueError('Destination must be the game project, not the editor project or disassembly')
    if (project / 'reference-inputs').is_symlink() or (project / 'imported').is_symlink():
        raise ValueError('Local import folders must not be symlinks')
    jobs = project / 'reference-inputs/import-jobs'
    if jobs.is_symlink(): raise ValueError('Import job folder must not be a symlink')
    jobs.mkdir(parents=True, exist_ok=True)
    job = Path(job_dir).resolve() if job_dir else jobs / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ-') + uuid.uuid4().hex[:8])
    if jobs.resolve() not in job.parents:
        raise ValueError('Import job directory must stay under reference-inputs/import-jobs/')
    job.mkdir(parents=True, exist_ok=True)
    if (job / 'status.json').exists():
        raise ValueError('Import job already has a status file; use a new job directory')
    status = {'state': 'running', 'progress': 0, 'message': 'Checking ROM',
              'revision': 'US PRG0', 'job': str(job), 'log': str(job / 'import.log')}
    def update(progress, message, **extra):
        status.update(progress=round(progress, 2), message=message, **extra)
        atomic_json(job / 'status.json', status)
    with (job / 'import.log').open('w', encoding='utf-8', buffering=1) as log, redirect_stdout(log), redirect_stderr(log):
        try:
            update(1, 'Verifying iNES header and US PRG0 payload')
            prg = read_rom(Path(rom))
            update(3, 'Verified US PRG0', verified=True, prg_sha1=PRG_SHA1)
            if validate_only:
                update(100, 'ROM is valid: US PRG0. No assets changed.', state='validated')
                return 0, status
            with import_lock(jobs, job):
                staging = job / 'assets'
                import_rom(prg, staging, progress=lambda fraction, message: update(5+fraction*85, message))
                update(91, 'Indexing graphics for the editor')
                catalog = build_catalog(staging)
                for name in ('world.tres', 'world_q2.tres', 'theme.tres', 'manifest.json', 'audio/manifest.json'):
                    if not (staging / name).is_file(): raise ValueError('Import missing required output: ' + name)
                manifest = json.loads((staging / 'manifest.json').read_text())
                if manifest.get('prg_sha1') != PRG_SHA1: raise ValueError('Generated manifest revision differs')
                update(94, 'Activating completed asset library')
                target, backup = project / 'imported', job / 'previous-import'
                activate(staging, target, backup)
                update(95, 'Assets installed', imported=str(target), images=len(catalog['entries']),
                       backup=str(backup) if backup.exists() else '')
                warnings = []
                if godot:
                    update(96, 'Preparing game textures in Godot; this may take a moment')
                    try:
                        result = subprocess.run([str(godot), '--headless', '--editor', '--path', str(project), '--quit',
                                                 '--log-file', str(job / 'godot.log')],
                                                stdout=log, stderr=log, timeout=180, check=False)
                        godot_log = (job / 'godot.log').read_text(errors='replace') if (job / 'godot.log').exists() else ''
                        if result.returncode or 'SCRIPT ERROR' in godot_log:
                            warnings.append('Assets imported; Godot preparation reported errors. Open the game in Godot and inspect godot.log.')
                    except (OSError, subprocess.TimeoutExpired) as error:
                        warnings.append('Assets imported; Godot preparation did not finish: ' + str(error))
                update(100, 'Imported US PRG0: %d images. Asset library refreshed.' % len(catalog['entries']),
                       state='complete', warnings=warnings)
                return 0, status
        except (Exception, KeyboardInterrupt) as error:
            traceback.print_exc()
            update(status['progress'], str(error) or 'Import interrupted', state='failed')
            return 1, status


def interrupted(*_):
    raise KeyboardInterrupt()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rom', type=Path)
    parser.add_argument('--project', type=Path, default=ROOT)
    parser.add_argument('--validate-only', action='store_true')
    parser.add_argument('--job-dir', type=Path, help='New job folder inside the game reference-inputs/import-jobs/')
    parser.add_argument('--godot', type=Path, help='Optionally prepare game textures after successful extraction')
    args = parser.parse_args()
    if hasattr(signal, 'SIGTERM'):
        signal.signal(signal.SIGTERM, interrupted)
    try:
        code, status = run(args.rom, args.project, args.job_dir, args.validate_only, args.godot)
        print(status['message'])
        print('Status:', Path(status['job']) / 'status.json')
        print('Log:', status['log'])
        for warning in status.get('warnings', []): print('Warning:', warning)
        return code
    except (ValueError, OSError) as error:
        if args.job_dir:
            job = args.job_dir.resolve()
            expected = args.project.resolve() / 'reference-inputs/import-jobs'
            allowed = expected.resolve()
            if allowed == expected and allowed in job.parents and job.is_dir() and not (job / 'status.json').exists():
                try:
                    (job / 'import.log').write_text(str(error) + '\n')
                    atomic_json(job / 'status.json', {'state':'failed', 'progress':0, 'message':str(error), 'job':str(job)})
                except OSError:
                    pass
        print('Import setup failed:', error, file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
