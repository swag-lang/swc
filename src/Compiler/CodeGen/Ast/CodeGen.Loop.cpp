#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct LoopStmtCodeGenPayload
    {
        MicroLabelRef continueLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel     = MicroLabelRef::invalid();
    };

    LoopStmtCodeGenPayload* loopStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<LoopStmtCodeGenPayload>(nodeRef);
    }

    LoopStmtCodeGenPayload& setLoopStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const LoopStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseLoopStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        LoopStmtCodeGenPayload* payload = loopStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }
}

Result AstWhileStmt::codeGenPreNode(CodeGen& codeGen)
{
    MicroBuilder&           builder = codeGen.builder();
    LoopStmtCodeGenPayload loopState;
    loopState.continueLabel = builder.createLabel();
    loopState.doneLabel     = builder.createLabel();
    setLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstWhileStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef bodyRef = codeGen.resolvedNodeRef(nodeBodyRef);
    MicroBuilder&    builder = codeGen.builder();

    if (childRef == exprRef)
    {
        builder.placeLabel(loopState->continueLabel);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        CodeGenFrame frame = codeGen.frame();
        frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
        frame.setCurrentLoopContinueLabel(loopState->continueLabel);
        frame.setCurrentLoopBreakLabel(loopState->doneLabel);
        codeGen.pushFrame(frame);
    }

    return Result::Continue;
}

Result AstWhileStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef bodyRef = codeGen.resolvedNodeRef(nodeBodyRef);

    if (childRef == exprRef)
    {
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        CodeGenCompareHelpers::emitConditionFalseJump(codeGen, exprPayload, exprView.typeRef(), loopState->doneLabel);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        MicroBuilder&          builder = codeGen.builder();
        const ScopedDebugNoStep noStep(builder, true);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->continueLabel);
        codeGen.popFrame();
    }

    return Result::Continue;
}

Result AstWhileStmt::codeGenPostNode(CodeGen& codeGen)
{
    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(loopState->doneLabel);
    eraseLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPreNode(CodeGen& codeGen)
{
    MicroBuilder&           builder = codeGen.builder();
    LoopStmtCodeGenPayload loopState;
    loopState.continueLabel = builder.createLabel();
    loopState.doneLabel     = builder.createLabel();
    setLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != codeGen.resolvedNodeRef(nodeBodyRef))
        return Result::Continue;

    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(loopState->continueLabel);

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
    frame.setCurrentLoopContinueLabel(loopState->continueLabel);
    frame.setCurrentLoopBreakLabel(loopState->doneLabel);
    codeGen.pushFrame(frame);
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != codeGen.resolvedNodeRef(nodeBodyRef))
        return Result::Continue;

    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    MicroBuilder&          builder = codeGen.builder();
    const ScopedDebugNoStep noStep(builder, true);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->continueLabel);
    codeGen.popFrame();
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPostNode(CodeGen& codeGen)
{
    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(loopState->doneLabel);
    eraseLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
