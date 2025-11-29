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
    TypeInfoRef typeBool_        = TypeInfoRef::invalid();
    TypeInfoRef typeString_      = TypeInfoRef::invalid();
    TypeInfoRef typeIntUnsigned_ = TypeInfoRef::invalid();
    TypeInfoRef typeIntSigned_   = TypeInfoRef::invalid();
    TypeInfoRef typeFloat_       = TypeInfoRef::invalid();
    TypeInfoRef typeU8_          = TypeInfoRef::invalid();
    TypeInfoRef typeU16_         = TypeInfoRef::invalid();
    TypeInfoRef typeU32_         = TypeInfoRef::invalid();
    TypeInfoRef typeU64_         = TypeInfoRef::invalid();
    TypeInfoRef typeS8_          = TypeInfoRef::invalid();
    TypeInfoRef typeS16_         = TypeInfoRef::invalid();
    TypeInfoRef typeS32_         = TypeInfoRef::invalid();
    TypeInfoRef typeS64_         = TypeInfoRef::invalid();
    TypeInfoRef typeF32_         = TypeInfoRef::invalid();
    TypeInfoRef typeF64_         = TypeInfoRef::invalid();

    std::vector<std::vector<TypeInfoRef>> promoteTable_;
    TypeInfoRef                           computePromotion(TypeInfoRef lhsRef, TypeInfoRef rhsRef) const;
    void                                  buildPromoteTable();

public:
    void setup(TaskContext& ctx);

    TypeInfoRef     addType(const TypeInfo& typeInfo);
    TypeInfoRef     getTypeBool() const { return typeBool_; }
    TypeInfoRef     getTypeString() const { return typeString_; }
    TypeInfoRef     getTypeInt(uint32_t bits, bool isUnsigned) const;
    TypeInfoRef     getTypeFloat(uint32_t bits) const;
    const TypeInfo& get(TypeInfoRef typeInfoRef) const;

    TypeInfoRef promote(TypeInfoRef lhs, TypeInfoRef rhs) const;

    std::string_view typeToString(TypeInfoRef typeInfoRef, TypeInfo::ToStringMode mode = TypeInfo::ToStringMode::Diagnostic) const;
    std::string_view typeToString(const TypeInfo& typeInfo, TypeInfo::ToStringMode mode = TypeInfo::ToStringMode::Diagnostic) const;
};

SWC_END_NAMESPACE()
