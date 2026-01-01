#include "pch.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Lexer/SourceView.h"
#include "Lexer/Token.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Math/Hash.h"

SWC_BEGIN_NAMESPACE()

void IdentifierManager::setup(TaskContext&)
{
    nameSwag_           = addIdentifier("Swag");
    nameEnumFlags_      = addIdentifier("EnumFlags");
    nameAttributeUsage_ = addIdentifier("AttributeUsage");
    nameTargetOs_       = addIdentifier("TargetOs");
}

IdentifierRef IdentifierManager::addIdentifier(const TaskContext& ctx, SourceViewRef srcViewRef, TokenRef tokRef)
{
    const SourceView&      srcView = ctx.compiler().srcView(srcViewRef);
    const Token&           tok     = srcView.token(tokRef);
    const std::string_view name    = tok.string(srcView);
    const uint32_t         crc     = tok.crc(srcView);
    return addIdentifier(name, crc);
}

IdentifierRef IdentifierManager::addIdentifier(std::string_view name)
{
    return addIdentifier(name, Math::hash(name));
}

IdentifierRef IdentifierManager::addIdentifier(std::string_view name, uint32_t hash)
{
    const uint32_t shardIndex = hash & (SHARD_COUNT - 1);
    auto&          shard      = shards_[shardIndex];

    {
        std::shared_lock lk(shard.mutex);
        if (const auto it = shard.map.find(name, hash))
            return *it;
    }

    std::unique_lock lk(shard.mutex);
    const auto [it, inserted] = shard.map.try_emplace(name, hash, IdentifierRef{});
    if (!inserted)
        return *it;

#if SWC_HAS_STATS
    Stats::get().numIdentifiers.fetch_add(1);
#endif

    const uint32_t localIndex = shard.store.size() / sizeof(Identifier);
    SWC_ASSERT(localIndex < LOCAL_MASK);
    shard.store.push_back(Identifier{name});

    auto result = IdentifierRef{(shardIndex << LOCAL_BITS) | localIndex};
#if SWC_HAS_DEBUG_INFO
    result.setDbgPtr(&get(result));
#endif

    *it = result;
    return result;
}

const Identifier& IdentifierManager::get(IdentifierRef idRef) const
{
    SWC_ASSERT(idRef.isValid());
    const auto shardIndex = idRef.get() >> LOCAL_BITS;
    const auto localIndex = idRef.get() & LOCAL_MASK;
    return *shards_[shardIndex].store.ptr<Identifier>(localIndex * sizeof(idRef));
}

SWC_END_NAMESPACE()
