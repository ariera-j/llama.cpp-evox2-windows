#include "../src/llama-qsa-noop-policy.h"
#include "../src/llama-kv-cells.h"
#include <cstdio>
#include <initializer_list>
#include <stdexcept>
static void check(bool v) { if(!v) throw std::runtime_error("Policy/metadata invariant"); }
int main() { try {
    using namespace llama_qsa_noop;
    const auto on=decide("1",true,true,true,true,4,1,1,false);
    check(on.enabled && on.eligible);
    for(const char *v : std::initializer_list<const char *>{nullptr,"0","true","01"," 1"}) check(!decide(v,true,true,true,true,4,1,1,false).enabled);
    check(!decide("1",false,true,true,true,4,1,1,false).enabled);
    check(!decide("1",true,false,true,true,4,1,1,false).enabled);
    check(!decide("1",true,true,false,true,4,1,1,false).enabled);
    check(!decide("1",true,true,true,false,4,1,1,false).enabled);
    check(!decide("1",true,true,true,true,8,1,1,false).enabled);
    check(!decide("1",true,true,true,true,4,2,1,false).enabled);
    check(!decide("1",true,true,true,true,4,1,2,false).enabled);
    check(!decide("1",true,true,true,true,4,1,1,true).enabled);
    check(!inspect(on,-1,false,true) && !inspect(on,1,false,true) && !inspect(on,0,true,true));
    const auto off=decide("0",true,true,true,true,4,1,1,false);
    check(!inspect(off,0,false,false) && inspect(off,0,false,true));
    check(suppress(on,true,0,0) && suppress(on,true,3,3));
    check(!suppress(on,false,3,3));
    check(!suppress(on,true,3,2) && !suppress(on,true,3,4) && !suppress(off,true,3,3));
    llama_kv_cells cells;cells.resize(8);
    check(cells.seq_pos_get(0).empty());
    check(suppress(on,true,cells.seq_pos_get(0).size(),cells.seq_pos_get(0).size()));
    for(unsigned i=0;i<4;++i) { cells.pos_set(i,i/2);cells.seq_add(i,0); }
    check(cells.seq_pos_get(0).size()==4); // two physical cells at each position
    for(auto range : {std::pair<int,int>{2,3},{1,1},{3,2}}) {
        const auto before=cells.seq_pos_get(0).size();
        for(unsigned i=0;i<cells.size();++i) if(cells.pos_in(i,range.first,range.second) && cells.seq_has(i,0)) cells.seq_rm(i,0);
        check(suppress(on,true,before,cells.seq_pos_get(0).size()));
    }
    const auto before=cells.seq_pos_get(0).size();
    for(unsigned i=0;i<cells.size();++i) if(cells.pos_in(i,1,2) && cells.seq_has(i,0)) cells.seq_rm(i,0);
    check(cells.seq_pos_get(0).size()==2 && !suppress(on,true,before,cells.seq_pos_get(0).size()));
    std::puts("QSA no-op policy: PASS");return 0;
} catch(const std::exception &e) { std::fprintf(stderr,"QSA no-op policy: FAIL: %s\n",e.what());return 1; } }
