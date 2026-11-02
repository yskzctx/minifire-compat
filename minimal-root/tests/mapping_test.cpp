#include "../src/mapping_permissions.hpp"
#include <cassert>
int main() {
    assert(mapping_permissions("1000-2000 r-xp 00000000 00:00 0",0x1000)==5);
    assert(mapping_permissions("1000-2000 rwxp 00000000 00:00 0",0x1800)==7);
    assert(mapping_permissions("1000-2000 rw-p 00000000 00:00 0 /file",0x1800)==3);
    assert(mapping_permissions("1000-2000 r-xs 00000000 00:00 0 /file",0x1800)==5);
    assert(mapping_permissions("1000-2000 r-xp 0 0 0",0x2000)==-1);
    assert(mapping_permissions("2000-1000 r-xp 0 0 0",0x1800)==-1);
    assert(mapping_permissions("1000-2000 r-xpp 0 0 0",0x1800)==-1);
    assert(mapping_permissions("1000-2000 r-qz 0 0 0",0x1800)==-1);
    assert(mapping_permissions("not a maps row",0x1800)==-1);
}
