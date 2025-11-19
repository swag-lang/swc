#pragma once
#include "Core/Store.h"
#include "Sema/TypeInfo.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

class TypeManager
{
    Store<>                                             store_;
    std::unordered_map<TypeInfo, TypeInfoRef, TypeInfoHash> map_;

    // Predefined types
    TypeInfoRef typeBool_ = TypeInfoRef::invalid();

public:
    void    setup();
    TypeInfoRef registerType(const TypeInfo& typeInfo);

    TypeInfoRef typeBool() const { return typeBool_; }
};

SWC_END_NAMESPACE()
