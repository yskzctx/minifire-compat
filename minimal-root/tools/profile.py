"""Generate a fixed, verified profile; never infer offsets from an unknown client."""
import argparse, hashlib, io, json, struct
from pathlib import Path
from elftools.elf.elffile import ELFFile

EXPECTED='7f61316eb49e95e416b2a96b744b3eb0cc94d9347bf3c3f5c5cf983bb18a05a6'
def inspect(path):
    data=Path(path).read_bytes()
    if hashlib.sha256(data).hexdigest()!=EXPECTED:
        raise ValueError('unsupported libtolua SHA256')
    elf=ELFFile(io.BytesIO(data))
    assert elf['e_machine']=='EM_AARCH64' and elf.little_endian
    loads=[s for s in elf.iter_segments() if s['p_type']=='PT_LOAD']
    def offset(address):
        for s in loads:
            if s['p_vaddr']<=address<s['p_vaddr']+s['p_filesz']:
                return s['p_offset']+address-s['p_vaddr']
        raise ValueError('address outside file')
    rel={r['r_offset']:r['r_addend'] for r in elf.get_section_by_name('.rela.dyn').iter_relocations() if r['r_info_type']==1027}
    def pointer(address): return rel.get(address,struct.unpack_from('<Q',data,offset(address))[0])
    table={}
    for address in range(0xb19a0,0xb19a0+0x150,16):
        name=pointer(address)
        if not name: break
        at=offset(name);end=data.find(b'\0',at,at+80)
        assert end>=0
        table[data[at:end].decode('ascii')]=pointer(address+8)
    encode=table['encode']; assert encode==0x1bd60
    names=['lua_gettop','lua_settop','lua_type','lua_tolstring','lua_tonumber','lua_pushinteger','lua_pushstring','lua_rawget','lua_rawset','lua_checkstack']
    symbols={s.name:s['st_value'] for s in elf.get_section_by_name('.dynsym').iter_symbols() if s.name in names}
    assert len(symbols)==len(names)
    for address in [encode,*symbols.values()]:
        assert any(s['p_flags']&1 and s['p_vaddr']<=address and address+32<=s['p_vaddr']+s['p_filesz'] for s in loads)
    note=elf.get_section_by_name('.note.gnu.build-id').data()
    return dict(sha256=EXPECTED,encode_rva=encode,encode_prefix=data[offset(encode):offset(encode)+32].hex(),api=symbols,note=note.hex())
def generate(profile):
    prefix=', '.join('0x'+profile['encode_prefix'][i:i+2] for i in range(0,64,2))
    lines=['#pragma once','#include <cstdint>','#include <cstddef>',
        '// Generated only after exact SHA256 and protobuf registration proof checks.',
        f'constexpr std::uintptr_t encode_rva=0x{profile["encode_rva"]:x};',
        f'constexpr unsigned char encode_prefix[32]={{{prefix}}};']
    for key,value in profile['api'].items(): lines.append(f'constexpr std::uintptr_t {key}_rva=0x{value:x};')
    return '\n'.join(lines)+'\n'
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('library');parser.add_argument('--out',type=Path,required=True);args=parser.parse_args()
    profile=inspect(args.library);args.out.mkdir(parents=True,exist_ok=True)
    (args.out/'profile.hpp').write_text(generate(profile),encoding='utf8')
    (args.out/'profile.json').write_text(json.dumps(profile,indent=2)+'\n',encoding='utf8')
    print(json.dumps(profile,indent=2))
