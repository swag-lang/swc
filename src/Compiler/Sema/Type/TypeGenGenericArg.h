#pragma once
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Generic/GenericInstanceKey.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace TypeGenGenericArg
{
    inline TypeRef genericArgValueTypeRef(const TaskContext& ctx, const GenericInstanceKey& arg)
    {
        if (arg.typeRef.isValid())
            return arg.typeRef;
        if (arg.cstRef.isValid())
            return ctx.cstMgr().get(arg.cstRef).typeRef();
        return TypeRef::invalid();
    }
}

SWC_END_NAMESPACE();
