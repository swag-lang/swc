#pragma once
#include "Core/StringMap.h"
#include "Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE()

class SymbolMap : public Symbol
{
    struct Shard
    {
        std::shared_mutex   mutex;
        StringMap<uint32_t> monoMap; // Map symbol name to one single symbol
        std::vector<Symbol> symbols; // local storage
    };

    constexpr static uint32_t NUM_SHARDS = 16;
    Shard                     shards_[NUM_SHARDS];

public:
    explicit SymbolMap(SymbolKind kind) :
        Symbol(kind)
    {
    }
};

SWC_END_NAMESPACE()
