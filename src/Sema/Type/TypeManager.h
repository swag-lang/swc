#pragma once
#include "Core/Store.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class CompilerInstance;

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

    TypeRef typeInt(uint32_t bits, TypeInfo::Sign sign) const;
    TypeRef typeInt() const { return typeInt_; }
    TypeRef typeIntSigned() const { return typeIntSigned_; }
    TypeRef typeIntUnsigned() const { return typeIntUnsigned_; }
    TypeRef typeFloat(uint32_t bits) const;
    TypeRef typeU8() const { return typeU8_; }
    TypeRef typeU64() const { return typeU64_; }

    TypeRef         addType(const TypeInfo& typeInfo);
    const TypeInfo& getNoLock(TypeRef typeRef) const;
    const TypeInfo& get(TypeRef typeRef) const;

    TypeRef         promote(TypeRef lhs, TypeRef rhs, bool force32BitInts) const;
    static uint32_t chooseConcreteScalarWidth(uint32_t minRequiredBits, bool& overflow);

    // clang-format off
    TypeRef enumTargetOs() const                { std::shared_lock lk(mutexRt_); return enumTargetOs_; }
    void    setEnumTargetOs(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); enumTargetOs_ = typeRef; }

    TypeRef structTypeInfo() const                { std::shared_lock lk(mutexRt_); return structTypeInfo_; }
    void    setStructTypeInfo(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfo_ = typeRef; }
    TypeRef structTypeInfoNative() const                { std::shared_lock lk(mutexRt_); return structTypeInfoNative_; }
    void    setStructTypeInfoNative(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoNative_ = typeRef; }
    TypeRef structTypeInfoPointer() const                { std::shared_lock lk(mutexRt_); return structTypeInfoPointer_; }
    void    setStructTypeInfoPointer(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoPointer_ = typeRef; }
    TypeRef structTypeInfoStruct() const                { std::shared_lock lk(mutexRt_); return structTypeInfoStruct_; }
    void    setStructTypeInfoStruct(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoStruct_ = typeRef; }
    TypeRef structTypeInfoFunc() const                { std::shared_lock lk(mutexRt_); return structTypeInfoFunc_; }
    void    setStructTypeInfoFunc(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoFunc_ = typeRef; }
    TypeRef structTypeInfoEnum() const                { std::shared_lock lk(mutexRt_); return structTypeInfoEnum_; }
    void    setStructTypeInfoEnum(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoEnum_ = typeRef; }
    TypeRef structTypeInfoArray() const                { std::shared_lock lk(mutexRt_); return structTypeInfoArray_; }
    void    setStructTypeInfoArray(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoArray_ = typeRef; }
    TypeRef structTypeInfoSlice() const                { std::shared_lock lk(mutexRt_); return structTypeInfoSlice_; }
    void    setStructTypeInfoSlice(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoSlice_ = typeRef; }
    TypeRef structTypeInfoAlias() const                { std::shared_lock lk(mutexRt_); return structTypeInfoAlias_; }
    void    setStructTypeInfoAlias(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoAlias_ = typeRef; }
    TypeRef structTypeInfoVariadic() const                { std::shared_lock lk(mutexRt_); return structTypeInfoVariadic_; }
    void    setStructTypeInfoVariadic(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoVariadic_ = typeRef; }
    TypeRef structTypeInfoGeneric() const                { std::shared_lock lk(mutexRt_); return structTypeInfoGeneric_; }
    void    setStructTypeInfoGeneric(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoGeneric_ = typeRef; }
    TypeRef structTypeInfoNamespace() const                { std::shared_lock lk(mutexRt_); return structTypeInfoNamespace_; }
    void    setStructTypeInfoNamespace(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoNamespace_ = typeRef; }
    TypeRef structTypeInfoCodeBlock() const                { std::shared_lock lk(mutexRt_); return structTypeInfoCodeBlock_; }
    void    setStructTypeInfoCodeBlock(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeInfoCodeBlock_ = typeRef; }
    TypeRef enumTypeInfoKind() const                { std::shared_lock lk(mutexRt_); return enumTypeInfoKind_; }
    void    setEnumTypeInfoKind(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); enumTypeInfoKind_ = typeRef; }
    TypeRef enumTypeInfoNativeKind() const                { std::shared_lock lk(mutexRt_); return enumTypeInfoNativeKind_; }
    void    setEnumTypeInfoNativeKind(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); enumTypeInfoNativeKind_ = typeRef; }
    TypeRef enumTypeInfoFlags() const                { std::shared_lock lk(mutexRt_); return enumTypeInfoFlags_; }
    void    setEnumTypeInfoFlags(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); enumTypeInfoFlags_ = typeRef; }
    TypeRef structTypeValue() const                { std::shared_lock lk(mutexRt_); return structTypeValue_; }
    void    setStructTypeValue(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structTypeValue_ = typeRef; }
    TypeRef enumTypeValueFlags() const                { std::shared_lock lk(mutexRt_); return enumTypeValueFlags_; }
    void    setEnumTypeValueFlags(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); enumTypeValueFlags_ = typeRef; }
    TypeRef structAttribute() const                { std::shared_lock lk(mutexRt_); return structAttribute_; }
    void    setStructAttribute(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structAttribute_ = typeRef; }
    TypeRef structAttributeParam() const                { std::shared_lock lk(mutexRt_); return structAttributeParam_; }
    void    setStructAttributeParam(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structAttributeParam_ = typeRef; }
    TypeRef structInterface() const                { std::shared_lock lk(mutexRt_); return structInterface_; }
    void    setStructInterface(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structInterface_ = typeRef; }
    TypeRef structSourceCodeLocation() const                { std::shared_lock lk(mutexRt_); return structSourceCodeLocation_; }
    void    setStructSourceCodeLocation(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structSourceCodeLocation_ = typeRef; }
    TypeRef structContext() const                { std::shared_lock lk(mutexRt_); return structContext_; }
    void    setStructContext(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structContext_ = typeRef; }
    TypeRef structModule() const                { std::shared_lock lk(mutexRt_); return structModule_; }
    void    setStructModule(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structModule_ = typeRef; }
    TypeRef structProcessInfos() const                { std::shared_lock lk(mutexRt_); return structProcessInfos_; }
    void    setStructProcessInfos(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structProcessInfos_ = typeRef; }
    TypeRef structGvtd() const                { std::shared_lock lk(mutexRt_); return structGvtd_; }
    void    setStructGvtd(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); structGvtd_ = typeRef; }
    // clang-format on

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
    mutable std::shared_mutex mutexRt_;
    TypeRef                   enumTargetOs_             = TypeRef::invalid();
    TypeRef                   enumTypeInfoKind_         = TypeRef::invalid();
    TypeRef                   enumTypeInfoNativeKind_   = TypeRef::invalid();
    TypeRef                   enumTypeInfoFlags_        = TypeRef::invalid();
    TypeRef                   enumTypeValueFlags_       = TypeRef::invalid();
    TypeRef                   structTypeInfo_           = TypeRef::invalid();
    TypeRef                   structTypeInfoNative_     = TypeRef::invalid();
    TypeRef                   structTypeInfoPointer_    = TypeRef::invalid();
    TypeRef                   structTypeInfoStruct_     = TypeRef::invalid();
    TypeRef                   structTypeInfoFunc_       = TypeRef::invalid();
    TypeRef                   structTypeInfoEnum_       = TypeRef::invalid();
    TypeRef                   structTypeInfoArray_      = TypeRef::invalid();
    TypeRef                   structTypeInfoSlice_      = TypeRef::invalid();
    TypeRef                   structTypeInfoAlias_      = TypeRef::invalid();
    TypeRef                   structTypeInfoVariadic_   = TypeRef::invalid();
    TypeRef                   structTypeInfoGeneric_    = TypeRef::invalid();
    TypeRef                   structTypeInfoNamespace_  = TypeRef::invalid();
    TypeRef                   structTypeInfoCodeBlock_  = TypeRef::invalid();
    TypeRef                   structTypeValue_          = TypeRef::invalid();
    TypeRef                   structAttribute_          = TypeRef::invalid();
    TypeRef                   structAttributeParam_     = TypeRef::invalid();
    TypeRef                   structInterface_          = TypeRef::invalid();
    TypeRef                   structSourceCodeLocation_ = TypeRef::invalid();
    TypeRef                   structContext_            = TypeRef::invalid();
    TypeRef                   structModule_             = TypeRef::invalid();
    TypeRef                   structProcessInfos_       = TypeRef::invalid();
    TypeRef                   structGvtd_               = TypeRef::invalid();

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
    TypeRef typeVariadic_          = TypeRef::invalid();
    TypeRef typeTypeInfo_          = TypeRef::invalid();

    std::vector<std::vector<TypeRef>>      promoteTable_;
    std::unordered_map<uint32_t, uint32_t> promoteIndex_;

    TypeRef computePromotion(TypeRef lhsRef, TypeRef rhsRef) const;
    void    buildPromoteTable();
};

SWC_END_NAMESPACE();
