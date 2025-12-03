#include "pch.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

Symbol* SymbolMap::findSymbol(IdentifierRef idRef) const
{
    const uint32_t   shardIndex = idRef.get() % SHARD_COUNT;
    std::shared_lock lk(shards_[shardIndex].mutex);
    const auto       it = shards_[shardIndex].monoMap.find(idRef);
    if (it == shards_[shardIndex].monoMap.end())
        return nullptr;
    return it->second.get();
}

Symbol* SymbolMap::addSymbol(std::unique_ptr<Symbol> symbol)
{
    SWC_ASSERT(symbol != nullptr);

    IdentifierRef  idRef = symbol->idRef();
    const uint32_t index = idRef.get() & SHARD_COUNT;
    Shard&         shard = shards_[index];

    std::unique_lock lock(shard.mutex);

    SWC_ASSERT(!shard.monoMap.contains(idRef));

    Symbol* rawPtr = symbol.get();
    shard.monoMap.emplace(idRef, std::move(symbol));
    return rawPtr;
}

SymbolConstant* SymbolMap::addConstant(const TaskContext& ctx, IdentifierRef idRef, ConstantRef cstRef)
{
    auto newSymbol = std::make_unique<SymbolConstant>(ctx, idRef, cstRef);
    return reinterpret_cast<SymbolConstant*>(addSymbol(std::move(newSymbol)));
}

SymbolNamespace* SymbolMap::addNamespace(const TaskContext& ctx, IdentifierRef idRef)
{
    auto newSymbol = std::make_unique<SymbolNamespace>(ctx, idRef);
    return reinterpret_cast<SymbolNamespace*>(addSymbol(std::move(newSymbol)));
}

SWC_END_NAMESPACE()
