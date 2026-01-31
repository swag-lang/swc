#include "pch.h"
#include "Sema/Type/TypeManager.h"
#include "Main/Stats.h"
#include "Sema/Core/Sema.h"
#include "Sema/Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE();

void TypeManager::setup(TaskContext& ctx)
{
    const auto& idMgr                                                                   = ctx.idMgr();
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TargetOs)]           = RuntimeTypeKind::TargetOs;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoKind)]       = RuntimeTypeKind::TypeInfoKind;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoNativeKind)] = RuntimeTypeKind::TypeInfoNativeKind;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoFlags)]      = RuntimeTypeKind::TypeInfoFlags;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeValueFlags)]     = RuntimeTypeKind::TypeValueFlags;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfo)]           = RuntimeTypeKind::TypeInfo;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoNative)]     = RuntimeTypeKind::TypeInfoNative;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoPointer)]    = RuntimeTypeKind::TypeInfoPointer;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoStruct)]     = RuntimeTypeKind::TypeInfoStruct;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoFunc)]       = RuntimeTypeKind::TypeInfoFunc;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoEnum)]       = RuntimeTypeKind::TypeInfoEnum;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoArray)]      = RuntimeTypeKind::TypeInfoArray;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoSlice)]      = RuntimeTypeKind::TypeInfoSlice;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoAlias)]      = RuntimeTypeKind::TypeInfoAlias;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoVariadic)]   = RuntimeTypeKind::TypeInfoVariadic;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoGeneric)]    = RuntimeTypeKind::TypeInfoGeneric;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoNamespace)]  = RuntimeTypeKind::TypeInfoNamespace;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeInfoCodeBlock)]  = RuntimeTypeKind::TypeInfoCodeBlock;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::TypeValue)]          = RuntimeTypeKind::TypeValue;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::Attribute)]          = RuntimeTypeKind::Attribute;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::AttributeParam)]     = RuntimeTypeKind::AttributeParam;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::Interface)]          = RuntimeTypeKind::Interface;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::SourceCodeLocation)] = RuntimeTypeKind::SourceCodeLocation;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::ErrorValue)]         = RuntimeTypeKind::ErrorValue;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::ScratchAllocator)]   = RuntimeTypeKind::ScratchAllocator;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::Context)]            = RuntimeTypeKind::Context;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::ContextFlags)]       = RuntimeTypeKind::ContextFlags;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::Module)]             = RuntimeTypeKind::Module;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::ProcessInfos)]       = RuntimeTypeKind::ProcessInfos;
    mapRtKind_[idMgr.predefined(IdentifierManager::PredefinedName::Gvtd)]               = RuntimeTypeKind::Gvtd;

    for (auto& rt : runtimeTypes_)
        rt = TypeRef::invalid();

    typeIntUnsigned_ = addType(TypeInfo::makeInt(0, TypeInfo::Sign::Unsigned));
    typeIntSigned_   = addType(TypeInfo::makeInt(0, TypeInfo::Sign::Signed));
    typeInt_         = addType(TypeInfo::makeInt(0, TypeInfo::Sign::Unknown));
    typeFloat_       = addType(TypeInfo::makeFloat(0));

    typeU8_  = addType(TypeInfo::makeInt(8, TypeInfo::Sign::Unsigned));
    typeU16_ = addType(TypeInfo::makeInt(16, TypeInfo::Sign::Unsigned));
    typeU32_ = addType(TypeInfo::makeInt(32, TypeInfo::Sign::Unsigned));
    typeU64_ = addType(TypeInfo::makeInt(64, TypeInfo::Sign::Unsigned));

    typeS8_  = addType(TypeInfo::makeInt(8, TypeInfo::Sign::Signed));
    typeS16_ = addType(TypeInfo::makeInt(16, TypeInfo::Sign::Signed));
    typeS32_ = addType(TypeInfo::makeInt(32, TypeInfo::Sign::Signed));
    typeS64_ = addType(TypeInfo::makeInt(64, TypeInfo::Sign::Signed));

    typeF32_ = addType(TypeInfo::makeFloat(32));
    typeF64_ = addType(TypeInfo::makeFloat(64));

    typeBool_   = addType(TypeInfo::makeBool());
    typeChar_   = addType(TypeInfo::makeChar());
    typeString_ = addType(TypeInfo::makeString());

    typeAny_       = addType(TypeInfo::makeAny());
    typeVoid_      = addType(TypeInfo::makeVoid());
    typeNull_      = addType(TypeInfo::makeNull());
    typeUndefined_ = addType(TypeInfo::makeUndefined());
    typeRune_      = addType(TypeInfo::makeRune());
    typeCString_   = addType(TypeInfo::makeCString());
    typeVariadic_  = addType(TypeInfo::makeVariadic());
    typeTypeInfo_  = addType(TypeInfo::makeTypeInfo());

    typeBlockPtrVoid_      = addType(TypeInfo::makeBlockPointer(typeVoid_));
    typeConstBlockPtrVoid_ = addType(TypeInfo::makeBlockPointer(typeVoid_, TypeInfoFlagsE::Const));
    typeBlockPtrU8_        = addType(TypeInfo::makeBlockPointer(typeU8_));
    typeConstBlockPtrU8_   = addType(TypeInfo::makeBlockPointer(typeU8_, TypeInfoFlagsE::Const));

    typeValuePtrVoid_      = addType(TypeInfo::makeValuePointer(typeVoid_));
    typeConstValuePtrVoid_ = addType(TypeInfo::makeValuePointer(typeVoid_, TypeInfoFlagsE::Const));
    typeValuePtrU8_        = addType(TypeInfo::makeValuePointer(typeU8_));
    typeConstValuePtrU8_   = addType(TypeInfo::makeValuePointer(typeU8_, TypeInfoFlagsE::Const));

    buildPromoteTable();
}

TypeRef TypeManager::typeInt(uint32_t bits, TypeInfo::Sign sign) const
{
    if (bits == 0)
    {
        if (sign == TypeInfo::Sign::Unknown)
            return typeInt_;
        return sign == TypeInfo::Sign::Unsigned ? typeIntUnsigned_ : typeIntSigned_;
    }

    if (sign == TypeInfo::Sign::Unsigned)
    {
        switch (bits)
        {
            case 8:
                return typeU8_;
            case 16:
                return typeU16_;
            case 32:
                return typeU32_;
            case 64:
                return typeU64_;
            default:
                SWC_UNREACHABLE();
        }
    }

    SWC_ASSERT(sign == TypeInfo::Sign::Signed);
    switch (bits)
    {
        case 8:
            return typeS8_;
        case 16:
            return typeS16_;
        case 32:
            return typeS32_;
        case 64:
            return typeS64_;
        default:
            SWC_UNREACHABLE();
    }
}

TypeRef TypeManager::typeFloat(uint32_t bits) const
{
    if (bits == 0)
        return typeFloat_;

    switch (bits)
    {
        case 32:
            return typeF32_;
        case 64:
            return typeF64_;
        default:
            SWC_UNREACHABLE();
    }
}

TypeRef TypeManager::addType(const TypeInfo& typeInfo)
{
    const uint32_t shardIndex = typeInfo.hash() & (SHARD_COUNT - 1);
    auto&          shard      = shards_[shardIndex];

    {
        std::shared_lock lk(shard.mutex);
        if (const auto it = shard.map.find(typeInfo); it != shard.map.end())
            return it->second;
    }

    std::unique_lock lk(shard.mutex);
    const auto [it, inserted] = shard.map.try_emplace(typeInfo, TypeRef{});
    if (!inserted)
        return it->second;

#if SWC_HAS_STATS
    Stats::get().numTypes.fetch_add(1);
    Stats::get().memTypes.fetch_add(sizeof(TypeInfo), std::memory_order_relaxed);
#endif

    const uint32_t localIndex = shard.store.push_back(typeInfo);
    SWC_ASSERT(localIndex < LOCAL_MASK);

    auto ptr      = shard.store.ptr<TypeInfo>(localIndex);
    auto result   = TypeRef{(shardIndex << LOCAL_BITS) | localIndex};
    ptr->typeRef_ = result;

#if SWC_HAS_REF_DEBUG_INFO
    result.dbgPtr = ptr;
#endif

    it->second = result;
    return result;
}

const TypeInfo& TypeManager::getNoLock(TypeRef typeRef) const
{
    SWC_ASSERT(typeRef.isValid());
    const auto shardIndex = typeRef.get() >> LOCAL_BITS;
    const auto localIndex = typeRef.get() & LOCAL_MASK;
    return *shards_[shardIndex].store.ptr<TypeInfo>(localIndex);
}

const TypeInfo& TypeManager::get(TypeRef typeRef) const
{
    const auto       shardIndex = typeRef.get() >> LOCAL_BITS;
    std::shared_lock lk(shards_[shardIndex].mutex);
    return getNoLock(typeRef);
}

TypeRef TypeManager::promote(TypeRef lhs, TypeRef rhs, bool force32BitInts) const
{
    if (lhs == rhs && !force32BitInts)
        return lhs;

    const auto itL = promoteIndex_.find(lhs.get());
    const auto itR = promoteIndex_.find(rhs.get());

    // If this ever trips, you're trying to promote a type that was not in
    // the numeric set when buildPromoteTable() was called.
    SWC_ASSERT(itL != promoteIndex_.end());
    SWC_ASSERT(itR != promoteIndex_.end());

    const TypeRef result = promoteTable_[itL->second][itR->second];
    if (!force32BitInts)
        return result;

    const TypeInfo& t = get(result);
    if (!t.isInt())
        return result;

    const uint32_t bits = t.payloadIntBits();
    if (bits != 8 && bits != 16)
        return result;

    return typeInt(32, t.isIntUnsigned() ? TypeInfo::Sign::Unsigned : TypeInfo::Sign::Signed);
}

uint32_t TypeManager::chooseConcreteScalarWidth(uint32_t minRequiredBits, bool& overflow)
{
    constexpr uint32_t minBits = 8;
    constexpr uint32_t maxBits = 64;
    const uint32_t     bits    = std::max(minRequiredBits, minBits);
    overflow                   = bits > maxBits;
    return bits;
}

TypeRef TypeManager::computePromotion(TypeRef lhsRef, TypeRef rhsRef) const
{
    const TypeInfo& lhs = get(lhsRef);
    const TypeInfo& rhs = get(rhsRef);

    if (lhsRef == rhsRef)
        return lhsRef;

    const bool lhsFloat = lhs.isFloat();
    const bool rhsFloat = rhs.isFloat();

    // Float promotions
    if (lhsFloat || rhsFloat)
    {
        // Both floats: pick the wider float
        if (lhsFloat && rhsFloat)
        {
            const uint32_t lhsBits = lhs.payloadFloatBits();
            const uint32_t rhsBits = rhs.payloadFloatBits();
            return (lhsBits >= rhsBits) ? lhsRef : rhsRef;
        }

        // Mixed float/int: Must return a float, potentially widened
        const TypeRef floatRef = lhsFloat ? lhsRef : rhsRef;
        const TypeRef intRef   = lhsFloat ? rhsRef : lhsRef;

        const TypeInfo& fInfo = get(floatRef);
        const TypeInfo& iInfo = get(intRef);

        const uint32_t fBits = fInfo.payloadFloatBits();
        const uint32_t iBits = iInfo.payloadIntLikeBits();

        uint32_t resultBits = std::max(fBits, iBits);
        if (resultBits)
            resultBits = std::max(resultBits, 32u);
        return typeFloat(resultBits);
    }

    // Integer promotions
    const uint32_t lhsBits = lhs.payloadIntLikeBits();
    const uint32_t rhsBits = rhs.payloadIntLikeBits();

    const bool lhsUnsigned = lhs.isIntLikeUnsigned();
    const bool rhsUnsigned = rhs.isIntLikeUnsigned();

    // Same signedness: pick larger
    if (lhsUnsigned == rhsUnsigned)
        return (lhsBits >= rhsBits) ? lhsRef : rhsRef;

    // Mixed signedness:
    const TypeRef unsignedRef = lhsUnsigned ? lhsRef : rhsRef;
    const TypeRef signedRef   = lhsUnsigned ? rhsRef : lhsRef;

    const uint32_t uBits = lhsUnsigned ? lhsBits : rhsBits;
    const uint32_t sBits = lhsUnsigned ? rhsBits : lhsBits;

    if (uBits >= sBits)
        return unsignedRef;
    return signedRef;
}

void TypeManager::buildPromoteTable()
{
    const std::array types = {
        typeIntUnsigned_,
        typeIntSigned_,
        typeInt_,
        typeFloat_,
        typeU8_,
        typeU16_,
        typeU32_,
        typeU64_,
        typeS8_,
        typeS16_,
        typeS32_,
        typeS64_,
        typeF32_,
        typeF64_,
        typeChar_,
        typeRune_};

    constexpr auto n = static_cast<uint32_t>(types.size());

    promoteIndex_.clear();
    promoteIndex_.reserve(n);

    // Build mapping from sharded TypeRef to a compact 0..n-1 index
    for (uint32_t i = 0; i < n; ++i)
    {
        const uint32_t key = types[i].get();
        const auto     res = promoteIndex_.emplace(key, i);
        SWC_ASSERT(res.second);
    }

    // Resize the promotion table with compact indices
    promoteTable_.assign(n, std::vector<TypeRef>(n));

    for (uint32_t i = 0; i < n; ++i)
    {
        const TypeRef lhs = types[i];
        for (uint32_t j = 0; j < n; ++j)
        {
            const TypeRef rhs   = types[j];
            promoteTable_[i][j] = computePromotion(lhs, rhs);
        }
    }
}

bool TypeManager::isTypeInfoRuntimeStruct(IdentifierRef idRef) const
{
    const auto it = mapRtKind_.find(idRef);
    if (it == mapRtKind_.end())
        return false;

    const auto     kind  = it->second;
    const uint32_t uKind = static_cast<uint32_t>(kind);
    return uKind >= static_cast<uint32_t>(RuntimeTypeKind::TypeInfo) &&
           uKind <= static_cast<uint32_t>(RuntimeTypeKind::TypeInfoCodeBlock);
}

void TypeManager::registerRuntimeType(IdentifierRef idRef, TypeRef typeRef)
{
    std::unique_lock lk(mutexRt_);
    const auto       it = mapRtKind_.find(idRef);
    if (it == mapRtKind_.end())
        return;
    runtimeTypes_[static_cast<uint32_t>(it->second)] = typeRef;
}

TypeRef TypeManager::runtimeType(RuntimeTypeKind kind) const
{
    std::shared_lock lk(mutexRt_);
    return runtimeTypes_[static_cast<uint32_t>(kind)];
}

SWC_END_NAMESPACE();
