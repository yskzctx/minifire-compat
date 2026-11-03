"""Execute the verified game's luaopen_pb machine code on an emulated CPU.

Lua APIs are stubs which capture registration, not a real Android/Lua startup.
This checks registration addresses and writes, not settings or thread safety.
"""
import hashlib
import io
import json
from pathlib import Path
import struct
import unittest
from elftools.elf.elffile import ELFFile
from unicorn import Uc, UC_ARCH_ARM64, UC_MODE_ARM, UC_HOOK_CODE
from unicorn import arm64_const as r

ROOT = Path(__file__).resolve().parents[1]
DATA = (ROOT.parent.parent / 'work/apk-files/lib/arm64-v8a/libtolua.so').read_bytes()
PROFILE = json.loads((ROOT / 'src/generated/profile.json').read_text())
assert hashlib.sha256(DATA).hexdigest() == PROFILE['sha256']
ELF = ELFFile(io.BytesIO(DATA))
SYMS = {s.name: s['st_value'] for s in ELF.get_section_by_name('.dynsym').iter_symbols()}
BASE, STACK, TLS, STOP = 0x10000000, 0x20000000, 0x30000000, 0x40000000


def run_registration(prepatched, metatable_created):
    cpu = Uc(UC_ARCH_ARM64, UC_MODE_ARM)
    pages = set()
    for seg in ELF.iter_segments():
        if seg['p_type'] != 'PT_LOAD':
            continue
        lo = (BASE + seg['p_vaddr']) & ~4095
        hi = (BASE + seg['p_vaddr'] + seg['p_memsz'] + 4095) & ~4095
        for page in range(lo, hi, 4096):
            if page not in pages:
                cpu.mem_map(page, 4096); pages.add(page)
        cpu.mem_write(BASE + seg['p_vaddr'], seg.data())
    for relocation in ELF.get_section_by_name('.rela.dyn').iter_relocations():
        if relocation['r_info_type'] == 1027:
            cpu.mem_write(BASE + relocation['r_offset'], struct.pack('<Q', BASE + relocation['r_addend']))
    cpu.mem_map(STACK, 0x4000); cpu.mem_map(TLS, 4096); cpu.mem_map(STOP, 4096)
    cpu.reg_write(r.UC_ARM64_REG_SP, STACK + 0x3000)
    cpu.reg_write(r.UC_ARM64_REG_TPIDR_EL0, TLS)
    cpu.reg_write(r.UC_ARM64_REG_X30, STOP)
    # Only mutate the emulated copy. The game's original library is never written.
    entry = bytes.fromhex('5100005820021fd6') + struct.pack('<Q', STOP)
    if prepatched:
        cpu.mem_write(BASE + PROFILE['encode_rva'], entry)
    registration = {}

    def string_at(address):
        if not address:
            return None
        return bytes(cpu.mem_read(address, 80)).split(b'\0', 1)[0].decode('ascii')

    def hook(machine, address, size, _):
        offset = address - BASE
        if offset == PROFILE['encode_rva']:
            raise AssertionError('initializer unexpectedly executed encoder')
        # Call targets are pinned to this exact hash, independently inspected
        # from luaopen_pb. Stub only its external memcpy/Lua API dependencies.
        if offset == 0x10fa0:  # memcpy: copy the actual relocated registration data
            dest, source, length = [machine.reg_read(x) for x in
                                    [r.UC_ARM64_REG_X0, r.UC_ARM64_REG_X1, r.UC_ARM64_REG_X2]]
            machine.mem_write(dest, bytes(machine.mem_read(source, length)))
        elif offset == 0x10bc0:  # luaL_newmetatable
            machine.reg_write(r.UC_ARM64_REG_X0, metatable_created)
        elif offset == 0x10bb0:  # luaL_register
            name = string_at(machine.reg_read(r.UC_ARM64_REG_X1))
            table = machine.reg_read(r.UC_ARM64_REG_X2)
            if name == 'pb':
                for index in range(21):
                    key, value = struct.unpack('<QQ', bytes(machine.mem_read(table + index * 16, 16)))
                    if not key:
                        break
                    registration[string_at(key)] = value
        elif offset not in (0xff00, 0x10b30):  # lua_pushvalue, lua_setfield
            return
        machine.reg_write(r.UC_ARM64_REG_PC, machine.reg_read(r.UC_ARM64_REG_X30))

    cpu.hook_add(UC_HOOK_CODE, hook)
    cpu.emu_start(BASE + SYMS['luaopen_pb'], STOP, count=1000)
    assert cpu.reg_read(r.UC_ARM64_REG_PC) == STOP, 'initializer did not return'
    assert cpu.reg_read(r.UC_ARM64_REG_X0) == 1, 'unexpected Lua return count'
    return registration, bytes(cpu.mem_read(BASE + PROFILE['encode_rva'], 16))


class RegistrationLifecycleTests(unittest.TestCase):
    def test_initializer_registers_same_encoder_before_and_after_entry_change(self):
        for created in [0, 1]:
            with self.subTest(metatable_created=created):
                plain, original = run_registration(False, created)
                patched, entry = run_registration(True, created)
                self.assertEqual(plain, patched)
                self.assertEqual(plain['encode'], BASE + PROFILE['encode_rva'])
                self.assertEqual(original, bytes.fromhex(PROFILE['encode_prefix'])[:16])
                self.assertEqual(entry, bytes.fromhex('5100005820021fd6') + struct.pack('<Q', STOP))


if __name__ == '__main__':
    unittest.main(verbosity=2)
