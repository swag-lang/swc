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
    mutable std::unordered_map<TypeInfo, Utf8, TypeInfoHash> mapName_[static_cast<int>(TypeInfo::ToStringMode::Count)];
    mutable std::shared_mutex                                mutexName_[static_cast<int>(TypeInfo::ToStringMode::Count)];

    // Predefined types
    TypeInfoRef typeBool_   = TypeInfoRef::invalid();
    TypeInfoRef typeString_ = TypeInfoRef::invalid();

public:
    void        setup(TaskContext& ctx);
    TypeInfoRef registerType(const TypeInfo& typeInfo);

    TypeInfoRef     getBool() const { return typeBool_; }
    TypeInfoRef     getString() const { return typeString_; }
    const TypeInfo& get(TypeInfoRef typeInfoRef) const;

    std::string_view typeToString(TypeInfoRef typeInfoRef, TypeInfo::ToStringMode mode = TypeInfo::ToStringMode::Diagnostic) const;
    std::string_view typeToString(const TypeInfo& typeInfo, TypeInfo::ToStringMode mode = TypeInfo::ToStringMode::Diagnostic) const;
};

SWC_END_NAMESPACE()
