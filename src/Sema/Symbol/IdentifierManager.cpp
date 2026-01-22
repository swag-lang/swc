#include "pch.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Lexer/SourceView.h"
#include "Lexer/Token.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Math/Hash.h"

SWC_BEGIN_NAMESPACE();

void IdentifierManager::setup(TaskContext&)
{
    nameSwag_ = addIdentifier("Swag");

    nameAttributeUsage_ = addIdentifier("AttributeUsage");
    nameEnumFlags_      = addIdentifier("EnumFlags");
    nameStrict_         = addIdentifier("Strict");
    nameMe_             = addIdentifier("me");

    nameTargetOs_ = addIdentifier("TargetOs");

    nameTypeInfo_           = addIdentifier("TypeInfo");
    nameTypeInfoNative_     = addIdentifier("TypeInfoNative");
    nameTypeInfoPointer_    = addIdentifier("TypeInfoPointer");
    nameTypeInfoStruct_     = addIdentifier("TypeInfoStruct");
    nameTypeInfoFunc_       = addIdentifier("TypeInfoFunc");
    nameTypeInfoEnum_       = addIdentifier("TypeInfoEnum");
    nameTypeInfoArray_      = addIdentifier("TypeInfoArray");
    nameTypeInfoSlice_      = addIdentifier("TypeInfoSlice");
    nameTypeInfoAlias_      = addIdentifier("TypeInfoAlias");
    nameTypeInfoVariadic_   = addIdentifier("TypeInfoVariadic");
    nameTypeInfoGeneric_    = addIdentifier("TypeInfoGeneric");
    nameTypeInfoNamespace_  = addIdentifier("TypeInfoNamespace");
    nameTypeInfoCodeBlock_  = addIdentifier("TypeInfoCodeBlock");
    nameTypeInfoKind_       = addIdentifier("TypeInfoKind");
    nameTypeInfoNativeKind_ = addIdentifier("TypeInfoNativeKind");
    nameTypeInfoFlags_      = addIdentifier("TypeInfoFlags");

    nameTypeValue_          = addIdentifier("TypeValue");
    nameTypeValueFlags_     = addIdentifier("TypeValueFlags");
    nameAttribute_          = addIdentifier("Attribute");
    nameAttributeParam_     = addIdentifier("AttributeParam");
    nameInterface_          = addIdentifier("Interface");
    nameSourceCodeLocation_ = addIdentifier("SourceCodeLocation");
    nameContext_            = addIdentifier("Context");
}

IdentifierRef IdentifierManager::addIdentifier(const TaskContext& ctx, SourceViewRef srcViewRef, TokenRef tokRef)
{
    const SourceView&      srcView = ctx.compiler().srcView(srcViewRef);
    const Token&           tok     = srcView.token(tokRef);
    const std::string_view name    = tok.string(srcView);

    if (tok.id == TokenId::Identifier)
    {
        const uint32_t crc = tok.crc(srcView);
        return addIdentifier(name, crc);
    }

    return addIdentifier(name);
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

    const uint32_t localIndex = shard.store.push_back(Identifier{name});
    SWC_ASSERT(localIndex < LOCAL_MASK);

    auto result = IdentifierRef{(shardIndex << LOCAL_BITS) | localIndex};
#if SWC_HAS_REF_DEBUG_INFO
    result.dbgPtr = &getNoLock(result);
#endif

    *it = result;
    return result;
}

const Identifier& IdentifierManager::getNoLock(IdentifierRef idRef) const
{
    SWC_ASSERT(idRef.isValid());
    const auto shardIndex = idRef.get() >> LOCAL_BITS;
    const auto localIndex = idRef.get() & LOCAL_MASK;
    return *shards_[shardIndex].store.ptr<Identifier>(localIndex);
}

const Identifier& IdentifierManager::get(IdentifierRef idRef) const
{
    const auto       shardIndex = idRef.get() >> LOCAL_BITS;
    std::shared_lock lk(shards_[shardIndex].mutex);
    return getNoLock(idRef);
}

SWC_END_NAMESPACE();
