#pragma once
#include <cstdint>
#include <cstdio>
// Read-only parsing of real maps entries. Never hide, rewrite or synthesize rows.
inline int mapping_permissions(const char* row,std::uintptr_t address) {
    unsigned long long begin=0,end=0;char permissions[5]{};int consumed=0;
    if(!row || std::sscanf(row,"%llx-%llx %4s%n",&begin,&end,permissions,&consumed)!=3 ||
        begin>=end || address<begin || address>=end || consumed<=0 ||
        (row[consumed] && row[consumed]!=' ' && row[consumed]!='\t' && row[consumed]!='\n')) return -1;
    if((permissions[0]!='r' && permissions[0]!='-') || (permissions[1]!='w' && permissions[1]!='-') ||
        (permissions[2]!='x' && permissions[2]!='-') || (permissions[3]!='p' && permissions[3]!='s')) return -1;
    return (permissions[0]=='r'?1:0)|(permissions[1]=='w'?2:0)|(permissions[2]=='x'?4:0);
}
