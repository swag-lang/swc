#pragma once
#include "Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

class MatchContext;

class SymbolMap : public Symbol
{
    friend class SymbolStruct;

public:
    explicit SymbolMap(const AstNode* decl, TokenRef tokRef, SymbolKind kind, IdentifierRef idRef, const SymbolFlags& flags);

    Symbol*  addSymbol(TaskContext& ctx, Symbol* symbol, bool acceptHomonyms);
    Symbol*  addSingleSymbol(TaskContext& ctx, Symbol* symbol);
    Symbol*  addSingleSymbolOrError(Sema& sema, Symbol* symbol);
    void     lookupAppend(IdentifierRef idRef, MatchContext& lookUpCxt) const;
    void     getAllSymbols(std::vector<const Symbol*>& out, bool includeIgnored = false) const;
    bool     empty() const noexcept;
    uint32_t count() const noexcept { return count_; }

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
    uint32_t                                   count_     = 0;

    bool isBig() const noexcept { return smallSize_ > SMALL_CAP; }
    bool isSharded() const noexcept { return shards_.load(std::memory_order_acquire) != nullptr; }

private:
    Entry*       smallFind(IdentifierRef key);
    const Entry* smallFind(IdentifierRef key) const;

    static uint32_t shardIndex(IdentifierRef idRef) noexcept { return idRef.get() & (SHARD_COUNT - 1); }
    void            maybeUpgradeToSharded(TaskContext& ctx);
    static Symbol*  insertIntoShard(Shard* shards, IdentifierRef idRef, Symbol* symbol, TaskContext& ctx, bool acceptHomonyms, bool notify);
};

template<SymbolKind K, typename E = void>
struct SymbolMapT : SymbolMap
{
    using FlagsE    = E;
    using FlagsType = std::conditional_t<std::is_void_v<E>, uint8_t, EnumFlags<E>>;

    explicit SymbolMapT(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(decl, tokRef, K, idRef, flags)
    {
    }

    FlagsType& extraFlags()
    {
        if constexpr (!std::is_void_v<E>)
            return *reinterpret_cast<FlagsType*>(&extraFlags_);
        else
            return extraFlags_;
    }

    const FlagsType& extraFlags() const
    {
        if constexpr (!std::is_void_v<E>)
            return *reinterpret_cast<const FlagsType*>(&extraFlags_);
        else
            return extraFlags_;
    }

    template<typename T = E>
    bool hasExtraFlag(T flag) const
    {
        if constexpr (!std::is_void_v<E>)
            return extraFlags().has(flag);
        return false;
    }

    template<typename T = E>
    void addExtraFlag(T flag)
    {
        if constexpr (!std::is_void_v<E>)
            extraFlags().add(flag);
    }

    template<typename T = E>
    void removeExtraFlag(T flag)
    {
        if constexpr (!std::is_void_v<E>)
            extraFlags().remove(flag);
    }
};

SWC_END_NAMESPACE();
