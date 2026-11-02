#include <sys/types.h>
#include "../../zygisk-root/vendor/zygisk.hpp"
#include "../../zygisk-root/vendor/dobby.h"
#include "../../app/src/main/cpp/login_filter.hpp"
#include "../../app/src/main/cpp/binary_guard.hpp"
#include "policy.hpp"
#include "generated/profile.hpp"
#include <android/log.h>
#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <link.h>
#include <pthread.h>
#include <sched.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

namespace {
constexpr const char* module_dir="/data/adb/modules/minifire_compat_zygisk";
int journal_fd=-1;
const volatile char* enabled_page=nullptr;
LuaApi lua{};
std::atomic<LuaCFunction> encoder{nullptr};
std::atomic<bool> installed{false}, encode_seen{false};
std::atomic<bool> journal_warning{false};

void event(const char* stage,const FilterResult* result=nullptr,int error=0) {
    char line[640]; timespec stamp{}; clock_gettime(CLOCK_REALTIME,&stamp);
    const int n=std::snprintf(line,sizeof(line),
        "{\"time_unix\":%lld,\"pid\":%d,\"stage\":\"%s\",\"error\":%d,\"message\":%d,\"applied\":%d,\"os_before\":%d,\"os_after\":%d,\"channel_before\":%d,\"channel_after\":%d,\"apple_version\":%d}\n",
        static_cast<long long>(stamp.tv_sec),getpid(),stage,error,result?result->message:0,
        result&&result->applied?1:0,result?result->original_os:-1,result?result->selected_os:-1,
        result?result->original_channel:-1,result?result->selected_channel:-1,result&&result->version_profile?1:0);
    if(n<=0 || static_cast<std::size_t>(n)>=sizeof(line)) return;
    struct stat info{};
    if(journal_fd>=0 && fstat(journal_fd,&info)==0 && info.st_size<1024*1024) {
        ssize_t count; do { count=write(journal_fd,line,static_cast<std::size_t>(n)); } while(count<0&&errno==EINTR);
        if(count!=n && !journal_warning.exchange(true))
            __android_log_print(ANDROID_LOG_WARN,"MinifireCompatM","private_log_append_failed errno=%d; system collector remains available",errno);
    }
    __android_log_print(ANDROID_LOG_INFO,"MinifireCompatM","%s",line);
}

int encode_replacement(lua_State* state) {
    // Installation publishes the trampoline before releasing this short barrier.
    while(!installed.load(std::memory_order_acquire)) sched_yield();
    const auto original=encoder.load(std::memory_order_acquire);
    if(!original) { event("encoder_trampoline_unavailable"); return 0; }
    if(!encode_seen.exchange(true)) event("encoder_called");
    if(enabled_page && *enabled_page=='1') {
        // No lock or C++ object requiring destruction may span Lua's longjmp.
        const auto result=apply_login_filter(lua,state,5);
        if(result.message) event(result.applied?(result.message==1?"terminal_login_rewritten":"lobby_login_rewritten"):"login_profile_rejected",&result);
    }
    return original(state);
}

bool readable(const dl_phdr_info* image,std::uintptr_t offset,std::size_t size,unsigned flags) {
    for(std::size_t i=0;i<image->dlpi_phnum;++i) {
        const auto& p=image->dlpi_phdr[i];
        if(p.p_type==PT_LOAD && (p.p_flags&flags)==flags && offset>=p.p_vaddr &&
            offset-p.p_vaddr<=p.p_memsz && size<=p.p_memsz-(offset-p.p_vaddr)) return true;
    }
    return false;
}
template<class T> T at(const dl_phdr_info* image,std::uintptr_t offset) {
    return reinterpret_cast<T>(image->dlpi_addr+offset);
}
int inspect_image(dl_phdr_info* image,std::size_t,void* output) {
    const auto name=std::string_view(image->dlpi_name?image->dlpi_name:"");
    constexpr auto suffix=std::string_view("libtolua.so");
    if(name!=suffix && !(name.size()>suffix.size() && name[name.size()-suffix.size()-1]=='/' && name.substr(name.size()-suffix.size())==suffix)) return 0;
    auto& found=*static_cast<bool*>(output); found=true;
    event("game_library_found");
    bool note_ok=false;
    for(std::size_t i=0;i<image->dlpi_phnum;++i) {
        const auto& p=image->dlpi_phdr[i];
        if(p.p_type==PT_NOTE && p.p_memsz<=65536 && readable(image,p.p_vaddr,p.p_memsz,PF_R) &&
            matches_game_note(at<const unsigned char*>(image,p.p_vaddr),p.p_memsz)) note_ok=true;
    }
    if(!note_ok) { event("client_build_id_rejected"); return 1; }
    if(!readable(image,encode_rva,sizeof(encode_prefix),PF_R|PF_X) ||
        std::memcmp(at<const void*>(image,encode_rva),encode_prefix,sizeof(encode_prefix))!=0) {
        event("encoder_code_rejected"); return 1;
    }
    const std::uintptr_t functions[]={lua_gettop_rva,lua_settop_rva,lua_type_rva,lua_tolstring_rva,lua_tonumber_rva,
        lua_pushinteger_rva,lua_pushstring_rva,lua_rawget_rva,lua_rawset_rva,lua_checkstack_rva};
    for(auto offset:functions) if(!readable(image,offset,4,PF_R|PF_X)) { event("lua_api_range_rejected"); return 1; }
    lua={at<decltype(lua.gettop)>(image,lua_gettop_rva),at<decltype(lua.settop)>(image,lua_settop_rva),
        at<decltype(lua.type)>(image,lua_type_rva),at<decltype(lua.tolstring)>(image,lua_tolstring_rva),
        at<decltype(lua.tonumber)>(image,lua_tonumber_rva),at<decltype(lua.pushinteger)>(image,lua_pushinteger_rva),
        at<decltype(lua.pushstring)>(image,lua_pushstring_rva),at<decltype(lua.rawget)>(image,lua_rawget_rva),
        at<decltype(lua.rawset)>(image,lua_rawset_rva),at<decltype(lua.checkstack)>(image,lua_checkstack_rva)};
    event("client_profile_verified");
    void* trampoline=nullptr;
    // The only DobbyHook call in this implementation. No loader/network/decode hooks.
    const int result=DobbyHook(at<void*>(image,encode_rva),reinterpret_cast<void*>(encode_replacement),&trampoline);
    encoder.store(reinterpret_cast<LuaCFunction>(trampoline),std::memory_order_release);
    installed.store(true,std::memory_order_release);
    event(result==0 && trampoline?"hook_installed":"hook_install_failed",nullptr,result);
    return 1;
}
void* worker(void*) {
    event("waiting_game_library");
    for(int attempt=0;attempt<2100;++attempt) {
        if(!enabled_page || *enabled_page!='1') { event("disabled_before_hook"); return nullptr; }
        bool found=false;
        // Keep the dynamic linker's enumeration lock while validating/installing,
        // so the inspected image cannot unload between range checks and the hook.
        dl_iterate_phdr(inspect_image,&found);
        if(found) return nullptr;
        usleep(attempt<1000?10000:100000);
    }
    event("game_library_wait_timeout"); return nullptr;
}

bool small_file(int directory,const char* name,char* value,std::size_t capacity) {
    int fd=openat(directory,name,O_RDONLY|O_CLOEXEC|O_NOFOLLOW);
    if(fd<0) return false;
    struct stat info{};
    const bool safe=fstat(fd,&info)==0 && S_ISREG(info.st_mode) && info.st_uid==0 && !(info.st_mode&0022) && info.st_size>0 && static_cast<std::size_t>(info.st_size)<capacity;
    const ssize_t n=safe?read(fd,value,capacity-1):-1; close(fd);
    if(n<=0) return false;
    value[n]=0;
    std::size_t end=static_cast<std::size_t>(n);
    while(end && (value[end-1]=='\n'||value[end-1]=='\r')) value[--end]=0;
    return end>0;
}

struct Request { int uid; char package[256]; };
void companion_error(const char* stage) {
    __android_log_print(ANDROID_LOG_WARN,"MinifireCompatM","root_companion stage=%s errno=%d",stage,errno);
}
void companion(int socket) {
    timeval deadline{3,0}; setsockopt(socket,SOL_SOCKET,SO_RCVTIMEO,&deadline,sizeof(deadline));
    Request request{};
    if(recv(socket,&request,sizeof(request),MSG_WAITALL)!=sizeof(request) || request.package[255]!=0 || !valid_package(request.package)) { companion_error("invalid_request"); return; }
    int dir=open(module_dir,O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW);
    if(dir<0) { companion_error("module_directory_open_failed"); return; }
    char package[256]{},flag[8]{};
    bool valid=small_file(dir,"target_package",package,sizeof(package)) && std::strcmp(package,request.package)==0 &&
        small_file(dir,"game_enabled",flag,sizeof(flag)) && std::strcmp(flag,"1")==0;
    // Confirm the selected app identity against the root package registry, not
    // an untrusted caller-supplied UID. Other Android users share the app ID.
    bool uid_ok=false;
    FILE* packages=std::fopen("/data/system/packages.list","r");
    char row[4096],registered[256]; int uid=0;
    if(packages) {
        while(std::fgets(row,sizeof(row),packages)) if(std::sscanf(row,"%255s %d",registered,&uid)==2 &&
            std::strcmp(registered,package)==0 && request.uid>=10000 && request.uid%100000==uid%100000) { uid_ok=true; break; }
        std::fclose(packages);
    }
    if(!valid || !uid_ok) { companion_error(!valid?"config_target_or_switch_rejected":"package_registry_uid_rejected"); close(dir); return; }
    mkdirat(dir,"state",0700);
    int state=openat(dir,"state",O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW);
    struct stat state_info{};
    if(state<0 || fstat(state,&state_info)!=0 || state_info.st_uid!=0 || (state_info.st_mode&0077)) {
        companion_error("root_state_permissions_rejected");
        if(state>=0) close(state); close(dir); return;
    }
    int fds[2]={openat(dir,"game_enabled",O_RDONLY|O_CLOEXEC|O_NOFOLLOW),
        openat(state,"hooks.jsonl",O_WRONLY|O_APPEND|O_CREAT|O_CLOEXEC|O_NOFOLLOW,0600)};
    struct stat log_info{};
    if(fds[0]>=0 && fds[1]>=0 && fstat(fds[1],&log_info)==0 && S_ISREG(log_info.st_mode) && log_info.st_uid==0 && !(log_info.st_mode&0077)) {
        char ok=1; iovec payload{&ok,1};
        alignas(cmsghdr) char control[CMSG_SPACE(sizeof(fds))]{};
        msghdr message{}; message.msg_iov=&payload; message.msg_iovlen=1;
        message.msg_control=control; message.msg_controllen=sizeof(control);
        auto* header=CMSG_FIRSTHDR(&message); header->cmsg_level=SOL_SOCKET; header->cmsg_type=SCM_RIGHTS; header->cmsg_len=CMSG_LEN(sizeof(fds));
        std::memcpy(CMSG_DATA(header),fds,sizeof(fds));
        if(sendmsg(socket,&message,MSG_NOSIGNAL)!=1) companion_error("fd_transfer_failed");
    } else companion_error("config_or_log_open_failed");
    for(int fd:fds) if(fd>=0) close(fd);
    close(state); close(dir);
}

class Module final:public zygisk::ModuleBase {
    zygisk::Api* api_=nullptr; JNIEnv* env_=nullptr; bool selected_=false;
public:
    void onLoad(zygisk::Api* api,JNIEnv* env) override { api_=api; env_=env; }
    void preAppSpecialize(zygisk::AppSpecializeArgs* args) override {
        int dir=api_->getModuleDir(); char package[256]{},flag[8]{};
        const bool configured=dir>=0 && small_file(dir,"target_package",package,sizeof(package)) && small_file(dir,"game_enabled",flag,sizeof(flag)) && std::strcmp(flag,"1")==0;
        if(dir>=0) close(dir);
        const char* name=args->nice_name?env_->GetStringUTFChars(args->nice_name,nullptr):nullptr;
        const char* data=args->app_data_dir?env_->GetStringUTFChars(args->app_data_dir,nullptr):nullptr;
        selected_=configured && name && data && selected_process(name,data,args->uid,package);
        if(name) env_->ReleaseStringUTFChars(args->nice_name,name);
        if(data) env_->ReleaseStringUTFChars(args->app_data_dir,data);
        if(!selected_) { api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY); return; }
        int socket=api_->connectCompanion();
        if(socket<0) { fail("root_companion_unavailable"); return; }
        timeval deadline{3,0}; setsockopt(socket,SOL_SOCKET,SO_RCVTIMEO,&deadline,sizeof(deadline));
        Request request{}; request.uid=args->uid; std::memcpy(request.package,package,std::strlen(package)+1);
        if(send(socket,&request,sizeof(request),MSG_NOSIGNAL)!=sizeof(request)) { close(socket); fail("root_companion_send_failed"); return; }
        char ok=0; iovec payload{&ok,1}; alignas(cmsghdr) char control[CMSG_SPACE(2*sizeof(int))]{};
        msghdr message{};message.msg_iov=&payload;message.msg_iovlen=1;message.msg_control=control;message.msg_controllen=sizeof(control);
        const auto received=recvmsg(socket,&message,MSG_CMSG_CLOEXEC); close(socket);
        auto* header=CMSG_FIRSTHDR(&message); int fds[2]={-1,-1};
        if(received!=1 || ok!=1 || (message.msg_flags&MSG_CTRUNC) || !header || header->cmsg_level!=SOL_SOCKET || header->cmsg_type!=SCM_RIGHTS || header->cmsg_len!=CMSG_LEN(sizeof(fds))) {
            fail("root_companion_config_or_log_failed"); return;
        }
        std::memcpy(fds,CMSG_DATA(header),sizeof(fds));
        void* page=mmap(nullptr,4096,PROT_READ,MAP_SHARED,fds[0],0); close(fds[0]);
        if(page==MAP_FAILED || !api_->exemptFd(fds[1])) { if(page!=MAP_FAILED) munmap(page,4096);close(fds[1]);fail("config_mapping_or_log_fd_failed");return; }
        enabled_page=static_cast<const volatile char*>(page);journal_fd=fds[1];
        event("target_selected");
    }
    void postAppSpecialize(const zygisk::AppSpecializeArgs*) override {
        if(!selected_) return;
        pthread_t thread;const int code=pthread_create(&thread,nullptr,worker,nullptr);
        if(code!=0) event("hook_worker_failed",nullptr,code);else pthread_detach(thread);
    }
    void preServerSpecialize(zygisk::ServerSpecializeArgs*) override { api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY); }
private:
    void fail(const char* stage) { selected_=false; event(stage,nullptr,errno);api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY); }
};
}
REGISTER_ZYGISK_MODULE(Module)
REGISTER_ZYGISK_COMPANION(companion)
