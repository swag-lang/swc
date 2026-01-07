#include "pch.h"
#include "Sema/Type/TypeInfo.h"
#include "Math/Hash.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

TypeInfo::~TypeInfo()
{
    switch (kind_)
    {
        case TypeInfoKind::Array:
            std::destroy_at(&asArray.dims);
            break;
        default:
            break;
    }
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
        case TypeInfoKind::Null:
        case TypeInfoKind::Any:
        case TypeInfoKind::Rune:
        case TypeInfoKind::CString:
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypeInfo:
        case TypeInfoKind::Undefined:
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
        case TypeInfoKind::TypedVariadic:
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
            std::construct_at(&asArray.dims, other.asArray.dims);
            asArray.typeRef = other.asArray.typeRef;
            break;
        case TypeInfoKind::Function:
            asFunction = other.asFunction;
            break;

        default:
            SWC_UNREACHABLE();
    }
}

TypeInfo::TypeInfo(TypeInfo&& other) noexcept :
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
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypeInfo:
        case TypeInfoKind::Undefined:
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
        case TypeInfoKind::TypedVariadic:
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
            std::construct_at(&asArray.dims, std::move(other.asArray.dims));
            asArray.typeRef = other.asArray.typeRef;
            break;
        case TypeInfoKind::Function:
            asFunction = other.asFunction;
            break;

        default:
            SWC_UNREACHABLE();
    }
}

TypeInfo& TypeInfo::operator=(const TypeInfo& other)
{
    if (this == &other)
        return *this;
    this->~TypeInfo();
    new (this) TypeInfo(other);
    return *this;
}

TypeInfo& TypeInfo::operator=(TypeInfo&& other) noexcept
{
    if (this == &other)
        return *this;
    this->~TypeInfo();
    new (this) TypeInfo(std::move(other));
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
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypeInfo:
            return true;

        case TypeInfoKind::Int:
            return asInt.bits == other.asInt.bits && asInt.sign == other.asInt.sign;
        case TypeInfoKind::Float:
            return asFloat.bits == other.asFloat.bits;

        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
            return asTypeRef.typeRef == other.asTypeRef.typeRef;

        case TypeInfoKind::Enum:
            return asEnum.sym == other.asEnum.sym;
        case TypeInfoKind::Struct:
            return asStruct.sym == other.asStruct.sym;
        case TypeInfoKind::Interface:
            return asInterface.sym == other.asInterface.sym;
        case TypeInfoKind::Alias:
            return asAlias.sym == other.asAlias.sym;
        case TypeInfoKind::Function:
            return asFunction.sym == other.asFunction.sym;

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
        case TypeInfoKind::Undefined:
            out += "undefined";
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
            out += asEnum.sym->name(ctx);
            break;
        case TypeInfoKind::Struct:
            out += asStruct.sym->name(ctx);
            break;
        case TypeInfoKind::Interface:
            out += asInterface.sym->name(ctx);
            break;
        case TypeInfoKind::Alias:
            out += asAlias.sym->name(ctx);
            break;
        case TypeInfoKind::Function:
            out += asFunction.sym->computeName(ctx);
            break;

        case TypeInfoKind::TypeInfo:
            out += "typeinfo";
            break;
        case TypeInfoKind::TypeValue:
        {
            const TypeInfo& type = ctx.typeMgr().get(asTypeRef.typeRef);
            out += std::format("typeinfo({})", type.toName(ctx));
            break;
        }

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
                    out += "unsigned integer"; // keep qualifiers
                else if (asInt.sign == Sign::Signed)
                    out += "signed integer";
                else
                    out += "integer";
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
                out += "float"; // keep qualifiers
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

        case TypeInfoKind::Variadic:
            out += "...";
            break;
        case TypeInfoKind::TypedVariadic:
        {
            const TypeInfo& type = ctx.typeMgr().get(asTypeRef.typeRef);
            out += std::format("{}...", type.toName(ctx));
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

TypeInfo TypeInfo::makeUndefined()
{
    return TypeInfo{TypeInfoKind::Undefined, TypeInfoFlagsE::Zero};
}

TypeInfo TypeInfo::makeCString(TypeInfoFlags flags)
{
    return TypeInfo{TypeInfoKind::CString, flags};
}

TypeInfo TypeInfo::makeTypeInfo()
{
    return TypeInfo{TypeInfoKind::TypeInfo};
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

TypeInfo TypeInfo::makeFunction(SymbolFunction* sym, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::Function, flags};
    ti.asFunction.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeVariadic()
{
    return TypeInfo{TypeInfoKind::Variadic};
}

TypeInfo TypeInfo::makeTypedVariadic(TypeRef typeRef)
{
    TypeInfo ti{TypeInfoKind::TypedVariadic};
    ti.asTypeRef = {.typeRef = typeRef};
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
        case TypeInfoKind::Undefined:
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypeInfo:
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
        case TypeInfoKind::TypedVariadic:
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
        case TypeInfoKind::Function:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(asFunction.sym));
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

uint64_t TypeInfo::sizeOf(TaskContext& ctx) const
{
    switch (kind_)
    {
        case TypeInfoKind::Void:
        case TypeInfoKind::Undefined:
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
        case TypeInfoKind::Null:
        case TypeInfoKind::TypeInfo:
            return 8;

        case TypeInfoKind::Function:
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

        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypedVariadic:
            return 0;

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
        case TypeInfoKind::Function:
        case TypeInfoKind::Slice:
        case TypeInfoKind::String:
        case TypeInfoKind::Interface:
        case TypeInfoKind::Any:
        case TypeInfoKind::Null:
        case TypeInfoKind::Undefined:
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypedVariadic:
        case TypeInfoKind::TypeInfo:
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
        case TypeInfoKind::Function:
        {
            if (asFunction.sym->returnType().isValid() && !ctx.typeMgr().get(asFunction.sym->returnType()).isCompleted(ctx))
                return false;
            for (const auto& param : asFunction.sym->parameters())
                if (!ctx.typeMgr().get(param->typeRef()).isCompleted(ctx))
                    return false;
            return true;
        }
        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(asTypeRef.typeRef).isCompleted(ctx);
        case TypeInfoKind::TypedVariadic:
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
        case TypeInfoKind::Function:
        {
            if (asFunction.sym->returnType().isValid())
            {
                if (const auto sym = ctx.typeMgr().get(asFunction.sym->returnType()).getSymbolDependency(ctx))
                    return sym;
            }
            for (const auto& param : asFunction.sym->parameters())
            {
                if (const auto sym = ctx.typeMgr().get(param->typeRef()).getSymbolDependency(ctx))
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
bool TypeInfo::isLambdaClosure() const noexcept
{
    SWC_ASSERT(isFunction());
    return asFunction.sym->hasFuncFlag(SymbolFunctionFlagsE::Closure);
}

bool TypeInfo::isLambdaMethod() const noexcept
{
    SWC_ASSERT(isFunction());
    return asFunction.sym->hasFuncFlag(SymbolFunctionFlagsE::Method);
}

bool TypeInfo::isLambdaThrowable() const noexcept
{
    SWC_ASSERT(isFunction());
    return asFunction.sym->hasFuncFlag(SymbolFunctionFlagsE::Throwable);
}

TypeRef TypeInfo::underlyingTypeRef() const noexcept
{
    if (isPointer() || isSlice() || isAlias() || isTypedVariadic() || isTypeValue())
        return asTypeRef.typeRef;
    if (isArray())
        return asArray.typeRef;
    return {};
}

TypeRef TypeInfo::ultimateTypeRef(const TaskContext& ctx) const noexcept
{
    TypeRef result = underlyingTypeRef();
    if (!result.isValid())
        return TypeRef::invalid();

    while (true)
    {
        TypeRef sub = ctx.typeMgr().get(result).underlyingTypeRef();
        if (!sub.isValid())
            break;
        result = sub;
    }

    return result;
}

TypeInfo::TypeInfo(TypeInfoKind kind, TypeInfoFlags flags) :
    kind_(kind),
    flags_(flags)
{
}

SWC_END_NAMESPACE();
