#include "pch.h"
#include "Math/ApValue.h"
#include "Core/hash.h"
#include "Main/TaskContext.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

const TypeInfo& ApValue::type(const TaskContext& ctx) const
{
    return ctx.compiler().typeMgr().getType(typeRef_);
}

ApValue ApValue::makeBool(const TaskContext& ctx, bool value)
{
    ApValue cv;
    cv.typeRef_  = ctx.compiler().typeMgr().getTypeBool();
    cv.kind_     = ConstantKind::Bool;
    cv.bool_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ApValue ApValue::makeString(const TaskContext& ctx, std::string_view value)
{
    ApValue cv;
    cv.typeRef_    = ctx.compiler().typeMgr().getTypeString();
    cv.kind_       = ConstantKind::String;
    cv.string_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

ApValue ApValue::makeInt(const TaskContext& ctx, const ApInt& value, uint32_t bits, bool isSigned)
{
    ApValue cv;
    cv.typeRef_ = ctx.compiler().typeMgr().getTypeInt(bits, isSigned);
    cv.kind_    = ConstantKind::Int;
    cv.int_.val = value;
    cv.int_.sig = isSigned;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

bool ApValue::operator==(const ApValue& other) const noexcept
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
            return getInt().equals(other.getInt());
        case ConstantKind::Float:
            return getFloat().equals(other.getFloat());            

        default:
            SWC_UNREACHABLE();
    }
}

Utf8 ApValue::toString() const
{
    switch (kind_)
    {
        case ConstantKind::Bool:
            return getBool() ? "true" : "false";
        case ConstantKind::String:
            return getString();
        case ConstantKind::Int:
            return "???";
        case ConstantKind::Float:
            return "???";            

        default:
            SWC_UNREACHABLE();
    }
}

size_t ConstantValueHash::operator()(const ApValue& v) const noexcept
{
    auto h = std::hash<int>()(static_cast<int>(v.kind()));

    switch (v.kind())
    {
        case ConstantKind::Bool:
            h = hash_combine(h, v.bool_.val);
            break;
        case ConstantKind::String:
            h = hash_combine(h, hash(v.string_.val));
            break;
        case ConstantKind::Int:
            h = hash_combine(h, v.int_.val.hash());
            break;
        case ConstantKind::Float:
            h = hash_combine(h, v.float_.val.hash());
            break;            

        default:
            SWC_UNREACHABLE();
    }

    return h;
}

SWC_END_NAMESPACE()
