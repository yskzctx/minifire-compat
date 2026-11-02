import importlib.util, json, pathlib, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('profile_generator',ROOT/'tools/profile.py')
profile=importlib.util.module_from_spec(spec);spec.loader.exec_module(profile)
class ProfileTests(unittest.TestCase):
    def test_known_library_proves_registration_and_generated_header(self):
        library=ROOT.parent.parent/'work/device-reinstalled-1.0.77/libtolua.so'
        result=profile.inspect(library)
        self.assertEqual(result,json.loads((ROOT/'src/generated/profile.json').read_text()))
        self.assertEqual(profile.generate(result),(ROOT/'src/generated/profile.hpp').read_text())
    def test_modified_library_is_rejected_before_addresses_are_used(self):
        data=bytearray((ROOT.parent.parent/'work/device-reinstalled-1.0.77/libtolua.so').read_bytes());data[0x1bd60]^=1
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'modified.so';path.write_bytes(data)
            with self.assertRaisesRegex(ValueError,'unsupported libtolua SHA256'): profile.inspect(path)
if __name__=='__main__': unittest.main(verbosity=2)
