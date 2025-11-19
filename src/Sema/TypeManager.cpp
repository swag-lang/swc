// ReSharper disable CppClangTidyClangDiagnosticMissingDesignatedFieldInitializers
#include "pch.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void TypeManager::setup(CompilerInstance&)
{
    typeBool_ = registerType(TypeInfo{.kind = TypeInfoKind::Bool});
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
    const auto       it = map_.find(typeInfo);
    if (it != map_.end())
        return it->second;

    TypeInfoRef ref{store_.push_back<TypeInfo>(typeInfo)};
    map_.emplace(typeInfo, ref);
    return ref;
}

SWC_END_NAMESPACE()
