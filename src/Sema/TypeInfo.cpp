#include "pch.h"
#include "Sema/TypeInfo.h"
#include "Core/hash.h"
#include "Lexer/Token.h"
#include "Parser/SyntaxColor.h"

SWC_BEGIN_NAMESPACE()

// ReSharper disable once CppPossiblyUninitializedMember
TypeInfo::TypeInfo(TypeInfoKind kind) :
    kind_(kind)
{
}

bool TypeInfo::operator==(const TypeInfo& other) const noexcept
{
    if (kind_ != other.kind_)
        return false;
    switch (kind_)
    {
        case TypeInfoKind::Bool:
        case TypeInfoKind::String:
            return true;
        case TypeInfoKind::Int:
            return int_.bits == other.int_.bits && int_.isSigned == other.int_.isSigned;
        case TypeInfoKind::Float:
            return float_.bits == other.float_.bits;

        default:
            SWC_UNREACHABLE();
    }
}

size_t TypeInfoHash::operator()(const TypeInfo& t) const noexcept
{
    auto h = std::hash<int>()(static_cast<int>(t.kind_));

    switch (t.kind_)
    {
        case TypeInfoKind::Bool:
        case TypeInfoKind::String:
            return h;

        case TypeInfoKind::Int:
            h = hash_combine(h, t.int_.bits);
            h = hash_combine(h, t.int_.isSigned);
            return h;
        case TypeInfoKind::Float:
            h = hash_combine(h, t.float_.bits);
            return h;

        default:
            SWC_UNREACHABLE();
    }
}

TypeInfo TypeInfo::makeBool()
{
    return TypeInfo{TypeInfoKind::Bool};
}

TypeInfo TypeInfo::makeString()
{
    return TypeInfo{TypeInfoKind::String};
}

TypeInfo TypeInfo::makeInt(uint32_t bits, bool isSigned)
{
    TypeInfo ti{TypeInfoKind::Int};
    ti.int_ = {.bits = bits, .isSigned = isSigned};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeFloat(uint32_t bits)
{
    TypeInfo ti{TypeInfoKind::Float};
    ti.float_ = {.bits = bits};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

Utf8 TypeInfo::toString(const TypeManager& typeMgr, ToStringMode mode) const
{
    switch (kind_)
    {
        case TypeInfoKind::Bool:
            return "bool";
        case TypeInfoKind::String:
            return "string";

        case TypeInfoKind::Int:
        {
            Utf8 out;
            out += int_.isSigned ? "s" : "u";
            out += std::to_string(int_.bits);
            return out;
        }
        case TypeInfoKind::Float:
        {
            Utf8 out;
            out += "f";
            out += std::to_string(int_.bits);
            return out;
        }

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE()
