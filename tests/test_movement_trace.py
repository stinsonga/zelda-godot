"""ROM-free checks that the comparator detects rather than hides differences."""
from copy import deepcopy
from pathlib import Path
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import movement_trace as m

class MovementTraceTests(unittest.TestCase):
    def traces(self):
        suite=m.read_json(m.SCENARIOS)
        suite['cases']=[{'id':'synthetic','segments':[{'buttons':['right'],'frames':3}]}]
        initial={'room':'ow_77','x':120,'y':77,'direction':8,'raw':{}}
        rows=[{'frame':i,'buttons':['right'],'room':'ow_77','x':120+i,'y':77,'direction':1,'phase':'play','raw':{}} for i in range(1,4)]
        ref={'schema':1,'engine':'nes','suite':suite,'suite_sha256':m.digest(suite),'rom_prg_sha1':'synthetic',
             'core':{'name':'synthetic'},'cases':[{'id':'synthetic','initial':initial,'frames':rows}]}
        native=deepcopy(ref); native['engine']='godot'
        return ref,native
    def test_equal_frames_match(self):
        self.assertTrue(m.compare(*self.traces())['matched'])
    def test_reports_first_difference_without_alignment(self):
        ref,native=self.traces()
        native['cases'][0]['frames'][1]['x']+=1
        native['cases'][0]['frames'][2]['direction']=8
        result=m.compare(ref,native)['cases'][0]
        self.assertEqual(result['different_frames'],2)
        self.assertEqual(result['first_difference']['frame'],2)
        self.assertEqual(result['first_difference']['fields'],['x'])
        self.assertEqual(result['first_difference']['delta'],{'x':1,'y':0})
        self.assertIn('First difference: frame 2',m.report_text(m.compare(ref,native)))
    def test_phase_is_compared_on_every_frame(self):
        ref,native=self.traces()
        native['cases'][0]['frames'][1]['phase']='transition'
        result=m.compare(ref,native)['cases'][0]
        self.assertEqual(result['first_difference']['fields'],['phase'])
    def test_positions_are_not_compared_during_transitions(self):
        ref,native=self.traces()
        for trace in (ref,native): trace['cases'][0]['frames'][1]['phase']='transition'
        native['cases'][0]['frames'][1]['x']=0
        native['cases'][0]['frames'][1]['room']='ow_78'
        self.assertTrue(m.compare(ref,native)['matched'])
    def test_case_rooms_must_be_overworld_ids(self):
        suite=m.read_json(m.SCENARIOS)
        self.assertEqual(m.allowed_rooms(suite,{'rooms':['ow_78']}),{'ow_77','ow_78'})
        with self.assertRaises(ValueError):m.allowed_rooms(suite,{'rooms':['cave_77']})
    def test_diagnostic_fractions_are_not_equated(self):
        ref,native=self.traces()
        ref['cases'][0]['frames'][0]['raw']={'fraction':128}
        native['cases'][0]['frames'][0]['raw']={'subposition_x':31104}
        self.assertTrue(m.compare(ref,native)['matched'])
    def test_truncated_trace_rejected(self):
        ref,native=self.traces(); native['cases'][0]['frames'].pop()
        with self.assertRaisesRegex(ValueError,'frames'):m.compare(ref,native)
    def test_changed_input_or_frame_rejected(self):
        for field,value in [('buttons',[]),('frame',2)]:
            ref,native=self.traces(); native['cases'][0]['frames'][0][field]=value
            with self.assertRaisesRegex(ValueError,'phase'):m.compare(ref,native)
    def test_wrong_fingerprints_rejected(self):
        for field in ('suite_sha256','rom_prg_sha1'):
            ref,native=self.traces(); native[field]='wrong'
            with self.assertRaises(ValueError):m.compare(ref,native)
    def test_different_initial_state_rejected(self):
        ref,native=self.traces(); native['cases'][0]['initial']['x']+=1
        with self.assertRaisesRegex(ValueError,'Initial states'):m.compare(ref,native)
    def test_ambiguous_or_invalid_inputs_rejected(self):
        for buttons,frames in [(['up','down'],1),(['left','right'],1),(['up','up'],1),(['up','right','left'],1),(['a'],1),([],True),([],0),([],1.5)]:
            with self.assertRaises(ValueError):m.expand({'segments':[{'buttons':buttons,'frames':frames}]})
    def test_authored_suite_has_seventeen_cases(self):
        suite=m.read_json(m.SCENARIOS); m.validate_suite(suite)
        self.assertEqual(len(suite['cases']),17)
        self.assertEqual(len({c['id'] for c in suite['cases']}),17)
        self.assertEqual(sum(len(m.expand(c)) for c in suite['cases']),1509)
    def test_generated_output_cannot_enter_shared_content(self):
        with self.assertRaises(ValueError):m.output_directory(ROOT/'content/capture')
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(m.output_directory(folder),Path(folder).resolve())

if __name__=='__main__':unittest.main()
