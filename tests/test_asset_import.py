"""ROM-free tests for staging, rollback, catalogs and invalid-ROM preservation."""
from pathlib import Path
import json
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import import_assets as assets
from import_rom import png, PRG_SHA1

class AssetImportTests(unittest.TestCase):
    def project(self, directory):
        project=Path(directory)/'game';(project/'scripts').mkdir(parents=True)
        (project/'project.godot').write_text('config_version=5')
        (project/'scripts/room_definition.gd').write_text('extends Resource')
        (project/'imported').mkdir();(project/'imported/old.txt').write_text('previous library')
        return project
    def fake_import(self, prg, output, progress):
        output.mkdir(parents=True)
        progress(.5,'Fake extraction')
        for name in ['world.tres','world_q2.tres','theme.tres']:(output/name).write_text('generated')
        (output/'manifest.json').write_text(json.dumps({'prg_sha1':PRG_SHA1}))
        (output/'audio').mkdir();(output/'audio/manifest.json').write_text('{}')
        png(output/'sprite.png',16,16,bytes([255,255,255,255])*256)
    def test_invalid_rom_preserves_existing_import(self):
        with tempfile.TemporaryDirectory() as folder:
            project=self.project(folder);rom=Path(folder)/'bad.nes';rom.write_bytes(b'not a rom')
            code,status=assets.run(rom,project)
            self.assertEqual(code,1);self.assertEqual(status['state'],'failed')
            self.assertIn('header',status['message'])
            self.assertEqual((project/'imported/old.txt').read_text(),'previous library')
    def test_failed_extraction_never_activates_partial_library(self):
        with tempfile.TemporaryDirectory() as folder:
            project=self.project(folder)
            def failing(prg,output,progress):
                output.mkdir();(output/'partial.txt').write_text('partial');raise ValueError('decoder failed')
            with patch.object(assets,'read_rom',return_value=b'valid'),patch.object(assets,'import_rom',side_effect=failing):
                code,status=assets.run('unused',project)
            self.assertEqual(code,1);self.assertEqual(status['message'],'decoder failed')
            self.assertTrue((project/'imported/old.txt').exists())
            self.assertFalse((project/'reference-inputs/import-jobs/import.lock').exists())
    def test_success_activates_catalog_and_keeps_backup(self):
        with tempfile.TemporaryDirectory() as folder:
            project=self.project(folder)
            with patch.object(assets,'read_rom',return_value=b'valid'),patch.object(assets,'import_rom',side_effect=self.fake_import):
                code,status=assets.run('unused',project)
            self.assertEqual(code,0);self.assertEqual(status['state'],'complete')
            self.assertFalse((project/'imported/old.txt').exists())
            self.assertEqual((Path(status['backup'])/'old.txt').read_text(),'previous library')
            catalog=json.loads((project/'imported/editor_catalog.json').read_text())
            self.assertEqual(catalog['source']['prg_sha1'],PRG_SHA1)
            self.assertEqual(catalog['entries'][0]['path'],'sprite.png')
            self.assertEqual(json.loads((Path(status['job'])/'status.json').read_text())['state'],'complete')
    def test_validate_only_does_not_generate_or_lock(self):
        with tempfile.TemporaryDirectory() as folder:
            project=self.project(folder)
            with patch.object(assets,'read_rom',return_value=b'valid'),patch.object(assets,'import_rom') as decoder:
                code,status=assets.run('unused',project,validate_only=True)
            decoder.assert_not_called();self.assertEqual(code,0)
            self.assertEqual(status['state'],'validated');self.assertTrue((project/'imported/old.txt').exists())
    def test_activation_failure_restores_previous_library(self):
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder);target=folder/'imported';target.mkdir();(target/'old').write_text('old')
            with self.assertRaises(FileNotFoundError):assets.activate(folder/'missing-stage',target,folder/'backup')
            self.assertEqual((target/'old').read_text(),'old');self.assertFalse((folder/'backup').exists())
    def test_concurrent_import_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            project=self.project(folder)
            lock=project/'reference-inputs/import-jobs/import.lock';lock.mkdir(parents=True)
            with patch.object(assets,'read_rom',return_value=b'valid'),patch.object(assets,'import_rom') as decoder:
                code,status=assets.run('unused',project)
            self.assertEqual(code,1);self.assertIn('Another import',status['message'])
            decoder.assert_not_called();self.assertTrue(lock.exists())
    def test_catalog_categories_and_dimensions(self):
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder);(folder/'levels').mkdir();(folder/'title').mkdir()
            for name in ['sprite.png','levels/level_1.png','title/atlas.png','hud_tiles.png']:
                png(folder/name,16,16,bytes([0,0,0,255])*256)
            catalog=assets.build_catalog(folder)
            entries={entry['path']:entry for entry in catalog['entries']}
            self.assertEqual(entries['levels/level_1.png']['category'],'tiles')
            self.assertEqual(entries['title/atlas.png']['category'],'interface')
            self.assertEqual(entries['sprite.png']['width'],16)
    def test_catalog_rejects_invalid_png_and_symlink(self):
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder);(folder/'bad.png').write_bytes(b'bad')
            with self.assertRaisesRegex(ValueError,'PNG'):assets.build_catalog(folder)
            (folder/'bad.png').unlink();(folder/'linked.png').symlink_to('/tmp/no-such-image')
            with self.assertRaisesRegex(ValueError,'symlink'):assets.build_catalog(folder)
    def test_job_and_output_stay_within_local_boundary(self):
        with tempfile.TemporaryDirectory() as folder:
            project=self.project(folder)
            with self.assertRaisesRegex(ValueError,'job directory'):assets.run('unused',project,Path(folder)/'public')
            with self.assertRaisesRegex(ValueError,'game project'):assets.run('unused',Path(folder))
    def test_godot_failure_is_reported_after_assets_are_installed(self):
        with tempfile.TemporaryDirectory() as folder:
            project=self.project(folder)
            with patch.object(assets,'read_rom',return_value=b'valid'),patch.object(assets,'import_rom',side_effect=self.fake_import):
                code,status=assets.run('unused',project,godot=Path(folder)/'missing-godot')
            self.assertEqual(code,0);self.assertEqual(status['state'],'complete')
            self.assertTrue(status['warnings']);self.assertTrue((project/'imported/editor_catalog.json').exists())

if __name__=='__main__':unittest.main()
