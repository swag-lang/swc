#pragma once
#include "Core/SmallVector.h"
#include "Math/Hash.h"
#include "Sema/Constant/ConstantValue.h"
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

    void         addSymbol(TaskContext& ctx, Symbol* symbol);
    Shard&       getShard(IdentifierRef idRef);
    const Shard& getShard(IdentifierRef idRef) const;

public:
    explicit SymbolMap(const TaskContext& ctx, SymbolKind kind, IdentifierRef idRef) :
        Symbol(ctx, kind, idRef, TypeRef::invalid())
    {
    }

    void lookup(IdentifierRef idRef, SmallVector<Symbol*>& out) const;

    SymbolConstant*  addConstant(TaskContext& ctx, IdentifierRef idRef, ConstantRef cstRef);
    SymbolVariable*  addVariable(TaskContext& ctx, IdentifierRef idRef, TypeRef typeRef);
    SymbolEnum*      addEnum(TaskContext& ctx, IdentifierRef idRef, TypeRef typeRef);
    SymbolNamespace* addNamespace(TaskContext& ctx, IdentifierRef idRef);
};

SWC_END_NAMESPACE()
