#pragma once
#include "Core/StringMap.h"
#include "Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE()

enum class DeclContextKind
{
    Invalid = -1,
    Module,
    Namespace,
};

class DeclContext
{
    DeclContextKind kind_ = DeclContextKind::Invalid;

    struct Shard
    {
        std::shared_mutex   mutex;
        StringMap<uint32_t> monoMap; // Map symbol name to one single symbol
        std::vector<Symbol> symbols; // local storage
    };

    constexpr static uint32_t NUM_SHARDS = 16;
    Shard                     shards_[NUM_SHARDS];

public:
    explicit DeclContext(DeclContextKind kind) :
        kind_(kind)
    {
    }

    DeclContextKind kind() const { return kind_; }
};

SWC_END_NAMESPACE()
