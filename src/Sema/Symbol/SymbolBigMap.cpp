#include "pch.h"

#include "LookUpContext.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/SymbolBigMap.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void prependSymbol(Symbol*& head, Symbol* symbol)
    {
        symbol->setNextHomonym(head);
        head = symbol;
    }

    void notifyIf(TaskContext& ctx, bool notify)
    {
        if (notify)
            ctx.compiler().notifySymbolAdded();
    }
}

SymbolBigMap::SymbolBigMap()
{
    unsharded_.reserve(16);
}

SymbolBigMap::Shard& SymbolBigMap::getShard(IdentifierRef idRef)
{
    Shard* shards = shards_.load(std::memory_order_acquire);
    SWC_ASSERT(shards != nullptr);
    return shards[shardIndex(idRef)];
}

const SymbolBigMap::Shard& SymbolBigMap::getShard(IdentifierRef idRef) const
{
    Shard* shards = shards_.load(std::memory_order_acquire);
    SWC_ASSERT(shards != nullptr);
    return shards[shardIndex(idRef)];
}

Symbol* SymbolBigMap::insertIntoShard(Shard* shards, IdentifierRef idRef, Symbol* symbol, TaskContext& ctx, bool acceptHomonyms, bool notify)
{
    SWC_ASSERT(shards != nullptr);

    Shard&           shard = shards[shardIndex(idRef)];
    std::unique_lock lock(shard.mutex);

    if (!acceptHomonyms)
    {
        const auto it = shard.map.find(idRef);
        if (it != shard.map.end())
            return it->second;
    }

    Symbol*& head = shard.map[idRef];
    prependSymbol(head, symbol);
    notifyIf(ctx, notify);
    return symbol;
}

void SymbolBigMap::maybeUpgradeToSharded(TaskContext& ctx)
{
    // Fast path: already sharded.
    if (isSharded())
        return;

    // Not enough keys yet — stay unsharded.
    if (unsharded_.size() < SHARD_AFTER_KEYS)
        return;

    // Another thread may have upgraded while we waited for the mutex.
    // Re-check before performing the one-time upgrade.
    if (isSharded())
        return;

    Shard* newShards = ctx.compiler().allocateArray<Shard>(SHARD_COUNT);

#if SWC_HAS_STATS
    Stats::get().memSymbols.fetch_add(sizeof(Shard) * SHARD_COUNT, std::memory_order_relaxed);
#endif

    const size_t totalKeys = unsharded_.size();
    const size_t perShard  = (totalKeys / SHARD_COUNT) + 1;
    for (uint32_t i = 0; i < SHARD_COUNT; ++i)
        newShards[i].map.reserve(perShard);

    for (const auto& [id, head] : unsharded_)
        newShards[shardIndex(id)].map.emplace(id, head);

    std::unordered_map<IdentifierRef, Symbol*>().swap(unsharded_);
    shards_.store(newShards, std::memory_order_release);
}

Symbol* SymbolBigMap::addSymbol(TaskContext& ctx, Symbol* symbol, bool acceptHomonyms, bool notify)
{
    SWC_ASSERT(symbol != nullptr);

    const IdentifierRef idRef = symbol->idRef();

    // Sharded fast path.
    if (Shard* shards = shards_.load(std::memory_order_acquire))
    {
        return insertIntoShard(shards, idRef, symbol, ctx, acceptHomonyms, notify);
    }

    // Unsharded path (may upgrade under lock).
    std::unique_lock unshardedLock(unshardedMutex_);
    maybeUpgradeToSharded(ctx);

    // If upgraded, insert into shards (release unsharded lock first).
    if (Shard* shards = shards_.load(std::memory_order_acquire))
    {
        unshardedLock.unlock();
        return insertIntoShard(shards, idRef, symbol, ctx, acceptHomonyms, notify);
    }

    // Still unsharded.
    if (!acceptHomonyms)
    {
        const auto it = unsharded_.find(idRef);
        if (it != unsharded_.end())
            return it->second;
    }

    Symbol*& head = unsharded_[idRef];
    prependSymbol(head, symbol);
    notifyIf(ctx, notify);
    return symbol;
}

void SymbolBigMap::lookupAppend(IdentifierRef idRef, LookUpContext& lookUpCxt) const
{
    if (const Shard* shards = shards_.load(std::memory_order_acquire))
    {
        const Shard&     shard = shards[shardIndex(idRef)];
        std::shared_lock lock(shard.mutex);

        const auto it = shard.map.find(idRef);
        if (it == shard.map.end())
            return;

        for (const Symbol* cur = it->second; cur; cur = cur->nextHomonym())
        {
            if (!cur->isIgnored())
                lookUpCxt.addSymbol(cur);
        }

        return;
    }

    std::shared_lock lock(unshardedMutex_);

    const auto it = unsharded_.find(idRef);
    if (it == unsharded_.end())
        return;
    for (const Symbol* cur = it->second; cur; cur = cur->nextHomonym())
    {
        if (!cur->isIgnored())
            lookUpCxt.addSymbol(cur);
    }
}

SWC_END_NAMESPACE()
