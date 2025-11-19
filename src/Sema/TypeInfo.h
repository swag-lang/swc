#pragma once

SWC_BEGIN_NAMESPACE()

enum class TypeInfoKind
{
    Invalid = 0,
    Bool,
};

struct TypeInfo
{
    TypeInfoKind kind;

    bool operator==(const TypeInfo& other) const noexcept;
};

struct TypeInfoHash
{
    size_t operator()(const TypeInfo& t) const noexcept
    {
        return std::hash<int>()(static_cast<int>(t.kind));
    }
};

SWC_END_NAMESPACE()
