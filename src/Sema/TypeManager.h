#pragma once
#include "Core/Store.h"
#include "Sema/TypeInfo.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()
class TaskContext;
class CompilerInstance;

class TypeManager
{
    Store<>                                                  store_;
    std::unordered_map<TypeInfo, TypeInfoRef, TypeInfoHash>  map_;
    mutable std::shared_mutex                                mutexAdd_;
    mutable std::unordered_map<TypeInfo, Utf8, TypeInfoHash> mapString_[static_cast<int>(TypeInfo::ToStringMode::Count)];
    mutable std::shared_mutex                                mutexString_[static_cast<int>(TypeInfo::ToStringMode::Count)];

    // Predefined types
    TypeInfoRef typeBool_   = TypeInfoRef::invalid();
    TypeInfoRef typeString_ = TypeInfoRef::invalid();

public:
    void setup(TaskContext& ctx);

    TypeInfoRef     addType(const TypeInfo& typeInfo);
    TypeInfoRef     getTypeBool() const { return typeBool_; }
    TypeInfoRef     getTypeString() const { return typeString_; }
    const TypeInfo& getType(TypeInfoRef typeInfoRef) const;

    std::string_view typeToString(TypeInfoRef typeInfoRef, TypeInfo::ToStringMode mode = TypeInfo::ToStringMode::Diagnostic) const;
    std::string_view typeToString(const TypeInfo& typeInfo, TypeInfo::ToStringMode mode = TypeInfo::ToStringMode::Diagnostic) const;
};

SWC_END_NAMESPACE()
