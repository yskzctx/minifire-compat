#pragma once
#include <cstddef>
#include <cstdint>
struct lua_State;
using LuaCFunction = int (*)(lua_State*);
struct LuaApi {
    int (*gettop)(lua_State*);
    void (*settop)(lua_State*, int);
    int (*type)(lua_State*, int);
    const char* (*tolstring)(lua_State*, int, std::size_t*);
    double (*tonumber)(lua_State*, int);
    void (*pushinteger)(lua_State*, std::intptr_t);
    void (*pushstring)(lua_State*, const char*);
    void (*rawget)(lua_State*, int);
    void (*rawset)(lua_State*, int);
    int (*checkstack)(lua_State*, int);
};
struct FilterResult {
    int message = 0;
    int original_os = -1, selected_os = -1;
    int original_channel = -1, selected_channel = -1;
    bool applied = false;
    bool version_profile = false;
};
FilterResult apply_login_filter(const LuaApi&, lua_State*, int mode);
