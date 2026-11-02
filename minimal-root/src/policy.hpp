#pragma once
#include <string_view>
inline bool valid_package(std::string_view value) {
    if(value.empty() || value.size()>255) return false;
    bool start=true, dot=false;
    for(char c:value) {
        if(c=='.') { if(start) return false; start=true; dot=true; continue; }
        const bool letter=(c>='a'&&c<='z')||(c>='A'&&c<='Z')||c=='_';
        if(!letter && (start || c<'0' || c>'9')) return false;
        start=false;
    }
    return dot&&!start;
}
inline bool selected_process(std::string_view name,std::string_view data,int uid,std::string_view selected) {
    return valid_package(selected) && uid>=10000 && uid%100000>=10000 && uid%100000<90000 &&
        name==selected && data.size()>selected.size() &&
        data[data.size()-selected.size()-1]=='/' && data.substr(data.size()-selected.size())==selected;
}
