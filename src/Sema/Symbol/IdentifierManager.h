#pragma once
#include "Core/Store.h"
#include "Core/StringMap.h"
#include "Lexer/SourceView.h"

SWC_BEGIN_NAMESPACE()

class TaskContext;

struct Identifier
{
    std::string_view name;
};

using IdentifierRef = StrongRef<Identifier>;

class IdentifierManager
{
    struct Shard
    {
        Store                     store;
        StringMap<IdentifierRef>  map;
        mutable std::shared_mutex mutex;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;
    Shard                     shards_[SHARD_COUNT];

public:
    IdentifierRef     addIdentifier(const TaskContext& ctx, SourceViewRef srcViewRef, TokenRef tokRef);
    IdentifierRef     addIdentifier(std::string_view name, uint32_t hash);
    const Identifier& get(IdentifierRef idRef) const;
};

SWC_END_NAMESPACE()
