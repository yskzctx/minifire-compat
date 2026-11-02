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
    def test_fixed_backend_is_file_backed_and_has_no_allocator_import(self):
        data=(ROOT/'build/libminifire_minimal.release.so').read_bytes()
        result=policy.inspect_fixed(data)
        self.assertEqual(result['static_trampoline_matches'],1)
        self.assertEqual(result['executable_allocator_imports'],[])
    def test_fixed_backend_rejects_engine_marker(self):
        data=(ROOT/'build/libminifire_minimal.release.so').read_bytes()+b'Dobby'
        with self.assertRaisesRegex(ValueError,'engine_marker_present'): policy.inspect_fixed(data)
    def test_fixed_backend_rejects_changed_trampoline(self):
        data=bytearray((ROOT/'build/libminifire_minimal.release.so').read_bytes())
        signature=bytes.fromhex('5f2403d5ff0302d1f85f04a9f65705a9f44f06a9')
        at=data.find(signature);self.assertGreaterEqual(at,0);data[at+8]^=1
        with self.assertRaisesRegex(ValueError,'static_trampoline_missing'): policy.inspect_fixed(data)
if __name__=='__main__': unittest.main(verbosity=2)
