// Fixed verified prologue from the supported ARM64 libtolua encoder. This code
// stays in the module's ordinary file-backed executable segment, never an arena.
.text
.p2align 4
.global mf_encode_original
.hidden mf_encode_original
.type mf_encode_original,%function
.hidden mf_encode_resume
mf_encode_original:
    .inst 0xd503245f // BTI c; a harmless HINT on older CPUs.
    .inst 0xd10203ff // sub sp,sp,#0x80
    .inst 0xa9045ff8 // stp x24,x23,[sp,#0x40]
    .inst 0xa90557f6 // stp x22,x21,[sp,#0x50]
    .inst 0xa9064ff4 // stp x20,x19,[sp,#0x60]
    adrp x17,mf_encode_resume
    ldr x17,[x17,:lo12:mf_encode_resume]
    br x17
.size mf_encode_original,.-mf_encode_original
.section .note.GNU-stack,"",%progbits
