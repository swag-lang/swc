#pragma once

SWC_BEGIN_NAMESPACE()

enum class TypeInfoKind
{
    Invalid = 0,
    Bool,
    Int,
};

struct TypeInfo
{
    TypeInfoKind kind;

    union
    {
        // clang-format off
        struct { uint8_t bits; bool isSigned; } int_;
        // clang-format on
    };

    bool operator==(const TypeInfo& other) const noexcept;
};

struct TypeInfoHash
{
    size_t operator()(const TypeInfo& t) const noexcept;
};

SWC_END_NAMESPACE()
