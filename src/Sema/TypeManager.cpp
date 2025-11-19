#include "pch.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void TypeManager::setup()
{
    typeBool_ = registerType(TypeInfo{.kind = TypeInfoKind::Bool});
}

TypeRef TypeManager::registerType(const TypeInfo& typeInfo)
{
    const auto it = map_.find(typeInfo);
    if (it != map_.end())
        return it->second;
    return TypeRef{store_.push_back<TypeInfo>(typeInfo)};
}

SWC_END_NAMESPACE()
