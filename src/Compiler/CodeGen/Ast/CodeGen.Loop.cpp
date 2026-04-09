#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Loop.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct LoopStmtCodeGenPayload
    {
        MicroLabelRef bodyLabel     = MicroLabelRef::invalid();
        MicroLabelRef continueLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel     = MicroLabelRef::invalid();
        SymbolVariable* indexStateSym = nullptr;
        bool            usesIndexState = false;
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

    MicroReg materializeLoopIndexStateAddress(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        SWC_ASSERT(symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
        return codeGen.resolveLocalStackPayload(symVar).reg;
    }

    void emitInitializeLoopIndexState(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        MicroBuilder&  builder      = codeGen.builder();
        const MicroReg stateAddrReg = materializeLoopIndexStateAddress(codeGen, symVar);
        const MicroReg zeroReg      = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(zeroReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitLoadMemReg(stateAddrReg, 0, zeroReg, MicroOpBits::B64);
    }

    MicroReg emitLoadLoopIndexState(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        MicroBuilder&  builder      = codeGen.builder();
        const MicroReg stateAddrReg = materializeLoopIndexStateAddress(codeGen, symVar);
        const MicroReg indexReg     = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(indexReg, stateAddrReg, 0, MicroOpBits::B64);
        return indexReg;
    }

    void emitAdvanceLoopIndexState(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        MicroBuilder&  builder      = codeGen.builder();
        const MicroReg stateAddrReg = materializeLoopIndexStateAddress(codeGen, symVar);
        const MicroReg indexReg     = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(indexReg, stateAddrReg, 0, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(indexReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitLoadMemReg(stateAddrReg, 0, indexReg, MicroOpBits::B64);
    }

}

Result AstWhileStmt::codeGenPreNode(CodeGen& codeGen)
{
    MicroBuilder&          builder = codeGen.builder();
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
        codeGen.pushDeferScope(AstNodeRef::invalid(), codeGen.curNodeRef());
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
        SWC_RESULT(codeGen.popDeferScope());
        MicroBuilder&           builder = codeGen.builder();
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
    MicroBuilder&          builder = codeGen.builder();
    LoopStmtCodeGenPayload loopState;
    const SemaNodeView     symbolsView = codeGen.viewSymbolList(codeGen.curNodeRef());
    const auto             symbols     = symbolsView.symList();
    loopState.bodyLabel     = builder.createLabel();
    loopState.continueLabel = builder.createLabel();
    loopState.doneLabel     = builder.createLabel();
    if (const auto* indexUsage = codeGen.sema().semaPayload<LoopSemaPayload>(codeGen.curNodeRef()))
        loopState.usesIndexState = indexUsage->usesLoopIndex;
    if (!symbols.empty())
        loopState.indexStateSym = &symbols.back()->cast<SymbolVariable>();
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
    if (loopState->usesIndexState)
    {
        SWC_ASSERT(loopState->indexStateSym != nullptr);
        emitInitializeLoopIndexState(codeGen, *loopState->indexStateSym);
    }
    builder.placeLabel(loopState->bodyLabel);

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
    frame.setCurrentLoopContinueLabel(loopState->usesIndexState ? loopState->continueLabel : loopState->bodyLabel);
    frame.setCurrentLoopBreakLabel(loopState->doneLabel);
    if (loopState->usesIndexState)
    {
        SWC_ASSERT(loopState->indexStateSym != nullptr);
        const MicroReg currentIndexReg = emitLoadLoopIndexState(codeGen, *loopState->indexStateSym);
        frame.setCurrentLoopIndex(currentIndexReg, codeGen.typeMgr().typeU64());
    }
    codeGen.pushFrame(frame);
    codeGen.pushDeferScope(AstNodeRef::invalid(), codeGen.curNodeRef());
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != codeGen.resolvedNodeRef(nodeBodyRef))
        return Result::Continue;

    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    SWC_RESULT(codeGen.popDeferScope());
    MicroBuilder&           builder = codeGen.builder();
    const ScopedDebugNoStep noStep(builder, true);
    if (loopState->usesIndexState)
    {
        SWC_ASSERT(loopState->indexStateSym != nullptr);
        builder.placeLabel(loopState->continueLabel);
        emitAdvanceLoopIndexState(codeGen, *loopState->indexStateSym);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->bodyLabel);
    }
    else
    {
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->bodyLabel);
    }
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
