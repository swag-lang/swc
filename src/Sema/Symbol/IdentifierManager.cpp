#include "pch.h"

#include "Main/Stats.h"
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

IdentifierRef IdentifierManager::addIdentifier(std::string_view name, uint32_t hash)
{
    const uint32_t shardIndex = hash & (SHARD_COUNT - 1);
    auto&          shard      = shards_[shardIndex];

    {
        std::shared_lock lk(shard.mutex);
        if (const auto it = shard.map.find(name, hash))
            return *it;
    }

    std::unique_lock lk(shard.mutex);
    const auto [it, inserted] = shard.map.try_emplace(name, hash, IdentifierRef{});
    if (!inserted)
        return *it;

#if SWC_HAS_STATS
    Stats::get().numIdentifiers.fetch_add(1);
#endif

    const uint32_t localIndex = shard.store.size() / sizeof(Identifier);
    SWC_ASSERT(localIndex <= LOCAL_MASK);
    shard.store.push_back(Identifier{name});

    const auto result = IdentifierRef{(shardIndex << LOCAL_BITS) | localIndex};
    *it               = result;
    return result;
}

SWC_END_NAMESPACE()
