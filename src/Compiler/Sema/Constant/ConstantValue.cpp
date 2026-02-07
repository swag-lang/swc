#include "pch.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Runtime/Runtime.h"
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class NumericCmp
    {
        Same,
        Eq,
    };

    bool compareSameKind(const ConstantValue& lhs, const ConstantValue& rhs, NumericCmp numericCmp) noexcept
    {
        SWC_ASSERT(lhs.kind() == rhs.kind());
        switch (lhs.kind())
        {
            case ConstantKind::Bool:
                return lhs.getBool() == rhs.getBool();
            case ConstantKind::Char:
                return lhs.getChar() == rhs.getChar();
            case ConstantKind::Rune:
                return lhs.getRune() == rhs.getRune();
            case ConstantKind::String:
                return lhs.getString() == rhs.getString();
            case ConstantKind::Struct:
                return lhs.getStruct().data() == rhs.getStruct().data();
            case ConstantKind::AggregateArray:
            case ConstantKind::AggregateStruct:
                return lhs.getAggregate() == rhs.getAggregate();
            case ConstantKind::Int:
                return numericCmp == NumericCmp::Same ? lhs.getInt().same(rhs.getInt()) : lhs.getInt().eq(rhs.getInt());
            case ConstantKind::Float:
                return numericCmp == NumericCmp::Same ? lhs.getFloat().same(rhs.getFloat()) : lhs.getFloat().eq(rhs.getFloat());
            case ConstantKind::TypeValue:
                return lhs.getTypeValue() == rhs.getTypeValue();
            case ConstantKind::EnumValue:
                return lhs.getEnumValue() == rhs.getEnumValue();
            case ConstantKind::ValuePointer:
                return lhs.getValuePointer() == rhs.getValuePointer();
            case ConstantKind::BlockPointer:
                return lhs.getBlockPointer() == rhs.getBlockPointer();
            case ConstantKind::Slice:
                return lhs.getSlice().data() == rhs.getSlice().data();
            case ConstantKind::Null:
                return true;
            case ConstantKind::Undefined:
                return true;

            default:
                SWC_UNREACHABLE();
        }
    }
}

// ReSharper disable once CppPossiblyUninitializedMember
ConstantValue::ConstantValue()
{
}

ConstantValue::ConstantValue(const ConstantValue& other) :
    kind_(other.kind_),
    typeRef_(other.typeRef_),
    payloadBorrowed_(other.payloadBorrowed_)
{
    switch (kind_)
    {
        case ConstantKind::Invalid:
        case ConstantKind::Bool:
            payloadBool_ = other.payloadBool_;
            break;
        case ConstantKind::Char:
        case ConstantKind::Rune:
            payloadCharRune_ = other.payloadCharRune_;
            break;
        case ConstantKind::String:
            payloadString_ = other.payloadString_;
            break;
        case ConstantKind::Struct:
            payloadStruct_ = other.payloadStruct_;
            break;
        case ConstantKind::Int:
            payloadInt_ = other.payloadInt_;
            break;
        case ConstantKind::Float:
            payloadFloat_ = other.payloadFloat_;
            break;
        case ConstantKind::ValuePointer:
        case ConstantKind::BlockPointer:
            payloadPointer_ = other.payloadPointer_;
            break;
        case ConstantKind::Slice:
            payloadSlice_ = other.payloadSlice_;
            break;
        case ConstantKind::TypeValue:
            payloadTypeValue_ = other.payloadTypeValue_;
            break;
        case ConstantKind::Null:
        case ConstantKind::Undefined:
            break;
        case ConstantKind::EnumValue:
            payloadEnumValue_ = other.payloadEnumValue_;
            break;
        case ConstantKind::AggregateArray:
        case ConstantKind::AggregateStruct:
            std::construct_at(&payloadAggregate_.val, other.payloadAggregate_.val);
            break;
        default:
            SWC_UNREACHABLE();
    }
}

ConstantValue::ConstantValue(ConstantValue&& other) noexcept :
    kind_(other.kind_),
    typeRef_(other.typeRef_),
    payloadBorrowed_(other.payloadBorrowed_)
{
    switch (kind_)
    {
        case ConstantKind::Invalid:
        case ConstantKind::Bool:
            payloadBool_ = other.payloadBool_;
            break;
        case ConstantKind::Char:
        case ConstantKind::Rune:
            payloadCharRune_ = other.payloadCharRune_;
            break;
        case ConstantKind::String:
            payloadString_ = other.payloadString_;
            break;
        case ConstantKind::Struct:
            payloadStruct_ = other.payloadStruct_;
            break;
        case ConstantKind::Int:
            payloadInt_ = other.payloadInt_;
            break;
        case ConstantKind::Float:
            payloadFloat_ = other.payloadFloat_;
            break;
        case ConstantKind::ValuePointer:
        case ConstantKind::BlockPointer:
            payloadPointer_ = other.payloadPointer_;
            break;
        case ConstantKind::Slice:
            payloadSlice_ = other.payloadSlice_;
            break;
        case ConstantKind::TypeValue:
            payloadTypeValue_ = other.payloadTypeValue_;
            break;
        case ConstantKind::Null:
        case ConstantKind::Undefined:
            break;
        case ConstantKind::EnumValue:
            payloadEnumValue_ = other.payloadEnumValue_;
            break;
        case ConstantKind::AggregateArray:
        case ConstantKind::AggregateStruct:
            std::construct_at(&payloadAggregate_.val, std::move(other.payloadAggregate_.val));
            break;
        default:
            SWC_UNREACHABLE();
    }

    other.kind_            = ConstantKind::Invalid;
    other.payloadBorrowed_ = false;
}

ConstantValue::~ConstantValue()
{
    switch (kind_)
    {
        case ConstantKind::AggregateArray:
        case ConstantKind::AggregateStruct:
            std::destroy_at(&payloadAggregate_.val);
            break;
        default:
            break;
    }
}

ConstantValue& ConstantValue::operator=(const ConstantValue& other)
{
    if (this == &other)
        return *this;
    this->~ConstantValue();
    new (this) ConstantValue(other);
    return *this;
}

ConstantValue& ConstantValue::operator=(ConstantValue&& other) noexcept
{
    if (this == &other)
        return *this;
    this->~ConstantValue();
    new (this) ConstantValue(std::move(other));
    return *this;
}

bool ConstantValue::operator==(const ConstantValue& rhs) const noexcept
{
    if (kind_ != rhs.kind_)
        return false;
    if (typeRef_ != rhs.typeRef_)
        return false;

    return compareSameKind(*this, rhs, NumericCmp::Same);
}

bool ConstantValue::eq(const ConstantValue& rhs) const noexcept
{
    SWC_ASSERT(kind_ == rhs.kind_);

    return compareSameKind(*this, rhs, NumericCmp::Eq);
}

bool ConstantValue::lt(const ConstantValue& rhs) const noexcept
{
    SWC_ASSERT(kind_ == rhs.kind_);
    switch (kind_)
    {
        case ConstantKind::Int:
            return getInt().lt(rhs.getInt());
        case ConstantKind::Float:
            return getFloat().lt(rhs.getFloat());
        case ConstantKind::Char:
            return getChar() < rhs.getChar();
        case ConstantKind::Rune:
            return getRune() < rhs.getRune();

        default:
            SWC_UNREACHABLE();
    }
}

bool ConstantValue::le(const ConstantValue& rhs) const noexcept
{
    SWC_ASSERT(kind_ == rhs.kind_);
    switch (kind_)
    {
        case ConstantKind::Int:
            return getInt().le(rhs.getInt());
        case ConstantKind::Float:
            return getFloat().le(rhs.getFloat());
        case ConstantKind::Char:
            return getChar() <= rhs.getChar();
        case ConstantKind::Rune:
            return getRune() <= rhs.getRune();

        default:
            SWC_UNREACHABLE();
    }
}

bool ConstantValue::gt(const ConstantValue& rhs) const noexcept
{
    SWC_ASSERT(kind_ == rhs.kind_);
    switch (kind_)
    {
        case ConstantKind::Int:
            return getInt().gt(rhs.getInt());
        case ConstantKind::Float:
            return getFloat().gt(rhs.getFloat());
        case ConstantKind::Char:
            return getChar() > rhs.getChar();
        case ConstantKind::Rune:
            return getRune() > rhs.getRune();

        default:
            SWC_UNREACHABLE();
    }
}

const TypeInfo& ConstantValue::type(const TaskContext& ctx) const
{
    return ctx.typeMgr().get(typeRef_);
}

ConstantValue ConstantValue::makeBool(const TaskContext& ctx, bool value)
{
    ConstantValue cv;
    cv.typeRef_         = ctx.typeMgr().typeBool();
    cv.kind_            = ConstantKind::Bool;
    cv.payloadBool_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeNull(const TaskContext& ctx)
{
    ConstantValue cv;
    cv.typeRef_ = ctx.typeMgr().typeNull();
    cv.kind_    = ConstantKind::Null;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeUndefined(const TaskContext& ctx)
{
    ConstantValue cv;
    cv.typeRef_ = ctx.typeMgr().typeUndefined();
    cv.kind_    = ConstantKind::Undefined;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeString(const TaskContext& ctx, std::string_view value)
{
    ConstantValue cv;
    cv.typeRef_           = ctx.typeMgr().typeString();
    cv.kind_              = ConstantKind::String;
    cv.payloadString_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeChar(const TaskContext& ctx, char32_t value)
{
    ConstantValue cv;
    cv.typeRef_             = ctx.typeMgr().typeChar();
    cv.kind_                = ConstantKind::Char;
    cv.payloadCharRune_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeRune(const TaskContext& ctx, char32_t value)
{
    ConstantValue cv;
    cv.typeRef_             = ctx.typeMgr().typeRune();
    cv.kind_                = ConstantKind::Rune;
    cv.payloadCharRune_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeTypeValue(TaskContext& ctx, TypeRef value)
{
    ConstantValue cv;
    cv.typeRef_              = ctx.typeMgr().addType(TypeInfo::makeTypeValue(value));
    cv.kind_                 = ConstantKind::TypeValue;
    cv.payloadTypeValue_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeInt(const TaskContext& ctx, const ApsInt& value, uint32_t bitWidth, TypeInfo::Sign sign)
{
    if (!bitWidth)
        return makeIntUnsized(ctx, value, sign);

    ConstantValue cv;
    cv.typeRef_        = ctx.typeMgr().typeInt(bitWidth, sign);
    cv.kind_           = ConstantKind::Int;
    cv.payloadInt_.val = value;
    cv.payloadInt_.val.setUnsigned(sign == TypeInfo::Sign::Unsigned);
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeIntUnsized(const TaskContext& ctx, const ApsInt& value, TypeInfo::Sign sign)
{
    SWC_ASSERT(value.bitWidth() == ApInt::maxBitWidth());

    ConstantValue cv;
    cv.typeRef_        = ctx.typeMgr().typeInt(0, sign);
    cv.kind_           = ConstantKind::Int;
    cv.payloadInt_.val = value;
    cv.payloadInt_.val.setUnsigned(sign == TypeInfo::Sign::Unsigned);
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeFloat(const TaskContext& ctx, const ApFloat& value, uint32_t bitWidth)
{
    if (!bitWidth)
        return makeFloatUnsized(ctx, value);

    ConstantValue cv;
    cv.typeRef_          = ctx.typeMgr().typeFloat(bitWidth);
    cv.kind_             = ConstantKind::Float;
    cv.payloadFloat_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeFloatUnsized(const TaskContext& ctx, const ApFloat& value)
{
    SWC_ASSERT(value.bitWidth() == ApFloat::maxBitWidth());

    ConstantValue cv;
    cv.typeRef_          = ctx.typeMgr().typeFloat(0);
    cv.kind_             = ConstantKind::Float;
    cv.payloadFloat_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeFromIntLike(const TaskContext& ctx, const ApsInt& v, const TypeInfo& ty)
{
    if (ty.isChar())
        return makeChar(ctx, static_cast<uint32_t>(v.asI64()));
    if (ty.isRune())
        return makeRune(ctx, static_cast<uint32_t>(v.asI64()));
    return makeInt(ctx, v, ty.payloadIntBits(), ty.payloadIntSign());
}

ConstantValue ConstantValue::makeEnumValue(const TaskContext&, ConstantRef valueCst, TypeRef typeRef)
{
    ConstantValue cv;
    cv.typeRef_              = typeRef;
    cv.kind_                 = ConstantKind::EnumValue;
    cv.payloadEnumValue_.val = valueCst;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeStruct(const TaskContext&, TypeRef typeRef, ByteSpan bytes)
{
    ConstantValue cv;
    cv.typeRef_           = typeRef;
    cv.kind_              = ConstantKind::Struct;
    cv.payloadStruct_.val = bytes;
    cv.payloadBorrowed_   = false;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeStructBorrowed(const TaskContext&, TypeRef typeRef, ByteSpan bytes)
{
    ConstantValue cv;
    cv.typeRef_           = typeRef;
    cv.kind_              = ConstantKind::Struct;
    cv.payloadStruct_.val = bytes;
    cv.payloadBorrowed_   = true;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeAggregateStruct(TaskContext& ctx, const std::span<IdentifierRef>& names, const std::span<ConstantRef>& values)
{
    SWC_ASSERT(values.size() == names.size());
    ConstantValue        cv;
    std::vector<TypeRef> memberTypes;
    memberTypes.reserve(values.size());
    for (const auto& v : values)
        memberTypes.push_back(ctx.cstMgr().get(v).typeRef());

    cv.typeRef_ = ctx.typeMgr().addType(TypeInfo::makeAggregate(names, memberTypes));
    cv.kind_    = ConstantKind::AggregateStruct;
    std::construct_at(&cv.payloadAggregate_.val, values.begin(), values.end());
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeAggregateArray(TaskContext& ctx, const std::span<ConstantRef>& values)
{
    SWC_ASSERT(!values.empty());

    ConstantValue cv;
    const TypeRef elemTypeRef = ctx.cstMgr().get(values[0]).typeRef();
    SmallVector   dims        = {values.size()};
    cv.typeRef_               = ctx.typeMgr().addType(TypeInfo::makeArray(dims, elemTypeRef));
    cv.kind_                  = ConstantKind::AggregateArray;
    std::construct_at(&cv.payloadAggregate_.val, values.begin(), values.end());
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeValuePointer(TaskContext& ctx, TypeRef typeRef, uint64_t value, TypeInfoFlags flags)
{
    ConstantValue  cv;
    const TypeInfo ty      = TypeInfo::makeValuePointer(typeRef, flags);
    cv.typeRef_            = ctx.typeMgr().addType(ty);
    cv.kind_               = ConstantKind::ValuePointer;
    cv.payloadPointer_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeBlockPointer(TaskContext& ctx, TypeRef typeRef, uint64_t value, TypeInfoFlags flags)
{
    ConstantValue  cv;
    const TypeInfo ty      = TypeInfo::makeBlockPointer(typeRef, flags);
    cv.typeRef_            = ctx.typeMgr().addType(ty);
    cv.kind_               = ConstantKind::BlockPointer;
    cv.payloadPointer_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeSlice(TaskContext& ctx, TypeRef typeRef, ByteSpan bytes, TypeInfoFlags flags)
{
    ConstantValue  cv;
    const TypeInfo ty    = TypeInfo::makeSlice(typeRef, flags);
    cv.typeRef_          = ctx.typeMgr().addType(ty);
    cv.kind_             = ConstantKind::Slice;
    cv.payloadSlice_.val = bytes;
    cv.payloadBorrowed_  = false;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeSliceBorrowed(TaskContext& ctx, TypeRef typeRef, ByteSpan bytes, TypeInfoFlags flags)
{
    ConstantValue  cv;
    const TypeInfo ty    = TypeInfo::makeSlice(typeRef, flags);
    cv.typeRef_          = ctx.typeMgr().addType(ty);
    cv.kind_             = ConstantKind::Slice;
    cv.payloadSlice_.val = bytes;
    cv.payloadBorrowed_  = true;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::make(TaskContext& ctx, const void* valuePtr, TypeRef typeRef)
{
    return make(ctx, valuePtr, typeRef, PayloadOwnership::Owned);
}

ConstantValue ConstantValue::make(TaskContext& ctx, const void* valuePtr, TypeRef typeRef, PayloadOwnership ownership)
{
    SWC_ASSERT(valuePtr);

    const TypeInfo& ty = ctx.typeMgr().get(typeRef);

    if (ty.isStruct())
    {
        const auto bytes = ByteSpan{static_cast<const std::byte*>(valuePtr), ty.sizeOf(ctx)};
        if (ownership == PayloadOwnership::Borrowed)
            return makeStructBorrowed(ctx, typeRef, bytes);
        return makeStruct(ctx, typeRef, bytes);
    }

    if (ty.isBool())
    {
        return makeBool(ctx, *static_cast<const bool*>(valuePtr));
    }

    if (ty.isIntLike())
    {
        const ApsInt apsInt(static_cast<const char*>(valuePtr), ty.payloadIntLikeBits(), ty.isIntUnsigned());
        return makeFromIntLike(ctx, apsInt, ty);
    }

    if (ty.isFloat())
    {
        const ApFloat apFloat(static_cast<const char*>(valuePtr), ty.payloadFloatBits());
        return makeFloat(ctx, apFloat, ty.payloadFloatBits());
    }

    if (ty.isString())
    {
        const auto str = static_cast<const Runtime::String*>(valuePtr);
        return makeString(ctx, std::string_view(str->ptr, str->length));
    }

    if (ty.isValuePointer())
    {
        const auto val = *static_cast<const uint64_t*>(valuePtr);
        return makeValuePointer(ctx, ty.payloadTypeRef(), val, ty.flags());
    }

    if (ty.isBlockPointer())
    {
        const auto val = *static_cast<const uint64_t*>(valuePtr);
        return makeBlockPointer(ctx, ty.payloadTypeRef(), val, ty.flags());
    }

    if (ty.isSlice())
    {
        const auto     slice = static_cast<const Runtime::Slice<uint8_t>*>(valuePtr);
        const ByteSpan span{reinterpret_cast<std::byte*>(slice->ptr), slice->count};
        if (ownership == PayloadOwnership::Borrowed)
            return makeSliceBorrowed(ctx, ty.payloadTypeRef(), span);
        return makeSlice(ctx, ty.payloadTypeRef(), span);
    }

    return ConstantValue{};
}

uint32_t ConstantValue::hash() const noexcept
{
    auto h = Math::hash(static_cast<uint32_t>(kind_));
    h      = Math::hashCombine(h, typeRef_.get());
    switch (kind_)
    {
        case ConstantKind::Bool:
            h = Math::hashCombine(h, payloadBool_.val);
            break;
        case ConstantKind::Char:
        case ConstantKind::Rune:
            h = Math::hashCombine(h, payloadCharRune_.val);
            break;
        case ConstantKind::String:
            h = Math::hashCombine(h, Math::hash(payloadString_.val));
            break;
        case ConstantKind::Struct:
            h = Math::hashCombine(h, Math::hash(payloadStruct_.val));
            break;
        case ConstantKind::Slice:
            h = Math::hashCombine(h, Math::hash(payloadSlice_.val));
            break;
        case ConstantKind::AggregateArray:
        case ConstantKind::AggregateStruct:
            for (auto& v : getAggregate())
                h = Math::hashCombine(h, v.get());
            break;
        case ConstantKind::TypeValue:
            h = Math::hashCombine(h, payloadTypeValue_.val.get());
            break;
        case ConstantKind::Int:
            h = Math::hashCombine(h, payloadInt_.val.hash());
            break;
        case ConstantKind::Float:
            h = Math::hashCombine(h, payloadFloat_.val.hash());
            break;
        case ConstantKind::ValuePointer:
        case ConstantKind::BlockPointer:
            h = Math::hashCombine(h, payloadPointer_.val);
            break;
        case ConstantKind::Null:
        case ConstantKind::Undefined:
            break;
        case ConstantKind::EnumValue:
            h = Math::hashCombine(h, payloadEnumValue_.val.get());
            break;

        default:
            SWC_UNREACHABLE();
    }

    return h;
}

ApsInt ConstantValue::getIntLike() const
{
    if (isInt())
        return getInt();
    if (isChar())
        return ApsInt(getChar(), 32, true);
    if (isRune())
        return ApsInt(getRune(), 32, true);
    if (isNull())
        return ApsInt(static_cast<uint64_t>(0), 64, true);
    SWC_UNREACHABLE();
}

bool ConstantValue::ge(const ConstantValue& rhs) const noexcept
{
    SWC_ASSERT(kind_ == rhs.kind_);
    switch (kind_)
    {
        case ConstantKind::Int:
            return getInt().ge(rhs.getInt());
        case ConstantKind::Float:
            return getFloat().ge(rhs.getFloat());
        case ConstantKind::Char:
            return getChar() >= rhs.getChar();
        case ConstantKind::Rune:
            return getRune() >= rhs.getRune();

        default:
            SWC_UNREACHABLE();
    }
}

Utf8 ConstantValue::toString(const TaskContext& ctx) const
{
    switch (kind_)
    {
        case ConstantKind::Bool:
            return getBool() ? "true" : "false";

        case ConstantKind::Char:
            return getChar();

        case ConstantKind::Rune:
            return getRune();

        case ConstantKind::String:
            return getString();

        case ConstantKind::Struct:
            return "<struct>";
        case ConstantKind::AggregateArray:
            return "<array>";
        case ConstantKind::AggregateStruct:
            return "<struct>";

        case ConstantKind::Int:
            return getInt().toString();

        case ConstantKind::Float:
            return getFloat().toString();

        case ConstantKind::TypeValue:
            return ctx.typeMgr().get(getTypeValue()).toName(ctx);

        case ConstantKind::EnumValue:
            return ctx.cstMgr().get(payloadEnumValue_.val).toString(ctx);

        case ConstantKind::ValuePointer:
        {
            const auto& type = ctx.typeMgr().get(typeRef_);
            if (type.isAnyTypeInfo(const_cast<TaskContext&>(ctx)))
            {
                const auto backType = ctx.typeGen().getBackTypeRef(reinterpret_cast<const void*>(getValuePointer()));
                if (backType.isValid())
                    return ctx.typeMgr().get(backType).toName(ctx);
            }
            return std::format("*0x{:016X}", getValuePointer());
        }

        case ConstantKind::BlockPointer:
            return std::format("[*] 0x{:016X}", getBlockPointer());

        case ConstantKind::Slice:
            return std::format("[..] (0x{:016X}, {})", reinterpret_cast<uintptr_t>(getSlice().data()), getSlice().size());

        case ConstantKind::Null:
            return "null";

        case ConstantKind::Undefined:
            return "undefined";

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
