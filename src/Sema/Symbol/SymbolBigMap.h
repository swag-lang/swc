#pragma once
#include "Core/SmallVector.h"
#include "Math/Hash.h"
#include "Sema/Symbol/Symbol.h"

template<>
struct std::hash<swc::IdentifierRef>
{
    size_t operator()(const swc::IdentifierRef& r) const noexcept
    {
        return swc::Math::hash(r.get());
    }
};

SWC_BEGIN_NAMESPACE()

class SymbolBigMap
{
    struct Shard
    {
        mutable std::shared_mutex                  mutex;
        std::unordered_map<IdentifierRef, Symbol*> map;
    };

    static constexpr uint32_t SHARD_BITS       = 3;
    static constexpr uint32_t SHARD_COUNT      = 1u << SHARD_BITS;
    static constexpr uint32_t SHARD_AFTER_KEYS = 64;

    // Start unsharded: one mutex + one map.
    mutable std::shared_mutex                  unshardedMutex_;
    std::unordered_map<IdentifierRef, Symbol*> unsharded_;

    // When sharded, shards_ != nullptr.
    std::atomic<Shard*> shards_{nullptr};

    bool            isSharded() const noexcept { return shards_.load(std::memory_order_acquire) != nullptr; }
    static uint32_t shardIndex(IdentifierRef idRef) noexcept { return idRef.get() & (SHARD_COUNT - 1); }
    void            maybeUpgradeToSharded(TaskContext& ctx);

    Shard&         getShard(IdentifierRef idRef);
    const Shard&   getShard(IdentifierRef idRef) const;
    static Symbol* insertIntoShard(Shard* shards, IdentifierRef idRef, Symbol* symbol, TaskContext& ctx, bool acceptHomonyms, bool notify);

public:
    SymbolBigMap();
    Symbol* addSymbol(TaskContext& ctx, Symbol* symbol, bool acceptHomonyms, bool notify);
    void    lookupAppend(IdentifierRef idRef, LookUpContext& lookUpCxt) const;
};

SWC_END_NAMESPACE()
