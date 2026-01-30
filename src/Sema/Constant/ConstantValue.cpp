#include "pch.h"
#include "Sema/Constant/ConstantValue.h"
#include "Main/TaskContext.h"
#include "Math/Hash.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

ConstantValue::ConstantValue()
{
}

ConstantValue::~ConstantValue()
{
    switch (kind_)
    {
        case ConstantKind::Aggregate:
            std::destroy_at(&asAggregate.val);
            break;
        default:
            break;
    }
}

ConstantValue::ConstantValue(const ConstantValue& other) :
    kind_(other.kind_),
    typeRef_(other.typeRef_)
{
    switch (kind_)
    {
        case ConstantKind::Invalid:
        case ConstantKind::Bool:
            asBool = other.asBool;
            break;
        case ConstantKind::Char:
        case ConstantKind::Rune:
            asCharRune = other.asCharRune;
            break;
        case ConstantKind::String:
            asString = other.asString;
            break;
        case ConstantKind::Struct:
            asStruct = other.asStruct;
            break;
        case ConstantKind::Int:
            asInt = other.asInt;
            break;
        case ConstantKind::Float:
            asFloat = other.asFloat;
            break;
        case ConstantKind::ValuePointer:
        case ConstantKind::BlockPointer:
            asPointer = other.asPointer;
            break;
        case ConstantKind::Slice:
            asSlice = other.asSlice;
            break;
        case ConstantKind::TypeValue:
            asTypeInfo = other.asTypeInfo;
            break;
        case ConstantKind::Null:
        case ConstantKind::Undefined:
            break;
        case ConstantKind::EnumValue:
            asEnumValue = other.asEnumValue;
            break;
        case ConstantKind::Aggregate:
            std::construct_at(&asAggregate.val, other.asAggregate.val);
            break;
        default:
            SWC_UNREACHABLE();
    }
}

ConstantValue::ConstantValue(ConstantValue&& other) noexcept :
    kind_(other.kind_),
    typeRef_(other.typeRef_)
{
    switch (kind_)
    {
        case ConstantKind::Invalid:
        case ConstantKind::Bool:
            asBool = other.asBool;
            break;
        case ConstantKind::Char:
        case ConstantKind::Rune:
            asCharRune = other.asCharRune;
            break;
        case ConstantKind::String:
            asString = other.asString;
            break;
        case ConstantKind::Struct:
            asStruct = other.asStruct;
            break;
        case ConstantKind::Int:
            asInt = other.asInt;
            break;
        case ConstantKind::Float:
            asFloat = other.asFloat;
            break;
        case ConstantKind::ValuePointer:
        case ConstantKind::BlockPointer:
            asPointer = other.asPointer;
            break;
        case ConstantKind::Slice:
            asSlice = other.asSlice;
            break;
        case ConstantKind::TypeValue:
            asTypeInfo = other.asTypeInfo;
            break;
        case ConstantKind::Null:
        case ConstantKind::Undefined:
            break;
        case ConstantKind::EnumValue:
            asEnumValue = other.asEnumValue;
            break;
        case ConstantKind::Aggregate:
            std::construct_at(&asAggregate.val, std::move(other.asAggregate.val));
            break;
        default:
            SWC_UNREACHABLE();
    }

    other.kind_ = ConstantKind::Invalid;
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

    switch (kind_)
    {
        case ConstantKind::Bool:
            return getBool() == rhs.getBool();
        case ConstantKind::Char:
            return getChar() == rhs.getChar();
        case ConstantKind::Rune:
            return getRune() == rhs.getRune();
        case ConstantKind::String:
            return getString() == rhs.getString();
        case ConstantKind::Struct:
            return getStruct() == rhs.getStruct();
        case ConstantKind::TypeValue:
            return getTypeValue() == rhs.getTypeValue();
        case ConstantKind::EnumValue:
            return getEnumValue() == rhs.getEnumValue();
        case ConstantKind::Aggregate:
            return getAggregate() == rhs.getAggregate();
        case ConstantKind::Int:
            return getInt().same(rhs.getInt());
        case ConstantKind::Float:
            return getFloat().same(rhs.getFloat());
        case ConstantKind::ValuePointer:
            return getValuePointer() == rhs.getValuePointer();
        case ConstantKind::BlockPointer:
            return getBlockPointer() == rhs.getBlockPointer();
        case ConstantKind::Slice:
            return getSlicePointer() == rhs.getSlicePointer() && getSliceCount() == rhs.getSliceCount();
        case ConstantKind::Null:
            return true;
        case ConstantKind::Undefined:
            return true;

        default:
            SWC_UNREACHABLE();
    }
}

bool ConstantValue::eq(const ConstantValue& rhs) const noexcept
{
    SWC_ASSERT(kind_ == rhs.kind_);
    switch (kind_)
    {
        case ConstantKind::Bool:
            return getBool() == rhs.getBool();
        case ConstantKind::Char:
            return getChar() == rhs.getChar();
        case ConstantKind::Rune:
            return getRune() == rhs.getRune();
        case ConstantKind::String:
            return getString() == rhs.getString();
        case ConstantKind::Struct:
            return getStruct() == rhs.getStruct();
        case ConstantKind::Aggregate:
            return getAggregate() == rhs.getAggregate();
        case ConstantKind::Int:
            return getInt().eq(rhs.getInt());
        case ConstantKind::Float:
            return getFloat().eq(rhs.getFloat());
        case ConstantKind::TypeValue:
            return getTypeValue() == rhs.getTypeValue();
        case ConstantKind::Null:
            return true;
        case ConstantKind::Undefined:
            return true;
        case ConstantKind::ValuePointer:
            return getValuePointer() == rhs.getValuePointer();
        case ConstantKind::BlockPointer:
            return getBlockPointer() == rhs.getBlockPointer();
        case ConstantKind::Slice:
            return getSlicePointer() == rhs.getSlicePointer() && getSliceCount() == rhs.getSliceCount();

        default:
            SWC_UNREACHABLE();
    }
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
    cv.typeRef_   = ctx.typeMgr().typeBool();
    cv.kind_      = ConstantKind::Bool;
    cv.asBool.val = value;
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
    cv.typeRef_     = ctx.typeMgr().typeString();
    cv.kind_        = ConstantKind::String;
    cv.asString.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeChar(const TaskContext& ctx, char32_t value)
{
    ConstantValue cv;
    cv.typeRef_       = ctx.typeMgr().typeChar();
    cv.kind_          = ConstantKind::Char;
    cv.asCharRune.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeRune(const TaskContext& ctx, char32_t value)
{
    ConstantValue cv;
    cv.typeRef_       = ctx.typeMgr().typeRune();
    cv.kind_          = ConstantKind::Rune;
    cv.asCharRune.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeTypeValue(TaskContext& ctx, TypeRef value)
{
    ConstantValue cv;
    cv.typeRef_       = ctx.typeMgr().addType(TypeInfo::makeTypeValue(value));
    cv.kind_          = ConstantKind::TypeValue;
    cv.asTypeInfo.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeInt(const TaskContext& ctx, const ApsInt& value, uint32_t bitWidth, TypeInfo::Sign sign)
{
    if (!bitWidth)
        return makeIntUnsized(ctx, value, sign);

    ConstantValue cv;
    cv.typeRef_  = ctx.typeMgr().typeInt(bitWidth, sign);
    cv.kind_     = ConstantKind::Int;
    cv.asInt.val = value;
    cv.asInt.val.setUnsigned(sign == TypeInfo::Sign::Unsigned);
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeIntUnsized(const TaskContext& ctx, const ApsInt& value, TypeInfo::Sign sign)
{
    SWC_ASSERT(value.bitWidth() == ApInt::maxBitWidth());

    ConstantValue cv;
    cv.typeRef_  = ctx.typeMgr().typeInt(0, sign);
    cv.kind_     = ConstantKind::Int;
    cv.asInt.val = value;
    cv.asInt.val.setUnsigned(sign == TypeInfo::Sign::Unsigned);
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeFloat(const TaskContext& ctx, const ApFloat& value, uint32_t bitWidth)
{
    if (!bitWidth)
        return makeFloatUnsized(ctx, value);

    ConstantValue cv;
    cv.typeRef_    = ctx.typeMgr().typeFloat(bitWidth);
    cv.kind_       = ConstantKind::Float;
    cv.asFloat.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeFloatUnsized(const TaskContext& ctx, const ApFloat& value)
{
    SWC_ASSERT(value.bitWidth() == ApFloat::maxBitWidth());

    ConstantValue cv;
    cv.typeRef_    = ctx.typeMgr().typeFloat(0);
    cv.kind_       = ConstantKind::Float;
    cv.asFloat.val = value;
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
    cv.typeRef_        = typeRef;
    cv.kind_           = ConstantKind::EnumValue;
    cv.asEnumValue.val = valueCst;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeStruct(const TaskContext&, TypeRef typeRef, std::string_view bytes)
{
    ConstantValue cv;
    cv.typeRef_     = typeRef;
    cv.kind_        = ConstantKind::Struct;
    cv.asStruct.val = bytes;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeAggregate(TaskContext& ctx, TypeRef typeRef, const std::vector<ConstantRef>& values)
{
    ConstantValue  cv;
    const TypeInfo aggTy = TypeInfo::makeAggregate(typeRef);
    cv.typeRef_          = ctx.typeMgr().addType(aggTy);
    cv.kind_             = ConstantKind::Aggregate;
    std::construct_at(&cv.asAggregate.val, values);
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeValuePointer(TaskContext& ctx, TypeRef typeRef, uint64_t value, TypeInfoFlagsE flags)
{
    ConstantValue  cv;
    const TypeInfo ty = TypeInfo::makeValuePointer(typeRef, flags);
    cv.typeRef_       = ctx.typeMgr().addType(ty);
    cv.kind_          = ConstantKind::ValuePointer;
    cv.asPointer.val  = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeBlockPointer(TaskContext& ctx, TypeRef typeRef, uint64_t value, TypeInfoFlagsE flags)
{
    ConstantValue  cv;
    const TypeInfo ty = TypeInfo::makeBlockPointer(typeRef, flags);
    cv.typeRef_       = ctx.typeMgr().addType(ty);
    cv.kind_          = ConstantKind::BlockPointer;
    cv.asPointer.val  = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeSlice(TaskContext& ctx, TypeRef typeRef, uint64_t ptr, uint64_t count, TypeInfoFlagsE flags)
{
    ConstantValue  cv;
    const TypeInfo ty = TypeInfo::makeSlice(typeRef, flags);
    cv.typeRef_       = ctx.typeMgr().addType(ty);
    cv.kind_          = ConstantKind::Slice;
    cv.asSlice.ptr    = ptr;
    cv.asSlice.count  = count;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

uint32_t ConstantValue::hash() const noexcept
{
    auto h = Math::hash(static_cast<uint32_t>(kind_));
    h      = Math::hashCombine(h, typeRef_.get());
    switch (kind_)
    {
        case ConstantKind::Bool:
            h = Math::hashCombine(h, asBool.val);
            break;
        case ConstantKind::Char:
        case ConstantKind::Rune:
            h = Math::hashCombine(h, asCharRune.val);
            break;
        case ConstantKind::String:
            h = Math::hashCombine(h, Math::hash(asString.val));
            break;
        case ConstantKind::Struct:
            h = Math::hashCombine(h, Math::hash(asStruct.val));
            break;
        case ConstantKind::Aggregate:
            for (auto& v : getAggregate())
                h = Math::hashCombine(h, v.get());
            break;
        case ConstantKind::TypeValue:
            h = Math::hashCombine(h, asTypeInfo.val.get());
            break;
        case ConstantKind::Int:
            h = Math::hashCombine(h, asInt.val.hash());
            break;
        case ConstantKind::Float:
            h = Math::hashCombine(h, asFloat.val.hash());
            break;
        case ConstantKind::ValuePointer:
        case ConstantKind::BlockPointer:
            h = Math::hashCombine(h, asPointer.val);
            break;
        case ConstantKind::Slice:
            h = Math::hashCombine(h, asSlice.ptr);
            h = Math::hashCombine(h, asSlice.count);
            break;
        case ConstantKind::Null:
        case ConstantKind::Undefined:
            break;
        case ConstantKind::EnumValue:
            h = Math::hashCombine(h, asEnumValue.val.get());
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
        case ConstantKind::Aggregate:
            return "<aggregate>";
        case ConstantKind::Int:
            return getInt().toString();
        case ConstantKind::Float:
            return getFloat().toString();
        case ConstantKind::TypeValue:
            return ctx.typeMgr().get(getTypeValue()).toName(ctx);
        case ConstantKind::EnumValue:
            return ctx.cstMgr().get(asEnumValue.val).toString(ctx);
        case ConstantKind::ValuePointer:
            return std::format("*0x{:016X}", getValuePointer());
        case ConstantKind::BlockPointer:
            return std::format("[*] 0x{:016X}", getBlockPointer());
        case ConstantKind::Slice:
            return std::format("[..] (0x{:016X}, {})", getSlicePointer(), getSliceCount());
        case ConstantKind::Null:
            return "null";
        case ConstantKind::Undefined:
            return "undefined";

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
