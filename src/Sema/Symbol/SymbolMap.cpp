#include "pch.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/MatchContext.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void prependSymbol(Symbol*& head, Symbol* symbol)
    {
        symbol->setNextHomonym(head);
        head = symbol;
    }
}

SymbolMap::SymbolMap(const AstNode* decl, TokenRef tokRef, SymbolKind kind, IdentifierRef idRef, const SymbolFlags& flags) :
    Symbol(decl, tokRef, kind, idRef, flags)
{
}

bool SymbolMap::empty() const noexcept
{
    if (isSharded())
        return false;
    std::shared_lock lk(mutex_);
    return smallSize_ == 0 && bigMap_.empty();
}

SymbolMap::Entry* SymbolMap::smallFind(IdentifierRef key)
{
    for (uint32_t i = 0; i < smallSize_; ++i)
        if (small_[i].key == key)
            return &small_[i];
    return nullptr;
}

const SymbolMap::Entry* SymbolMap::smallFind(IdentifierRef key) const
{
    for (uint32_t i = 0; i < smallSize_; ++i)
        if (small_[i].key == key)
            return &small_[i];
    return nullptr;
}

void SymbolMap::maybeUpgradeToSharded(TaskContext& ctx)
{
    // Fast path: already sharded.
    if (isSharded())
        return;

    // Not enough keys yet — stay unsharded.
    if (bigMap_.size() < SHARD_AFTER_KEYS)
        return;

    Shard* newShards = ctx.compiler().allocateArray<Shard>(SHARD_COUNT);

#if SWC_HAS_STATS
    Stats::get().memSymbols.fetch_add(sizeof(Shard) * SHARD_COUNT, std::memory_order_relaxed);
#endif

    const size_t totalKeys = bigMap_.size();
    const size_t perShard  = (totalKeys / SHARD_COUNT) + 1;
    for (uint32_t i = 0; i < SHARD_COUNT; ++i)
        newShards[i].map.reserve(perShard);

    for (const auto& [id, head] : bigMap_)
        newShards[shardIndex(id)].map.emplace(id, head);

    std::unordered_map<IdentifierRef, Symbol*>().swap(bigMap_);
    shards_.store(newShards, std::memory_order_release);
}

Symbol* SymbolMap::insertIntoShard(Shard* shards, IdentifierRef idRef, Symbol* symbol, TaskContext& ctx, bool acceptHomonyms, bool notify)
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
    if (notify)
        ctx.compiler().notifySymbolAdded();
    return symbol;
}

void SymbolMap::lookupAppend(IdentifierRef idRef, MatchContext& lookUpCxt) const
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

    std::shared_lock lk(mutex_);

    // Check sharded again after lock
    if (const Shard* shards = shards_.load(std::memory_order_acquire))
    {
        lk.unlock();
        const Shard&     shard = shards[shardIndex(idRef)];
        std::shared_lock lock(shard.mutex);
        const auto       it = shard.map.find(idRef);
        if (it == shard.map.end())
            return;
        for (const Symbol* cur = it->second; cur; cur = cur->nextHomonym())
        {
            if (!cur->isIgnored())
                lookUpCxt.addSymbol(cur);
        }
        return;
    }

    const Symbol* head = nullptr;
    if (isBig())
    {
        const auto it = bigMap_.find(idRef);
        if (it != bigMap_.end())
            head = it->second;
    }
    else if (const Entry* e = smallFind(idRef))
    {
        head = e->head;
    }

    for (const Symbol* cur = head; cur; cur = cur->nextHomonym())
    {
        if (!cur->isIgnored())
            lookUpCxt.addSymbol(cur);
    }
}

Symbol* SymbolMap::addSymbol(TaskContext& ctx, Symbol* symbol, bool acceptHomonyms)
{
    SWC_ASSERT(symbol != nullptr);

    const IdentifierRef idRef = symbol->idRef();

    // Sharded fast path.
    if (Shard* shards = shards_.load(std::memory_order_acquire))
    {
        Symbol* insertedSym = insertIntoShard(shards, idRef, symbol, ctx, acceptHomonyms, true);
        if (insertedSym == symbol)
            symbol->setSymMap(this);
        return insertedSym;
    }

    std::unique_lock lk(mutex_);

    // If upgraded to sharded while waiting for lock
    if (Shard* shards = shards_.load(std::memory_order_acquire))
    {
        lk.unlock();
        Symbol* insertedSym = insertIntoShard(shards, idRef, symbol, ctx, acceptHomonyms, true);
        if (insertedSym == symbol)
            symbol->setSymMap(this);
        return insertedSym;
    }

    if (!isBig())
    {
        if (Entry* e = smallFind(idRef))
        {
            if (!acceptHomonyms)
                return e->head;
            symbol->setSymMap(this);
            prependSymbol(e->head, symbol);
            ctx.compiler().notifySymbolAdded();
            return symbol;
        }

        if (smallSize_ < SMALL_CAP)
        {
            symbol->setSymMap(this);
            symbol->setNextHomonym(nullptr);
            small_[smallSize_++] = Entry{.head = symbol, .key = idRef};
            ctx.compiler().notifySymbolAdded();
            return symbol;
        }

        // Transition to big
        bigMap_.reserve(SMALL_CAP * 2);
        for (uint32_t i = 0; i < smallSize_; ++i)
            bigMap_.emplace(small_[i].key, small_[i].head);
        smallSize_ = SMALL_CAP + 1; // Mark as big
    }

    maybeUpgradeToSharded(ctx);

    // If upgraded to sharded during, maybeUpgradeToSharded
    if (Shard* shards = shards_.load(std::memory_order_acquire))
    {
        lk.unlock();
        Symbol* insertedSym = insertIntoShard(shards, idRef, symbol, ctx, acceptHomonyms, true);
        if (insertedSym == symbol)
            symbol->setSymMap(this);
        return insertedSym;
    }

    // Still unsharded big map.
    if (!acceptHomonyms)
    {
        const auto it = bigMap_.find(idRef);
        if (it != bigMap_.end())
            return it->second;
    }

    Symbol*& head = bigMap_[idRef];
    prependSymbol(head, symbol);
    symbol->setSymMap(this);
    ctx.compiler().notifySymbolAdded();
    return symbol;
}

Symbol* SymbolMap::addSingleSymbolOrError(Sema& sema, Symbol* symbol)
{
    auto&   ctx         = sema.ctx();
    Symbol* insertedSym = addSymbol(ctx, symbol, true);
    if (symbol->nextHomonym())
        SemaError::raiseAlreadyDefined(sema, symbol, symbol->nextHomonym());
    return insertedSym;
}

Symbol* SymbolMap::addSingleSymbol(TaskContext& ctx, Symbol* symbol)
{
    return addSymbol(ctx, symbol, false);
}

SWC_END_NAMESPACE();
