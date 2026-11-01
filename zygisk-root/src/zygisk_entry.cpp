#include <sys/types.h>
#include "../vendor/zygisk.hpp"
#include "target_policy.hpp"
#include <android/dlext.h>
#include <android/log.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <jni.h>
#include <unistd.h>

class GameModule final : public zygisk::ModuleBase {
    zygisk::Api* api_ = nullptr;
    JNIEnv* env_ = nullptr;
    Target target_ = Target::None;
    int core_fd_ = -1;
public:
    void onLoad(zygisk::Api* api, JNIEnv* env) override { api_ = api; env_ = env; }
    void preAppSpecialize(zygisk::AppSpecializeArgs* args) override {
        const char* name = args->nice_name ? env_->GetStringUTFChars(args->nice_name, nullptr) : nullptr;
        const char* data = args->app_data_dir ? env_->GetStringUTFChars(args->app_data_dir, nullptr) : nullptr;
        target_ = name && data ? target_process(name, data, args->uid) : Target::None;
        if (name) env_->ReleaseStringUTFChars(args->nice_name, name);
        if (data) env_->ReleaseStringUTFChars(args->app_data_dir, data);
        if (target_ == Target::None) { api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY); return; }

        int dir = api_->getModuleDir();
        if (dir < 0) { disable(-1); return; }
        const char* flag_name = target_ == Target::Game ? "game_enabled" : "hunter_enabled";
        int flag_fd = openat(dir, flag_name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
        char flag = 0;
        const bool enabled = flag_fd >= 0 && read(flag_fd, &flag, 1) == 1 && flag == '1';
        if (flag_fd >= 0) close(flag_fd);
        if (enabled) {
            core_fd_ = openat(dir, "lib/arm64-v8a/libminifire_core.so", O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
            if (core_fd_ >= 0 && !api_->exemptFd(core_fd_)) { close(core_fd_); core_fd_ = -1; }
        }
        close(dir);
        if (core_fd_ < 0) { disable(enabled ? -2 : 0); return; }
        __android_log_print(ANDROID_LOG_INFO, "MinifireCompatZ", "target=%d selected=1", static_cast<int>(target_));
    }
    void postAppSpecialize(const zygisk::AppSpecializeArgs*) override {
        if (core_fd_ < 0) return;
        android_dlextinfo ext{};
        ext.flags = ANDROID_DLEXT_USE_LIBRARY_FD;
        ext.library_fd = core_fd_;
        void* handle = android_dlopen_ext("libminifire_core.so", RTLD_NOW | RTLD_LOCAL, &ext);
        close(core_fd_); core_fd_ = -1;
        if (!handle) {
            __android_log_print(ANDROID_LOG_WARN, "MinifireCompatZ", "target=%d core_load_failed", static_cast<int>(target_));
            return;
        }
        using Start = int(*)(int);
        auto start = reinterpret_cast<Start>(dlsym(handle, "minifire_core_start"));
        int hooks = start ? start(static_cast<int>(target_)) : -1;
        __android_log_print(hooks > 0 ? ANDROID_LOG_INFO : ANDROID_LOG_WARN,
                            "MinifireCompatZ", "target=%d loader_hooks=%d", static_cast<int>(target_), hooks);
    }
    void preServerSpecialize(zygisk::ServerSpecializeArgs*) override {
        api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }
private:
    void disable(int reason) {
        __android_log_print(ANDROID_LOG_INFO, "MinifireCompatZ", "target=%d selected=0 reason=%d",
                            static_cast<int>(target_), reason);
        target_ = Target::None;
        api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }
};

REGISTER_ZYGISK_MODULE(GameModule)
