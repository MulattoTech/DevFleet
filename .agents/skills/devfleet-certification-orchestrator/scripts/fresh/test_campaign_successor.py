import importlib.util, json, pathlib, tempfile, unittest
HERE=pathlib.Path(__file__).parent
class SuccessorTests(unittest.TestCase):
 def setUp(self):
  spec=importlib.util.spec_from_file_location('journal',HERE/'fresh_attempts.py');self.m=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.m)
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=pathlib.Path(self.temp.name)
  self.auth=self.root/'old-auth.md';self.auth.write_text('Original user request')
  self.old=self.root/'old.json';self.m.initialize(self.old,self.auth,[])
  self.auth2=self.root/'new-auth.md';self.auth2.write_text('New user explicitly requests full new allowance')
  self.new=self.root/'new.json';self.policy='DF-FRESH-CERTIFICATION-20260926-R2'
 def test_successor_starts_full_preserving_parent_bytes(self):
  before=self.old.read_bytes();self.m.initialize(self.new,self.auth2,[self.old],policy_id=self.policy)
  self.assertEqual(self.old.read_bytes(),before);self.assertEqual(self.m.status(self.new)['remaining'],self.m.LIMITS)
  self.assertEqual(self.m.status(self.new)['policyId'],self.policy)
 def test_successor_requires_parent(self):
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth2,[],policy_id=self.policy)
 def test_successor_cannot_reuse_old_authorization(self):
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth,[self.old],policy_id=self.policy)
 def test_unknown_policy_rejected(self):
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth2,[self.old],policy_id='unknown')
 def test_existing_successor_cannot_reset(self):
  self.m.initialize(self.new,self.auth2,[self.old],policy_id=self.policy)
  with self.assertRaises(ValueError):self.m.initialize(self.new,self.auth2,[self.old],policy_id=self.policy)
if __name__=='__main__':unittest.main()
