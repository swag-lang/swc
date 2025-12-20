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

    Shard&       getShard(IdentifierRef idRef);
    const Shard& getShard(IdentifierRef idRef) const;

public:
    explicit SymbolMap(const TaskContext& ctx, const AstNode* decl, SymbolKind kind, IdentifierRef idRef, TypeRef typeRef, SymbolFlags flags) :
        Symbol(ctx, decl, kind, idRef, typeRef, flags)
    {
    }

    void addSymbol(TaskContext& ctx, Symbol* symbol);
    void lookup(IdentifierRef idRef, SmallVector<Symbol*>& out) const;
};

SWC_END_NAMESPACE()
