#pragma once
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenParameterReg
{
    inline MicroReg parameterSourcePhysReg(const CallConv& callConv, const CodeGenFunctionHelpers::FunctionParameterInfo& paramInfo)
    {
        if (paramInfo.isFloat)
        {
            SWC_ASSERT(paramInfo.registerIndex < callConv.floatArgRegs.size());
            return callConv.floatArgRegs[paramInfo.registerIndex];
        }

        SWC_ASSERT(paramInfo.registerIndex < callConv.intArgRegs.size());
        return callConv.intArgRegs[paramInfo.registerIndex];
    }
}

SWC_END_NAMESPACE();
