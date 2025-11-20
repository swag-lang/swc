#include "pch.h"
#include "Sema/ConstantValue.h"
#include "Main/TaskContext.h"
#include "TypeManager.h"

SWC_BEGIN_NAMESPACE()

const TypeInfo& ConstantValue::type(const TaskContext& ctx) const
{
    return ctx.compiler().typeMgr().get(typeRef);
}

ConstantValue ConstantValue::makeBool(const TaskContext& ctx, bool value)
{
    ConstantValue cv;
    cv.typeRef = ctx.compiler().typeMgr().getBool();
    cv.kind    = ConstantKind::Bool;
    cv.value   = value;
    return cv;
}

bool ConstantValue::operator==(const ConstantValue& other) const noexcept
{
    if (kind != other.kind)
        return false;

    switch (kind)
    {
        case ConstantKind::Bool:
            return std::get<bool>(value) == std::get<bool>(other.value);

        default:
            SWC_UNREACHABLE();
    }
}

size_t ConstantValueHash::operator()(const ConstantValue& v) const noexcept
{
    auto h = std::hash<int>()(static_cast<int>(v.kind));

    switch (v.kind)
    {
        case ConstantKind::Bool:
            return std::get<bool>(v.value);

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE()
