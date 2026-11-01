#include "../src/target_policy.hpp"
#include <cassert>
int main() {
    assert(target_process("com.miniworldroyale.sparkgame","/data/user/0/com.miniworldroyale.sparkgame",10468));
    assert(!target_process("com.miniworldroyale.sparkgame:service","/data/user/0/com.miniworldroyale.sparkgame",10468));
    assert(!target_process("com.bank.app","/data/user/0/com.bank.app",10468));
    assert(!target_process("system_server","/data/system",1000));
    assert(!target_process("com.miniworldroyale.sparkgame","/data/user/0/com.other",10468));
}
