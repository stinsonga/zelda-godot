# Local asset boundary

The project separates implementation and hand-authored placeholder content from
all ROM-derived content, including graphics, text, terrain, and generated Godot
resources. Keep that boundary when publishing this folder as its own repository.

| Directory | Contents | Source snapshot |
| --- | --- | --- |
| `scripts/`, `scenes/`, `tools/`, `tests/`, `docs/` | Implementation, importer, checks, and documentation | Included |
| `content/` | Hand-authored placeholder rooms and native gameplay definitions | Included |
| `reference-inputs/` | Locally supplied ROM; ignored by Git and Godot's importer | Excluded |
| `imported/` | All ROM-derived graphics, dialogue, maps, palettes, and generated resources | Excluded |
| `.godot/` | Editor state and processed texture caches | Excluded |
| `exports/` | Local build outputs | Excluded |

The importer reads a supplied ROM and regenerates `imported/` locally. There is
no ROM download code and no runtime dependency on the ROM. Without generated
resources, the project runs the hand-authored placeholder rooms. No generated
textures or map data belong under `content/`; copying imported resources there
is for private editing, and those copies must be excluded before sharing.

## Prepare a source-only copy

From the project directory, choose a new destination outside the project:

```sh
python3 tools/prepare_public_project.py /tmp/zelda-godot-public
```

This copies an explicit list of source directories and project files, omitting
all local input, generated content, engine caches, and loose files. It refuses to
overwrite an existing destination. Review any privately edited copies under
`content/` before using it; the tool cannot establish the origin of arbitrary
future files placed there.

Importing a ROM remains an optional setup step for someone who has their own
input. See [import instructions](IMPORTING.md).

Git ignore rules protect normal source commits, not arbitrary Godot game exports
or manually created archives. A private export from the imported project may
contain its imported resources. Use the source-only copy for a public source
repository and verify any separately distributed game build's contents.

The original disassembly remains outside this boundary and unchanged. A future
standalone repository should be created from the source-only Godot snapshot,
not by copying the parent repository or its Git history.
