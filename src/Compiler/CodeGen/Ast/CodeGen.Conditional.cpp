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

    void materializeScalarOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        outReg = codeGen.nextVirtualRegisterForType(operandTypeRef);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }
}

Result AstConditionalExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView condView   = codeGen.viewType(nodeCondRef);
    const SemaNodeView trueView   = codeGen.viewType(nodeTrueRef);
    const SemaNodeView falseView  = codeGen.viewType(nodeFalseRef);
    const SemaNodeView resultView = codeGen.curViewType();
    SWC_ASSERT(condView.type() && trueView.type() && falseView.type() && resultView.type());

    const CodeGenNodePayload& condPayload  = codeGen.payload(nodeCondRef);
    const CodeGenNodePayload& truePayload  = codeGen.payload(nodeTrueRef);
    const CodeGenNodePayload& falsePayload = codeGen.payload(nodeFalseRef);

    const TypeRef condTypeRef   = condPayload.typeRef.isValid() ? condPayload.typeRef : condView.typeRef();
    const TypeRef resultTypeRef = resultView.typeRef();
    const TypeRef trueTypeRef   = truePayload.typeRef.isValid() ? truePayload.typeRef : trueView.typeRef();
    const TypeRef falseTypeRef  = falsePayload.typeRef.isValid() ? falsePayload.typeRef : falseView.typeRef();

    const MicroOpBits condBits   = compareOpBits(codeGen.typeMgr().get(condTypeRef));
    const MicroOpBits resultBits = compareOpBits(codeGen.typeMgr().get(resultTypeRef));
    SWC_ASSERT(condBits != MicroOpBits::Zero && resultBits != MicroOpBits::Zero);

    MicroReg condReg, trueReg, falseReg;
    materializeScalarOperand(condReg, codeGen, condPayload, condTypeRef, condBits);
    materializeScalarOperand(trueReg, codeGen, truePayload, trueTypeRef, resultBits);
    materializeScalarOperand(falseReg, codeGen, falsePayload, falseTypeRef, resultBits);

    CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
    resultPayload.reg                 = codeGen.nextVirtualRegisterForType(resultTypeRef);

    MicroBuilder&       builder    = codeGen.builder();
    const MicroLabelRef falseLabel = builder.createLabel();
    const MicroLabelRef doneLabel  = builder.createLabel();

    builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, falseLabel);
    builder.emitLoadRegReg(resultPayload.reg, trueReg, resultBits);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(falseLabel);
    builder.emitLoadRegReg(resultPayload.reg, falseReg, resultBits);
    builder.placeLabel(doneLabel);

    return Result::Continue;
}

SWC_END_NAMESPACE();
