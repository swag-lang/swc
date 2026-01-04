#include "pch.h"
#include "Sema/Type/TypeInfo.h"
#include "Math/Hash.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

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
        case TypeInfoKind::Null:
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
            asEnum = other.asEnum;
            break;
        case TypeInfoKind::Struct:
            asStruct = other.asStruct;
            break;
        case TypeInfoKind::Interface:
            asInterface = other.asInterface;
            break;
        case TypeInfoKind::Alias:
            asAlias = other.asAlias;
            break;

        case TypeInfoKind::Array:
            std::construct_at(&asArray, other.asArray);
            break;
        case TypeInfoKind::Lambda:
            std::construct_at(&asLambda, other.asLambda);
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
        case TypeInfoKind::Lambda:
            std::destroy_at(&asLambda);
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
        case TypeInfoKind::Null:
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
            asEnum = other.asEnum;
            break;
        case TypeInfoKind::Struct:
            asStruct = other.asStruct;
            break;
        case TypeInfoKind::Interface:
            asInterface = other.asInterface;
            break;
        case TypeInfoKind::Alias:
            asAlias = other.asAlias;
            break;

        case TypeInfoKind::Array:
            new (&asArray) decltype(asArray)(other.asArray);
            break;
        case TypeInfoKind::Lambda:
            new (&asLambda) decltype(asLambda)(other.asLambda);
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
        case TypeInfoKind::Null:
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
            return asEnum.sym == other.asEnum.sym;
        case TypeInfoKind::Struct:
            return asStruct.sym == other.asStruct.sym;
        case TypeInfoKind::Interface:
            return asInterface.sym == other.asInterface.sym;
        case TypeInfoKind::Alias:
            return asAlias.sym == other.asAlias.sym;

        case TypeInfoKind::Array:
            if (asArray.dims.size() != other.asArray.dims.size())
                return false;
            if (asArray.typeRef != other.asArray.typeRef)
                return false;
            for (uint32_t i = 0; i < asArray.dims.size(); ++i)
                if (asArray.dims[i] != other.asArray.dims[i])
                    return false;
            return true;
        case TypeInfoKind::Lambda:
            if (asLambda.flags != other.asLambda.flags)
                return false;
            if (asLambda.paramTypes.size() != other.asLambda.paramTypes.size())
                return false;
            if (asLambda.returnType != other.asLambda.returnType)
                return false;
            for (uint32_t i = 0; i < asLambda.paramTypes.size(); ++i)
                if (asLambda.paramTypes[i] != other.asLambda.paramTypes[i])
                    return false;
            return true;

        default:
            SWC_UNREACHABLE();
    }
}

Utf8 TypeInfo::toName(const TaskContext& ctx) const
{
    Utf8 out;

    if (isNullable())
        out += "#null ";
    if (isConst())
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
        case TypeInfoKind::Null:
            out += "null";
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
            out += std::format("enum {}", asEnum.sym->name(ctx));
            break;
        case TypeInfoKind::Struct:
            out += std::format("struct {}", asStruct.sym->name(ctx));
            break;
        case TypeInfoKind::Interface:
            out += std::format("interface {}", asInterface.sym->name(ctx));
            break;
        case TypeInfoKind::Alias:
            out += asAlias.sym->name(ctx);
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
            if (asFloat.bits == 0)
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
        case TypeInfoKind::Lambda:
        {
            out += "func(";
            for (size_t i = 0; i < asLambda.paramTypes.size(); ++i)
            {
                if (i != 0)
                    out += ", ";
                const TypeInfo& paramType = ctx.typeMgr().get(asLambda.paramTypes[i]);
                out += paramType.toName(ctx);
            }
            out += ")";
            if (asLambda.returnType.isValid())
            {
                out += " -> ";
                const TypeInfo& returnType = ctx.typeMgr().get(asLambda.returnType);
                out += returnType.toName(ctx);
            }
            break;
        }

        default:
            SWC_UNREACHABLE();
    }

    return out;
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

TypeInfo TypeInfo::makeRune()
{
    return TypeInfo{TypeInfoKind::Rune};
}

TypeInfo TypeInfo::makeAny(TypeInfoFlags flags)
{
    return TypeInfo{TypeInfoKind::Any, flags};
}

TypeInfo TypeInfo::makeVoid()
{
    return TypeInfo{TypeInfoKind::Void};
}

TypeInfo TypeInfo::makeNull()
{
    return TypeInfo{TypeInfoKind::Null};
}

TypeInfo TypeInfo::makeCString(TypeInfoFlags flags)
{
    return TypeInfo{TypeInfoKind::CString, flags};
}

TypeInfo TypeInfo::makeEnum(SymbolEnum* sym)
{
    TypeInfo ti{TypeInfoKind::Enum};
    ti.asEnum.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeStruct(SymbolStruct* sym)
{
    TypeInfo ti{TypeInfoKind::Struct};
    ti.asStruct.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeInterface(SymbolInterface* sym)
{
    TypeInfo ti{TypeInfoKind::Interface};
    ti.asInterface.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeAlias(SymbolAlias* sym)
{
    TypeInfo ti{TypeInfoKind::Alias};
    ti.asAlias.sym = sym;
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

TypeInfo TypeInfo::makeLambda(const std::vector<TypeRef>& paramTypes, TypeRef returnType, TypeInfoFlags flags, LambdaFlags lambdaFlags)
{
    TypeInfo ti{TypeInfoKind::Lambda, flags};
    std::construct_at(&ti.asLambda.paramTypes, paramTypes);
    ti.asLambda.returnType = returnType;
    ti.asLambda.flags      = lambdaFlags;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
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
        case TypeInfoKind::Null:
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
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(asEnum.sym));
            return h;
        case TypeInfoKind::Struct:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(asStruct.sym));
            return h;
        case TypeInfoKind::Interface:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(asInterface.sym));
            return h;
        case TypeInfoKind::Alias:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(asAlias.sym));
            return h;
        case TypeInfoKind::Array:
            h = Math::hashCombine(h, asArray.typeRef.get());
            for (const auto dim : asArray.dims)
                h = Math::hashCombine(h, dim);
            return h;
        case TypeInfoKind::Lambda:
            h = Math::hashCombine(h, static_cast<uint32_t>(asLambda.flags.get()));
            h = Math::hashCombine(h, asLambda.returnType.get());
            for (const auto& param : asLambda.paramTypes)
                h = Math::hashCombine(h, param.get());
            return h;

        default:
            SWC_UNREACHABLE();
    }
}

uint64_t TypeInfo::sizeOf(TaskContext& ctx) const
{
    switch (kind_)
    {
        case TypeInfoKind::Void:
            return 0;

        case TypeInfoKind::Bool:
            return 1;

        case TypeInfoKind::Char:
        case TypeInfoKind::Rune:
            return 4;

        case TypeInfoKind::Int:
            return asInt.bits / 8;
        case TypeInfoKind::Float:
            return asFloat.bits / 8;

        case TypeInfoKind::CString:
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Lambda:
        case TypeInfoKind::Null:
            return 8;

        case TypeInfoKind::Slice:
        case TypeInfoKind::String:
        case TypeInfoKind::Interface:
        case TypeInfoKind::Any:
            return 16;

        case TypeInfoKind::Array:
        {
            uint64_t count = ctx.typeMgr().get(asArray.typeRef).sizeOf(ctx);
            for (const uint64_t d : asArray.dims)
                count *= d;
            return count;
        }

        case TypeInfoKind::Struct:
            return structSym().sizeOf();
        case TypeInfoKind::Enum:
            return enumSym().sizeOf(ctx);
        case TypeInfoKind::Alias:
            return aliasSym().sizeOf(ctx);

        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(asTypeRef.typeRef).sizeOf(ctx);

        default:
            SWC_UNREACHABLE();
    }
}

uint32_t TypeInfo::alignOf(TaskContext& ctx) const
{
    switch (kind_)
    {
        case TypeInfoKind::Void:
        case TypeInfoKind::Bool:
        case TypeInfoKind::Char:
        case TypeInfoKind::Rune:
        case TypeInfoKind::Int:
        case TypeInfoKind::Float:
        case TypeInfoKind::CString:
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Lambda:
        case TypeInfoKind::Slice:
        case TypeInfoKind::String:
        case TypeInfoKind::Interface:
        case TypeInfoKind::Any:
        case TypeInfoKind::Null:
            return static_cast<uint32_t>(sizeOf(ctx));

        case TypeInfoKind::Array:
            return ctx.typeMgr().get(asArray.typeRef).alignOf(ctx);

        case TypeInfoKind::Struct:
            return structSym().alignment();
        case TypeInfoKind::Enum:
            return enumSym().underlyingType(ctx).alignOf(ctx);
        case TypeInfoKind::Alias:
            return aliasSym().type(ctx).alignOf(ctx);

        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(asTypeRef.typeRef).alignOf(ctx);

        default:
            SWC_UNREACHABLE();
    }
}

bool TypeInfo::isCompleted(TaskContext& ctx) const
{
    switch (kind_)
    {
        case TypeInfoKind::Struct:
            return structSym().isCompleted();
        case TypeInfoKind::Enum:
            return enumSym().isCompleted();
        case TypeInfoKind::Interface:
            return interfaceSym().isCompleted();
        case TypeInfoKind::Alias:
            return aliasSym().isCompleted();

        case TypeInfoKind::Array:
            return ctx.typeMgr().get(asArray.typeRef).isCompleted(ctx);
        case TypeInfoKind::Lambda:
        {
            if (asLambda.returnType.isValid() && !ctx.typeMgr().get(asLambda.returnType).isCompleted(ctx))
                return false;
            for (const auto& param : asLambda.paramTypes)
                if (!ctx.typeMgr().get(param).isCompleted(ctx))
                    return false;
            return true;
        }
        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(asTypeRef.typeRef).isCompleted(ctx);
        default:
            break;
    }

    return true;
}

Symbol* TypeInfo::getSymbolDependency(TaskContext& ctx) const
{
    switch (kind_)
    {
        case TypeInfoKind::Struct:
            return &structSym();
        case TypeInfoKind::Enum:
            return &enumSym();
        case TypeInfoKind::Interface:
            return &interfaceSym();
        case TypeInfoKind::Alias:
            return &aliasSym();

        case TypeInfoKind::Array:
            return ctx.typeMgr().get(asArray.typeRef).getSymbolDependency(ctx);
        case TypeInfoKind::Lambda:
        {
            if (asLambda.returnType.isValid())
            {
                if (auto sym = ctx.typeMgr().get(asLambda.returnType).getSymbolDependency(ctx))
                    return sym;
            }
            for (const auto& param : asLambda.paramTypes)
            {
                if (auto sym = ctx.typeMgr().get(param).getSymbolDependency(ctx))
                    return sym;
            }
            return nullptr;
        }
        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(asTypeRef.typeRef).getSymbolDependency(ctx);
        default:
            break;
    }

    return nullptr;
}

// ReSharper disable once CppPossiblyUninitializedMember
TypeInfo::TypeInfo(TypeInfoKind kind, TypeInfoFlags flags) :
    kind_(kind),
    flags_(flags)
{
}

SWC_END_NAMESPACE()
