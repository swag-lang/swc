#include "pch.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

SymbolMap::~SymbolMap()
{
    for (auto& shard : shards_)
    {
        std::unique_lock lk(shard.mutex);

        for (auto& head : shard.map | std::views::values)
        {
            Symbol* cur = head;
            while (cur)
            {
                Symbol* next = cur->nextHomonym();
                cur->setNextHomonym(nullptr);
                delete cur;
                cur = next;
            }

            head = nullptr;
        }

        shard.map.clear();
    }
}

Symbol* SymbolMap::lookupOne(IdentifierRef idRef) const
{
    const uint32_t shardIndex = idRef.get() & (SHARD_COUNT - 1);
    const Shard&   shard      = shards_[shardIndex];

    std::shared_lock lk(shard.mutex);
    const auto       it = shard.map.find(idRef);
    if (it == shard.map.end())
        return nullptr;

    return it->second;
}

void SymbolMap::lookupAll(IdentifierRef idRef, SmallVector<Symbol*>& out) const
{
    out.clear();

    const uint32_t shardIndex = idRef.get() & (SHARD_COUNT - 1);
    const Shard&   shard      = shards_[shardIndex];

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

void SymbolMap::addSymbol(Symbol* symbol)
{
    SWC_ASSERT(symbol != nullptr);

    const IdentifierRef idRef = symbol->idRef();
    const uint32_t      index = idRef.get() & (SHARD_COUNT - 1);
    Shard&              shard = shards_[index];

    std::unique_lock lock(shard.mutex);

    Symbol*& head = shard.map[idRef];
    symbol->setNextHomonym(head);
    head = symbol;
}

SymbolConstant* SymbolMap::addConstant(const TaskContext& ctx, IdentifierRef idRef, ConstantRef cstRef)
{
    auto* sym = new SymbolConstant(ctx, idRef, cstRef);
    addSymbol(sym);
    return sym;
}

SymbolNamespace* SymbolMap::addNamespace(const TaskContext& ctx, IdentifierRef idRef)
{
    auto* sym = new SymbolNamespace(ctx, idRef);
    addSymbol(sym);
    return sym;
}

SWC_END_NAMESPACE()
