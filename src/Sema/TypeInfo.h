#pragma once

SWC_BEGIN_NAMESPACE()

enum class TypeInfoKind
{
    Invalid = 0,
    Bool,
    Int,
    String,
};

struct TypeInfo
{
    enum class ToStringMode
    {
        Diagnostic,
        Count,
    };

    TypeInfoKind kind;

    union
    {
        // clang-format off
        struct { uint8_t bits; bool isSigned; } int_;
        struct { std::string_view string; } string_;
        // clang-format on
    };

    bool operator==(const TypeInfo& other) const noexcept;

    bool isBool() const noexcept { return kind == TypeInfoKind::Bool; }
    bool isString() const noexcept { return kind == TypeInfoKind::String; }

    static TypeInfo makeBool();
    static TypeInfo makeString();

    Utf8 toString(ToStringMode mode = ToStringMode::Diagnostic) const;
};

struct TypeInfoHash
{
    size_t operator()(const TypeInfo& t) const noexcept;
};

SWC_END_NAMESPACE()
