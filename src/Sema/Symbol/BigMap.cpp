#include "pch.h"
#include "Sema/Symbol/BigMap.h"

SWC_BEGIN_NAMESPACE()

BigMap::BigMap()
{
    unsharded_.reserve(16);
}

BigMap::Shard& BigMap::getShard(IdentifierRef idRef)
{
    Shard* s = shards_.load(std::memory_order_acquire);
    SWC_ASSERT(s != nullptr);
    return s[shardIndex(idRef)];
}

const BigMap::Shard& BigMap::getShard(IdentifierRef idRef) const
{
    Shard* s = shards_.load(std::memory_order_acquire);
    SWC_ASSERT(s != nullptr);
    return s[shardIndex(idRef)];
}

void BigMap::maybeUpgradeToSharded(TaskContext& ctx)
{
    // Fast path: already sharded.
    if (isSharded())
        return;

    // Only upgrade if we have enough distinct keys in the unsharded map.
    // IMPORTANT: this must be called under unshardedMutex_ unique lock.
    if (unsharded_.size() < SHARD_AFTER_KEYS)
        return;

    // Double-check: another thread could have upgraded while we were waiting for lock,
    // but since the caller holds unshardedMutex_ unique lock, we only need to re-check shards_.
    if (isSharded())
        return;

    printf("X");

    // Allocate a shard array.
    Shard* newShards = ctx.compiler().allocateArray<Shard>(SHARD_COUNT);

#if SWC_HAS_STATS
    // Memory stats: count the shards + maps (approx). At least record the shard array.
    Stats::get().memSymbols.fetch_add(sizeof(Shard) * SHARD_COUNT, std::memory_order_relaxed);
#endif

    // Optional: pre-reserve per shard to reduce rehashing during migration.
    // A decent heuristic: total keys / shard_count * 1.3
    const size_t total = unsharded_.size();
    const size_t per   = (total / SHARD_COUNT) + 1;
    for (uint32_t i = 0; i < SHARD_COUNT; ++i)
        newShards[i].map.reserve(per);

    // Move everything into shards. (unordered_map node handles make the move cheap)
    for (const auto& kv : unsharded_)
    {
        const IdentifierRef id   = kv.first;
        Symbol*             head = kv.second;

        Shard& shard = newShards[shardIndex(id)];
        // No need to lock: shards not published yet.
        shard.map.emplace(id, head);
    }

    // Free the old unsharded storage by clearing (keeps buckets unless a swap trick).
    unsharded_.clear();
    std::unordered_map<IdentifierRef, Symbol*>().swap(unsharded_);

    // Publish shards.
    shards_.store(newShards, std::memory_order_release);
}

void BigMap::addSymbol(TaskContext& ctx, Symbol* symbol, bool notify)
{
    SWC_ASSERT(symbol != nullptr);
    const IdentifierRef idRef = symbol->idRef();

    // If sharded, go straight there.
    if (Shard* s = shards_.load(std::memory_order_acquire))
    {
        Shard&           shard = s[shardIndex(idRef)];
        std::unique_lock lock(shard.mutex);
        Symbol*&         head = shard.map[idRef];
        symbol->setNextHomonym(head);
        head = symbol;
        if (notify)
            ctx.compiler().notifySymbolAdded();
        return;
    }

    // Unsharded path
    {
        std::unique_lock lock(unshardedMutex_);

        // Upgrade check (still unsharded at this moment).
        maybeUpgradeToSharded(ctx);

        // If upgraded, fall through to sharded insert (without recursion).
        if (Shard* s2 = shards_.load(std::memory_order_acquire))
        {
            lock.unlock();
            Shard&           shard = s2[shardIndex(idRef)];
            std::unique_lock lock2(shard.mutex);
            Symbol*&         head = shard.map[idRef];
            symbol->setNextHomonym(head);
            head = symbol;
            if (notify)
                ctx.compiler().notifySymbolAdded();
            return;
        }

        // Still unsharded: insert here.
        Symbol*& head = unsharded_[idRef];
        symbol->setNextHomonym(head);
        head = symbol;

        if (notify)
            ctx.compiler().notifySymbolAdded();
    }
}

void BigMap::lookup(IdentifierRef idRef, SmallVector<Symbol*>& out) const
{
    out.clear();

    if (const Shard* s = shards_.load(std::memory_order_acquire))
    {
        const Shard&     shard = s[shardIndex(idRef)];
        std::shared_lock lk(shard.mutex);

        const auto it = shard.map.find(idRef);
        if (it == shard.map.end())
            return;
        for (Symbol* cur = it->second; cur; cur = cur->nextHomonym())
            out.push_back(cur);

        return;
    }

    // Unsharded lookup
    std::shared_lock lk(unshardedMutex_);

    const auto it = unsharded_.find(idRef);
    if (it == unsharded_.end())
        return;

    for (Symbol* cur = it->second; cur; cur = cur->nextHomonym())
        out.push_back(cur);
}

SWC_END_NAMESPACE()
