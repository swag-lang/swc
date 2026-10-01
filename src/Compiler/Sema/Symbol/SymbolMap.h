#pragma once
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class MatchContext;

class SymbolMap : public Symbol
{
    friend class SymbolStruct;

public:
    explicit SymbolMap(const AstNode* decl, TokenRef tokRef, SymbolKind kind, IdentifierRef idRef, const SymbolFlags& flags);

    Symbol*       addSymbol(TaskContext& ctx, Symbol* symbol, bool acceptHomonyms);
    Symbol*       addSingleSymbol(TaskContext& ctx, Symbol* symbol);
    Symbol*       addSingleSymbolOrError(Sema& sema, Symbol* symbol);
    void          addUsingSymMap(TaskContext& ctx, SymbolMap* symMap);
    void          copyUsingSymMaps(SmallVector<const SymbolMap*>& out) const;
    const Symbol* findFirstSymbol(IdentifierRef idRef, bool includeIgnored = false) const;
    void          lookupAppend(IdentifierRef idRef, MatchContext& lookUpCxt) const;
    void          getAllSymbols(std::vector<Symbol*>& out, bool includeIgnored = false) const;
    void          getAllSymbols(std::vector<const Symbol*>& out, bool includeIgnored = false) const;
    bool          empty() const noexcept;
    uint32_t      count() const noexcept { return count_.load(std::memory_order_relaxed); }

protected:
    // A small entry is written once, before 'smallSize_' publishes it, so readers scan the
    // published prefix without a lock. Only its head moves, to another symbol of the same name.
    struct Entry
    {
        std::atomic<Symbol*> head = nullptr;
        IdentifierRef        key  = IdentifierRef::invalid();
    };

    // Open-addressed and append-only: a key slot, once filled, never changes, and a head only
    // moves to another symbol of the same name. Readers probe it without any lock; writers fill
    // it under the owning mutex and publish a key after its head. Growing allocates a new table
    // and publishes it whole, leaving the old one (arena memory) valid for readers still on it.
    struct HeadTable
    {
        std::atomic<uint64_t>* keys     = nullptr; // identifier reference + 1; zero marks an empty slot
        std::atomic<Symbol*>*  heads    = nullptr;
        uint32_t               capacity = 0; // power of two
        uint32_t               size     = 0; // writer-only
    };

    // Every worker reads the module-level maps, so a lookup must not write a shared lock word.
    // Each shard owns its cache line so writers of neighbouring shards do not disturb it either.
    struct alignas(64) Shard
    {
        std::mutex              mutex; // writers only
        std::atomic<HeadTable*> table = nullptr;
    };

    struct UsingSymMap
    {
        SymbolMap*         symbol   = nullptr;
        const UsingSymMap* previous = nullptr;
    };

    static constexpr uint32_t SMALL_CAP        = 8;
    static constexpr uint32_t SHARD_BITS       = 3;
    static constexpr uint32_t SHARD_COUNT      = 1u << SHARD_BITS;
    static constexpr uint32_t SHARD_AFTER_KEYS = 64;

    // Every function, struct and namespace owns a map, and most never outgrow 'small_'. Past it,
    // one table holds the names; past SHARD_AFTER_KEYS, shards spread the writers.
    std::array<Entry, SMALL_CAP> small_;
    std::atomic<HeadTable*>      bigTable_ = nullptr;
    std::atomic<Shard*>          shards_   = nullptr;
    // Serializes writers until the map is sharded. Lookups never take it.
    mutable std::shared_mutex mutex_;
    // Entries are immutable after publication and live in the compiler's arena.
    // Readers keep a stable prefix while writers append under mutex_.
    std::atomic<const UsingSymMap*> usingSymMaps_ = nullptr;
    std::atomic<uint32_t>           smallSize_    = 0;
    // Different shards publish symbols concurrently; their locks do not protect this total.
    std::atomic<uint32_t> count_ = 0;

    bool isBig() const noexcept { return smallSize_.load(std::memory_order_acquire) > SMALL_CAP; }
    bool isSharded() const noexcept { return shards_.load(std::memory_order_acquire) != nullptr; }

private:
    Entry*  smallFind(IdentifierRef key);
    Symbol* smallFindHead(IdentifierRef key, uint32_t smallSize) const noexcept;
    Symbol* findHead(IdentifierRef idRef) const noexcept;

    static uint32_t shardIndex(IdentifierRef idRef) noexcept;
    static uint32_t tableSlot(const HeadTable& table, uint64_t key) noexcept;
    static Symbol*  tableFindHead(const HeadTable* table, IdentifierRef idRef) noexcept;
    static void     tablePlace(HeadTable& table, uint64_t key, Symbol* head) noexcept;
    static void     tableReserve(TaskContext& ctx, std::atomic<HeadTable*>& published, uint32_t minSize);
    template<typename F>
    static void     forEachHead(const HeadTable* table, const F& fn);
    static void     notifyInserted(TaskContext& ctx, IdentifierRef idRef);
    Symbol*         tableInsert(TaskContext& ctx, std::atomic<HeadTable*>& published, IdentifierRef idRef, Symbol* symbol, bool acceptHomonyms);
    void            upgradeToSharded(TaskContext& ctx);
    Symbol*         insertIntoShard(Shard* shards, IdentifierRef idRef, Symbol* symbol, TaskContext& ctx, bool acceptHomonyms);
};

template<SymbolKind K, typename E = void>
struct SymbolMapT : SymbolExtraFlagsT<SymbolMap, K, E>
{
    using SymbolExtraFlagsT<SymbolMap, K, E>::SymbolExtraFlagsT;
};

SWC_END_NAMESPACE();
