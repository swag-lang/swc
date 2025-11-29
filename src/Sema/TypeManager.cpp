#include "pch.h"
#include "Sema/TypeManager.h"
#include "Main/Stats.h"
#include <ranges>

SWC_BEGIN_NAMESPACE()

void TypeManager::setup(TaskContext&)
{
    typeIntUnsigned_ = addType(TypeInfo::makeInt(0, true));
    typeIntSigned_   = addType(TypeInfo::makeInt(0, false));
    typeFloat_       = addType(TypeInfo::makeFloat(0));

    typeU8_  = addType(TypeInfo::makeInt(8, true));
    typeU16_ = addType(TypeInfo::makeInt(16, true));
    typeU32_ = addType(TypeInfo::makeInt(32, true));
    typeU64_ = addType(TypeInfo::makeInt(64, true));

    typeS8_  = addType(TypeInfo::makeInt(8, false));
    typeS16_ = addType(TypeInfo::makeInt(16, false));
    typeS32_ = addType(TypeInfo::makeInt(32, false));
    typeS64_ = addType(TypeInfo::makeInt(64, false));

    typeF32_ = addType(TypeInfo::makeFloat(32));
    typeF64_ = addType(TypeInfo::makeFloat(64));

    buildPromoteTable();

    typeBool_   = addType(TypeInfo::makeBool());
    typeString_ = addType(TypeInfo::makeString());
}

TypeInfoRef TypeManager::computePromotion(TypeInfoRef lhsRef, TypeInfoRef rhsRef) const
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
        const uint32_t lhsBits = lhsFloat ? lhs.floatBits() : 0;
        const uint32_t rhsBits = rhsFloat ? rhs.floatBits() : 0;
        return (lhsBits >= rhsBits) ? lhsRef : rhsRef;
    }

    // Integer promotions
    const uint32_t lhsBits = lhs.intBits();
    const uint32_t rhsBits = rhs.intBits();

    const bool lhsUnsigned = lhs.isIntUnsigned();
    const bool rhsUnsigned = rhs.isIntUnsigned();

    // Same signedness: pick larger
    if (lhsUnsigned == rhsUnsigned)
        return (lhsBits >= rhsBits) ? lhsRef : rhsRef;

    // Mixed signedness:
    const TypeInfoRef unsignedRef = lhsUnsigned ? lhsRef : rhsRef;
    const TypeInfoRef signedRef   = lhsUnsigned ? rhsRef : lhsRef;

    const uint32_t uBits = lhsUnsigned ? lhsBits : rhsBits;
    const uint32_t sBits = lhsUnsigned ? rhsBits : lhsBits;

    // If the signed type is strictly larger, it can hold all unsigned values
    if (sBits > uBits)
        return signedRef;

    return unsignedRef;
}

void TypeManager::buildPromoteTable()
{
    const size_t n = map_.size();

    std::vector<uint32_t> arithmeticTypes;
    for (const auto ref : map_ | std::views::values)
        arithmeticTypes.push_back(ref.get());

    promoteTable_.resize(n);
    for (uint32_t i = 0; i < n; ++i)
        promoteTable_[i].resize(n);

    for (uint32_t i = 0; i < n; ++i)
    {
        for (uint32_t j = 0; j < n; ++j)
        {
            const auto lhs      = TypeInfoRef{arithmeticTypes[i]};
            const auto rhs      = TypeInfoRef{arithmeticTypes[j]};
            promoteTable_[i][j] = computePromotion(lhs, rhs);
        }
    }
}

TypeInfoRef TypeManager::promote(TypeInfoRef lhs, TypeInfoRef rhs) const
{
    return promoteTable_[lhs.get()][rhs.get()];
}

TypeInfoRef TypeManager::addType(const TypeInfo& typeInfo)
{
    {
        std::shared_lock lk(mutexAdd_);
        const auto       it = map_.find(typeInfo);
        if (it != map_.end())
            return it->second;
    }

    std::unique_lock lk(mutexAdd_);
    const auto [it, inserted] = map_.try_emplace(typeInfo, TypeInfoRef{});
    if (!inserted)
        return it->second;

#if SWC_HAS_STATS
    Stats::get().numTypes.fetch_add(1);
    Stats::get().memTypes.fetch_add(sizeof(TypeInfo), std::memory_order_relaxed);
#endif

    const TypeInfoRef ref{store_.push_back(typeInfo) / static_cast<uint32_t>(sizeof(TypeInfoRef))};
    it->second = ref;
    return ref;
}

TypeInfoRef TypeManager::getTypeInt(uint32_t bits, bool isUnsigned) const
{
    if (bits == 0)
        return isUnsigned ? typeIntUnsigned_ : typeIntSigned_;

    if (isUnsigned)
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

TypeInfoRef TypeManager::getTypeFloat(uint32_t bits) const
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

const TypeInfo& TypeManager::get(TypeInfoRef typeInfoRef) const
{
    std::shared_lock lk(mutexAdd_);
    SWC_ASSERT(typeInfoRef.isValid());
    return *store_.ptr<TypeInfo>(typeInfoRef.get() * sizeof(TypeInfoRef));
}

std::string_view TypeManager::typeToString(TypeInfoRef typeInfoRef, TypeInfo::ToStringMode mode) const
{
    SWC_ASSERT(typeInfoRef.isValid());
    return typeToString(get(typeInfoRef), mode);
}

std::string_view TypeManager::typeToString(const TypeInfo& typeInfo, TypeInfo::ToStringMode mode) const
{
    const auto idx = static_cast<int>(mode);

    {
        std::shared_lock lk(mutexString_[idx]);
        const auto       it = mapString_[idx].find(typeInfo);
        if (it != mapString_[idx].end())
            return it->second;
    }

    std::unique_lock lk(mutexString_[idx]);
    const auto [it, inserted] = mapString_[idx].try_emplace(typeInfo, Utf8{});
    if (!inserted)
        return it->second;

    it->second = typeInfo.toString(mode);
    return it->second;
}

SWC_END_NAMESPACE()
