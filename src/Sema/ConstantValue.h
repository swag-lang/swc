#pragma once

SWC_BEGIN_NAMESPACE()
class TaskContext;
struct TypeInfo;

enum class ConstantKind
{
    Invalid,
    Bool,
};

struct ConstantValue
{
    ConstantKind kind    = ConstantKind::Invalid;
    TypeInfoRef  typeRef = TypeInfoRef::invalid();

    std::variant<bool> value;

    bool operator==(const ConstantValue& other) const noexcept;

    bool isValid() const { return kind != ConstantKind::Invalid; }
    bool isBool() const { return kind == ConstantKind::Bool; }

    const TypeInfo& type(const TaskContext& ctx) const;

    static ConstantValue makeBool(const TaskContext& ctx, bool value);
};

struct ConstantValueHash
{
    size_t operator()(const ConstantValue& v) const noexcept;
};

SWC_END_NAMESPACE()
