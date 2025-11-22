#include "pch.h"
#include "Sema/ConstantValue.h"
#include "Core/hash.h"
#include "Main/TaskContext.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

const TypeInfo& ConstantValue::type(const TaskContext& ctx) const
{
    return ctx.compiler().typeMgr().get(typeRef_);
}

ConstantValue ConstantValue::makeBool(const TaskContext& ctx, bool value)
{
    ConstantValue cv;
    cv.typeRef_ = ctx.compiler().typeMgr().getBool();
    cv.kind_    = ConstantKind::Bool;
    cv.value_   = value;
    return cv;
}

ConstantValue ConstantValue::makeString(const TaskContext& ctx, std::string_view value)
{
    ConstantValue cv;
    cv.typeRef_ = ctx.compiler().typeMgr().getBool();
    cv.kind_    = ConstantKind::String;
    cv.value_   = value;
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
            h = hash_combine(h, v.getBool());
            break;

        case ConstantKind::String:
            h = hash_combine(h, hash(v.getString()));
            break;

        default:
            SWC_UNREACHABLE();
    }

    return h;
}

SWC_END_NAMESPACE()
