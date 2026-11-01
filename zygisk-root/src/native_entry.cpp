#include "login_filter.hpp"
#include "binary_guard.hpp"
#include <android/log.h>
#include <atomic>
#include <cstdint>
#include <dlfcn.h>
#include <jni.h>
#include <link.h>
#include <mutex>
#include <string_view>

// The application-process loader supplies the hook engine.
using HookFunction = int (*)(void*, void*, void**);
using UnhookFunction = int (*)(void*);
using OnLoaded = void (*)(const char*, void*);
struct NativeAPIEntries { std::uint32_t version; HookFunction hook; UnhookFunction unhook; };
static std::atomic<HookFunction> hook_function{nullptr};
static std::atomic<int> mode{0}, stage{0}, terminal_count{0}, lobby_count{0};
struct RequestStats {
    std::atomic<int> original_os{-1}, selected_os{-1}, original_channel{-1}, selected_channel{-1};
    std::atomic<int> version_profile{0};
};
static RequestStats terminal_stats, lobby_stats;
static LuaApi api{};
static LuaCFunction open_backup = nullptr, encode_backup = nullptr;
static LuaCFunction (*to_cfunction)(lua_State*, int) = nullptr;
static std::mutex install_mutex;
static bool library_ready = false, encoder_ready = false;
static void log_stage(int value) {
    __android_log_print(ANDROID_LOG_INFO,"MinifireCompatZ","native_stage=%d",value);
}

static std::string_view bounded_name(const char* name) {
    if (!name) return {};
    std::size_t size=0;
    while (size<4096 && name[size]) ++size;
    return size<4096 ? std::string_view(name,size) : std::string_view{};
}
static bool is_game_library(std::string_view name) {
    constexpr std::string_view suffix="libtolua.so";
    return name==suffix || (name.size()>suffix.size() &&
        name[name.size()-suffix.size()-1]=='/' && name.substr(name.size()-suffix.size())==suffix);
}
struct NoteCheck { void* base; bool found; };
static int check_library_note(dl_phdr_info* info, std::size_t, void* opaque) {
    auto* check=static_cast<NoteCheck*>(opaque);
    if (reinterpret_cast<void*>(info->dlpi_addr)!=check->base) return 0;
    for (std::size_t i=0; i<info->dlpi_phnum; ++i) {
        const auto& note=info->dlpi_phdr[i];
        if (note.p_type!=PT_NOTE || note.p_memsz>65536) continue;
        bool readable=false;
        for (std::size_t j=0; j<info->dlpi_phnum; ++j) {
            const auto& load=info->dlpi_phdr[j];
            if (load.p_type==PT_LOAD && (load.p_flags&PF_R) && note.p_vaddr>=load.p_vaddr &&
                note.p_vaddr-load.p_vaddr<=load.p_memsz &&
                note.p_memsz<=load.p_memsz-(note.p_vaddr-load.p_vaddr)) readable=true;
        }
        if (readable && matches_game_note(reinterpret_cast<const unsigned char*>(
                info->dlpi_addr+note.p_vaddr),note.p_memsz)) { check->found=true; return 1; }
    }
    return 1;
}
static int encode_replacement(lua_State* state) {
    // No lock or nontrivial destructor spans a Lua call: Lua can longjmp.
    const auto result=apply_login_filter(api,state,mode.load(std::memory_order_acquire));
    if (result.message) {
        auto& stats=result.message==1 ? terminal_stats : lobby_stats;
        stats.original_os.store(result.original_os); stats.selected_os.store(result.selected_os);
        stats.original_channel.store(result.original_channel); stats.selected_channel.store(result.selected_channel);
        stats.version_profile.store(result.version_profile ? 1 : 0);
        if (result.message==1) terminal_count.fetch_add(1); else lobby_count.fetch_add(1);
        __android_log_print(ANDROID_LOG_INFO,"MinifireCompatZ","login_filter message=%d applied=%d profile=%d",
                            result.message,result.applied?1:0,result.version_profile?1:0);
    }
    return encode_backup(state);
}
static LuaCFunction table_function(lua_State* state, int top, const char* key) {
    api.pushstring(state,key); api.rawget(state,top);
    const auto function=to_cfunction(state,-1); api.settop(state,top);
    return function;
}
static int open_replacement(lua_State* state) {
    const int results=open_backup(state);
    if (results!=1 || api.type(state,-1)!=5 || !api.checkstack(state,2)) return results;
    const int top=api.gettop(state);
    const auto encoder=table_function(state,top,"encode");
    Dl_info encode_info{};
    if (!encoder || !dladdr(reinterpret_cast<void*>(encoder),&encode_info)) return results;
    // The backup trampoline is outside the original library; compare against
    // a Lua API function still inside the verified game library instead.
    Dl_info api_info{};
    if (!dladdr(reinterpret_cast<void*>(api.gettop),&api_info) ||
        api_info.dli_fbase!=encode_info.dli_fbase) return results;
    {
        std::lock_guard<std::mutex> lock(install_mutex);
        if (encoder_ready) return results;
        const auto hook=hook_function.load();
        if (!hook || hook(reinterpret_cast<void*>(encoder),reinterpret_cast<void*>(encode_replacement),
                           reinterpret_cast<void**>(&encode_backup))!=0 || !encode_backup) {
            stage.store(-3); return results;
        }
        encoder_ready=true; stage.store(4); log_stage(4);
    }
    return results;
}
template<typename T> static T symbol(void* handle,const char* name) {
    return reinterpret_cast<T>(dlsym(handle,name));
}
static void on_loaded(const char* name, void* handle) {
    const int active_mode = mode.load();
    if (!handle || !is_game_library(bounded_name(name)) || (active_mode!=3 && active_mode!=4 && active_mode!=5)) return;
    std::lock_guard<std::mutex> lock(install_mutex);
    if (library_ready) return;
    const auto open=symbol<LuaCFunction>(handle,"luaopen_pb");
    Dl_info image{};
    if (!open || !dladdr(reinterpret_cast<void*>(open),&image)) { stage.store(-2); log_stage(-2); return; }
    NoteCheck check{image.dli_fbase,false}; dl_iterate_phdr(check_library_note,&check);
    if (!check.found) { stage.store(2); log_stage(2); return; }
    api={symbol<decltype(api.gettop)>(handle,"lua_gettop"),symbol<decltype(api.settop)>(handle,"lua_settop"),
        symbol<decltype(api.type)>(handle,"lua_type"),symbol<decltype(api.tolstring)>(handle,"lua_tolstring"),
        symbol<decltype(api.tonumber)>(handle,"lua_tonumber"),symbol<decltype(api.pushinteger)>(handle,"lua_pushinteger"),
        symbol<decltype(api.pushstring)>(handle,"lua_pushstring"),symbol<decltype(api.rawget)>(handle,"lua_rawget"),
        symbol<decltype(api.rawset)>(handle,"lua_rawset"),symbol<decltype(api.checkstack)>(handle,"lua_checkstack")};
    to_cfunction=symbol<decltype(to_cfunction)>(handle,"lua_tocfunction");
    if (!api.gettop || !api.settop || !api.type || !api.tolstring || !api.tonumber || !api.pushinteger ||
        !api.pushstring || !api.rawget || !api.rawset || !api.checkstack || !to_cfunction) {
        stage.store(-2); log_stage(-2); return;
    }
    const auto hook=hook_function.load();
    if (!hook || hook(reinterpret_cast<void*>(open),reinterpret_cast<void*>(open_replacement),
                       reinterpret_cast<void**>(&open_backup))!=0 || !open_backup) { stage.store(-3); return; }
    library_ready=true; stage.store(3); log_stage(3);
}
extern "C" __attribute__((visibility("default"),used)) OnLoaded native_init(const NativeAPIEntries* entries) {
    if (!entries || (entries->version!=1 && entries->version!=2) || !entries->hook) {
        stage.store(-1); return nullptr;
    }
    hook_function.store(entries->hook); return on_loaded;
}
extern "C" JNIEXPORT void JNICALL
Java_com_codex_minifire_compatlab_NativeBridge_configure(JNIEnv*,jclass,jint selected) {
    if (selected!=3 && selected!=4 && selected!=5) return;
    mode.store(selected,std::memory_order_release);
    if (!hook_function.load()) { stage.store(-1); return; }
    stage.store(1);
    // If the library has already loaded, install without loading or executing it.
    void* existing=dlopen("libtolua.so",RTLD_NOW|RTLD_NOLOAD);
    if (existing) { on_loaded("libtolua.so",existing); dlclose(existing); }
}
extern "C" JNIEXPORT jintArray JNICALL
Java_com_codex_minifire_compatlab_NativeBridge_snapshot(JNIEnv* env,jclass) {
    const jint values[]={stage.load(),terminal_count.load(),lobby_count.load(),
        terminal_stats.original_os.load(),terminal_stats.selected_os.load(),
        terminal_stats.original_channel.load(),terminal_stats.selected_channel.load(),
        lobby_stats.original_os.load(),lobby_stats.selected_os.load(),
        lobby_stats.original_channel.load(),lobby_stats.selected_channel.load(),
        -1000001,0,0,
        terminal_stats.version_profile.load(),lobby_stats.version_profile.load()};
    auto array=env->NewIntArray(16);
    if (array) env->SetIntArrayRegion(array,0,16,values);
    return array;
}
