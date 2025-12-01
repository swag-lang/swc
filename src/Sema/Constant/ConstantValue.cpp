#include "pch.h"
#include "Sema/Constant/ConstantValue.h"
#include "Core/hash.h"
#include "Main/TaskContext.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

const TypeInfo& ConstantValue::type(const TaskContext& ctx) const
{
    return ctx.compiler().typeMgr().get(typeRef_);
}

ConstantValue ConstantValue::makeBool(const TaskContext& ctx, bool value)
{
    ConstantValue cv;
    cv.typeRef_  = ctx.compiler().typeMgr().getTypeBool();
    cv.kind_     = ConstantKind::Bool;
    cv.asBool.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeString(const TaskContext& ctx, std::string_view value)
{
    ConstantValue cv;
    cv.typeRef_    = ctx.compiler().typeMgr().getTypeString();
    cv.kind_       = ConstantKind::String;
    cv.asString.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeInt(const TaskContext& ctx, const ApsInt& value, uint32_t bitWidth)
{
    ConstantValue cv;
    cv.typeRef_ = ctx.compiler().typeMgr().getTypeInt(bitWidth, value.isUnsigned());
    cv.kind_    = ConstantKind::Int;
    cv.asInt.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ConstantValue ConstantValue::makeFloat(const TaskContext& ctx, const ApFloat& value, uint32_t bitWidth)
{
    ConstantValue cv;
    cv.typeRef_   = ctx.compiler().typeMgr().getTypeFloat(bitWidth);
    cv.kind_      = ConstantKind::Float;
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

size_t ConstantValueHash::operator()(const ConstantValue& v) const noexcept
{
    auto h = std::hash<int>()(static_cast<int>(v.kind()));

    switch (v.kind())
    {
        case ConstantKind::Bool:
            h = hash_combine(h, v.asBool.val);
            break;
        case ConstantKind::String:
            h = hash_combine(h, hash(v.asString.val));
            break;
        case ConstantKind::Int:
            h = hash_combine(h, v.asInt.val.hash());
            break;
        case ConstantKind::Float:
            h = hash_combine(h, v.asFloat.val.hash());
            break;

        default:
            SWC_UNREACHABLE();
    }

    return h;
}

SWC_END_NAMESPACE()
