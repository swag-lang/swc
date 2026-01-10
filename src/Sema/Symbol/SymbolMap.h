#pragma once
#include "Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

class MatchContext;

class SymbolMap : public Symbol
{
    friend class SymbolStruct;

public:
    explicit SymbolMap(const AstNode* decl, TokenRef tokRef, SymbolKind kind, IdentifierRef idRef, const SymbolFlags& flags);

    bool empty() const noexcept;

    Symbol* addSymbol(TaskContext& ctx, Symbol* symbol, bool acceptHomonyms);
    Symbol* addSingleSymbol(TaskContext& ctx, Symbol* symbol);
    Symbol* addSingleSymbolOrError(Sema& sema, Symbol* symbol);
    void    lookupAppend(IdentifierRef idRef, MatchContext& lookUpCxt) const;
    void    merge(TaskContext& ctx, SymbolMap* other);

protected:
    struct Entry
    {
        Symbol*       head = nullptr;
        IdentifierRef key  = IdentifierRef::invalid();
    };

    struct Shard
    {
        mutable std::shared_mutex                  mutex;
        std::unordered_map<IdentifierRef, Symbol*> map;
    };

    static constexpr uint32_t SMALL_CAP        = 8;
    static constexpr uint32_t SHARD_BITS       = 3;
    static constexpr uint32_t SHARD_COUNT      = 1u << SHARD_BITS;
    static constexpr uint32_t SHARD_AFTER_KEYS = 64;

    std::array<Entry, SMALL_CAP>               small_;
    std::unordered_map<IdentifierRef, Symbol*> bigMap_;
    std::atomic<Shard*>                        shards_ = nullptr;
    mutable std::shared_mutex                  mutex_;
    uint32_t                                   smallSize_ = 0;

    bool isBig() const noexcept { return smallSize_ > SMALL_CAP; }
    bool isSharded() const noexcept { return shards_.load(std::memory_order_acquire) != nullptr; }

private:
    Entry*       smallFind(IdentifierRef key);
    const Entry* smallFind(IdentifierRef key) const;

    static uint32_t shardIndex(IdentifierRef idRef) noexcept { return idRef.get() & (SHARD_COUNT - 1); }
    void            maybeUpgradeToSharded(TaskContext& ctx);
    static Symbol*  insertIntoShard(Shard* shards, IdentifierRef idRef, Symbol* symbol, TaskContext& ctx, bool acceptHomonyms, bool notify);
};

SWC_END_NAMESPACE();
