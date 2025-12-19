#include "pch.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

SymbolMap::Shard& SymbolMap::getShard(const IdentifierRef idRef)
{
    const uint32_t index = idRef.get() & (SHARD_COUNT - 1);
    Shard&         shard = shards_[index];
    return shard;
}

const SymbolMap::Shard& SymbolMap::getShard(const IdentifierRef idRef) const
{
    const uint32_t index = idRef.get() & (SHARD_COUNT - 1);
    const Shard&   shard = shards_[index];
    return shard;
}

void SymbolMap::lookup(IdentifierRef idRef, SmallVector<Symbol*>& out) const
{
    out.clear();

    const Shard& shard = getShard(idRef);

    std::shared_lock lk(shard.mutex);
    const auto       it = shard.map.find(idRef);
    if (it == shard.map.end())
        return;

    Symbol* cur = it->second;
    while (cur)
    {
        out.push_back(cur);
        cur = cur->nextHomonym();
    }
}

void SymbolMap::addSymbol(TaskContext& ctx, Symbol* symbol)
{
    SWC_ASSERT(symbol != nullptr);

    const IdentifierRef idRef = symbol->idRef();
    Shard&              shard = getShard(idRef);

    std::unique_lock lock(shard.mutex);

    Symbol*& head = shard.map[idRef];
    symbol->setSymMap(this);
    symbol->setNextHomonym(head);
    head = symbol;

    ctx.compiler().notifySymbolAdded();
}

SymbolConstant* SymbolMap::addConstant(TaskContext& ctx, IdentifierRef idRef, ConstantRef cstRef, SymbolFlags flags)
{
    auto* sym = ctx.compiler().allocate<SymbolConstant>(ctx, idRef, cstRef, flags);
    addSymbol(ctx, sym);
    return sym;
}

SymbolVariable* SymbolMap::addVariable(TaskContext& ctx, IdentifierRef idRef, TypeRef typeRef, SymbolFlags flags)
{
    auto* sym = ctx.compiler().allocate<SymbolVariable>(ctx, idRef, typeRef, flags);
    addSymbol(ctx, sym);
    return sym;
}

SymbolEnum* SymbolMap::addEnum(TaskContext& ctx, IdentifierRef idRef, TypeRef typeRef, SymbolFlags flags)
{
    auto* sym = ctx.compiler().allocate<SymbolEnum>(ctx, idRef, typeRef, flags);
    addSymbol(ctx, sym);
    return sym;
}

SymbolNamespace* SymbolMap::addNamespace(TaskContext& ctx, IdentifierRef idRef, SymbolFlags flags)
{
    auto* sym = ctx.compiler().allocate<SymbolNamespace>(ctx, idRef, flags);
    if (idRef != IdentifierRef::invalid())
        addSymbol(ctx, sym);
    return sym;
}

SWC_END_NAMESPACE()
