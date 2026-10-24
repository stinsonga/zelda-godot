#!/usr/bin/env python3
"""Create a source-only project snapshot without local ROM inputs or imported data."""
import argparse
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
DIRECTORIES = ('scripts', 'scenes', 'content', 'docs', 'tests', 'tools')
FILES = ('project.godot', 'README.md', '.gitignore')


def prepare(destination):
    destination = Path(destination).resolve()
    if destination == ROOT or ROOT in destination.parents:
        raise ValueError('Destination must be outside the Godot project directory')
    if destination.exists():
        raise ValueError('Destination already exists; choose a new directory')
    # Explicit source directories exclude imported/, reference-inputs/, exports/,
    # .godot/ (including its imported texture cache), and any loose local files.
    source_files = []
    for name in FILES:
        source_files.append(ROOT / name)
    for directory in DIRECTORIES:
        source_files.extend(path for path in (ROOT / directory).rglob('*')
                            if path.is_file() and '__pycache__' not in path.parts
                            and path.suffix not in ('.pyc', '.nes', '.pck', '.zip'))
    if any(path.is_symlink() for path in source_files):
        raise ValueError('Symlinks in source folders must be reviewed before packaging')
    destination.mkdir(parents=True)
    for source in source_files:
        target = destination / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    print(f'Prepared {len(source_files)} source files in {destination}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    try:
        prepare(args.destination)
    except (OSError, ValueError) as exc:
        parser.exit(1, f'Packaging failed: {exc}\n')


if __name__ == '__main__':
    main()
