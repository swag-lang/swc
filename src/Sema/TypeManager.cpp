#include "pch.h"
#include "Sema/TypeManager.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE()

void TypeManager::setup(TaskContext&)
{
    typeBool_   = addType(TypeInfo::makeBool());
    typeString_ = addType(TypeInfo::makeString());

    typeApIntUnsigned_ = addType(TypeInfo::makeInt(0, false));
    typeApIntSigned_   = addType(TypeInfo::makeInt(0, true));
    typeApFloat_       = addType(TypeInfo::makeFloat(0));

    typeU8_  = addType(TypeInfo::makeInt(8, false));
    typeU16_ = addType(TypeInfo::makeInt(16, false));
    typeU32_ = addType(TypeInfo::makeInt(32, false));
    typeU64_ = addType(TypeInfo::makeInt(64, false));

    typeS8_  = addType(TypeInfo::makeInt(8, true));
    typeS16_ = addType(TypeInfo::makeInt(16, true));
    typeS32_ = addType(TypeInfo::makeInt(32, true));
    typeS64_ = addType(TypeInfo::makeInt(64, true));

    typeF32_ = addType(TypeInfo::makeFloat(32));
    typeF64_ = addType(TypeInfo::makeFloat(64));
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

    const TypeInfoRef ref{store_.push_back(typeInfo)};
    it->second = ref;
    return ref;
}

TypeInfoRef TypeManager::getTypeInt(uint32_t bits, bool isSigned) const
{
    if (bits == 0)
        return isSigned ? typeApIntSigned_ : typeApIntUnsigned_;

    if (isSigned)
    {
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

TypeInfoRef TypeManager::getTypeFloat(uint32_t bits) const
{
    if (bits == 0)
        return typeApFloat_;

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
    return *store_.ptr<TypeInfo>(typeInfoRef.get());
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

    it->second = typeInfo.toString(*this, mode);
    return it->second;
}

SWC_END_NAMESPACE()
