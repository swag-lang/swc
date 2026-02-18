#include "pch.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::array<RuntimeTypeKind, static_cast<size_t>(IdentifierManager::PredefinedName::Count)> makePredefinedRuntimeMap()
    {
        using Pn                                                        = IdentifierManager::PredefinedName;
        std::array<RuntimeTypeKind, static_cast<size_t>(Pn::Count)> map = {};
        map.fill(RuntimeTypeKind::Count);
        map[static_cast<size_t>(Pn::TargetOs)]           = RuntimeTypeKind::TargetOs;
        map[static_cast<size_t>(Pn::TargetArch)]         = RuntimeTypeKind::TargetArch;
        map[static_cast<size_t>(Pn::TypeInfoKind)]       = RuntimeTypeKind::TypeInfoKind;
        map[static_cast<size_t>(Pn::TypeInfoNativeKind)] = RuntimeTypeKind::TypeInfoNativeKind;
        map[static_cast<size_t>(Pn::TypeInfoFlags)]      = RuntimeTypeKind::TypeInfoFlags;
        map[static_cast<size_t>(Pn::TypeValueFlags)]     = RuntimeTypeKind::TypeValueFlags;
        map[static_cast<size_t>(Pn::TypeInfo)]           = RuntimeTypeKind::TypeInfo;
        map[static_cast<size_t>(Pn::TypeInfoNative)]     = RuntimeTypeKind::TypeInfoNative;
        map[static_cast<size_t>(Pn::TypeInfoPointer)]    = RuntimeTypeKind::TypeInfoPointer;
        map[static_cast<size_t>(Pn::TypeInfoStruct)]     = RuntimeTypeKind::TypeInfoStruct;
        map[static_cast<size_t>(Pn::TypeInfoFunc)]       = RuntimeTypeKind::TypeInfoFunc;
        map[static_cast<size_t>(Pn::TypeInfoEnum)]       = RuntimeTypeKind::TypeInfoEnum;
        map[static_cast<size_t>(Pn::TypeInfoArray)]      = RuntimeTypeKind::TypeInfoArray;
        map[static_cast<size_t>(Pn::TypeInfoSlice)]      = RuntimeTypeKind::TypeInfoSlice;
        map[static_cast<size_t>(Pn::TypeInfoAlias)]      = RuntimeTypeKind::TypeInfoAlias;
        map[static_cast<size_t>(Pn::TypeInfoVariadic)]   = RuntimeTypeKind::TypeInfoVariadic;
        map[static_cast<size_t>(Pn::TypeInfoGeneric)]    = RuntimeTypeKind::TypeInfoGeneric;
        map[static_cast<size_t>(Pn::TypeInfoNamespace)]  = RuntimeTypeKind::TypeInfoNamespace;
        map[static_cast<size_t>(Pn::TypeInfoCodeBlock)]  = RuntimeTypeKind::TypeInfoCodeBlock;
        map[static_cast<size_t>(Pn::TypeValue)]          = RuntimeTypeKind::TypeValue;
        map[static_cast<size_t>(Pn::Attribute)]          = RuntimeTypeKind::Attribute;
        map[static_cast<size_t>(Pn::AttributeParam)]     = RuntimeTypeKind::AttributeParam;
        map[static_cast<size_t>(Pn::Interface)]          = RuntimeTypeKind::Interface;
        map[static_cast<size_t>(Pn::SourceCodeLocation)] = RuntimeTypeKind::SourceCodeLocation;
        map[static_cast<size_t>(Pn::ErrorValue)]         = RuntimeTypeKind::ErrorValue;
        map[static_cast<size_t>(Pn::ScratchAllocator)]   = RuntimeTypeKind::ScratchAllocator;
        map[static_cast<size_t>(Pn::Context)]            = RuntimeTypeKind::Context;
        map[static_cast<size_t>(Pn::ContextFlags)]       = RuntimeTypeKind::ContextFlags;
        map[static_cast<size_t>(Pn::Module)]             = RuntimeTypeKind::Module;
        map[static_cast<size_t>(Pn::ProcessInfos)]       = RuntimeTypeKind::ProcessInfos;
        map[static_cast<size_t>(Pn::Gvtd)]               = RuntimeTypeKind::Gvtd;
        map[static_cast<size_t>(Pn::BuildCfg)]           = RuntimeTypeKind::BuildCfg;
        return map;
    }

    constexpr std::array<RuntimeTypeKind, static_cast<size_t>(IdentifierManager::PredefinedName::Count)> PREDEFINED_RUNTIME_MAP = makePredefinedRuntimeMap();
}

void TypeManager::setup(TaskContext& ctx)
{
    const IdentifierManager& idMgr = ctx.idMgr();
    for (size_t i = 0; i < PREDEFINED_RUNTIME_MAP.size(); ++i)
    {
        const RuntimeTypeKind kind = PREDEFINED_RUNTIME_MAP[i];
        if (kind == RuntimeTypeKind::Count)
            continue;
        const auto name                    = static_cast<IdentifierManager::PredefinedName>(i);
        mapRtKind_[idMgr.predefined(name)] = kind;
    }

    for (TypeRef& rt : runtimeTypes_)
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
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    auto& shard = shards_[shardIndex];

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

    const uint32_t localIndex = shard.store.pushBack(typeInfo);
    SWC_ASSERT(localIndex < LOCAL_MASK);

    TypeInfo* ptr = shard.store.ptr<TypeInfo>(localIndex);
    TypeRef   result{(shardIndex << LOCAL_BITS) | localIndex};
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
    const uint32_t shardIndex = typeRef.get() >> LOCAL_BITS;
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    const uint32_t localIndex = typeRef.get() & LOCAL_MASK;
    return *SWC_CHECK_NOT_NULL(shards_[shardIndex].store.ptr<TypeInfo>(localIndex));
}

const TypeInfo& TypeManager::get(TypeRef typeRef) const
{
    SWC_ASSERT(typeRef.isValid());
    const uint32_t shardIndex = typeRef.get() >> LOCAL_BITS;
    SWC_ASSERT(shardIndex < SHARD_COUNT);
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

bool TypeManager::isTypeInfoRuntimeStruct(IdentifierRef idRef) const
{
    const auto it = mapRtKind_.find(idRef);
    if (it == mapRtKind_.end())
        return false;

    const RuntimeTypeKind kind  = it->second;
    const uint32_t        uKind = static_cast<uint32_t>(kind);
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

TypeRef TypeManager::runtimeType(IdentifierManager::PredefinedName name) const
{
    const RuntimeTypeKind kind = PREDEFINED_RUNTIME_MAP[static_cast<size_t>(name)];
    if (kind == RuntimeTypeKind::Count)
        return TypeRef::invalid();
    return runtimeType(kind);
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

    constexpr uint32_t n = types.size();

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

SWC_END_NAMESPACE();
