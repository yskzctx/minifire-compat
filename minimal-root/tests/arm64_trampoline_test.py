"""CPU-level checks of the actual linked file trampoline, not Android acceptance."""
import io, json, random, struct, unittest
from pathlib import Path
from elftools.elf.elffile import ELFFile
from unicorn import Uc, UC_ARCH_ARM64, UC_MODE_ARM
from unicorn import arm64_const as reg

ROOT=Path(__file__).resolve().parents[1]
IMAGE=ELFFile(io.BytesIO((ROOT/'build/libminifire_minimal.so').read_bytes()))
SYMBOLS={s.name:s['st_value'] for s in IMAGE.get_section_by_name('.symtab').iter_symbols()}
PROFILE=json.loads((ROOT/'src/generated/profile.json').read_text())
PREFIX=bytes.fromhex(PROFILE['encode_prefix'])
BASE=0x10000000;GAME=0x20000000;STACK=0x30000000;REPLACEMENT=0x50000000

def machine(seed):
    cpu=Uc(UC_ARCH_ARM64,UC_MODE_ARM);mapped=set()
    for segment in IMAGE.iter_segments():
        if segment['p_type']!='PT_LOAD': continue
        begin=(BASE+segment['p_vaddr'])&~4095
        end=(BASE+segment['p_vaddr']+segment['p_memsz']+4095)&~4095
        for page in range(begin,end,4096):
            if page not in mapped:cpu.mem_map(page,4096);mapped.add(page)
        cpu.mem_write(BASE+segment['p_vaddr'],segment.data())
    cpu.mem_map(GAME,4096);cpu.mem_write(GAME,PREFIX)
    cpu.mem_map(STACK,0x4000);cpu.mem_map(REPLACEMENT,4096)
    rng=random.Random(seed)
    for index in range(31):cpu.reg_write(getattr(reg,'UC_ARM64_REG_X'+str(index)),rng.getrandbits(64))
    for index in range(32):cpu.reg_write(getattr(reg,'UC_ARM64_REG_Q'+str(index)),rng.getrandbits(128))
    cpu.reg_write(reg.UC_ARM64_REG_SP,STACK+0x3000);cpu.reg_write(reg.UC_ARM64_REG_NZCV,0xa0000000)
    cpu.mem_write(STACK,bytes(rng.getrandbits(8) for _ in range(0x4000)))
    cpu.mem_write(BASE+SYMBOLS['mf_encode_resume'],struct.pack('<Q',GAME+16))
    return cpu

def snapshot(cpu):
    # x17 is the ABI's IP1 scratch register; it is intentionally used to branch.
    values=[cpu.reg_read(getattr(reg,'UC_ARM64_REG_X'+str(i))) for i in range(31) if i!=17]
    values += [cpu.reg_read(getattr(reg,'UC_ARM64_REG_Q'+str(i))) for i in range(32)]
    values += [cpu.reg_read(reg.UC_ARM64_REG_SP),cpu.reg_read(reg.UC_ARM64_REG_NZCV)]
    return values,bytes(cpu.mem_read(STACK+0x2f80,128))

class Arm64TrampolineTests(unittest.TestCase):
    def test_static_instructions_match_the_verified_original_prefix(self):
        symbol=SYMBOLS['mf_encode_original']
        for segment in IMAGE.iter_segments():
            if segment['p_type']=='PT_LOAD' and segment['p_vaddr']<=symbol<segment['p_vaddr']+segment['p_filesz']:
                at=symbol-segment['p_vaddr'];code=segment.data()[at:at+32];break
        else:self.fail('trampoline not file-backed')
        self.assertEqual(code[:4],bytes.fromhex('5f2403d5'))
        self.assertEqual(code[4:20],PREFIX[:16])
    def test_original_and_file_trampoline_preserve_registers_stack_and_resume(self):
        for seed in range(32):
            with self.subTest(seed=seed):
                original=machine(seed);fixed=machine(seed)
                original.emu_start(GAME,GAME+16,count=40)
                fixed.emu_start(BASE+SYMBOLS['mf_encode_original'],GAME+16,count=40)
                self.assertEqual(fixed.reg_read(reg.UC_ARM64_REG_PC),GAME+16)
                self.assertEqual(snapshot(fixed),snapshot(original))
    def test_entry_branch_keeps_arguments_and_returns_to_replacement(self):
        cpu=machine(72);before=snapshot(cpu)
        cpu.mem_write(GAME,bytes.fromhex('5100005820021fd6')+struct.pack('<Q',REPLACEMENT))
        cpu.emu_start(GAME,REPLACEMENT,count=8)
        self.assertEqual(cpu.reg_read(reg.UC_ARM64_REG_PC),REPLACEMENT)
        self.assertEqual(snapshot(cpu),before)

if __name__=='__main__':unittest.main(verbosity=2)
