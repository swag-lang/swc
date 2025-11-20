// ReSharper disable CppClangTidyClangDiagnosticMissingDesignatedFieldInitializers
#include "pch.h"
#include "Sema/TypeManager.h"

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

SWC_END_NAMESPACE()
