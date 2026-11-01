#pragma once
#include <string_view>
inline bool target_process(std::string_view name,std::string_view data,int uid) {
    constexpr std::string_view game="com.miniworldroyale.sparkgame";
    return name==game && uid>=10000 && uid%100000>=10000 && uid%100000<90000 &&
        data.size()>game.size() && data.substr(data.size()-game.size())==game &&
        data[data.size()-game.size()-1]=='/';
}
