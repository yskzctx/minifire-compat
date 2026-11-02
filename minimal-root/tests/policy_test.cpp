#include "../src/policy.hpp"
#include <cassert>
#include <string>
int main() {
    constexpr auto game="com.miniworldroyale.sparkgame";
    assert(selected_process(game,"/data/user/0/com.miniworldroyale.sparkgame",10240,game));
    assert(selected_process(game,"/data/user/10/com.miniworldroyale.sparkgame",1010240,game));
    assert(!selected_process("com.miniworldroyale.sparkgame:service","/data/user/0/com.miniworldroyale.sparkgame",10240,game));
    assert(!selected_process(game,"/data/user/0/com.example.bank",10240,game));
    assert(!selected_process(game,"/data/user/0/com.miniworldroyale.sparkgame",99001,game));
    assert(!selected_process(game,"/data/user/0/com.miniworldroyale.sparkgame",1000,game));
    assert(!valid_package("com.game;id") && !valid_package("com..game") && !valid_package("/data/game"));
    assert(!valid_package(std::string(256,'a')));
    assert(valid_package("com.example.channel_233"));
}
