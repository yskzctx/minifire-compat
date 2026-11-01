#include "../vendor/dobby.h"
#include <dlfcn.h>
#include <jni.h>
#include <cstring>

using OnLoaded = void(*)(const char*, void*);
struct NativeAPIEntries { unsigned version; int(*hook)(void*,void*,void**); int(*unhook)(void*); };
extern "C" OnLoaded native_init(const NativeAPIEntries*);
extern "C" void Java_com_codex_minifire_compatlab_NativeBridge_configure(JNIEnv*, jclass, jint);
static OnLoaded on_loaded = nullptr;
static void* (*original_dlopen)(const char*, int) = nullptr;
static void* (*original_ext)(const char*, int, const void*) = nullptr;

static bool game_library(const char* name) {
    if (!name) return false;
    const size_t n = strnlen(name, 4096);
    constexpr char suffix[] = "libtolua.so";
    return n < 4096 && n >= sizeof(suffix)-1 &&
        std::strcmp(name+n-sizeof(suffix)+1, suffix) == 0 &&
        (n == sizeof(suffix)-1 || name[n-sizeof(suffix)] == '/');
}
static void notify(const char* name, void* handle) {
    if (handle && on_loaded && game_library(name)) on_loaded(name, handle);
}
static void* replacement_dlopen(const char* name, int flags) {
    void* handle = original_dlopen(name, flags); notify(name, handle); return handle;
}
static void* replacement_ext(const char* name, int flags, const void* ext) {
    void* handle = original_ext(name, flags, ext); notify(name, handle); return handle;
}
static int hook(void* address, void* replacement, void** original) {
    return DobbyHook(address, replacement, original);
}
extern "C" __attribute__((visibility("default"))) int minifire_core_start(int) {
    const NativeAPIEntries entries{2, hook, nullptr};
    on_loaded = native_init(&entries);
    if (!on_loaded) return -1;
    Java_com_codex_minifire_compatlab_NativeBridge_configure(nullptr, nullptr, 5);
    void* plain = dlsym(RTLD_DEFAULT, "dlopen");
    void* extended = dlsym(RTLD_DEFAULT, "android_dlopen_ext");
    int count = 0;
    if (plain) count += DobbyHook(plain, reinterpret_cast<void*>(replacement_dlopen),
                                  reinterpret_cast<void**>(&original_dlopen)) == 0;
    if (extended) count += DobbyHook(extended, reinterpret_cast<void*>(replacement_ext),
                                     reinterpret_cast<void**>(&original_ext)) == 0;
    return count;
}
