#include "pch.h"
#include "Sema/ConstantValue.h"
#include "Core/hash.h"
#include "Main/TaskContext.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

const TypeInfo& ConstantValue::type(const TaskContext& ctx) const
{
    return ctx.compiler().typeMgr().getType(typeRef_);
}

ConstantValue ConstantValue::makeBool(const TaskContext& ctx, bool value)
{
    ConstantValue cv;
    cv.typeRef_  = ctx.compiler().typeMgr().getTypeBool();
    cv.kind_     = ConstantKind::Bool;
    cv.bool_.val = value;
    return cv;
}

ConstantValue ConstantValue::makeString(const TaskContext& ctx, std::string_view value)
{
    ConstantValue cv;
    cv.typeRef_    = ctx.compiler().typeMgr().getTypeString();
    cv.kind_       = ConstantKind::String;
    cv.string_.val = value;
    return cv;
}

ConstantValue ConstantValue::makeInt(const TaskContext& ctx, const ConstantInt& value, uint32_t bits, bool isSigned)
{
    ConstantValue cv;
    cv.typeRef_ = ctx.compiler().typeMgr().getTypeInt(bits, isSigned);
    cv.kind_    = ConstantKind::Int;
    cv.int_.val = value;
    cv.int_.sig = isSigned;
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
            return getInt().equals(other.getInt());

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
            return "???";

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
