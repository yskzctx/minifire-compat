// Test adapter only. Production receives these functions from the game's libtolua.
extern "C" {
#include "lua.h"
#include "lauxlib.h"
}
#include "../app/src/main/cpp/login_filter.hpp"
#include "../app/src/main/cpp/binary_guard.hpp"
extern "C" __declspec(dllexport) int verify_game_note(const unsigned char* bytes, std::size_t size) {
    return matches_game_note(bytes, size) ? 1 : 0;
}
static int apply(lua_State* state) {
    int mode = static_cast<int>(lua_tointeger(state, 3));
    const LuaApi api{lua_gettop, lua_settop, lua_type, lua_tolstring,
        lua_tonumber, lua_pushinteger, lua_pushstring, lua_rawget, lua_rawset, lua_checkstack};
    apply_login_filter(api, state, mode);
    return 0;
}
extern "C" __declspec(dllexport) int luaopen_compat_test(lua_State* state) {
    lua_pushcfunction(state, apply);
    return 1;
}
