package com.codex.minifire.compatlab;

final class NativeBridge {
    private NativeBridge() {}
    static native void configure(int mode);
    static native int[] snapshot();
}
