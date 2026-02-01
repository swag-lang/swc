#include "pch.h"
#include "Sema/Type/TypeInfo.h"
#include "Support/Core/Utf8Helper.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

TypeInfo::~TypeInfo()
{
    switch (kind_)
    {
        case TypeInfoKind::Array:
            std::destroy_at(&payloadArray_.dims);
            break;
        case TypeInfoKind::Aggregate:
            std::destroy_at(&payloadAggregate_.types);
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
            payloadInt_ = other.payloadInt_;
            break;

        case TypeInfoKind::Float:
            payloadFloat_ = other.payloadFloat_;
            break;

        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
            payloadTypeRef_ = other.payloadTypeRef_;
            break;

        case TypeInfoKind::Aggregate:
            std::construct_at(&payloadAggregate_.types, other.payloadAggregate_.types);
            break;

        case TypeInfoKind::Enum:
            payloadEnum_ = other.payloadEnum_;
            break;
        case TypeInfoKind::Struct:
            payloadStruct_ = other.payloadStruct_;
            break;
        case TypeInfoKind::Interface:
            payloadInterface_ = other.payloadInterface_;
            break;
        case TypeInfoKind::Alias:
            payloadAlias_ = other.payloadAlias_;
            break;

        case TypeInfoKind::Array:
            std::construct_at(&payloadArray_.dims, other.payloadArray_.dims);
            payloadArray_.typeRef = other.payloadArray_.typeRef;
            break;
        case TypeInfoKind::Function:
            payloadFunction_ = other.payloadFunction_;
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
            payloadInt_ = other.payloadInt_;
            break;

        case TypeInfoKind::Float:
            payloadFloat_ = other.payloadFloat_;
            break;

        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
            payloadTypeRef_ = other.payloadTypeRef_;
            break;

        case TypeInfoKind::Aggregate:
            std::construct_at(&payloadAggregate_.types, std::move(other.payloadAggregate_.types));
            break;

        case TypeInfoKind::Enum:
            payloadEnum_ = other.payloadEnum_;
            break;
        case TypeInfoKind::Struct:
            payloadStruct_ = other.payloadStruct_;
            break;
        case TypeInfoKind::Interface:
            payloadInterface_ = other.payloadInterface_;
            break;
        case TypeInfoKind::Alias:
            payloadAlias_ = other.payloadAlias_;
            break;

        case TypeInfoKind::Array:
            std::construct_at(&payloadArray_.dims, std::move(other.payloadArray_.dims));
            payloadArray_.typeRef = other.payloadArray_.typeRef;
            break;
        case TypeInfoKind::Function:
            payloadFunction_ = other.payloadFunction_;
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
            h = Math::hashCombine(h, payloadInt_.bits);
            h = Math::hashCombine(h, static_cast<uint32_t>(payloadInt_.sign));
            return h;
        case TypeInfoKind::Float:
            h = Math::hashCombine(h, payloadFloat_.bits);
            return h;
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
            h = Math::hashCombine(h, payloadTypeRef_.typeRef.get());
            return h;

        case TypeInfoKind::Aggregate:
            h = Math::hashCombine(h, static_cast<uint32_t>(payloadAggregate_.types.size()));
            for (const TypeRef tr : payloadAggregate_.types)
                h = Math::hashCombine(h, tr.get());
            return h;
        case TypeInfoKind::Enum:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(payloadEnum_.sym));
            return h;
        case TypeInfoKind::Struct:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(payloadStruct_.sym));
            return h;
        case TypeInfoKind::Interface:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(payloadInterface_.sym));
            return h;
        case TypeInfoKind::Alias:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(payloadAlias_.sym));
            return h;
        case TypeInfoKind::Function:
            h = Math::hashCombine(h, reinterpret_cast<uintptr_t>(payloadFunction_.sym));
            return h;
        case TypeInfoKind::Array:
            h = Math::hashCombine(h, payloadArray_.typeRef.get());
            for (const auto dim : payloadArray_.dims)
                h = Math::hashCombine(h, static_cast<uint32_t>(dim));
            return h;

        default:
            SWC_UNREACHABLE();
    }
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
            return payloadInt_.bits == other.payloadInt_.bits && payloadInt_.sign == other.payloadInt_.sign;
        case TypeInfoKind::Float:
            return payloadFloat_.bits == other.payloadFloat_.bits;

        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
        case TypeInfoKind::Slice:
        case TypeInfoKind::TypeValue:
        case TypeInfoKind::TypedVariadic:
            return payloadTypeRef_.typeRef == other.payloadTypeRef_.typeRef;

        case TypeInfoKind::Aggregate:
            if (payloadAggregate_.types.size() != other.payloadAggregate_.types.size())
                return false;
            for (uint32_t i = 0; i < payloadAggregate_.types.size(); ++i)
                if (payloadAggregate_.types[i] != other.payloadAggregate_.types[i])
                    return false;
            return true;

        case TypeInfoKind::Enum:
            return payloadEnum_.sym == other.payloadEnum_.sym;
        case TypeInfoKind::Struct:
            return payloadStruct_.sym == other.payloadStruct_.sym;
        case TypeInfoKind::Interface:
            return payloadInterface_.sym == other.payloadInterface_.sym;
        case TypeInfoKind::Alias:
            return payloadAlias_.sym == other.payloadAlias_.sym;
        case TypeInfoKind::Function:
            return payloadFunction_.sym == other.payloadFunction_.sym;

        case TypeInfoKind::Array:
            if (payloadArray_.dims.size() != other.payloadArray_.dims.size())
                return false;
            if (payloadArray_.typeRef != other.payloadArray_.typeRef)
                return false;
            for (uint32_t i = 0; i < payloadArray_.dims.size(); ++i)
                if (payloadArray_.dims[i] != other.payloadArray_.dims[i])
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
            out += payloadEnum_.sym->name(ctx);
            break;
        case TypeInfoKind::Struct:
            out += payloadStruct_.sym->name(ctx);
            break;
        case TypeInfoKind::Interface:
            out += payloadInterface_.sym->name(ctx);
            break;
        case TypeInfoKind::Alias:
            out += payloadAlias_.sym->name(ctx);
            break;
        case TypeInfoKind::Function:
            out += payloadFunction_.sym->computeName(ctx);
            break;

        case TypeInfoKind::TypeInfo:
            out += "typeinfo";
            break;
        case TypeInfoKind::TypeValue:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("typeinfo({})", type.toName(ctx));
            break;
        }

        case TypeInfoKind::Aggregate:
            out += "aggregate";
            if (!payloadAggregate_.types.empty())
            {
                out += "{";
                for (uint32_t i = 0; i < payloadAggregate_.types.size(); ++i)
                {
                    if (i)
                        out += ", ";
                    out += ctx.typeMgr().get(payloadAggregate_.types[i]).toName(ctx);
                }
                out += "}";
            }
            break;

        case TypeInfoKind::ValuePointer:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("*{}", type.toName(ctx));
            break;
        }
        case TypeInfoKind::BlockPointer:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("[*] {}", type.toName(ctx));
            break;
        }
        case TypeInfoKind::Reference:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("&{}", type.toName(ctx));
            break;
        }

        case TypeInfoKind::Int:
            if (payloadInt_.bits == 0)
            {
                if (payloadInt_.sign == Sign::Unsigned)
                    out += "unsigned integer"; // keep qualifiers
                else if (payloadInt_.sign == Sign::Signed)
                    out += "signed integer";
                else
                    out += "integer";
            }
            else
            {
                SWC_ASSERT(payloadInt_.sign != Sign::Unknown);
                out += payloadInt_.sign == Sign::Unsigned ? "u" : "s";
                out += std::to_string(payloadInt_.bits);
            }
            break;

        case TypeInfoKind::Float:
            if (payloadFloat_.bits == 0)
                out += "float"; // keep qualifiers
            else
            {
                out += "f";
                out += std::to_string(payloadFloat_.bits);
            }
            break;

        case TypeInfoKind::Slice:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("[..] {}", type.toName(ctx));
            break;
        }

        case TypeInfoKind::Array:
        {
            if (payloadArray_.dims.empty())
                out += "[?]";
            else
            {
                out += "[";
                for (size_t i = 0; i < payloadArray_.dims.size(); ++i)
                {
                    if (i != 0)
                        out += ", ";
                    out += std::to_string(payloadArray_.dims[i]);
                }
                out += "]";
            }
            const TypeInfo& elemType = ctx.typeMgr().get(payloadArray_.typeRef);
            if (!elemType.isArray())
                out += " ";
            out += elemType.toName(ctx);
            break;
        }

        case TypeInfoKind::Variadic:
            out += "...";
            break;
        case TypeInfoKind::TypedVariadic:
        {
            const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
            out += std::format("{}...", type.toName(ctx));
            break;
        }

        default:
            SWC_UNREACHABLE();
    }

    return out;
}

Utf8 TypeInfo::toFamily(const TaskContext&) const
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
        case TypeInfoKind::Null:
            return "null";
        case TypeInfoKind::Undefined:
            return "undefined";
        case TypeInfoKind::Any:
            return "any";
        case TypeInfoKind::Rune:
            return "rune";
        case TypeInfoKind::CString:
            return "cstring";
        case TypeInfoKind::Enum:
            return "enum";
        case TypeInfoKind::Struct:
            return "struct";
        case TypeInfoKind::Interface:
            return "interface";
        case TypeInfoKind::Alias:
            return "alias";
        case TypeInfoKind::Function:
            return "function";
        case TypeInfoKind::TypeInfo:
        case TypeInfoKind::TypeValue:
            return "typeinfo";
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
            return "pointer";
        case TypeInfoKind::Reference:
            return "reference";
        case TypeInfoKind::Int:
            return "integer";
        case TypeInfoKind::Float:
            return "float";
        case TypeInfoKind::Slice:
            return "slice";
        case TypeInfoKind::Array:
            return "array";
        case TypeInfoKind::Aggregate:
            return "aggregate";
        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypedVariadic:
            return "variadic";
        default:
            SWC_UNREACHABLE();
    }
}

Utf8 TypeInfo::toArticleFamily(const TaskContext& ctx) const
{
    return Utf8Helper::addArticleAAn(toFamily(ctx));
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
    ti.payloadInt_ = {.bits = bits, .sign = sign};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeFloat(uint32_t bits)
{
    TypeInfo ti{TypeInfoKind::Float};
    ti.payloadFloat_ = {.bits = bits};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeTypeValue(TypeRef typeRef)
{
    TypeInfo ti{TypeInfoKind::TypeValue};
    ti.payloadTypeRef_ = {.typeRef = typeRef};
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
    ti.payloadEnum_.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeStruct(SymbolStruct* sym)
{
    TypeInfo ti{TypeInfoKind::Struct};
    ti.payloadStruct_.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeInterface(SymbolInterface* sym)
{
    TypeInfo ti{TypeInfoKind::Interface};
    ti.payloadInterface_.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeAlias(SymbolAlias* sym)
{
    TypeInfo ti{TypeInfoKind::Alias};
    ti.payloadAlias_.sym = sym;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeValuePointer(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::ValuePointer, flags};
    ti.payloadTypeRef_.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeBlockPointer(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::BlockPointer, flags};
    ti.payloadTypeRef_.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeReference(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::Reference, flags};
    ti.payloadTypeRef_.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeSlice(TypeRef pointeeTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::Slice, flags};
    ti.payloadTypeRef_.typeRef = pointeeTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeArray(const std::span<uint64_t>& dims, TypeRef elementTypeRef, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::Array, flags};
    std::construct_at(&ti.payloadArray_.dims, dims.begin(), dims.end());
    ti.payloadArray_.typeRef = elementTypeRef;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeAggregate(const std::span<TypeRef>& types)
{
    TypeInfo ti{TypeInfoKind::Aggregate, TypeInfoFlagsE::Const};
    std::construct_at(&ti.payloadAggregate_.types, types.begin(), types.end());
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
}

TypeInfo TypeInfo::makeFunction(SymbolFunction* sym, TypeInfoFlags flags)
{
    TypeInfo ti{TypeInfoKind::Function, flags};
    ti.payloadFunction_.sym = sym;
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
    ti.payloadTypeRef_ = {.typeRef = typeRef};
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return ti;
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
            return payloadInt_.bits / 8;
        case TypeInfoKind::Float:
            return payloadFloat_.bits / 8;

        case TypeInfoKind::CString:
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
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
            uint64_t count = ctx.typeMgr().get(payloadArray_.typeRef).sizeOf(ctx);
            for (const uint64_t d : payloadArray_.dims)
                count *= d;
            return count;
        }

        case TypeInfoKind::Struct:
            return payloadSymStruct().sizeOf();
        case TypeInfoKind::Enum:
            return payloadSymEnum().sizeOf(ctx);
        case TypeInfoKind::Alias:
            return payloadSymAlias().sizeOf(ctx);

        case TypeInfoKind::Variadic:
        case TypeInfoKind::TypedVariadic:
            return 0;

        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(payloadTypeRef_.typeRef).sizeOf(ctx);

        case TypeInfoKind::Aggregate:
        {
            uint64_t size  = 0;
            uint32_t align = 1;
            for (const TypeRef tr : payloadAggregate_.types)
            {
                const TypeInfo& ty = ctx.typeMgr().get(tr);
                const uint32_t  a  = ty.alignOf(ctx);
                const uint64_t  s  = ty.sizeOf(ctx);
                align              = std::max(align, a);
                size               = ((size + static_cast<uint64_t>(a) - 1) / static_cast<uint64_t>(a)) * static_cast<uint64_t>(a);
                size += s;
            }
            size = ((size + static_cast<uint64_t>(align) - 1) / static_cast<uint64_t>(align)) * static_cast<uint64_t>(align);
            return size;
        }

        default:
            SWC_UNREACHABLE();
    }
}

uint32_t TypeInfo::alignOf(TaskContext& ctx) const
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
        case TypeInfoKind::Float:
            return static_cast<uint32_t>(sizeOf(ctx));
        case TypeInfoKind::CString:
        case TypeInfoKind::ValuePointer:
        case TypeInfoKind::BlockPointer:
        case TypeInfoKind::Reference:
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
            return 8;

        case TypeInfoKind::Aggregate:
        {
            uint32_t align = 1;
            for (const TypeRef tr : payloadAggregate_.types)
                align = std::max(align, ctx.typeMgr().get(tr).alignOf(ctx));
            return align;
        }

        case TypeInfoKind::Array:
            return ctx.typeMgr().get(payloadArray_.typeRef).alignOf(ctx);

        case TypeInfoKind::Struct:
            return payloadSymStruct().alignment();
        case TypeInfoKind::Enum:
            return payloadSymEnum().underlyingType(ctx).alignOf(ctx);
        case TypeInfoKind::Alias:
            return payloadSymAlias().type(ctx).alignOf(ctx);

        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(payloadTypeRef_.typeRef).alignOf(ctx);

        default:
            SWC_UNREACHABLE();
    }
}

bool TypeInfo::isCompleted(TaskContext& ctx) const
{
    switch (kind_)
    {
        case TypeInfoKind::Struct:
            return payloadSymStruct().isCompleted();
        case TypeInfoKind::Enum:
            return payloadSymEnum().isCompleted();
        case TypeInfoKind::Interface:
            return payloadSymInterface().isCompleted();
        case TypeInfoKind::Alias:
            return payloadSymAlias().isCompleted();

        case TypeInfoKind::Array:
            return ctx.typeMgr().get(payloadArray_.typeRef).isCompleted(ctx);
        case TypeInfoKind::Function:
        {
            if (payloadFunction_.sym->returnTypeRef().isValid() && !ctx.typeMgr().get(payloadFunction_.sym->returnTypeRef()).isCompleted(ctx))
                return false;
            for (const auto& param : payloadFunction_.sym->parameters())
                if (!ctx.typeMgr().get(param->typeRef()).isCompleted(ctx))
                    return false;
            return true;
        }
        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(payloadTypeRef_.typeRef).isCompleted(ctx);
        case TypeInfoKind::TypedVariadic:
            return ctx.typeMgr().get(payloadTypeRef_.typeRef).isCompleted(ctx);
        case TypeInfoKind::Aggregate:
            for (const TypeRef tr : payloadAggregate_.types)
                if (!ctx.typeMgr().get(tr).isCompleted(ctx))
                    return false;
            return true;
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
            return &payloadSymStruct();
        case TypeInfoKind::Enum:
            return &payloadSymEnum();
        case TypeInfoKind::Interface:
            return &payloadSymInterface();
        case TypeInfoKind::Alias:
            return &payloadSymAlias();

        case TypeInfoKind::Array:
            return ctx.typeMgr().get(payloadArray_.typeRef).getSymbolDependency(ctx);
        case TypeInfoKind::Function:
        {
            if (payloadFunction_.sym->returnTypeRef().isValid())
            {
                if (const auto sym = ctx.typeMgr().get(payloadFunction_.sym->returnTypeRef()).getSymbolDependency(ctx))
                    return sym;
            }
            for (const auto& param : payloadFunction_.sym->parameters())
            {
                if (const auto sym = ctx.typeMgr().get(param->typeRef()).getSymbolDependency(ctx))
                    return sym;
            }
            return nullptr;
        }
        case TypeInfoKind::TypeValue:
            return ctx.typeMgr().get(payloadTypeRef_.typeRef).getSymbolDependency(ctx);
        case TypeInfoKind::Aggregate:
            for (const TypeRef tr : payloadAggregate_.types)
                if (auto* sym = ctx.typeMgr().get(tr).getSymbolDependency(ctx))
                    return sym;
            return nullptr;
        default:
            break;
    }

    return nullptr;
}

bool TypeInfo::isEnumFlags() const noexcept
{
    return isEnum() && payloadEnum_.sym->isEnumFlags();
}

bool TypeInfo::isLambdaClosure() const noexcept
{
    return isFunction() && payloadFunction_.sym->hasExtraFlag(SymbolFunctionFlagsE::Closure);
}

bool TypeInfo::isLambdaMethod() const noexcept
{
    return isFunction() && payloadFunction_.sym->hasExtraFlag(SymbolFunctionFlagsE::Method);
}

bool TypeInfo::isAnyTypeInfo(TaskContext& ctx) const noexcept
{
    if (isTypeInfo())
        return true;
    if (!isConst())
        return false;
    if (!isValuePointer())
        return false;
    const TypeInfo& type = ctx.typeMgr().get(payloadTypeRef_.typeRef);
    if (!type.isStruct())
        return false;
    return type.payloadSymStruct().hasExtraFlag(SymbolStructFlagsE::TypeInfo);
}

TypeRef TypeInfo::unwrap(const TaskContext& ctx, TypeRef defaultTypeRef, TypeExpand expandFlags) const noexcept
{
    auto result = typeRef_;

    while (true)
    {
        const TypeInfo& ty  = ctx.typeMgr().get(result);
        TypeRef         sub = TypeRef::invalid();

        if (expandFlags.has(TypeExpandE::Alias) && ty.isAlias())
            sub = ty.payloadAlias_.sym->underlyingTypeRef();
        else if (expandFlags.has(TypeExpandE::Enum) && ty.isEnum())
            sub = ty.payloadEnum_.sym->underlyingTypeRef();
        else if (expandFlags.has(TypeExpandE::Pointer) && ty.isAnyPointer())
            sub = ty.payloadTypeRef_.typeRef;
        else if (expandFlags.has(TypeExpandE::Aggregate) && ty.isAggregate())
            sub = TypeRef::invalid();
        else if (expandFlags.has(TypeExpandE::Array) && ty.isArray())
            sub = ty.payloadArray_.typeRef;
        else if (expandFlags.has(TypeExpandE::Slice) && ty.isSlice())
            sub = ty.payloadTypeRef_.typeRef;
        else if (expandFlags.has(TypeExpandE::Variadic) && ty.isTypedVariadic())
            sub = ty.payloadTypeRef_.typeRef;
        else if (expandFlags.has(TypeExpandE::Function) && ty.isFunction())
            sub = ty.payloadFunction_.sym->returnTypeRef();

        if (sub.isInvalid())
            break;
        result = sub;
    }

    if (result == typeRef_)
        return defaultTypeRef;
    return result;
}

// ReSharper disable once CppPossiblyUninitializedMember
TypeInfo::TypeInfo(TypeInfoKind kind, TypeInfoFlags flags) :
    kind_(kind),
    flags_(flags)
{
}

SWC_END_NAMESPACE();
