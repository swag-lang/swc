#pragma once
#include "Math/ApFloat.h"
#include "Math/ApsInt.h"

SWC_BEGIN_NAMESPACE()
class TaskContext;
class TypeInfo;

enum class ConstantKind
{
    Invalid,
    Bool,
    String,
    Int,
    Float,
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
        struct { bool val; } asBool;
        struct { ApsInt val; } asInt;
        struct { ApFloat val; } asFloat;
        // clang-format on
    };

public:
    // ReSharper disable once CppPossiblyUninitializedMember
    ConstantValue() {}

    bool operator==(const ConstantValue& other) const noexcept;

    bool eq(const ConstantValue& other) const noexcept;
    bool lt(const ConstantValue& other) const noexcept;

    ConstantKind kind() const { return kind_; }
    TypeRef      typeRef() const { return typeRef_; }
    bool         isValid() const { return kind_ != ConstantKind::Invalid; }
    bool         isBool() const { return kind_ == ConstantKind::Bool; }
    bool         isString() const { return kind_ == ConstantKind::String; }
    bool         isInt() const { return kind_ == ConstantKind::Int; }
    bool         isFloat() const { return kind_ == ConstantKind::Float; }

    // clang-format off
    bool getBool() const { SWC_ASSERT(isBool()); return asBool.val; }
    std::string_view getString() const { SWC_ASSERT(isString()); return asString.val; }
    const ApsInt& getInt() const { SWC_ASSERT(isInt()); return asInt.val; }
    const ApFloat& getFloat() const { SWC_ASSERT(isFloat()); return asFloat.val; }
    // clang-format on

    const TypeInfo& type(const TaskContext& ctx) const;

    static ConstantValue makeBool(const TaskContext& ctx, bool value);
    static ConstantValue makeString(const TaskContext& ctx, std::string_view value);
    static ConstantValue makeInt(const TaskContext& ctx, const ApsInt& value, uint32_t bitWidth = 0);
    static ConstantValue makeFloat(const TaskContext& ctx, const ApFloat& value, uint32_t bitWidth = 0);

    Utf8 toString() const;
};

struct ConstantValueHash
{
    size_t operator()(const ConstantValue& v) const noexcept;
};

SWC_END_NAMESPACE()
