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

class SymbolMap : public Symbol
{
    struct Shard
    {
        mutable std::shared_mutex                  mutex;
        std::unordered_map<IdentifierRef, Symbol*> map;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;
    Shard                     shards_[SHARD_COUNT];

    void addSymbol(Symbol* symbol);

public:
    explicit SymbolMap(const TaskContext& ctx, SymbolKind kind, IdentifierRef idRef) :
        Symbol(ctx, kind, idRef)
    {
    }

    ~SymbolMap();

    Symbol* lookupOne(IdentifierRef idRef) const;
    void    lookupAll(IdentifierRef idRef, SmallVector<Symbol*>& out) const;

    SymbolConstant*  addConstant(const TaskContext& ctx, IdentifierRef idRef, ConstantRef cstRef);
    SymbolNamespace* addNamespace(const TaskContext& ctx, IdentifierRef idRef);
};

SWC_END_NAMESPACE()
