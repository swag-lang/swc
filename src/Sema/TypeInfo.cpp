#include "pch.h"
#include "Sema/TypeInfo.h"
#include "Core/hash.h"

SWC_BEGIN_NAMESPACE()

bool TypeInfo::operator==(const TypeInfo& other) const noexcept
{
    if (kind != other.kind)
        return false;
    switch (kind)
    {
        case TypeInfoKind::Bool:
        case TypeInfoKind::String:
            return true;

        case TypeInfoKind::Int:
            return int_.bits == other.int_.bits && int_.isSigned == other.int_.isSigned;

        default:
            SWC_UNREACHABLE();
    }
}

size_t TypeInfoHash::operator()(const TypeInfo& t) const noexcept
{
    auto h = std::hash<int>()(static_cast<int>(t.kind));

    switch (t.kind)
    {
        case TypeInfoKind::Bool:
        case TypeInfoKind::String:
            return h;

        case TypeInfoKind::Int:
            h = hash_combine(h, t.int_.bits);
            h = hash_combine(h, t.int_.isSigned);
            return h;

        default:
            SWC_UNREACHABLE();
    }
}

TypeInfo TypeInfo::makeBool()
{
    TypeInfo ti{};
    ti.kind = TypeInfoKind::Bool;
    return ti;
}

TypeInfo TypeInfo::makeString()
{
    TypeInfo ti{};
    ti.kind = TypeInfoKind::String;
    return ti;
}

SWC_END_NAMESPACE()
