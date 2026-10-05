#include "binary_guard.hpp"
#include <array>
#include <cstdint>
namespace {
constexpr std::array<unsigned char,20> expected = {
    0x49,0x88,0x7b,0xb2,0xb6,0x89,0x37,0xaa,0x67,0x88,
    0x22,0x69,0x4e,0xd6,0x1b,0x75,0x27,0xa0,0xda,0x3a};
std::uint32_t read32(const unsigned char* p) {
    return std::uint32_t(p[0]) | (std::uint32_t(p[1])<<8) |
        (std::uint32_t(p[2])<<16) | (std::uint32_t(p[3])<<24);
}
}
bool matches_game_note(const unsigned char* bytes, std::size_t size) {
    if (!bytes || size > 65536) return false;
    std::size_t at = 0;
    while (at <= size && size-at >= 12) {
        const std::size_t namesize = read32(bytes+at);
        const std::size_t descsize = read32(bytes+at+4);
        const auto type = read32(bytes+at+8);
        at += 12;
        if (namesize > size-at) return false;
        const std::size_t namepad = (namesize+3) & ~std::size_t(3);
        if (namepad > size-at) return false;
        const bool gnu = namesize == 4 && bytes[at]=='G' && bytes[at+1]=='N' &&
            bytes[at+2]=='U' && bytes[at+3]==0;
        at += namepad;
        if (descsize > size-at) return false;
        if (gnu && type==3 && descsize==expected.size()) {
            bool equal = true;
            for (std::size_t i=0; i<expected.size(); ++i) equal = equal && bytes[at+i]==expected[i];
            if (equal) return true;
        }
        const std::size_t descpad = (descsize+3) & ~std::size_t(3);
        if (descpad > size-at) return false;
        at += descpad;
    }
    return false;
}
