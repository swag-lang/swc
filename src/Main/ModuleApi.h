#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Symbol;
class TaskContext;

struct ModuleApiFileEntry
{
    std::vector<AstNodeRef> publicDeclRefs;
    bool                    hasUnsupportedPublicDecl = false;
};

struct ModuleApiState
{
    struct Shard
    {
        mutable std::shared_mutex                             mutex;
        std::unordered_map<SourceViewRef, ModuleApiFileEntry> files;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;

    static uint32_t shardIndex(const SourceViewRef srcViewRef) noexcept
    {
        return srcViewRef.get() & (SHARD_COUNT - 1);
    }

    std::array<Shard, SHARD_COUNT> shards;
};

namespace ModuleApi
{
    void   onSymbolSemaCompleted(ModuleApiState& state, TaskContext& ctx, const Symbol& symbol);
    Result exportFiles(TaskContext& ctx, const ModuleApiState& state);
}

SWC_END_NAMESPACE();
