#pragma once
#include "Core/Store.h"
#include "Sema/TypeInfo.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()
class TaskContext;
class CompilerInstance;

class TypeManager
{
    Store<>                                                 store_;
    std::unordered_map<TypeInfo, TypeInfoRef, TypeInfoHash> map_;
    mutable std::shared_mutex                               mutex_;

    // Predefined types
    TypeInfoRef typeBool_ = TypeInfoRef::invalid();

public:
    void        setup(TaskContext& ctx);
    TypeInfoRef registerType(const TypeInfo& typeInfo);

    TypeInfoRef     getBool() const { return typeBool_; }
    const TypeInfo& get(TypeInfoRef typeInfoRef) const;

    Utf8 toString(TypeInfoRef typeInfoRef) const;
};

SWC_END_NAMESPACE()
