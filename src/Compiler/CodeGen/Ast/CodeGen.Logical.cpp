#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenExprView.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void materializeLogicalOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        const TypeInfo& operandType = codeGen.typeMgr().get(operandTypeRef);

        if (operandType.isBool() && operandPayload.isValue())
        {
            outReg = operandPayload.reg;
            return;
        }

        const MicroOpBits operandBits = CodeGenTypeHelpers::compareBits(operandType, codeGen.ctx());
        outReg                        = CodeGenCompareHelpers::materializeConditionOperand(codeGen, operandPayload, operandTypeRef, operandType, operandBits);

        if (operandType.isBool())
            return;

        const MicroReg boolReg = codeGen.nextVirtualIntRegister();
        CodeGenCompareHelpers::emitTruthyBool(codeGen, boolReg, outReg, operandType, operandBits);
        outReg = boolReg;
    }

    bool emitLogicalRightOperandAndDone(CodeGen& codeGen, AstNodeRef nodeRef, AstNodeRef nodeRightRef)
    {
        LogicalExprCodeGenPayload* state = codeGen.safeNodePayload<LogicalExprCodeGenPayload>(nodeRef);
        if (state == nullptr || state->doneLabel == MicroLabelRef::invalid())
            return false;

        const CodeGenNodePayload& rightPayload = codeGen.payload(nodeRightRef);
        const TypeRef             rightType    = CodeGenExprView::payloadTypeRef(codeGen, rightPayload, nodeRightRef);

        MicroReg rightReg;
        materializeLogicalOperand(rightReg, codeGen, rightPayload, rightType);

        // Reuse the lhs result register so both control-flow paths converge on a single payload.
        const CodeGenNodePayload& resultPayload = codeGen.payload(nodeRef);
        if (resultPayload.reg != rightReg)
            codeGen.builder().emitLoadRegReg(resultPayload.reg, rightReg, MicroOpBits::B8);

        codeGen.builder().placeLabel(state->doneLabel);
        state->doneLabel = MicroLabelRef::invalid();
        return true;
    }
}

Result AstLogicalExpr::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef resolvedLeftRef  = codeGen.resolvedNodeRef(nodeLeftRef);
    const AstNodeRef resolvedChildRef = codeGen.resolvedNodeRef(childRef);
    const auto*      logicalState     = codeGen.safeNodePayload<LogicalExprCodeGenPayload>(codeGen.curNodeRef());

    // Rewrites can change the lhs reference; the first callback is still the lhs.
    if ((resolvedLeftRef.isValid() && resolvedChildRef == resolvedLeftRef) || logicalState == nullptr)
    {
        const CodeGenNodePayload& leftPayload = codeGen.payload(nodeLeftRef);
        const TypeRef             leftType    = CodeGenExprView::payloadTypeRef(codeGen, leftPayload, nodeLeftRef);

        MicroReg leftReg;
        materializeLogicalOperand(leftReg, codeGen, leftPayload, leftType);

        LogicalExprCodeGenPayload& state   = codeGen.ensureNodePayload<LogicalExprCodeGenPayload>(codeGen.curNodeRef());
        MicroBuilder&              builder = codeGen.builder();

        // The rhs overwrites the result register. Copy a bool held in a parameter/local
        // register so short-circuit evaluation cannot clobber that variable.
        if (leftReg == leftPayload.reg)
        {
            const MicroReg resultReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(resultReg, leftReg, MicroOpBits::B8);
            leftReg = resultReg;
        }

        auto& resultPayload   = codeGen.ensureNodePayload<CodeGenNodePayload>(codeGen.curNodeRef());
        resultPayload.reg     = leftReg;
        resultPayload.typeRef = codeGen.curViewType().typeRef();
        resultPayload.setIsValue();
        state.doneLabel = builder.createLabel();

        // Keep the lhs result and evaluate the rhs only when required.
        builder.emitCmpRegImm(resultPayload.reg, ApInt(0, 64), MicroOpBits::B8);
        const Token& tok = codeGen.token(codeRef());
        if (tok.id == TokenId::KwdAnd)
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, state.doneLabel);
        else if (tok.id == TokenId::KwdOr)
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, state.doneLabel);
        else
            SWC_UNREACHABLE();

        return Result::Continue;
    }

    const AstNodeRef resolvedRightRef = codeGen.resolvedNodeRef(nodeRightRef);
    if (resolvedRightRef.isValid() && resolvedChildRef == resolvedRightRef)
    {
        const bool finalized = emitLogicalRightOperandAndDone(codeGen, codeGen.curNodeRef(), nodeRightRef);
        SWC_ASSERT(finalized);
    }

    return Result::Continue;
}

Result AstLogicalExpr::codeGenPostNode(CodeGen& codeGen)
{
    const auto& node = codeGen.node(codeGen.curNodeRef()).cast<AstLogicalExpr>();
    emitLogicalRightOperandAndDone(codeGen, codeGen.curNodeRef(), node.nodeRightRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
