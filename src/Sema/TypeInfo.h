#pragma once

SWC_BEGIN_NAMESPACE()

enum class TypeInfoKind
{
    Invalid = 0,
    Bool,
    Int,
    String,
};

class TypeInfo
{
    friend struct TypeInfoHash;
    friend class TypeManager;

public:
    enum class ToStringMode
    {
        Diagnostic,
        Count,
    };

private:
    TypeInfo() = delete;
    explicit TypeInfo(TypeInfoKind kind);
    Utf8 toString(ToStringMode mode = ToStringMode::Diagnostic) const;

    TypeInfoKind kind_ = TypeInfoKind::Invalid;

    union
    {
        // clang-format off
        struct { uint8_t bits; bool isSigned; } int_;
        struct { std::string_view string; } string_;
        // clang-format on
    };

public:
    bool operator==(const TypeInfo& other) const noexcept;

    TypeInfoKind kind() const noexcept { return kind_; }
    bool         isBool() const noexcept { return kind_ == TypeInfoKind::Bool; }
    bool         isString() const noexcept { return kind_ == TypeInfoKind::String; }

    static TypeInfo makeBool();
    static TypeInfo makeString();
};

struct TypeInfoHash
{
    size_t operator()(const TypeInfo& t) const noexcept;
};

SWC_END_NAMESPACE()
