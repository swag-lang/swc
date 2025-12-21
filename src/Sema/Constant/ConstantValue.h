#pragma once
#include "Math/ApFloat.h"
#include "Math/ApsInt.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE()
class TaskContext;
class TypeInfo;

class ConstantValue;
using ConstantRef = StrongRef<ConstantValue>;

enum class ConstantKind
{
    Invalid,
    Bool,
    Char,
    Rune,
    String,
    Int,
    Float,
    TypeInfo,
    EnumValue,
};

class ConstantValue
{
    friend struct ConstantValueHash;
    friend class ConstantManager;

    ConstantKind kind_    = ConstantKind::Invalid;
    TypeRef      typeRef_ = TypeRef::invalid();

    union
    {
        // clang-format off
        struct { std::string_view val; } asString;
        struct { char32_t val; } asCharRune;
        struct { bool val; } asBool;
        struct { ApsInt val; } asInt;
        struct { ApFloat val; } asFloat;
        struct { TypeRef val; } asTypeInfo;
        struct { ConstantRef val; } asEnumValue;
        // clang-format on
    };

public:
    // ReSharper disable once CppPossiblyUninitializedMember
    ConstantValue() {}

    bool operator==(const ConstantValue& rhs) const noexcept;

    bool eq(const ConstantValue& rhs) const noexcept;
    bool lt(const ConstantValue& rhs) const noexcept;
    bool le(const ConstantValue& rhs) const noexcept;
    bool gt(const ConstantValue& rhs) const noexcept;

    ConstantKind kind() const { return kind_; }
    TypeRef      typeRef() const { return typeRef_; }
    bool         isValid() const { return kind_ != ConstantKind::Invalid; }
    bool         isBool() const { return kind_ == ConstantKind::Bool; }
    bool         isChar() const { return kind_ == ConstantKind::Char; }
    bool         isRune() const { return kind_ == ConstantKind::Rune; }
    bool         isString() const { return kind_ == ConstantKind::String; }
    bool         isInt() const { return kind_ == ConstantKind::Int; }
    bool         isFloat() const { return kind_ == ConstantKind::Float; }
    bool         isTypeInfo() const { return kind_ == ConstantKind::TypeInfo; }
    bool         isEnumValue() const { return kind_ == ConstantKind::EnumValue; }

    // clang-format off
    bool getBool() const { SWC_ASSERT(isBool()); return asBool.val; }
    char32_t getChar() const { SWC_ASSERT(isChar()); return asCharRune.val; }
    char32_t getRune() const { SWC_ASSERT(isRune()); return asCharRune.val; }
    std::string_view getString() const { SWC_ASSERT(isString()); return asString.val; }
    const ApsInt& getInt() const { SWC_ASSERT(isInt()); return asInt.val; }
    const ApFloat& getFloat() const { SWC_ASSERT(isFloat()); return asFloat.val; }
    TypeRef getTypeIndo() const { SWC_ASSERT(isTypeInfo()); return asTypeInfo.val; }
    ConstantRef getEnumValue() const { SWC_ASSERT(isEnumValue()); return asEnumValue.val; }
    // clang-format on

    const TypeInfo& type(const TaskContext& ctx) const;

    static ConstantValue makeBool(const TaskContext& ctx, bool value);
    static ConstantValue makeString(const TaskContext& ctx, std::string_view value);
    static ConstantValue makeChar(const TaskContext& ctx, char32_t value);
    static ConstantValue makeRune(const TaskContext& ctx, char32_t value);
    static ConstantValue makeTypeInfo(TaskContext& ctx, TypeRef value);
    static ConstantValue makeInt(const TaskContext& ctx, const ApsInt& value, uint32_t bitWidth, TypeInfo::Sign sign);
    static ConstantValue makeIntUnsized(const TaskContext& ctx, const ApsInt& value, TypeInfo::Sign sign);
    static ConstantValue makeFloat(const TaskContext& ctx, const ApFloat& value, uint32_t bitWidth);
    static ConstantValue makeFloatUnsized(const TaskContext& ctx, const ApFloat& value);
    static ConstantValue makeFromIntLike(const TaskContext& ctx, const ApsInt& v, const TypeInfo& ty);
    static ConstantValue makeEnumValue(const TaskContext& ctx, ConstantRef valueCst, TypeRef typeRef);

    uint32_t hash() const noexcept;
    ApsInt   getIntLike() const;
    bool     ge(const ConstantValue& rhs) const noexcept;
    Utf8     toString(const TaskContext& ctx) const;
};

struct ConstantValueHash
{
    size_t operator()(const ConstantValue& v) const noexcept { return v.hash(); }
};

SWC_END_NAMESPACE()
