#include "pch.h"
#include "Sema/Constant/ConstantValue.h"
#include "Main/TaskContext.h"
#include "Math/Hash.h"
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

ConstantValue ConstantValue::makeInt(const TaskContext& ctx, const ApsInt& value, uint32_t bitWidth)
{
    ConstantValue cv;
    cv.typeRef_  = ctx.typeMgr().getTypeInt(bitWidth, value.isUnsigned());
    cv.kind_     = ConstantKind::Int;
    cv.asInt.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeFloat(const TaskContext& ctx, const ApFloat& value, uint32_t bitWidth)
{
    ConstantValue cv;
    cv.typeRef_    = ctx.typeMgr().getTypeFloat(bitWidth);
    cv.kind_       = ConstantKind::Float;
    cv.asFloat.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

bool ConstantValue::operator==(const ConstantValue& other) const noexcept
{
    if (kind_ != other.kind_)
        return false;

    switch (kind_)
    {
        case ConstantKind::Bool:
            return getBool() == other.getBool();
        case ConstantKind::String:
            return getString() == other.getString();
        case ConstantKind::Int:
            return getInt().same(other.getInt());
        case ConstantKind::Float:
            return getFloat().same(other.getFloat());

        default:
            SWC_UNREACHABLE();
    }
}

bool ConstantValue::eq(const ConstantValue& other) const noexcept
{
    SWC_ASSERT(kind_ == other.kind_);
    switch (kind_)
    {
        case ConstantKind::Bool:
            return getBool() == other.getBool();
        case ConstantKind::String:
            return getString() == other.getString();
        case ConstantKind::Int:
            return getInt().eq(other.getInt());
        case ConstantKind::Float:
            return getFloat().eq(other.getFloat());

        default:
            SWC_UNREACHABLE();
    }
}

bool ConstantValue::lt(const ConstantValue& other) const noexcept
{
    SWC_ASSERT(kind_ == other.kind_);
    switch (kind_)
    {
        case ConstantKind::Int:
            return getInt().lt(other.getInt());
        case ConstantKind::Float:
            return getFloat().lt(other.getFloat());

        default:
            SWC_UNREACHABLE();
    }
}

bool ConstantValue::le(const ConstantValue& other) const noexcept
{
    SWC_ASSERT(kind_ == other.kind_);
    switch (kind_)
    {
        case ConstantKind::Int:
            return getInt().le(other.getInt());
        case ConstantKind::Float:
            return getFloat().le(other.getFloat());

        default:
            SWC_UNREACHABLE();
    }
}

bool ConstantValue::gt(const ConstantValue& other) const noexcept
{
    SWC_ASSERT(kind_ == other.kind_);
    switch (kind_)
    {
        case ConstantKind::Int:
            return getInt().gt(other.getInt());
        case ConstantKind::Float:
            return getFloat().gt(other.getFloat());

        default:
            SWC_UNREACHABLE();
    }
}

bool ConstantValue::ge(const ConstantValue& other) const noexcept
{
    SWC_ASSERT(kind_ == other.kind_);
    switch (kind_)
    {
        case ConstantKind::Int:
            return getInt().ge(other.getInt());
        case ConstantKind::Float:
            return getFloat().ge(other.getFloat());

        default:
            SWC_UNREACHABLE();
    }
}

Utf8 ConstantValue::toString() const
{
    switch (kind_)
    {
        case ConstantKind::Bool:
            return getBool() ? "true" : "false";
        case ConstantKind::String:
            return getString();
        case ConstantKind::Int:
            return getInt().toString();
        case ConstantKind::Float:
            return getFloat().toString();

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
        case ConstantKind::String:
            h = Math::hashCombine(h, Math::hash(asString.val));
            break;
        case ConstantKind::Int:
            h = Math::hashCombine(h, asInt.val.hash());
            break;
        case ConstantKind::Float:
            h = Math::hashCombine(h, asFloat.val.hash());
            break;

        default:
            SWC_UNREACHABLE();
    }

    return h;
}

SWC_END_NAMESPACE()
