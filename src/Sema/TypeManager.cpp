#include "pch.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void TypeManager::setup(CompilerInstance&)
{
    typeBool_ = registerType(TypeInfo{.kind = TypeInfoKind::Bool});
}

TypeInfoRef TypeManager::registerType(const TypeInfo& typeInfo)
{
    const auto it = map_.find(typeInfo);
    if (it != map_.end())
        return it->second;
    return TypeInfoRef{store_.push_back<TypeInfo>(typeInfo)};
}

SWC_END_NAMESPACE()
