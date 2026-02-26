#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroOpBits compareOpBits(const TypeInfo& typeInfo)
    {
        if (typeInfo.isFloat())
        {
            const uint32_t floatBits = typeInfo.payloadFloatBits() ? typeInfo.payloadFloatBits() : 64;
            return microOpBitsFromBitWidth(floatBits);
        }

        if (typeInfo.isIntLike())
        {
            const uint32_t intBits = typeInfo.payloadIntLikeBits() ? typeInfo.payloadIntLikeBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        if (typeInfo.isBool())
            return MicroOpBits::B8;

        return MicroOpBits::B64;
    }

    void materializeLogicalOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        const TypeInfo&   operandType = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits operandBits = compareOpBits(operandType);
        outReg                        = codeGen.nextVirtualRegisterForType(operandTypeRef);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, operandBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, operandBits);

        if (operandType.isBool())
            return;

        builder.emitCmpRegImm(outReg, ApInt(0, 64), operandBits);

        const MicroReg boolReg = codeGen.nextVirtualIntRegister();
        builder.emitSetCondReg(boolReg, MicroCond::NotEqual);
        outReg = boolReg;
    }
}

Result AstLogicalExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const CodeGenNodePayload& leftPayload  = codeGen.payload(nodeLeftRef);
    const CodeGenNodePayload& rightPayload = codeGen.payload(nodeRightRef);

    const SemaNodeView leftView  = codeGen.viewType(nodeLeftRef);
    const SemaNodeView rightView = codeGen.viewType(nodeRightRef);
    const TypeRef      leftType  = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();
    const TypeRef      rightType = rightPayload.typeRef.isValid() ? rightPayload.typeRef : rightView.typeRef();

    MicroReg leftReg, rightReg;
    materializeLogicalOperand(leftReg, codeGen, leftPayload, leftType);
    materializeLogicalOperand(rightReg, codeGen, rightPayload, rightType);

    const CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
    MicroBuilder&             builder     = codeGen.builder();
    builder.emitLoadRegReg(nodePayload.reg, leftReg, MicroOpBits::B8);

    const Token& tok = codeGen.token(codeRef());
    if (tok.id == TokenId::KwdAnd)
        builder.emitOpBinaryRegReg(nodePayload.reg, rightReg, MicroOp::And, MicroOpBits::B8);
    else if (tok.id == TokenId::KwdOr)
        builder.emitOpBinaryRegReg(nodePayload.reg, rightReg, MicroOp::Or, MicroOpBits::B8);
    else
        SWC_UNREACHABLE();

    return Result::Continue;
}

SWC_END_NAMESPACE();
