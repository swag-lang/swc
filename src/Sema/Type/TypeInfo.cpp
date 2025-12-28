#include "pch.h"
#include "Sema/Type/TypeInfo.h"
#include "Math/Hash.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()
class TaskContext;

// ReSharper disable once CppPossiblyUninitializedMember
TypeInfo::TypeInfo(TypeInfoKind kind, TypeInfoFlags flags) :
    kind_(kind),
    flags_(flags)
{
}

TypeInfo::TypeInfo(const TypeInfo& other) :
    kind_(other.kind_),
    flags_(other.flags_)
{
    switch (kind_)
    {
        case TypeInfoKind::Bool:
        case TypeInfoKind::Char:
        case TypeInfoKind::String:
        case TypeInfoKind::Void:
        case TypeInfoKind::Any:
        case TypeInfoKind::Rune:
        case TypeInfoKind::CString:
            // no payload
            break;

        case TypeInfoKind::Int:
            asInt = other.asInt;
            break;

        case TypeInfoKind::Float:
            asFloat = other.asFloat;
            break;

        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
            asTypeRef = other.asTypeRef;
            break;

        case TypeInfoKind::Enum:
            asEnumSym = other.asEnumSym;
            break;

        case TypeInfoKind::Array:
            asArray = other.asArray;
            break;

        default:
            SWC_UNREACHABLE();
    }
}

TypeInfo& TypeInfo::operator=(const TypeInfo& other)
{
    if (this == &other)
        return *this;

    switch (kind_)
    {
        case TypeInfoKind::Array:
            std::destroy_at(&asArray);
            break;

        default:
            break;
    }

    kind_  = other.kind_;
    flags_ = other.flags_;

    // Copy payload for new kind
    switch (kind_)
    {
        case TypeInfoKind::Bool:
        case TypeInfoKind::Char:
        case TypeInfoKind::String:
        case TypeInfoKind::Void:
        case TypeInfoKind::Any:
        case TypeInfoKind::Rune:
        case TypeInfoKind::CString:
            break;

        case TypeInfoKind::Int:
            asInt = other.asInt;
            break;

        case TypeInfoKind::Float:
            asFloat = other.asFloat;
            break;

        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
            asTypeRef = other.asTypeRef;
            break;

        case TypeInfoKind::Enum:
            asEnumSym = other.asEnumSym;
            break;

        case TypeInfoKind::Array:
            new (&asArray) decltype(asArray)(other.asArray);
            break;

        default:
            SWC_UNREACHABLE();
    }

    return *this;
}

bool TypeInfo::operator==(const TypeInfo& other) const noexcept
{
    if (kind_ != other.kind_)
        return false;
    if (flags_ != other.flags_)
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
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
            return asTypeRef.typeRef == other.asTypeRef.typeRef;
        case TypeInfoKind::Enum:
            return asEnumSym.enumSym == other.asEnumSym.enumSym;

        case TypeInfoKind::Array:
            if (asArray.dims.size() != other.asArray.dims.size())
                return false;
            if (asArray.typeRef != other.asArray.typeRef)
                return false;
            for (uint32_t i = 0; i < asArray.dims.size(); ++i)
                if (asArray.dims[i] != other.asArray.dims[i])
                    return false;
            return true;

        default:
            SWC_UNREACHABLE();
    }
}

uint32_t TypeInfo::hash() const
{
    auto h = Math::hash(static_cast<uint32_t>(kind_));
    h      = Math::hashCombine(h, static_cast<uint32_t>(flags_.get()));

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
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
            h = Math::hashCombine(h, asTypeRef.typeRef.get());
            return h;
        case TypeInfoKind::Enum:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(asEnumSym.enumSym));
            return h;
        case TypeInfoKind::Array:
            h = Math::hashCombine(h, asArray.typeRef.get());
            for (const auto dim : asArray.dims)
                h = Math::hashCombine(h, dim);
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

TypeInfo TypeInfo::makeString(TypeInfoFlags flags)
{
    return TypeInfo{TypeInfoKind::String, flags};
}

TypeInfo TypeInfo::makeVoid()
{
    return TypeInfo{TypeInfoKind::Void};
}

TypeInfo TypeInfo::makeAny(TypeInfoFlags flags)
{
    return TypeInfo{TypeInfoKind::Any, flags};
}

TypeInfo TypeInfo::makeRune()
{
    return TypeInfo{TypeInfoKind::Rune};
}

TypeInfo TypeInfo::makeCString(TypeInfoFlags flags)
{
    return TypeInfo{TypeInfoKind::CString, flags};
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
    ti.asTypeRef = {.typeRef = typeRef};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeEnum(SymbolEnum* enumSym)
{
    TypeInfo ti{TypeInfoKind::Enum};
    ti.asEnumSym.enumSym = enumSym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeValuePointer(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::ValuePointer, flags};
    ti.asTypeRef.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeBlockPointer(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::BlockPointer, flags};
    ti.asTypeRef.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeSlice(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::Slice, flags};
    ti.asTypeRef.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeArray(const std::vector<uint64_t>& dims, TypeRef elementTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::Array, flags};
    std::construct_at(&ti.asArray.dims, dims);
    ti.asArray.typeRef = elementTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

Utf8 TypeInfo::toName(const TaskContext& ctx) const
{
    Utf8 out;

    if (hasFlag(TypeInfoFlagsE::Nullable))
        out += "#null ";
    if (hasFlag(TypeInfoFlagsE::Const))
        out += "const ";

    switch (kind_)
    {
        case TypeInfoKind::Bool:
            out += "bool";
            break;
        case TypeInfoKind::Char:
            out += "character";
            break;
        case TypeInfoKind::String:
            out += "string";
            break;
        case TypeInfoKind::Void:
            out += "void";
            break;
        case TypeInfoKind::Any:
            out += "any";
            break;
        case TypeInfoKind::Rune:
            out += "rune";
            break;
        case TypeInfoKind::CString:
            out += "cstring";
            break;
        case TypeInfoKind::Enum:
            out += std::format("enum {}", asEnumSym.enumSym->name(ctx));
            break;

        case TypeInfoKind::TypeValue:
            if (asTypeRef.typeRef.isInvalid())
                out += "typeinfo";
            else
            {
                const TypeInfo& type = ctx.typeMgr().get(asTypeRef.typeRef);
                out += std::format("typeinfo({})", type.toName(ctx));
            }
            break;

        case TypeInfoKind::ValuePointer:
        {
            const TypeInfo& type = ctx.typeMgr().get(asTypeRef.typeRef);
            out += std::format("*{}", type.toName(ctx));
            break;
        }
        case TypeInfoKind::BlockPointer:
        {
            const TypeInfo& type = ctx.typeMgr().get(asTypeRef.typeRef);
            out += std::format("[*] {}", type.toName(ctx));
            break;
        }

        case TypeInfoKind::Int:
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
            break;

        case TypeInfoKind::Float:
            if (asInt.bits == 0)
                out = "float";
            else
            {
                out += "f";
                out += std::to_string(asFloat.bits);
            }
            break;

        case TypeInfoKind::Slice:
        {
            const TypeInfo& type = ctx.typeMgr().get(asTypeRef.typeRef);
            out += std::format("[..] {}", type.toName(ctx));
            break;
        }

        case TypeInfoKind::Array:
        {
            if (asArray.dims.empty())
                out += "[?]";
            else
            {
                out += "[";
                for (size_t i = 0; i < asArray.dims.size(); ++i)
                {
                    if (i != 0)
                        out += ", ";
                    out += std::to_string(asArray.dims[i]);
                }
                out += "]";
            }
            out += " ";
            const TypeInfo& elemType = ctx.typeMgr().get(asArray.typeRef);
            out += elemType.toName(ctx);
            break;
        }

        default:
            SWC_UNREACHABLE();
    }

    return out;
}

SWC_END_NAMESPACE()
