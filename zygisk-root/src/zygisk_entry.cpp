#include <sys/types.h>
#include "../vendor/zygisk.hpp"
#include "../vendor/dobby.h"
#include "target_policy.hpp"
#include <android/log.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <jni.h>
#include <cstring>
#include <unistd.h>

using OnLoaded=void(*)(const char*,void*);
struct NativeAPIEntries{unsigned version;int(*hook)(void*,void*,void**);int(*unhook)(void*);};
extern "C" OnLoaded native_init(const NativeAPIEntries*);
extern "C" void Java_com_codex_minifire_compatlab_NativeBridge_configure(JNIEnv*,jclass,jint);
static OnLoaded on_loaded=nullptr;
static void* (*original_dlopen)(const char*,int)=nullptr;
static void* (*original_ext)(const char*,int,const void*)=nullptr;
static bool game_library(const char* name) {
    if (!name) return false;
    const size_t n=strnlen(name,4096); constexpr char suffix[]="libtolua.so";
    return n<4096 && n>=sizeof(suffix)-1 &&
        std::strcmp(name+n-sizeof(suffix)+1,suffix)==0 &&
        (n==sizeof(suffix)-1 || name[n-sizeof(suffix)]=='/');
}
static void notify(const char* name,void* handle) {
    if (handle && on_loaded && game_library(name)) on_loaded(name,handle);
}
static void* replacement_dlopen(const char* name,int flags) {
    void* handle=original_dlopen(name,flags); notify(name,handle); return handle;
}
static void* replacement_ext(const char* name,int flags,const void* ext) {
    void* handle=original_ext(name,flags,ext); notify(name,handle); return handle;
}
static int hook(void* address,void* replacement,void** original) {
    return DobbyHook(address,replacement,original);
}
class GameModule final:public zygisk::ModuleBase {
    zygisk::Api* api_=nullptr; JNIEnv* env_=nullptr; Target target_=Target::None;
public:
    void onLoad(zygisk::Api* api,JNIEnv* env) override { api_=api; env_=env; }
    void preAppSpecialize(zygisk::AppSpecializeArgs* args) override {
        const char* name=args->nice_name?env_->GetStringUTFChars(args->nice_name,nullptr):nullptr;
        const char* data=args->app_data_dir?env_->GetStringUTFChars(args->app_data_dir,nullptr):nullptr;
        target_=name&&data?target_process(name,data,args->uid):Target::None;
        if (name) env_->ReleaseStringUTFChars(args->nice_name,name);
        if (data) env_->ReleaseStringUTFChars(args->app_data_dir,data);
        if (target_!=Target::None) {
            int dir=api_->getModuleDir();
            if (dir<0) target_=Target::None;
            else {
                const char* config=target_==Target::Game?"game_enabled":"hunter_enabled";
                int fd=openat(dir,config,O_RDONLY|O_CLOEXEC|O_NOFOLLOW);
                char flag=0; bool enabled=fd>=0 && read(fd,&flag,1)==1 && flag=='1';
                if (!enabled) target_=Target::None;
                if (fd>=0) close(fd); close(dir);
            }
        }
        if (target_==Target::None) api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }
    void postAppSpecialize(const zygisk::AppSpecializeArgs*) override {
        if (target_==Target::None) return;
        const NativeAPIEntries entries{2,hook,nullptr}; on_loaded=native_init(&entries);
        Java_com_codex_minifire_compatlab_NativeBridge_configure(nullptr,nullptr,5);
        void* plain=dlsym(RTLD_DEFAULT,"dlopen");
        void* extended=dlsym(RTLD_DEFAULT,"android_dlopen_ext");
        int ok=0;
        if (plain) ok+=DobbyHook(plain,(void*)replacement_dlopen,(void**)&original_dlopen)==0;
        if (extended) ok+=DobbyHook(extended,(void*)replacement_ext,(void**)&original_ext)==0;
        __android_log_print(ok?ANDROID_LOG_INFO:ANDROID_LOG_WARN,"MinifireCompatZ","target=%d loader_hooks=%d",static_cast<int>(target_),ok);
    }
    void preServerSpecialize(zygisk::ServerSpecializeArgs*) override { api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY); }
};
REGISTER_ZYGISK_MODULE(GameModule)
