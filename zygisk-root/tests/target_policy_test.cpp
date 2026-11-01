#include "../src/target_policy.hpp"
#include <cassert>
int main() {
    assert(target_process("com.miniworldroyale.sparkgame","/data/user/0/com.miniworldroyale.sparkgame",10468)==Target::Game);
    assert(target_process("com.zhenxi.hunter","/data/user/0/com.zhenxi.hunter",10469)==Target::Hunter);
    assert(target_process("com.zhenxi.hunter:hunter_main_process","/data/user/0/com.zhenxi.hunter",10469)==Target::Hunter);
    assert(target_process("com.miniworldroyale.sparkgame:service","/data/user/0/com.miniworldroyale.sparkgame",10468)==Target::None);
    assert(target_process("com.zhenxi.hunter:other","/data/user/0/com.zhenxi.hunter",10469)==Target::None);
    assert(target_process("com.bank.app","/data/user/0/com.bank.app",10468)==Target::None);
    assert(target_process("system_server","/data/system",1000)==Target::None);
    assert(target_process("com.zhenxi.hunter","/data/user/0/com.other",10469)==Target::None);
    assert(target_process("com.zhenxi.hunter","/data/user/0/com.zhenxi.hunter",1000)==Target::None);
}
