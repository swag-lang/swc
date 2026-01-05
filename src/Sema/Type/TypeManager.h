#pragma once
#include "Core/Store.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE()

class TaskContext;
class CompilerInstance;

class TypeManager
{
public:
    void setup(TaskContext& ctx);

    TypeRef typeBool() const { return typeBool_; }
    TypeRef typeChar() const { return typeChar_; }
    TypeRef typeString() const { return typeString_; }
    TypeRef typeInt(uint32_t bits, TypeInfo::Sign sign) const;
    TypeRef typeFloat(uint32_t bits) const;
    TypeRef typeAny() const { return typeAny_; }
    TypeRef typeVoid() const { return typeVoid_; }
    TypeRef typeNull() const { return typeNull_; }
    TypeRef typeUndefined() const { return typeUndefined_; }
    TypeRef typeRune() const { return typeRune_; }
    TypeRef typeCString() const { return typeCString_; }
    TypeRef typeVariadic() const { return typeVariadic_; }
    TypeRef typeTypeInfo() const { return typeTypeInfo_; }

    TypeRef         addType(const TypeInfo& typeInfo);
    const TypeInfo& get(TypeRef typeRef) const;

    TypeRef         promote(TypeRef lhs, TypeRef rhs, bool force32BitInts) const;
    static uint32_t chooseConcreteScalarWidth(uint32_t minRequiredBits, bool& overflow);

    // clang-format off
    TypeRef enumTargetOs() const                { std::shared_lock lk(mutexRt_); return enumTargetOs_; }
    void    setEnumTargetOs(TypeRef typeRef)    { std::unique_lock lk(mutexRt_); enumTargetOs_ = typeRef; }
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
    TypeRef                   enumTargetOs_ = TypeRef::invalid();

    // Predefined types
    TypeRef typeBool_        = TypeRef::invalid();
    TypeRef typeChar_        = TypeRef::invalid();
    TypeRef typeString_      = TypeRef::invalid();
    TypeRef typeIntUnsigned_ = TypeRef::invalid();
    TypeRef typeIntSigned_   = TypeRef::invalid();
    TypeRef typeInt_         = TypeRef::invalid();
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
    TypeRef typeAny_         = TypeRef::invalid();
    TypeRef typeVoid_        = TypeRef::invalid();
    TypeRef typeNull_        = TypeRef::invalid();
    TypeRef typeUndefined_   = TypeRef::invalid();
    TypeRef typeRune_        = TypeRef::invalid();
    TypeRef typeCString_     = TypeRef::invalid();
    TypeRef typeVariadic_    = TypeRef::invalid();
    TypeRef typeTypeInfo_    = TypeRef::invalid();

    std::vector<std::vector<TypeRef>>      promoteTable_;
    std::unordered_map<uint32_t, uint32_t> promoteIndex_;

    TypeRef computePromotion(TypeRef lhsRef, TypeRef rhsRef) const;
    void    buildPromoteTable();
};

SWC_END_NAMESPACE()
