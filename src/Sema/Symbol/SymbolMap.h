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
class SymbolModule;
class SymbolNamespace;
class SymbolConstant;
class SymbolVariable;
class SymbolEnum;

class BigMap
{
    struct Shard
    {
        mutable std::shared_mutex                  mutex;
        std::unordered_map<IdentifierRef, Symbol*> map;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;

    Shard shards_[SHARD_COUNT];

    Shard&       getShard(IdentifierRef idRef);
    const Shard& getShard(IdentifierRef idRef) const;

public:
    void addSymbol(TaskContext& ctx, Symbol* symbol, bool notify = true);
    void lookup(IdentifierRef idRef, SmallVector<Symbol*>& out) const;
};

class SymbolMap : public Symbol
{
    struct Entry
    {
        IdentifierRef key  = IdentifierRef::invalid();
        Symbol*       head = nullptr;
    };

    static constexpr uint32_t SMALL_CAP = 8;

    uint8_t smallSize_ = 0;
    Entry   small_[SMALL_CAP];

    mutable std::shared_mutex mutex_;
    std::atomic<BigMap*>      big_{nullptr};

    Entry*       smallFind(IdentifierRef key);
    const Entry* smallFind(IdentifierRef key) const;
    BigMap*      buildBig(TaskContext& ctx) const;

public:
    explicit SymbolMap(const TaskContext& ctx, const AstNode* decl, SymbolKind kind, IdentifierRef idRef, SymbolFlags flags);

    void addSymbol(TaskContext& ctx, Symbol* symbol);
    void lookup(IdentifierRef idRef, SmallVector<Symbol*>& out) const;
};

SWC_END_NAMESPACE()
