#include "pch.h"
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

Symbol* SymbolMap::findSymbol(IdentifierRef idRef) const
{
    const uint32_t shardIndex = idRef.get() % SHARD_COUNT;
    const auto     it         = shards_[shardIndex].monoMap.find(idRef);
    if (it == shards_[shardIndex].monoMap.end())
        return nullptr;
    return it->second;
}

SWC_END_NAMESPACE()
