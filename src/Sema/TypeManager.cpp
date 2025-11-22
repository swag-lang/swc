#include "pch.h"
#include "Sema/TypeManager.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE()

void TypeManager::setup(TaskContext&)
{
    typeBool_ = registerType(TypeInfo::makeBool());
}

TypeInfoRef TypeManager::registerType(const TypeInfo& typeInfo)
{
    {
        std::shared_lock lk(mutex_);
        const auto       it = map_.find(typeInfo);
        if (it != map_.end())
            return it->second;
    }

    std::unique_lock lk(mutex_);
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
    std::shared_lock lk(mutex_);
    SWC_ASSERT(typeInfoRef.isValid());
    return *store_.ptr<TypeInfo>(typeInfoRef.get());
}

Utf8 TypeManager::toString(TypeInfoRef typeInfoRef) const
{
    SWC_ASSERT(typeInfoRef.isValid());
    const auto typeInfo = get(typeInfoRef);
    return "toto";
}

SWC_END_NAMESPACE()
