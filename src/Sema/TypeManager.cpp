#include "pch.h"
#include "Sema/TypeManager.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE()

void TypeManager::setup(TaskContext&)
{
    typeBool_   = registerType(TypeInfo::makeBool());
    typeString_ = registerType(TypeInfo::makeString());
}

TypeInfoRef TypeManager::registerType(const TypeInfo& typeInfo)
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
        std::shared_lock lk(mutexName_[idx]);
        const auto       it = mapName_[idx].find(typeInfo);
        if (it != mapName_[idx].end())
            return it->second;
    }

    std::unique_lock lk(mutexName_[idx]);
    const auto [it, inserted] = mapName_[idx].try_emplace(typeInfo, Utf8{});
    if (!inserted)
        return it->second;

    it->second = typeInfo.toString(mode);
    return it->second;
}

SWC_END_NAMESPACE()
