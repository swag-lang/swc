#pragma once
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

namespace CastConstant
{
    inline void materializeArrayPayload(Sema& sema, CastRequest& castRequest, TypeRef dstTypeRef)
    {
        if (castRequest.isConstantFolding() && castRequest.materializeConstantResult())
        {
            const ConstantValue& cst = sema.cstMgr().get(castRequest.constantFoldingSrc());
            if (cst.isArray())
                castRequest.outConstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, dstTypeRef, cst.getArray());
        }
    }

    inline ConstantRef addValuePointerConstant(Sema& sema, TypeRef dstPointeeTypeRef, TypeInfoFlags dstFlags, uint64_t ptrValue)
    {
        const ConstantValue ptrCst = ConstantValue::makeValuePointer(sema.ctx(), dstPointeeTypeRef, ptrValue, dstFlags);
        return sema.cstMgr().addConstant(sema.ctx(), ptrCst);
    }
}

SWC_END_NAMESPACE();
