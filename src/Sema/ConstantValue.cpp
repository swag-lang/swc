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

SWC_END_NAMESPACE()
