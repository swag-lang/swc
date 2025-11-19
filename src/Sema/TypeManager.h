#pragma once
#include "Core/Store.h"
#include "Sema/TypeInfo.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

class TypeManager
{
    Store<>                                             store_;
    std::unordered_map<TypeInfo, TypeRef, TypeInfoHash> map_;

    // Predefined types
    TypeRef typeBool_ = TypeRef::invalid();

public:
    void    setup();
    TypeRef registerType(const TypeInfo& typeInfo);

    TypeRef typeBool() const { return typeBool_; }
};

SWC_END_NAMESPACE()
