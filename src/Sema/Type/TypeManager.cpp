#include "pch.h"
#include "Sema/Type/TypeManager.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE()

void TypeManager::setup(TaskContext&)
{
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

    typeAny_     = addType(TypeInfo::makeAny());
    typeVoid_    = addType(TypeInfo::makeVoid());
    typeRune_    = addType(TypeInfo::makeRune());
    typeCString_ = addType(TypeInfo::makeCString());

    buildPromoteTable();
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
            const uint32_t lhsBits = lhs.floatBits();
            const uint32_t rhsBits = rhs.floatBits();
            return (lhsBits >= rhsBits) ? lhsRef : rhsRef;
        }

        // Mixed float/int: Must return a float, potentially widened
        const TypeRef floatRef = lhsFloat ? lhsRef : rhsRef;
        const TypeRef intRef   = lhsFloat ? rhsRef : lhsRef;

        const TypeInfo& fInfo = get(floatRef);
        const TypeInfo& iInfo = get(intRef);

        const uint32_t fBits = fInfo.floatBits();
        const uint32_t iBits = iInfo.intLikeBits();

        uint32_t resultBits = std::max(fBits, iBits);
        if (resultBits)
            resultBits = std::max(resultBits, 32u);
        return getTypeFloat(resultBits);
    }

    // Integer promotions
    const uint32_t lhsBits = lhs.intLikeBits();
    const uint32_t rhsBits = rhs.intLikeBits();

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

    if (sBits >= uBits)
        return signedRef;
    return unsignedRef;
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

TypeRef TypeManager::promote(TypeRef lhs, TypeRef rhs, bool force32BitInts) const
{
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

    const uint32_t bits = t.intBits();
    if (bits != 8 && bits != 16)
        return result;

    return getTypeInt(32, t.isIntUnsigned() ? TypeInfo::Sign::Unsigned : TypeInfo::Sign::Signed);
}

TypeRef TypeManager::getTypeInt(uint32_t bits, TypeInfo::Sign sign) const
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

TypeRef TypeManager::addType(const TypeInfo& typeInfo)
{
    const uint32_t shardIndex = typeInfo.hash() & (SHARD_COUNT - 1);
    auto&          shard      = shards_[shardIndex];

    {
        std::shared_lock lk(shard.mutexAdd);
        if (const auto it = shard.map.find(typeInfo); it != shard.map.end())
            return it->second;
    }

    std::unique_lock lk(shard.mutexAdd);
    const auto [it, inserted] = shard.map.try_emplace(typeInfo, TypeRef{});
    if (!inserted)
        return it->second;

#if SWC_HAS_STATS
    Stats::get().numTypes.fetch_add(1);
    Stats::get().memTypes.fetch_add(sizeof(TypeInfo), std::memory_order_relaxed);
#endif

    const uint32_t localIndex = shard.store.size() / sizeof(TypeInfo);
    SWC_ASSERT(localIndex <= LOCAL_MASK);
    shard.store.push_back(typeInfo);

    auto result = TypeRef{(shardIndex << LOCAL_BITS) | localIndex};
#if SWC_HAS_DEBUG_INFO
    result.setDbgPtr(&get(result));
#endif

    it->second = result;
    return result;
}

TypeRef TypeManager::getTypeFloat(uint32_t bits) const
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

std::string_view TypeManager::typeToName(TypeRef typeInfoRef) const
{
    SWC_ASSERT(typeInfoRef.isValid());

    const TypeInfo& typeInfo   = get(typeInfoRef);
    const uint32_t  shardIndex = typeInfoRef.get() >> LOCAL_BITS;
    auto&           shard      = shards_[shardIndex];

    {
        std::shared_lock lk(shard.mutexName);
        const auto       it = shard.mapName.find(typeInfo);
        if (it != shard.mapName.end())
            return it->second;
    }

    std::unique_lock lk(shard.mutexName);
    const auto [it, inserted] = shard.mapName.try_emplace(typeInfo, Utf8{});
    if (!inserted)
        return it->second;

    it->second = typeInfo.toName(*this);
    return it->second;
}

const TypeInfo& TypeManager::get(TypeRef typeRef) const
{
    SWC_ASSERT(typeRef.isValid());
    const auto shardIndex = typeRef.get() >> LOCAL_BITS;
    const auto localIndex = typeRef.get() & LOCAL_MASK;
    return *shards_[shardIndex].store.ptr<TypeInfo>(localIndex * sizeof(TypeInfo));
}

uint32_t TypeManager::chooseConcreteScalarWidth(uint32_t minRequiredBits, bool& overflow)
{
    constexpr uint32_t minBits = 8;
    constexpr uint32_t maxBits = 64;
    const uint32_t     bits    = std::max(minRequiredBits, minBits);
    overflow                   = bits > maxBits;
    return bits;
}

SWC_END_NAMESPACE()
