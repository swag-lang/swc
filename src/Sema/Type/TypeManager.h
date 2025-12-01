#pragma once
#include "Core/Store.h"
#include "Sema/Type/TypeInfo.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()
class TaskContext;
class CompilerInstance;

class TypeManager
{
    Store                                                    store_;
    
    std::unordered_map<TypeInfo, TypeRef, TypeInfoHash>      map_;
    mutable std::shared_mutex                                mutexAdd_;
    mutable std::unordered_map<TypeInfo, Utf8, TypeInfoHash> mapString_[static_cast<int>(TypeInfo::ToStringMode::Count)];
    mutable std::shared_mutex                                mutexString_[static_cast<int>(TypeInfo::ToStringMode::Count)];

    // Predefined types
    TypeRef typeBool_        = TypeRef::invalid();
    TypeRef typeString_      = TypeRef::invalid();
    TypeRef typeIntUnsigned_ = TypeRef::invalid();
    TypeRef typeIntSigned_   = TypeRef::invalid();
    TypeRef typeFloat_       = TypeRef::invalid();
    TypeRef typeU8_          = TypeRef::invalid();
    TypeRef typeU16_         = TypeRef::invalid();
    TypeRef typeU32_         = TypeRef::invalid();
    TypeRef typeU64_         = TypeRef::invalid();
    TypeRef typeS8_          = TypeRef::invalid();
    TypeRef typeS16_         = TypeRef::invalid();
    TypeRef typeS32_         = TypeRef::invalid();
    TypeRef typeS64_         = TypeRef::invalid();
    TypeRef typeF32_         = TypeRef::invalid();
    TypeRef typeF64_         = TypeRef::invalid();

    std::vector<std::vector<TypeRef>> promoteTable_;
    TypeRef                           computePromotion(TypeRef lhsRef, TypeRef rhsRef) const;
    void                              buildPromoteTable();

public:
    void setup(TaskContext& ctx);

    TypeRef         addType(const TypeInfo& typeInfo);
    TypeRef         getTypeBool() const { return typeBool_; }
    TypeRef         getTypeString() const { return typeString_; }
    TypeRef         getTypeInt(uint32_t bits, bool isUnsigned) const;
    TypeRef         getTypeFloat(uint32_t bits) const;
    const TypeInfo& get(TypeRef typeInfoRef) const;

    TypeRef promote(TypeRef lhs, TypeRef rhs) const;

    std::string_view typeToString(TypeRef typeInfoRef, TypeInfo::ToStringMode mode = TypeInfo::ToStringMode::Diagnostic) const;
    std::string_view typeToString(const TypeInfo& typeInfo, TypeInfo::ToStringMode mode = TypeInfo::ToStringMode::Diagnostic) const;
};

SWC_END_NAMESPACE()
