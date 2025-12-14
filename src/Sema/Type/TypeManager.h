#pragma once
#include "Core/Store.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE()

class TaskContext;
class CompilerInstance;

struct ConcreteWidthPolicy
{
    uint32_t minBits    = 32;
    uint32_t maxBits    = 64;
    bool     clampToMax = false;
};

class TypeManager
{
    struct Shard
    {
        Store                                                    store;
        std::unordered_map<TypeInfo, TypeRef, TypeInfoHash>      map;
        mutable std::shared_mutex                                mutexAdd;
        mutable std::unordered_map<TypeInfo, Utf8, TypeInfoHash> mapName;
        mutable std::shared_mutex                                mutexName;
    };

    static constexpr uint32_t SHARD_BITS  = 3;
    static constexpr uint32_t SHARD_COUNT = 1u << SHARD_BITS;
    static constexpr uint32_t LOCAL_BITS  = 32 - SHARD_BITS;
    static constexpr uint32_t LOCAL_MASK  = (1u << LOCAL_BITS) - 1;
    Shard                     shards_[SHARD_COUNT];

    // Predefined types
    TypeRef typeBool_        = TypeRef::invalid();
    TypeRef typeChar_        = TypeRef::invalid();
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
    TypeRef typeAny_         = TypeRef::invalid();
    TypeRef typeVoid_        = TypeRef::invalid();
    TypeRef typeRune_        = TypeRef::invalid();
    TypeRef typeCString_     = TypeRef::invalid();

    std::vector<std::vector<TypeRef>>      promoteTable_;
    std::unordered_map<uint32_t, uint32_t> promoteIndex_;

    TypeRef computePromotion(TypeRef lhsRef, TypeRef rhsRef) const;
    void    buildPromoteTable();

public:
    void setup(TaskContext& ctx);

    TypeRef getTypeBool() const { return typeBool_; }
    TypeRef getTypeChar() const { return typeChar_; }
    TypeRef getTypeString() const { return typeString_; }
    TypeRef getTypeInt(uint32_t bits, bool isUnsigned) const;
    TypeRef getTypeFloat(uint32_t bits) const;
    TypeRef getTypeAny() const { return typeAny_; }
    TypeRef getTypeVoid() const { return typeVoid_; }
    TypeRef getTypeRune() const { return typeRune_; }
    TypeRef getTypeCString() const { return typeCString_; }

    TypeRef         addType(const TypeInfo& typeInfo);
    const TypeInfo& get(TypeRef typeRef) const;

    TypeRef         promote(TypeRef lhs, TypeRef rhs, bool force32BitInts) const;
    static uint32_t chooseConcreteScalarWidth(uint32_t minRequiredBits, ConcreteWidthPolicy policy, bool& overflow);

    std::string_view typeToName(TypeRef typeInfoRef) const;
};

SWC_END_NAMESPACE()
