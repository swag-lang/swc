#include "pch.h"

#include "Main/TaskContext.h"
#include "Math/Hash.h"
#include "Sema/Type/TypeInfo.h"
#include "TypeManager.h"

SWC_BEGIN_NAMESPACE()
class TaskContext;

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
        case TypeInfoKind::Char:
        case TypeInfoKind::String:
            return true;
        case TypeInfoKind::Int:
            return asInt.bits == other.asInt.bits && asInt.isUnsigned == other.asInt.isUnsigned;
        case TypeInfoKind::Float:
            return asFloat.bits == other.asFloat.bits;
        case TypeInfoKind::TypeInfo:
            return asTypeInfo.typeRef == other.asTypeInfo.typeRef;

        default:
            SWC_UNREACHABLE();
    }
}

uint32_t TypeInfo::hash() const
{
    auto h = Math::hash(static_cast<uint32_t>(kind_));

    switch (kind_)
    {
        case TypeInfoKind::Bool:
        case TypeInfoKind::Char:
        case TypeInfoKind::String:
            return h;

        case TypeInfoKind::Int:
            h = Math::hashCombine(h, asInt.bits);
            h = Math::hashCombine(h, asInt.isUnsigned);
            return h;
        case TypeInfoKind::Float:
            h = Math::hashCombine(h, asFloat.bits);
            return h;
        case TypeInfoKind::TypeInfo:
            h = Math::hashCombine(h, asTypeInfo.typeRef.get());
            return h;

        default:
            SWC_UNREACHABLE();
    }
}

TypeInfo TypeInfo::makeBool()
{
    return TypeInfo{TypeInfoKind::Bool};
}

TypeInfo TypeInfo::makeChar()
{
    return TypeInfo{TypeInfoKind::Char};
}

TypeInfo TypeInfo::makeString()
{
    return TypeInfo{TypeInfoKind::String};
}

TypeInfo TypeInfo::makeInt(uint32_t bits, bool isUnsigned)
{
    TypeInfo ti{TypeInfoKind::Int};
    ti.asInt = {.bits = bits, .isUnsigned = isUnsigned};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeFloat(uint32_t bits)
{
    TypeInfo ti{TypeInfoKind::Float};
    ti.asFloat = {.bits = bits};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeTypeInfo(TypeRef typeRef)
{
    TypeInfo ti{TypeInfoKind::TypeInfo};
    ti.asTypeInfo = {.typeRef = typeRef};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

Utf8 TypeInfo::toName(const TypeManager& typeMgr, ToNameMode mode) const
{
    switch (kind_)
    {
        case TypeInfoKind::Bool:
            return "bool";
        case TypeInfoKind::Char:
            return "character";
        case TypeInfoKind::String:
            return "string";
        case TypeInfoKind::TypeInfo:
            if (asTypeInfo.typeRef.isInvalid())
                return "typeinfo";
            return std::format("typeinfo({})", typeMgr.typeToName(asTypeInfo.typeRef, mode));

        case TypeInfoKind::Int:
        {
            Utf8 out;
            if (asInt.bits == 0)
                out = "integer";
            else
            {
                out += asInt.isUnsigned ? "u" : "s";
                out += std::to_string(asInt.bits);
            }
            return out;
        }
        case TypeInfoKind::Float:
        {
            Utf8 out;
            if (asInt.bits == 0)
                out = "float";
            else
            {
                out += "f";
                out += std::to_string(asFloat.bits);
            }
            return out;
        }

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE()
