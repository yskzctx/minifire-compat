#pragma once
#include <string_view>
enum class Target { None=0, Game=1, Hunter=2 };
inline bool target_data(std::string_view data,std::string_view package) {
    return data.size()>package.size() && data.substr(data.size()-package.size())==package &&
        data[data.size()-package.size()-1]=='/';
}
inline Target target_process(std::string_view name,std::string_view data,int uid) {
    constexpr std::string_view game="com.miniworldroyale.sparkgame";
    constexpr std::string_view hunter="com.zhenxi.hunter";
    if (uid<10000 || uid%100000<10000 || uid%100000>=90000) return Target::None;
    if (name==game && target_data(data,game)) return Target::Game;
    if ((name==hunter || name=="com.zhenxi.hunter:hunter_main_process") && target_data(data,hunter)) return Target::Hunter;
    return Target::None;
}
