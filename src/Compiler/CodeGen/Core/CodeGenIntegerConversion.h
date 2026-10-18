#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroTypes.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
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

    struct ScalarOperand
    {
        const TypeInfo* type = nullptr;
        MicroOpBits     bits = MicroOpBits::Zero;
    };

    // Converts outReg between integer and float scalars, as an operand of type 'src' read as 'dst'.
    // False when the pair is not a scalar conversion, with outReg untouched.
    inline bool tryConvertScalarOperand(CodeGen& codeGen, MicroReg& outReg, const ScalarOperand& src, const ScalarOperand& dst, TypeRef dstTypeRef)
    {
        const TypeInfo&   srcType = *src.type;
        const TypeInfo&   dstType = *dst.type;
        const MicroOpBits srcBits = src.bits;
        const MicroOpBits dstBits = dst.bits;
        MicroBuilder&     builder = codeGen.builder();

        if (srcType.isIntLike() && dstType.isIntLike())
        {
            convertOperand(codeGen, outReg, srcType, srcBits, dstBits);
            return true;
        }

        if (srcType.isIntLike() && dstType.isFloat())
        {
            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef, dstType);
            CodeGenMemoryHelpers::emitConvertIntToFloat(codeGen, dstReg, outReg, srcBits, dstBits, !srcType.isIntSigned());
            outReg = dstReg;
            return true;
        }

        if (srcType.isFloat() && dstType.isFloat())
        {
            if (srcBits == dstBits)
                return true;

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef, dstType);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, outReg, MicroOp::ConvertFloatToFloat, srcBits);
            outReg = dstReg;
            return true;
        }

        return false;
    }
}

SWC_END_NAMESPACE();
