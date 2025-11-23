#include "pch.h"
#include "Core/hash.h"
#include "Main/TaskContext.h"
#include "Sema/APValue.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

const TypeInfo& APValue::type(const TaskContext& ctx) const
{
    return ctx.compiler().typeMgr().getType(typeRef_);
}

APValue APValue::makeBool(const TaskContext& ctx, bool value)
{
    APValue cv;
    cv.typeRef_  = ctx.compiler().typeMgr().getTypeBool();
    cv.kind_     = ConstantKind::Bool;
    cv.bool_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

APValue APValue::makeString(const TaskContext& ctx, std::string_view value)
{
    APValue cv;
    cv.typeRef_    = ctx.compiler().typeMgr().getTypeString();
    cv.kind_       = ConstantKind::String;
    cv.string_.val = value;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

APValue APValue::makeInt(const TaskContext& ctx, const APInt& value, uint32_t bits, bool isSigned)
{
    APValue cv;
    cv.typeRef_ = ctx.compiler().typeMgr().getTypeInt(bits, isSigned);
    cv.kind_    = ConstantKind::Int;
    cv.int_.val = value;
    cv.int_.sig = isSigned;
    // ReSharper disable once CppSomeObjectMembersMightNotBeInitialized
    return cv;
}

bool APValue::operator==(const APValue& other) const noexcept
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

        default:
            SWC_UNREACHABLE();
    }
}

Utf8 APValue::toString() const
{
    switch (kind_)
    {
        case ConstantKind::Bool:
            return getBool() ? "true" : "false";
        case ConstantKind::String:
            return getString();
        case ConstantKind::Int:
            return "???";

        default:
            SWC_UNREACHABLE();
    }
}

size_t ConstantValueHash::operator()(const APValue& v) const noexcept
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

        default:
            SWC_UNREACHABLE();
    }

    return h;
}

SWC_END_NAMESPACE()
