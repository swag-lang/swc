#include "pch.h"
#include "Sema/Constant/ConstantValue.h"
#include "Main/TaskContext.h"
#include "Math/Hash.h"
#include "Report/LogColor.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

const TypeInfo& ConstantValue::type(const TaskContext& ctx) const
{
    return ctx.typeMgr().get(typeRef_);
}

ConstantValue ConstantValue::makeBool(const TaskContext& ctx, bool value)
{
    ConstantValue cv;
    cv.typeRef_   = ctx.typeMgr().getTypeBool();
    cv.kind_      = ConstantKind::Bool;
    cv.asBool.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeString(const TaskContext& ctx, std::string_view value)
{
    ConstantValue cv;
    cv.typeRef_     = ctx.typeMgr().getTypeString();
    cv.kind_        = ConstantKind::String;
    cv.asString.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeChar(const TaskContext& ctx, char32_t value)
{
    ConstantValue cv;
    cv.typeRef_       = ctx.typeMgr().getTypeChar();
    cv.kind_          = ConstantKind::Char;
    cv.asCharRune.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeRune(const TaskContext& ctx, char32_t value)
{
    ConstantValue cv;
    cv.typeRef_       = ctx.typeMgr().getTypeRune();
    cv.kind_          = ConstantKind::Rune;
    cv.asCharRune.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeTypeInfo(TaskContext& ctx, TypeRef value)
{
    ConstantValue cv;
    cv.typeRef_       = ctx.typeMgr().addType(TypeInfo::makeTypeInfo(value));
    cv.kind_          = ConstantKind::TypeInfo;
    cv.asTypeInfo.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeInt(const TaskContext& ctx, const ApsInt& value, uint32_t bitWidth)
{
    if (!bitWidth)
        return makeIntUnsized(ctx, value);

    ConstantValue cv;
    cv.typeRef_  = ctx.typeMgr().getTypeInt(bitWidth, value.isUnsigned());
    cv.kind_     = ConstantKind::Int;
    cv.asInt.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeIntUnsized(const TaskContext& ctx, const ApsInt& value)
{
    SWC_ASSERT(value.bitWidth() == ApInt::maxBitWidth());

    ConstantValue cv;
    cv.typeRef_  = ctx.typeMgr().getTypeInt(0, value.isUnsigned());
    cv.kind_     = ConstantKind::Int;
    cv.asInt.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeFloat(const TaskContext& ctx, const ApFloat& value, uint32_t bitWidth)
{
    if (!bitWidth)
        return makeFloatUnsized(ctx, value);

    ConstantValue cv;
    cv.typeRef_    = ctx.typeMgr().getTypeFloat(bitWidth);
    cv.kind_       = ConstantKind::Float;
    cv.asFloat.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeFloatUnsized(const TaskContext& ctx, const ApFloat& value)
{
    SWC_ASSERT(value.bitWidth() == ApFloat::maxBitWidth());

    ConstantValue cv;
    cv.typeRef_    = ctx.typeMgr().getTypeFloat(0);
    cv.kind_       = ConstantKind::Float;
    cv.asFloat.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

bool ConstantValue::operator==(const ConstantValue& rhs) const noexcept
{
    if (kind_ != rhs.kind_)
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
        case ConstantKind::TypeInfo:
            return getTypeIndo() == rhs.getTypeIndo();

        case ConstantKind::Int:
            return typeRef_ == rhs.typeRef_ && getInt().same(rhs.getInt());
        case ConstantKind::Float:
            return typeRef_ == rhs.typeRef_ && getFloat().same(rhs.getFloat());

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
        case ConstantKind::Int:
            return getInt().eq(rhs.getInt());
        case ConstantKind::Float:
            return getFloat().eq(rhs.getFloat());
        case ConstantKind::TypeInfo:
            return getTypeIndo() == rhs.getTypeIndo();

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
        case ConstantKind::Int:
            return getInt().toString();
        case ConstantKind::Float:
            return getFloat().toString();
        case ConstantKind::TypeInfo:
            return ctx.typeMgr().typeToName(getTypeIndo());

        default:
            SWC_UNREACHABLE();
    }
}

uint32_t ConstantValue::hash() const noexcept
{
    auto h = Math::hash(static_cast<uint32_t>(kind_));
    switch (kind_)
    {
        case ConstantKind::Bool:
            h = Math::hashCombine(h, asBool.val);
            break;
        case ConstantKind::Char:
            h = Math::hashCombine(h, Math::hash(asCharRune.val));
            break;
        case ConstantKind::Rune:
            h = Math::hashCombine(h, Math::hash(asCharRune.val));
            break;
        case ConstantKind::String:
            h = Math::hashCombine(h, Math::hash(asString.val));
            break;
        case ConstantKind::TypeInfo:
            h = Math::hashCombine(h, asTypeInfo.val.get());
            break;
        case ConstantKind::Int:
            h = Math::hashCombine(h, typeRef_.get());
            h = Math::hashCombine(h, asInt.val.hash());
            break;
        case ConstantKind::Float:
            h = Math::hashCombine(h, typeRef_.get());
            h = Math::hashCombine(h, asFloat.val.hash());
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
    SWC_UNREACHABLE();
}

ConstantValue ConstantValue::makeFromIntLike(const TaskContext& ctx, const ApsInt& v, const TypeInfo& ty)
{
    if (ty.isChar())
        return makeChar(ctx, static_cast<uint32_t>(v.asI64()));
    if (ty.isRune())
        return makeRune(ctx, static_cast<uint32_t>(v.asI64()));
    return makeInt(ctx, v, ty.intBits());
}

SWC_END_NAMESPACE()
