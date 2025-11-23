#pragma once
#include "Sema/ConstantInt.h"

SWC_BEGIN_NAMESPACE()
class TaskContext;
class TypeInfo;

enum class ConstantKind
{
    Invalid,
    Bool,
    String,
    Int,
};

class ConstantValue
{
    friend class ConstantManager;

    ConstantKind kind_    = ConstantKind::Invalid;
    TypeInfoRef  typeRef_ = TypeInfoRef::invalid();

    union
    {
        // clang-format off
        struct { bool val; } bool_;
        struct { std::string_view val; } string_;
        struct { ConstantInt val; bool sig; } int_;
        // clang-format on
    };

public:
    ConstantValue() {}
    bool operator==(const ConstantValue& other) const noexcept;

    ConstantKind kind() const { return kind_; }
    TypeInfoRef  typeRef() const { return typeRef_; }
    bool         isValid() const { return kind_ != ConstantKind::Invalid; }
    bool         isBool() const { return kind_ == ConstantKind::Bool; }
    bool         isString() const { return kind_ == ConstantKind::String; }
    bool         isInt() const { return kind_ == ConstantKind::Int; }

    // clang-format off
    bool getBool() const { SWC_ASSERT(isBool()); return bool_.val; }
    std::string_view getString() const { SWC_ASSERT(isString()); return string_.val; }
    ConstantInt getInt() const { SWC_ASSERT(isInt()); return int_.val; }
    // clang-format on

    const TypeInfo& type(const TaskContext& ctx) const;

    static ConstantValue makeBool(const TaskContext& ctx, bool value);
    static ConstantValue makeString(const TaskContext& ctx, std::string_view value);
    static ConstantValue makeInt(const TaskContext& ctx, const ConstantInt& value, uint32_t bits, bool isSigned);

    Utf8 toString() const;
};

struct ConstantValueHash
{
    size_t operator()(const ConstantValue& v) const noexcept;
};

SWC_END_NAMESPACE()
