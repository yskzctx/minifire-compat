#include "../src/fixed_patch.hpp"
#include <array>
#include <cassert>
#include <cstring>
#include <vector>
alignas(4096) static std::array<unsigned char,4096> memory{};
static std::vector<int> calls;
static int fail_write=0,fail_restore=0,flushes=0;
static int protect(void*,std::size_t,int mode) {
    calls.push_back(mode);
    if(mode==7 && fail_write) return 13;
    if(mode==5 && fail_restore-->0) return 1;
    return 0;
}
static void flush(void*,std::size_t) {++flushes;}
static void reset(){memory.fill(0x90);calls.clear();fail_write=fail_restore=flushes=0;}
int main(){
    const PatchOps ops{protect,flush};std::array<unsigned char,32> expected{};expected.fill(0x90);
    reset();auto result=install_fixed_patch(memory.data(),0x1122334455667788ULL,expected.data(),expected.size(),4096,ops);
    assert(result.installed && result.rx_restored && calls==std::vector<int>({7,5}) && flushes==1);
    const unsigned char jump[16]={0x51,0x00,0x00,0x58,0x20,0x02,0x1f,0xd6,0x88,0x77,0x66,0x55,0x44,0x33,0x22,0x11};
    assert(std::memcmp(memory.data(),jump,16)==0);
    reset();memory[7]^=1;result=install_fixed_patch(memory.data(),0x1000,expected.data(),expected.size(),4096,ops);
    assert(!result.installed && result.stage==PatchStage::UnexpectedPrefix && calls.empty());
    reset();fail_write=1;result=install_fixed_patch(memory.data(),0x1000,expected.data(),expected.size(),4096,ops);
    assert(!result.installed && result.stage==PatchStage::WritableFailed && calls==std::vector<int>({7}) && std::memcmp(memory.data(),expected.data(),32)==0);
    reset();fail_restore=1;result=install_fixed_patch(memory.data(),0x1000,expected.data(),expected.size(),4096,ops);
    assert(!result.installed && result.bytes_restored && result.rx_restored && result.stage==PatchStage::RestoreFailed && calls==std::vector<int>({7,5,5}) && flushes==2 && std::memcmp(memory.data(),expected.data(),32)==0);
    reset();fail_restore=2;result=install_fixed_patch(memory.data(),0x1000,expected.data(),expected.size(),4096,ops);
    assert(!result.installed && result.bytes_restored && !result.rx_restored && result.restore_error==1 && std::memcmp(memory.data(),expected.data(),32)==0);
    reset();result=install_fixed_patch(memory.data()+1,0x1000,expected.data(),expected.size(),4096,ops);
    assert(result.stage==PatchStage::InvalidArguments && calls.empty());
    reset();result=install_fixed_patch(memory.data(),0x1000,expected.data(),8,4096,ops);
    assert(result.stage==PatchStage::InvalidArguments && calls.empty());
}
