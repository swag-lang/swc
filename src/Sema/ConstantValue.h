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
public:
    using TypeInt = ConstantInt<64, false>;

private:
    ConstantKind kind_    = ConstantKind::Invalid;
    TypeInfoRef  typeRef_ = TypeInfoRef::invalid();

    using TypeDataT = std::variant<bool, std::string_view, TypeInt>;
    TypeDataT value_;

public:
    bool operator==(const ConstantValue& other) const noexcept;

    ConstantKind kind() const { return kind_; }
    TypeInfoRef  typeRef() const { return typeRef_; }
    bool         isValid() const { return kind_ != ConstantKind::Invalid; }
    bool         isBool() const { return kind_ == ConstantKind::Bool; }
    bool         isString() const { return kind_ == ConstantKind::String; }
    bool         isInt() const { return kind_ == ConstantKind::Int; }

    // clang-format off
    bool getBool() const { SWC_ASSERT(isBool()); return std::get<bool>(value_); }
    std::string_view getString() const { SWC_ASSERT(isString()); return std::get<std::string_view>(value_); }
    TypeInt getInt() const { return std::get<TypeInt>(value_); }
    // clang-format on

    const TypeInfo&         type(const TaskContext& ctx) const;
    decltype(value_)&       value() { return value_; }
    const decltype(value_)& value() const { return value_; }

    static ConstantValue makeBool(const TaskContext& ctx, bool value);
    static ConstantValue makeString(const TaskContext& ctx, std::string_view value);
    static ConstantValue makeInt(const TaskContext& ctx, const TypeInt& value, uint8_t bits, bool isSigned);

    Utf8 toString() const;
};

struct ConstantValueHash
{
    size_t operator()(const ConstantValue& v) const noexcept;
};

SWC_END_NAMESPACE()
