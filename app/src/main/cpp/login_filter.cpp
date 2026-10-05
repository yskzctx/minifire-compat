#include "login_filter.hpp"
#include <string_view>
namespace {
constexpr int string_type = 4, table_type = 5, number_type = 3;
double raw_number(const LuaApi& api, lua_State* state, const char* key, bool* missing = nullptr) {
    api.pushstring(state, key);
    api.rawget(state, 2);
    const int type=api.type(state, -1);
    if (missing) *missing=type==0;
    const double value = type == number_type ? api.tonumber(state, -1) : -1;
    api.settop(state, -2);
    return value;
}
void raw_integer(const LuaApi& api, lua_State* state, const char* key, int value) {
    api.pushstring(state, key);
    api.pushinteger(state, value);
    api.rawset(state, 2);
}
int raw_version(const LuaApi& api, lua_State* state, const char* key) {
    api.pushstring(state, key); api.rawget(state, 2);
    int version = 0;
    if (api.type(state, -1) == string_type) {
        std::size_t size = 0;
        const char* text = api.tolstring(state, -1, &size);
        if (text && size == 6) {
            const std::string_view value(text, size);
            if (value == "1.0.77") version = 1;
            else if (value == "1.0.78") version = 2;
        }
    }
    api.settop(state, -2);
    return version;
}
void raw_string(const LuaApi& api, lua_State* state, const char* key, const char* value) {
    api.pushstring(state, key); api.pushstring(state, value); api.rawset(state, 2);
}
}
FilterResult apply_login_filter(const LuaApi& api, lua_State* state, int mode) {
    FilterResult result;
    if ((mode != 3 && mode != 4 && mode != 5) || api.gettop(state) < 2 ||
        api.type(state, 1) != string_type || api.type(state, 2) != table_type ||
        !api.checkstack(state, 4)) return result;
    std::size_t size = 0;
    const char* name = api.tolstring(state, 1, &size);
    if (!name || size > 64) return result;
    const std::string_view message(name, size);
    const char* os_key;
    if (message == "md.ApiLoginRequest") { result.message = 1; os_key = "PhoneOs"; }
    else if (message == "md.Login") { result.message = 2; os_key = "Phone_Os"; }
    else return result;
    const double os = raw_number(api, state, os_key);
    if (os != 1 && os != 2) return result;
    result.original_os = static_cast<int>(os);
    result.selected_os = result.original_os;
    bool channel_missing=false;
    const double channel = raw_number(api, state, "ChannelID", &channel_missing);
    if (channel >= 0 && channel <= 1000000 && channel == static_cast<int>(channel))
        result.original_channel = static_cast<int>(channel);
    result.selected_channel = result.original_channel;
    // OS-only mode preserves every channel. Combined mode accepts only the
    // two game build-channel values verified in the official metadata.
    if ((mode == 4 || mode == 5) && channel != 23 && channel != 888 && !(result.message==2 && channel_missing)) return result;
    if (mode == 5) {
        const int version = raw_version(api, state, "Version");
        // The game merges its saved lobby login into a new terminal request.
        // A cached Version=1.0.78 can coexist with the installed VersionName=1.0.77.
        // Both must be known; normalize them together without touching credentials.
        if (!version || (result.message == 1 && !raw_version(api, state, "VersionName"))) return result;
    }
    raw_integer(api, state, os_key, 2);
    result.selected_os = 2;
    if (mode == 4 || mode == 5) { raw_integer(api, state, "ChannelID", 888); result.selected_channel = 888; }
    if (mode == 5) {
        raw_string(api, state, "Version", "1.0.78");
        if (result.message == 1) raw_string(api, state, "VersionName", "1.0.78");
        result.version_profile = true;
    }
    result.applied = true;
    return result;
}
