#pragma once

SWC_BEGIN_NAMESPACE()
class TaskContext;
struct TypeInfo;

enum class ConstantKind
{
    Invalid,
    Bool,
};

class ConstantValue
{
    ConstantKind kind_    = ConstantKind::Invalid;
    TypeInfoRef  typeRef_ = TypeInfoRef::invalid();

    std::variant<bool> value_;

public:
    bool operator==(const ConstantValue& other) const noexcept;

    ConstantKind kind() const { return kind_; }
    TypeInfoRef  typeRef() const { return typeRef_; }
    bool         isValid() const { return kind_ != ConstantKind::Invalid; }
    bool         isBool() const { return kind_ == ConstantKind::Bool; }

    // clang-format off
    bool getBool() const{ SWC_ASSERT(isBool()); return std::get<bool>(value_); }
    // clang-format on

    const TypeInfo& type(const TaskContext& ctx) const;

    static ConstantValue makeBool(const TaskContext& ctx, bool value);
};

struct ConstantValueHash
{
    size_t operator()(const ConstantValue& v) const noexcept;
};

SWC_END_NAMESPACE()
