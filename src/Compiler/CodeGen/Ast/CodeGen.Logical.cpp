#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct LogicalExprCodeGenPayload : CodeGenNodePayload
    {
        MicroLabelRef doneLabel = MicroLabelRef::invalid();
    };

    void materializeLogicalOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        const TypeInfo&   operandType = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits operandBits = CodeGenTypeHelpers::compareBits(operandType, codeGen.ctx());

        if (operandType.isBool() && operandPayload.isValue())
        {
            outReg = operandPayload.reg;
            return;
        }

        outReg = codeGen.nextVirtualRegisterForType(operandTypeRef);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, operandBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, operandBits);

        if (operandType.isBool())
            return;

        const MicroReg boolReg = codeGen.nextVirtualIntRegister();
        CodeGenCompareHelpers::emitTruthyBool(codeGen, boolReg, outReg, operandType, operandBits);
        outReg = boolReg;
    }

    LogicalExprCodeGenPayload* logicalExprCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<LogicalExprCodeGenPayload>(nodeRef);
    }

    LogicalExprCodeGenPayload& ensureLogicalExprCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.ensureNodePayload<LogicalExprCodeGenPayload>(nodeRef);
    }

    void eraseLogicalExprCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        LogicalExprCodeGenPayload* payload = logicalExprCodeGenPayload(codeGen, nodeRef);
        if (payload)
            payload->doneLabel = MicroLabelRef::invalid();
    }

    bool emitLogicalRightOperandAndDone(CodeGen& codeGen, AstNodeRef nodeRef, AstNodeRef nodeRightRef)
    {
        const LogicalExprCodeGenPayload* state = logicalExprCodeGenPayload(codeGen, nodeRef);
        if (state == nullptr || state->doneLabel == MicroLabelRef::invalid())
            return false;

        const CodeGenNodePayload& rightPayload = codeGen.payload(nodeRightRef);
        const SemaNodeView        rightView    = codeGen.viewType(nodeRightRef);
        const TypeRef             rightType    = rightPayload.typeRef.isValid() ? rightPayload.typeRef : rightView.typeRef();

        MicroReg rightReg;
        materializeLogicalOperand(rightReg, codeGen, rightPayload, rightType);

        // Reuse the lhs result register so both control-flow paths converge on a single payload.
        if (state->reg != rightReg)
            codeGen.builder().emitLoadRegReg(state->reg, rightReg, MicroOpBits::B8);
        codeGen.builder().placeLabel(state->doneLabel);
        eraseLogicalExprCodeGenPayload(codeGen, nodeRef);
        return true;
    }
}

Result AstLogicalExpr::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const Token&     tok              = codeGen.token(codeRef());
    const AstNodeRef resolvedLeftRef  = codeGen.resolvedNodeRef(nodeLeftRef);
    const AstNodeRef resolvedRightRef = codeGen.resolvedNodeRef(nodeRightRef);
    const AstNodeRef resolvedChildRef = codeGen.resolvedNodeRef(childRef);
    const auto*      logicalState     = logicalExprCodeGenPayload(codeGen, codeGen.curNodeRef());

    // Some semantic rewrites can substitute the lhs through helper nodes that no longer compare
    // equal by ref at codegen time. The first callback for a logical expression is still the lhs.
    if ((resolvedLeftRef.isValid() && resolvedChildRef == resolvedLeftRef) || logicalState == nullptr)
    {
        const CodeGenNodePayload& leftPayload = codeGen.payload(nodeLeftRef);
        const SemaNodeView        leftView    = codeGen.viewType(nodeLeftRef);
        const TypeRef             leftType    = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();

        MicroReg leftReg;
        materializeLogicalOperand(leftReg, codeGen, leftPayload, leftType);

        LogicalExprCodeGenPayload& state   = ensureLogicalExprCodeGenPayload(codeGen, codeGen.curNodeRef());
        MicroBuilder&              builder = codeGen.builder();
        state.reg                          = leftReg;
        state.typeRef                      = codeGen.curViewType().typeRef();
        state.setIsValue();
        state.doneLabel = builder.createLabel();

        // Short-circuit by keeping the lhs boolean as the provisional result and only evaluating rhs when
        // the operator still needs it.
        builder.emitCmpRegImm(state.reg, ApInt(0, 64), MicroOpBits::B8);
        if (tok.id == TokenId::KwdAnd)
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, state.doneLabel);
        else if (tok.id == TokenId::KwdOr)
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, state.doneLabel);
        else
            SWC_UNREACHABLE();

        return Result::Continue;
    }

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
