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
    def test_case_rooms_must_be_overworld_or_level_ids(self):
        suite=m.read_json(m.SCENARIOS)
        self.assertEqual(m.allowed_rooms(suite,{'rooms':['ow_78','l1_73']}),{'ow_77','ow_78','l1_73'})
        for bad in ('cave_77','l0_73','l1_80','ow_7'):
            with self.assertRaises(ValueError):m.allowed_rooms(suite,{'rooms':[bad]})
    def test_a_button_joins_the_d_pad(self):
        self.assertEqual(m.expand({'segments':[{'buttons':['up','right','a'],'frames':1}]}),[['up','right','a']])
        self.assertEqual(m.BUTTONS['a'],0x80)
    def test_setup_frames_are_validated_like_segments(self):
        self.assertEqual(m.setup_frames({'segments':[]}),[])
        self.assertEqual(m.setup_frames({'setup':[{'buttons':['up'],'frames':2}]}),[['up'],['up']])
        with self.assertRaises(ValueError):m.setup_frames({'setup':[{'buttons':['up','down'],'frames':1}]})
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
        for buttons,frames in [(['up','down'],1),(['left','right'],1),(['up','up'],1),(['up','right','left'],1),(['b'],1),(['a','a'],1),([],True),([],0),([],1.5)]:
            with self.assertRaises(ValueError):m.expand({'segments':[{'buttons':buttons,'frames':frames}]})
    def test_authored_suite_pins_its_cases(self):
        suite=m.read_json(m.SCENARIOS); m.validate_suite(suite)
        self.assertEqual(len(suite['cases']),27)
        self.assertEqual(len({c['id'] for c in suite['cases']}),27)
        self.assertEqual(sum(len(m.expand(c)) for c in suite['cases']),16622)
    def test_inspect_shows_the_differing_slot_with_internals(self):
        ref,native=self.traces()
        ref['suite']['cases'][0]['objects']=True
        native['suite']=ref['suite']
        for trace in (ref,native): trace['suite_sha256']=m.digest(ref['suite'])
        for i,(e,o) in enumerate(zip(ref['cases'][0]['frames'],native['cases'][0]['frames'])):
            e['objects']=[[3,8,100+i,61,2]]; o['objects']=[[3,8,100+i,61,2]]
            e['raw']={'objects':{'3':{'timer':9-i}}}; o['raw']={'objects':{'3':{'timer':8-i}}}
        native['cases'][0]['frames'][2]['objects']=[[3,8,101,61,2]]
        self.assertEqual(m.differing_slots(ref['cases'][0]['frames'][2],native['cases'][0]['frames'][2]),([3],[]))
        text=m.inspect_text(ref,native)
        self.assertIn('DIFF synthetic at frame 3',text)
        self.assertIn("slot 3 nes [3, 8, 102, 61, 2] {'timer': 7}",text)
        self.assertIn("godot [3, 8, 101, 61, 2] {'timer': 6}",text)
        self.assertNotIn('link nes',text)
    def test_shots_and_the_beam_are_reported_apart_from_slots(self):
        e={'objects':[[1,8,0,0,1],['shot',83,5,5],['beam',9,9]]}
        o={'objects':[[1,8,0,0,1],['beam',9,9]]}
        self.assertEqual(m.differing_slots(e,o),([],['shot']))
    def test_capture_cache_depends_on_capture_code(self):
        self.assertEqual(len(m.CAPTURE_SOURCE),64)
    def test_autopilot_records_segments_and_swings_only_ahead(self):
        import route_autopilot as a
        self.assertEqual(a.segments([['up'],['up'],['up','a'],[]]),
                         [{'buttons':['up'],'frames':2},{'buttons':['up','a'],'frames':1},{'buttons':[],'frames':1}])
        snap={'x':100,'y':77,'objects':[[1,3,80,77,1],['shot',83,90,77]]}
        self.assertTrue(a.monster_ahead(snap,'left'))
        self.assertFalse(a.monster_ahead(snap,'right'))
        self.assertFalse(a.monster_ahead(snap,'up'))
    def test_generated_output_cannot_enter_shared_content(self):
        with self.assertRaises(ValueError):m.output_directory(ROOT/'content/capture')
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(m.output_directory(folder),Path(folder).resolve())

if __name__=='__main__':unittest.main()
