#pragma once
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

class SymbolMap : public Symbol
{
    struct Shard
    {
        std::shared_mutex                          mutex;
        std::unordered_map<IdentifierRef, Symbol*> monoMap; // Map symbol name to one single symbol
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;
    Shard                     shards_[SHARD_COUNT];

public:
    explicit SymbolMap(SymbolKind kind) :
        Symbol(kind)
    {
    }

    explicit SymbolMap(const TaskContext& ctx, SymbolKind kind, IdentifierRef idRef) :
        Symbol(ctx, kind, idRef)
    {
    }

    Symbol* findSymbol(IdentifierRef idRef) const;
};

SWC_END_NAMESPACE()
