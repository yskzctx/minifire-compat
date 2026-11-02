"""Release integrity checks, not a runtime anti-detection mechanism."""
import json, struct, sys
from pathlib import Path

def inspect(source):
    data=bytes(source)
    if len(data)<64 or data[:6]!=b'\x7fELF\x02\x01' or struct.unpack_from('<HH',data,16)!=(3,183):
        raise ValueError('android_arm64_shared_elf_required')
    phoff,shoff=struct.unpack_from('<QQ',data,32)
    phsize,phnum,shsize,shnum,shnames=struct.unpack_from('<HHHHH',data,54)
    if phsize<56 or shsize<64 or not phnum or not shnum or phoff+phsize*phnum>len(data) or shoff+shsize*shnum>len(data):
        raise ValueError('elf_header_ranges_invalid')
    programs=[struct.unpack_from('<IIQQQQQQ',data,phoff+i*phsize) for i in range(phnum)]
    sections=[struct.unpack_from('<IIQQQQIIQQ',data,shoff+i*shsize) for i in range(shnum)]
    def content(index):
        if not 0<=index<len(sections): raise ValueError('section_index_invalid')
        s=sections[index]
        if s[4]+s[5]>len(data): raise ValueError('section_range_invalid')
        return data[s[4]:s[4]+s[5]]
    def string(table,offset):
        if offset<0 or offset>=len(table): raise ValueError('string_offset_invalid')
        end=table.find(b'\0',offset)
        if end<0: raise ValueError('string_unterminated')
        return table[offset:end].decode('ascii')
    names=content(shnames);section_names=[string(names,s[0]) for s in sections]
    exports=[];dependencies=[];textrel=False;now=False
    for i,s in enumerate(sections):
        if s[1]==11:  # SHT_DYNSYM
            symbols=content(i);strings=content(s[6]);step=s[9]
            if step<24 or len(symbols)%step: raise ValueError('dynsym_invalid')
            for at in range(0,len(symbols),step):
                name,info,visibility,index,_,_=struct.unpack_from('<IBBHQQ',symbols,at)
                if name and index and info>>4 in (1,2) and visibility&3 in (0,3): exports.append(string(strings,name))
        if s[1]==6:  # SHT_DYNAMIC
            values=content(i);strings=content(s[6])
            for at in range(0,len(values),16):
                tag,value=struct.unpack_from('<qQ',values,at)
                if tag==1: dependencies.append(string(strings,value))
                if tag==22 or (tag==30 and value&4): textrel=True
                if tag==24 or (tag==30 and value&8) or (tag==0x6ffffffb and value&1): now=True
    result=dict(exports=sorted(exports),dependencies=sorted(dependencies),
        writable_executable_load=any(p[0]==1 and p[1]&3==3 for p in programs),
        executable_stack=any(p[0]==0x6474e551 and p[1]&1 for p in programs),
        text_relocations=textrel,full_relro=now and any(p[0]==0x6474e552 for p in programs),
        minimum_load_alignment=min(p[7] for p in programs if p[0]==1),
        debug_sections=[n for n in section_names if n.startswith(('.debug','.zdebug')) or n=='.symtab'])
    for key in ['writable_executable_load','executable_stack','text_relocations']:
        if result[key]: raise ValueError(key)
    if result['exports']!=['zygisk_companion_entry','zygisk_module_entry']: raise ValueError('unexpected_exports')
    if set(dependencies)-{'libc.so','libdl.so','liblog.so','libm.so'}: raise ValueError('unexpected_dependency')
    if not result['full_relro'] or result['minimum_load_alignment']<16384 or result['debug_sections']:
        raise ValueError('release_hardening_missing')
    return result

if __name__=='__main__': print(json.dumps(inspect(Path(sys.argv[1]).read_bytes()),indent=2))
