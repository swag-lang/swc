#pragma once
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Core/Store.h"

SWC_BEGIN_NAMESPACE();

class Sema;
struct SemaNodeView;
class TaskContext;
class CompilerInstance;

enum class RuntimeTypeKind : uint32_t
{
    TargetOs,
    TypeInfoKind,
    TypeInfoNativeKind,
    TypeInfoFlags,
    TypeValueFlags,
    TypeInfo,
    TypeInfoNative,
    TypeInfoPointer,
    TypeInfoStruct,
    TypeInfoFunc,
    TypeInfoEnum,
    TypeInfoArray,
    TypeInfoSlice,
    TypeInfoAlias,
    TypeInfoVariadic,
    TypeInfoGeneric,
    TypeInfoNamespace,
    TypeInfoCodeBlock,
    TypeValue,
    Attribute,
    AttributeParam,
    Interface,
    SourceCodeLocation,
    ErrorValue,
    ScratchAllocator,
    Context,
    ContextFlags,
    Module,
    ProcessInfos,
    Gvtd,
    Count
};

class TypeManager
{
public:
    void setup(TaskContext& ctx);

    TypeRef typeBool() const { return typeBool_; }
    TypeRef typeChar() const { return typeChar_; }
    TypeRef typeString() const { return typeString_; }
    TypeRef typeAny() const { return typeAny_; }
    TypeRef typeVoid() const { return typeVoid_; }
    TypeRef typeNull() const { return typeNull_; }
    TypeRef typeUndefined() const { return typeUndefined_; }
    TypeRef typeRune() const { return typeRune_; }
    TypeRef typeCString() const { return typeCString_; }
    TypeRef typeVariadic() const { return typeVariadic_; }
    TypeRef typeTypeInfo() const { return typeTypeInfo_; }

    TypeRef typeBlockPtrVoid() const { return typeBlockPtrVoid_; }
    TypeRef typeConstBlockPtrVoid() const { return typeConstBlockPtrVoid_; }
    TypeRef typeBlockPtrU8() const { return typeBlockPtrU8_; }
    TypeRef typeConstBlockPtrU8() const { return typeConstBlockPtrU8_; }
    TypeRef typeValuePtrVoid() const { return typeValuePtrVoid_; }
    TypeRef typeConstValuePtrVoid() const { return typeConstValuePtrVoid_; }
    TypeRef typeValuePtrU8() const { return typeValuePtrU8_; }
    TypeRef typeConstValuePtrU8() const { return typeConstValuePtrU8_; }

    TypeRef typeInt(uint32_t bits, TypeInfo::Sign sign) const;
    TypeRef typeInt() const { return typeInt_; }
    TypeRef typeIntSigned() const { return typeIntSigned_; }
    TypeRef typeIntUnsigned() const { return typeIntUnsigned_; }
    TypeRef typeFloat(uint32_t bits) const;
    TypeRef typeS8() const { return typeS8_; }
    TypeRef typeU8() const { return typeU8_; }
    TypeRef typeS16() const { return typeS16_; }
    TypeRef typeU16() const { return typeU16_; }
    TypeRef typeS32() const { return typeS32_; }
    TypeRef typeU32() const { return typeU32_; }
    TypeRef typeS64() const { return typeS64_; }
    TypeRef typeU64() const { return typeU64_; }

    TypeRef         addType(const TypeInfo& typeInfo);
    const TypeInfo& getNoLock(TypeRef typeRef) const;
    const TypeInfo& get(TypeRef typeRef) const;

    TypeRef         promote(TypeRef lhs, TypeRef rhs, bool force32BitInts) const;
    static uint32_t chooseConcreteScalarWidth(uint32_t minRequiredBits, bool& overflow);

    bool    isTypeInfoRuntimeStruct(IdentifierRef idRef) const;
    void    registerRuntimeType(IdentifierRef idRef, TypeRef typeRef);
    TypeRef runtimeType(RuntimeTypeKind kind) const;

    TypeRef structTypeInfo() const { return runtimeType(RuntimeTypeKind::TypeInfo); }
    TypeRef structTypeInfoNative() const { return runtimeType(RuntimeTypeKind::TypeInfoNative); }
    TypeRef structTypeInfoPointer() const { return runtimeType(RuntimeTypeKind::TypeInfoPointer); }
    TypeRef structTypeInfoStruct() const { return runtimeType(RuntimeTypeKind::TypeInfoStruct); }
    TypeRef structTypeInfoFunc() const { return runtimeType(RuntimeTypeKind::TypeInfoFunc); }
    TypeRef structTypeInfoEnum() const { return runtimeType(RuntimeTypeKind::TypeInfoEnum); }
    TypeRef structTypeInfoArray() const { return runtimeType(RuntimeTypeKind::TypeInfoArray); }
    TypeRef structTypeInfoSlice() const { return runtimeType(RuntimeTypeKind::TypeInfoSlice); }
    TypeRef structTypeInfoAlias() const { return runtimeType(RuntimeTypeKind::TypeInfoAlias); }
    TypeRef structTypeInfoVariadic() const { return runtimeType(RuntimeTypeKind::TypeInfoVariadic); }
    TypeRef structTypeInfoGeneric() const { return runtimeType(RuntimeTypeKind::TypeInfoGeneric); }
    TypeRef structTypeInfoNamespace() const { return runtimeType(RuntimeTypeKind::TypeInfoNamespace); }
    TypeRef structTypeInfoCodeBlock() const { return runtimeType(RuntimeTypeKind::TypeInfoCodeBlock); }
    TypeRef structTypeValue() const { return runtimeType(RuntimeTypeKind::TypeValue); }
    TypeRef structAttribute() const { return runtimeType(RuntimeTypeKind::Attribute); }
    TypeRef structAttributeParam() const { return runtimeType(RuntimeTypeKind::AttributeParam); }
    TypeRef structInterface() const { return runtimeType(RuntimeTypeKind::Interface); }
    TypeRef structSourceCodeLocation() const { return runtimeType(RuntimeTypeKind::SourceCodeLocation); }
    TypeRef structErrorValue() const { return runtimeType(RuntimeTypeKind::ErrorValue); }
    TypeRef structScratchAllocator() const { return runtimeType(RuntimeTypeKind::ScratchAllocator); }
    TypeRef structContext() const { return runtimeType(RuntimeTypeKind::Context); }
    TypeRef structModule() const { return runtimeType(RuntimeTypeKind::Module); }
    TypeRef structProcessInfos() const { return runtimeType(RuntimeTypeKind::ProcessInfos); }
    TypeRef structGvtd() const { return runtimeType(RuntimeTypeKind::Gvtd); }

    TypeRef enumContextFlags() const { return runtimeType(RuntimeTypeKind::ContextFlags); }
    TypeRef enumTargetOs() const { return runtimeType(RuntimeTypeKind::TargetOs); }
    TypeRef enumTypeInfoKind() const { return runtimeType(RuntimeTypeKind::TypeInfoKind); }
    TypeRef enumTypeInfoNativeKind() const { return runtimeType(RuntimeTypeKind::TypeInfoNativeKind); }
    TypeRef enumTypeInfoFlags() const { return runtimeType(RuntimeTypeKind::TypeInfoFlags); }
    TypeRef enumTypeValueFlags() const { return runtimeType(RuntimeTypeKind::TypeValueFlags); }

private:
    struct Shard
    {
        Store                                               store;
        std::unordered_map<TypeInfo, TypeRef, TypeInfoHash> map;
        mutable std::shared_mutex                           mutex;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;
    Shard                     shards_[SHARD_COUNT];

    // Runtime types
    mutable std::shared_mutex                                          mutexRt_;
    std::unordered_map<IdentifierRef, RuntimeTypeKind>                 mapRtKind_;
    std::array<TypeRef, static_cast<uint32_t>(RuntimeTypeKind::Count)> runtimeTypes_;

    // Predefined types
    TypeRef typeBool_              = TypeRef::invalid();
    TypeRef typeChar_              = TypeRef::invalid();
    TypeRef typeString_            = TypeRef::invalid();
    TypeRef typeIntUnsigned_       = TypeRef::invalid();
    TypeRef typeIntSigned_         = TypeRef::invalid();
    TypeRef typeInt_               = TypeRef::invalid();
    TypeRef typeFloat_             = TypeRef::invalid();
    TypeRef typeU8_                = TypeRef::invalid();
    TypeRef typeU16_               = TypeRef::invalid();
    TypeRef typeU32_               = TypeRef::invalid();
    TypeRef typeU64_               = TypeRef::invalid();
    TypeRef typeS8_                = TypeRef::invalid();
    TypeRef typeS16_               = TypeRef::invalid();
    TypeRef typeS32_               = TypeRef::invalid();
    TypeRef typeS64_               = TypeRef::invalid();
    TypeRef typeF32_               = TypeRef::invalid();
    TypeRef typeF64_               = TypeRef::invalid();
    TypeRef typeAny_               = TypeRef::invalid();
    TypeRef typeVoid_              = TypeRef::invalid();
    TypeRef typeNull_              = TypeRef::invalid();
    TypeRef typeUndefined_         = TypeRef::invalid();
    TypeRef typeRune_              = TypeRef::invalid();
    TypeRef typeCString_           = TypeRef::invalid();
    TypeRef typeBlockPtrVoid_      = TypeRef::invalid();
    TypeRef typeConstBlockPtrVoid_ = TypeRef::invalid();
    TypeRef typeBlockPtrU8_        = TypeRef::invalid();
    TypeRef typeConstBlockPtrU8_   = TypeRef::invalid();
    TypeRef typeValuePtrVoid_      = TypeRef::invalid();
    TypeRef typeConstValuePtrVoid_ = TypeRef::invalid();
    TypeRef typeValuePtrU8_        = TypeRef::invalid();
    TypeRef typeConstValuePtrU8_   = TypeRef::invalid();
    TypeRef typeVariadic_          = TypeRef::invalid();
    TypeRef typeTypeInfo_          = TypeRef::invalid();

    std::vector<std::vector<TypeRef>>      promoteTable_;
    std::unordered_map<uint32_t, uint32_t> promoteIndex_;

    TypeRef computePromotion(TypeRef lhsRef, TypeRef rhsRef) const;
    void    buildPromoteTable();
};

SWC_END_NAMESPACE();
