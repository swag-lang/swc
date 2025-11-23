#include "pch.h"
#include "Sema/TypeManager.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE()

void TypeManager::setup(TaskContext&)
{
    typeBool_   = addType(TypeInfo::makeBool());
    typeString_ = addType(TypeInfo::makeString());
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

const TypeInfo& TypeManager::getType(TypeInfoRef typeInfoRef) const
{
    std::shared_lock lk(mutexAdd_);
    SWC_ASSERT(typeInfoRef.isValid());
    return *store_.ptr<TypeInfo>(typeInfoRef.get());
}

std::string_view TypeManager::typeToString(TypeInfoRef typeInfoRef, TypeInfo::ToStringMode mode) const
{
    SWC_ASSERT(typeInfoRef.isValid());
    return typeToString(getType(typeInfoRef), mode);
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
