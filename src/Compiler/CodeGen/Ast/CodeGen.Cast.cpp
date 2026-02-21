#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isNumericIntLike(const TypeInfo& typeInfo)
    {
        return typeInfo.isIntLike() || typeInfo.isBool();
    }

    bool isNumericSigned(const TypeInfo& typeInfo)
    {
        if (typeInfo.isBool())
            return false;
        return typeInfo.isIntSigned();
    }

    MicroOpBits castPayloadBits(const TypeInfo& typeInfo)
    {
        if (typeInfo.isFloat())
        {
            const uint32_t floatBits = typeInfo.payloadFloatBits() ? typeInfo.payloadFloatBits() : 64;
            return microOpBitsFromBitWidth(floatBits);
        }

        if (typeInfo.isBool())
            return MicroOpBits::B8;

        if (typeInfo.isIntLike())
        {
            const uint32_t intBits = typeInfo.payloadIntLikeBits() ? typeInfo.payloadIntLikeBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        return MicroOpBits::Zero;
    }

    Result emitNumericCast(CodeGen& codeGen, AstNodeRef srcNodeRef, TypeRef dstTypeRef)
    {
        const CodeGenNodePayload* srcPayload = codeGen.payload(srcNodeRef);
        SWC_ASSERT(srcPayload != nullptr);

        if (dstTypeRef.isInvalid())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef);
            return Result::Continue;
        }

        if (!srcPayload->typeRef.isValid())
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const TypeInfo& srcType        = codeGen.typeMgr().get(srcPayload->typeRef);
        const TypeInfo& dstType        = codeGen.typeMgr().get(dstTypeRef);
        const bool      srcFloatType   = srcType.isFloat();
        const bool      srcIntLikeType = isNumericIntLike(srcType);
        const bool      dstFloatType   = dstType.isFloat();
        const bool      dstIntLikeType = isNumericIntLike(dstType);

        if (srcIntLikeType && dstIntLikeType)
        {
            const MicroOpBits srcOpBits = castPayloadBits(srcType);
            const MicroOpBits dstOpBits = castPayloadBits(dstType);
            SWC_ASSERT(srcOpBits != MicroOpBits::Zero);
            SWC_ASSERT(dstOpBits != MicroOpBits::Zero);

            MicroReg srcReg = srcPayload->reg;
            if (srcPayload->isAddress())
            {
                srcReg = codeGen.nextVirtualIntRegister();
                codeGen.builder().emitLoadRegMem(srcReg, srcPayload->reg, 0, srcOpBits);
            }

            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualIntRegister();

            if (dstType.isBool())
            {
                const MicroReg zeroReg = codeGen.nextVirtualIntRegister();
                codeGen.builder().emitClearReg(zeroReg, srcOpBits);
                codeGen.builder().emitCmpRegReg(srcReg, zeroReg, srcOpBits);
                codeGen.builder().emitSetCondReg(dstPayload.reg, MicroCond::NotEqual);
                return Result::Continue;
            }

            const uint32_t srcWidth = static_cast<uint32_t>(srcOpBits);
            const uint32_t dstWidth = static_cast<uint32_t>(dstOpBits);
            if (srcWidth == dstWidth)
            {
                codeGen.builder().emitLoadRegReg(dstPayload.reg, srcReg, dstOpBits);
                return Result::Continue;
            }

            if (srcWidth > dstWidth)
            {
                codeGen.builder().emitLoadRegReg(dstPayload.reg, srcReg, dstOpBits);
                return Result::Continue;
            }

            if (isNumericSigned(srcType))
            {
                codeGen.builder().emitLoadSignedExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
                return Result::Continue;
            }

            codeGen.builder().emitLoadZeroExtendRegReg(dstPayload.reg, srcReg, dstOpBits, srcOpBits);
            return Result::Continue;
        }

        if (srcPayload->typeRef == dstTypeRef)
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        if (!((srcIntLikeType && dstFloatType) || (srcFloatType && dstFloatType) || (srcFloatType && dstIntLikeType)))
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        const MicroOpBits srcOpBits = castPayloadBits(srcType);
        const MicroOpBits dstOpBits = castPayloadBits(dstType);
        if (srcOpBits == MicroOpBits::Zero || dstOpBits == MicroOpBits::Zero)
        {
            codeGen.inheritPayload(codeGen.curNodeRef(), srcNodeRef, dstTypeRef);
            return Result::Continue;
        }

        MicroReg srcReg = srcPayload->reg;
        if (srcPayload->isAddress())
        {
            srcReg = codeGen.nextVirtualRegisterForType(srcPayload->typeRef);
            codeGen.builder().emitLoadRegMem(srcReg, srcPayload->reg, 0, srcOpBits);
        }

        if (srcIntLikeType && dstFloatType)
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);
            codeGen.builder().emitClearReg(dstPayload.reg, dstOpBits);
            codeGen.builder().emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertIntToFloat, dstOpBits);
            return Result::Continue;
        }

        if (srcFloatType && dstFloatType)
        {
            CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
            dstPayload.reg                 = srcReg;
            codeGen.builder().emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertFloatToFloat, srcOpBits);
            return Result::Continue;
        }

        CodeGenNodePayload& dstPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), dstTypeRef);
        dstPayload.reg                 = codeGen.nextVirtualRegisterForType(dstTypeRef);
        codeGen.builder().emitClearReg(dstPayload.reg, dstOpBits);
        codeGen.builder().emitOpBinaryRegReg(dstPayload.reg, srcReg, MicroOp::ConvertFloatToInt, srcOpBits);

        return Result::Continue;
    }
}

Result AstAutoCastExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return emitNumericCast(codeGen, nodeExprRef, codeGen.curViewType().typeRef());
}

Result AstCastExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return emitNumericCast(codeGen, nodeExprRef, codeGen.curViewType().typeRef());
}

SWC_END_NAMESPACE();
