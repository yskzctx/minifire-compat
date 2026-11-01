"""Fail-closed static fingerprint of the known 1.0.77 login signing method.

This identifies one fixed input. It does not reproduce or validate the
application-layer signature and does not inspect any live credentials.
"""

import hashlib
from pathlib import Path
import re
import struct

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
from elftools.elf.elffile import ELFFile


def _read_va(elf, stream, address, size):
    for segment in elf.iter_segments():
        start = segment["p_vaddr"]
        if start <= address and address + size <= start + segment["p_filesz"]:
            stream.seek(segment["p_offset"] + address - start)
            return stream.read(size)
    raise ValueError(f"unmapped ELF address: {address:#x}")


def _literal_usage_address(elf, stream, method_rva):
    code = _read_va(elf, stream, method_rva, 500)
    instructions = list(Cs(CS_ARCH_ARM64, CS_MODE_ARM).disasm(code, method_rva))
    candidates = []
    for position, instruction in enumerate(instructions):
        if instruction.mnemonic != "ldr" or instruction.op_str != "x22, [x8]":
            continue
        prefix = instructions[max(0, position - 6):position]
        loads = [item for item in prefix if item.mnemonic == "ldr" and
                 re.fullmatch(r"x8, \[x8, #0x[0-9a-f]+\]", item.op_str)]
        pages = [item for item in prefix if item.mnemonic == "adrp" and
                 re.fullmatch(r"x8, #0x[0-9a-f]+", item.op_str)]
        if len(loads) != 1 or len(pages) != 1 or pages[0].address >= loads[0].address:
            continue
        page = int(pages[0].op_str.split("#")[1], 16)
        offset = int(loads[0].op_str.split("#")[1].rstrip("]"), 16)
        candidates.append(page + offset)
    if len(candidates) != 1:
        raise ValueError("login signing literal reference changed or ambiguous")
    return candidates[0]


def inspect_signing_input(binary_path, metadata_path, http_method_rva, next_http_method_rva):
    binary = Path(binary_path).read_bytes()
    anchor = struct.pack("<QQ", http_method_rva, next_http_method_rva)
    if binary.count(anchor) != 1:
        raise ValueError("known HTTP method pointer pair absent or ambiguous")
    table_position = binary.index(anchor)
    sign_method_rva = struct.unpack_from("<Q", binary, table_position - 3 * 8)[0]
    with Path(binary_path).open("rb") as stream:
        elf = ELFFile(stream)
        literal_pointer_rva = _literal_usage_address(elf, stream, sign_method_rva)
        usage_pointer = struct.unpack("<Q", _read_va(elf, stream, literal_pointer_rva, 8))[0]
        usage = struct.unpack("<Q", _read_va(elf, stream, usage_pointer, 8))[0]
    if usage >> 29 != 5 or usage & 1 != 1:
        raise ValueError("unexpected string-literal metadata usage")
    literal_index = (usage & 0x1FFFFFFF) >> 1
    metadata = Path(metadata_path).read_bytes()
    encoded_header = struct.unpack_from("<6I", metadata)
    literal_table = encoded_header[2] ^ 0x66666666
    table_size = encoded_header[3] ^ 0x66666666
    literal_data = encoded_header[4] ^ 0x66666666
    data_size = encoded_header[5] ^ 0x66666666
    if literal_index >= table_size // 8:
        raise ValueError("literal index outside metadata table")
    length, offset = struct.unpack_from("<II", metadata, literal_table + literal_index * 8)
    if length > 256 or offset + length > data_size:
        raise ValueError("literal outside metadata data")
    literal = metadata[literal_data + offset:literal_data + offset + length]
    return {
        "client_sha256": hashlib.sha256(binary).hexdigest(),
        "sign_method_rva": hex(sign_method_rva),
        "literal_length": length,
        "literal_sha256": hashlib.sha256(literal).hexdigest(),
    }
