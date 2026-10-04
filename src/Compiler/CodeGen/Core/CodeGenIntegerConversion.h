#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroTypes.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenIntegerConversion
{
    inline void convertOperand(CodeGen& codeGen, MicroReg& outReg, const TypeInfo& srcType, MicroOpBits srcBits, MicroOpBits dstBits)
    {
        const MicroReg dstReg  = codeGen.nextVirtualIntRegister();
        MicroBuilder&  builder = codeGen.builder();
        if (srcBits == dstBits || getNumBits(srcBits) > getNumBits(dstBits))
        {
            builder.emitLoadRegReg(dstReg, outReg, dstBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isIntSigned())
            builder.emitLoadSignedExtendRegReg(dstReg, outReg, dstBits, srcBits);
        else
            builder.emitLoadZeroExtendRegReg(dstReg, outReg, dstBits, srcBits);
        outReg = dstReg;
    }
}

SWC_END_NAMESPACE();
