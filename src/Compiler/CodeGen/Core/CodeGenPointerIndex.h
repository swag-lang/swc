#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenPointerIndex
{
    inline MicroReg materialize(CodeGen& codeGen, const CodeGenNodePayload& operandPayload, const TypeInfo& operandType, MicroOpBits srcBits)
    {
        SWC_ASSERT(operandType.isIntLike());
        SWC_ASSERT(srcBits != MicroOpBits::Zero);

        const MicroReg resultReg = codeGen.nextVirtualIntRegister();
        MicroBuilder&  builder   = codeGen.builder();
        if (operandPayload.isAddress())
        {
            if (srcBits == MicroOpBits::B64)
                builder.emitLoadRegMem(resultReg, operandPayload.reg, 0, MicroOpBits::B64);
            else if (operandType.isIntLikeUnsigned())
                builder.emitLoadZeroExtendRegMem(resultReg, operandPayload.reg, 0, MicroOpBits::B64, srcBits);
            else
                builder.emitLoadSignedExtendRegMem(resultReg, operandPayload.reg, 0, MicroOpBits::B64, srcBits);
        }
        else
        {
            if (srcBits == MicroOpBits::B64)
                builder.emitLoadRegReg(resultReg, operandPayload.reg, MicroOpBits::B64);
            else if (operandType.isIntLikeUnsigned())
                builder.emitLoadZeroExtendRegReg(resultReg, operandPayload.reg, MicroOpBits::B64, srcBits);
            else
                builder.emitLoadSignedExtendRegReg(resultReg, operandPayload.reg, MicroOpBits::B64, srcBits);
        }

        return resultReg;
    }
}

SWC_END_NAMESPACE();
