#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
enum class PatchStage { InvalidArguments,UnexpectedPrefix,WritableFailed,RestoreFailed,Installed };
struct PatchResult {
    PatchStage stage=PatchStage::InvalidArguments;
    bool installed=false,bytes_restored=false,rx_restored=false;
    int error=0,restore_error=0;
};
struct PatchOps {
    int (*protect)(void*,std::size_t,int); // Return errno, zero on success.
    void (*flush)(void*,std::size_t);
};
// A fixed-version entry replacement, not a general instruction relocator.
// It only writes the verified 16-byte entry, never allocates executable memory.
inline PatchResult install_fixed_patch(void* target,std::uintptr_t replacement,
        const unsigned char* expected,std::size_t expected_size,std::size_t page_size,PatchOps ops) {
    PatchResult result;
    const auto address=reinterpret_cast<std::uintptr_t>(target);
    if(!address || address%16 || !replacement || replacement%4 || !expected || expected_size!=32 ||
        page_size<4096 || (page_size&(page_size-1)) || !ops.protect || !ops.flush) return result;
    if(std::memcmp(target,expected,expected_size)!=0) {result.stage=PatchStage::UnexpectedPrefix;return result;}
    const auto page=address&~(static_cast<std::uintptr_t>(page_size)-1);
    if(address-page>page_size-16) return result;
    std::array<unsigned char,16> original{};std::memcpy(original.data(),target,original.size());
    std::array<unsigned char,16> entry{0x51,0x00,0x00,0x58,0x20,0x02,0x1f,0xd6};
    for(std::size_t i=0;i<8;++i) entry[8+i]=static_cast<unsigned char>(replacement>>(8*i));
    result.error=ops.protect(reinterpret_cast<void*>(page),page_size,7);
    if(result.error) {result.stage=PatchStage::WritableFailed;return result;}
    // Keep execution enabled during this brief write: other functions share the
    // page. This does not provide stop-the-world or an atomic 16-byte code patch.
    std::memcpy(target,entry.data(),entry.size());ops.flush(target,entry.size());
    result.error=ops.protect(reinterpret_cast<void*>(page),page_size,5);
    if(!result.error) {result.stage=PatchStage::Installed;result.installed=true;result.rx_restored=true;return result;}
    // With a failed single-page restore the previous RWX protection remains.
    // Roll back the exact entry and retry RX; never report an installed hook.
    std::memcpy(target,original.data(),original.size());ops.flush(target,original.size());
    result.bytes_restored=true;result.restore_error=ops.protect(reinterpret_cast<void*>(page),page_size,5);
    result.rx_restored=result.restore_error==0;result.stage=PatchStage::RestoreFailed;
    return result;
}
