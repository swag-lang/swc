#include "pch.h"
#include "Sema/Type/TypeInfo.h"
#include "Math/Hash.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"

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
        case TypeInfoKind::Void:
        case TypeInfoKind::Any:
        case TypeInfoKind::Rune:
        case TypeInfoKind::CString:
            return true;

        case TypeInfoKind::Int:
            return asInt.bits == other.asInt.bits && asInt.sign == other.asInt.sign;
        case TypeInfoKind::Float:
            return asFloat.bits == other.asFloat.bits;
        case TypeInfoKind::TypeValue:
            return asTypeValue.typeRef == other.asTypeValue.typeRef;
        case TypeInfoKind::Enum:
            return asEnum.enumSym == other.asEnum.enumSym;

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
        case TypeInfoKind::Void:
        case TypeInfoKind::Any:
        case TypeInfoKind::Rune:
        case TypeInfoKind::CString:
            return h;

        case TypeInfoKind::Int:
            h = Math::hashCombine(h, asInt.bits);
            h = Math::hashCombine(h, static_cast<uint32_t>(asInt.sign));
            return h;
        case TypeInfoKind::Float:
            h = Math::hashCombine(h, asFloat.bits);
            return h;
        case TypeInfoKind::TypeValue:
            h = Math::hashCombine(h, asTypeValue.typeRef.get());
            return h;
        case TypeInfoKind::Enum:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(asEnum.enumSym));
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

TypeInfo TypeInfo::makeVoid()
{
    return TypeInfo{TypeInfoKind::Void};
}

TypeInfo TypeInfo::makeAny()
{
    return TypeInfo{TypeInfoKind::Any};
}

TypeInfo TypeInfo::makeRune()
{
    return TypeInfo{TypeInfoKind::Rune};
}

TypeInfo TypeInfo::makeCString()
{
    return TypeInfo{TypeInfoKind::CString};
}

TypeInfo TypeInfo::makeInt(uint32_t bits, Sign sign)
{
    TypeInfo ti{TypeInfoKind::Int};
    ti.asInt = {.bits = bits, .sign = sign};
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

TypeInfo TypeInfo::makeTypeValue(TypeRef typeRef)
{
    TypeInfo ti{TypeInfoKind::TypeValue};
    ti.asTypeValue = {.typeRef = typeRef};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeEnum(SymbolEnum* enumSym)
{
    TypeInfo ti{TypeInfoKind::Enum};
    ti.asEnum.enumSym = enumSym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

Utf8 TypeInfo::toName(const TaskContext& ctx) const
{
    switch (kind_)
    {
        case TypeInfoKind::Bool:
            return "bool";
        case TypeInfoKind::Char:
            return "character";
        case TypeInfoKind::String:
            return "string";
        case TypeInfoKind::Void:
            return "void";
        case TypeInfoKind::Any:
            return "any";
        case TypeInfoKind::Rune:
            return "rune";
        case TypeInfoKind::CString:
            return "cstring";
        case TypeInfoKind::Enum:
            return std::format("enum {}", asEnum.enumSym->name(ctx));

        case TypeInfoKind::TypeValue:
            if (asTypeValue.typeRef.isInvalid())
                return "typeinfo";
            return std::format("typeinfo({})", ctx.typeMgr().typeToName(ctx, asTypeValue.typeRef));

        case TypeInfoKind::Int:
        {
            Utf8 out;
            if (asInt.bits == 0)
            {
                if (asInt.sign == Sign::Unsigned)
                    out = "unsigned integer";
                else if (asInt.sign == Sign::Signed)
                    out = "signed integer";
                else
                    out = "integer";
            }
            else
            {
                SWC_ASSERT(asInt.sign != Sign::Unknown);
                out += asInt.sign == Sign::Unsigned ? "u" : "s";
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
