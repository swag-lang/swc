#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct IfStmtCodeGenPayload
    {
        MicroLabelRef falseLabel   = MicroLabelRef::invalid();
        MicroLabelRef doneLabel    = MicroLabelRef::invalid();
        bool          hasElseBlock = false;
    };

    IfStmtCodeGenPayload* ifStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<IfStmtCodeGenPayload>(nodeRef);
    }

    IfStmtCodeGenPayload& setIfStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const IfStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseIfStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        IfStmtCodeGenPayload* payload = ifStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

}

Result AstIfStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    MicroBuilder&    builder              = codeGen.builder();
    const AstNodeRef ifRef                = codeGen.curNodeRef();
    const AstNodeRef resolvedConditionRef = codeGen.resolvedNodeRef(nodeConditionRef);
    const AstNodeRef resolvedIfBlockRef   = codeGen.resolvedNodeRef(nodeIfBlockRef);
    const AstNodeRef resolvedElseBlockRef = codeGen.resolvedNodeRef(nodeElseBlockRef);
    const AstNodeRef resolvedChildRef     = codeGen.resolvedNodeRef(childRef);

    if (resolvedConditionRef.isValid() && resolvedChildRef == resolvedConditionRef)
    {
        const CodeGenNodePayload& conditionPayload = codeGen.payload(nodeConditionRef);
        const SemaNodeView        conditionView    = codeGen.viewType(nodeConditionRef);
        SWC_ASSERT(conditionView.type() != nullptr);
        const MicroOpBits condBits = CodeGenTypeHelpers::conditionBits(*conditionView.type(), codeGen.ctx());
        const MicroReg    condReg  = codeGen.nextVirtualIntRegister();

        if (conditionPayload.isAddress())
            builder.emitLoadRegMem(condReg, conditionPayload.reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, conditionPayload.reg, condBits);

        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);

        IfStmtCodeGenPayload state;
        state.falseLabel   = builder.createLabel();
        state.doneLabel    = builder.createLabel();
        state.hasElseBlock = resolvedElseBlockRef.isValid();
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, state.falseLabel);
        setIfStmtCodeGenPayload(codeGen, ifRef, state);

        return Result::Continue;
    }

    const bool isIfBlockChild   = resolvedIfBlockRef.isValid() && resolvedChildRef == resolvedIfBlockRef;
    const bool isElseBlockChild = resolvedElseBlockRef.isValid() && resolvedChildRef == resolvedElseBlockRef;
    if (!isIfBlockChild && !isElseBlockChild)
        return Result::Continue;

    const IfStmtCodeGenPayload* state = ifStmtCodeGenPayload(codeGen, ifRef);
    SWC_ASSERT(state != nullptr);

    if (isIfBlockChild)
    {
        if (state->hasElseBlock)
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, state->doneLabel);

        builder.placeLabel(state->falseLabel);

        if (!state->hasElseBlock)
            eraseIfStmtCodeGenPayload(codeGen, ifRef);

        return Result::Continue;
    }

    if (isElseBlockChild)
    {
        builder.placeLabel(state->doneLabel);
        eraseIfStmtCodeGenPayload(codeGen, ifRef);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
