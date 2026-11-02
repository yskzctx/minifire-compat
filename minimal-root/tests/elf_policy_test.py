import importlib.util, pathlib, struct, unittest, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('elf_policy',ROOT/'tools/elf_policy.py')
policy=importlib.util.module_from_spec(spec);spec.loader.exec_module(policy)
class ElfPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with zipfile.ZipFile(ROOT.parent.parent/'outputs/Minifire-Minimal-Hook-2.0.1-candidate.zip') as archive:
            cls.binary=archive.read('zygisk/arm64-v8a.so')
    def test_successful_release_has_only_framework_exports_and_no_wx_load(self):
        info=policy.inspect(self.binary)
        self.assertEqual(info['exports'],['zygisk_companion_entry','zygisk_module_entry'])
        self.assertFalse(info['writable_executable_load']);self.assertFalse(info['executable_stack']);self.assertFalse(info['text_relocations'])
    def test_wx_segment_is_rejected(self):
        data=bytearray(self.binary);start=struct.unpack_from('<Q',data,32)[0];step,count=struct.unpack_from('<HH',data,54)
        for index in range(count):
            at=start+index*step
            if struct.unpack_from('<I',data,at)[0]==1:
                struct.pack_into('<I',data,at+4,7);break
        with self.assertRaisesRegex(ValueError,'writable_executable_load'): policy.inspect(data)
    def test_executable_stack_is_rejected(self):
        data=bytearray(self.binary);start=struct.unpack_from('<Q',data,32)[0];step,count=struct.unpack_from('<HH',data,54)
        for index in range(count):
            at=start+index*step
            if struct.unpack_from('<I',data,at)[0]==0x6474e551:
                struct.pack_into('<I',data,at+4,7);break
        else: self.fail('stack header missing from fixture')
        with self.assertRaisesRegex(ValueError,'executable_stack'): policy.inspect(data)
if __name__=='__main__': unittest.main(verbosity=2)
