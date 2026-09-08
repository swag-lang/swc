#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct LoopStmtCodeGenPayload
    {
        MicroLabelRef bodyLabel     = MicroLabelRef::invalid();
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

namespace
{
    // Reads one bound of a parallel range into a register this statement owns, so adjusting it
    // cannot disturb the value the operand node published.
    MicroReg materializeParallelBound(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        const CodeGenNodePayload& payload = codeGen.payload(codeGen.resolvedNodeRef(nodeRef));
        const MicroReg            outReg  = codeGen.nextVirtualIntRegister();
        if (payload.isAddress())
            codeGen.builder().emitLoadRegMem(outReg, payload.reg, 0, MicroOpBits::B64);
        else
            codeGen.builder().emitLoadRegReg(outReg, payload.reg, MicroOpBits::B64);
        return outReg;
    }
}

// The statement is one call: the runtime splits the range and runs the closure once per
// partition, on its worker pool, and returns when every partition has finished.
Result AstParallelForStmt::codeGenPostNode(CodeGen& codeGen) const
{
    const bool          fallible    = hasFlag(AstParallelForStmtFlagsE::Fallible);
    const auto          runtimeKind = fallible ? IdentifierManager::RuntimeFunctionKind::ParallelRangeFallible : IdentifierManager::RuntimeFunctionKind::ParallelRange;
    const IdentifierRef idRef       = codeGen.idMgr().runtimeFunction(runtimeKind);
    SymbolFunction*     parallelFn  = codeGen.compiler().runtimeFunctionSymbol(idRef);
    SWC_ASSERT(parallelFn != nullptr);
    if (!parallelFn)
    {
        auto diag = SemaError::report(codeGen.sema(), DiagnosticId::misc_err_internal_codegen_failure, codeGen.curNodeRef());
        diag.addArgument(Diagnostic::ARG_WHAT, codeGen.function().getFullScopedName(codeGen.ctx()));
        diag.addArgument(Diagnostic::ARG_BECAUSE, fallible ? "missing runtime helper '__parallelRangeFallible'" : "missing runtime helper '__parallelRange'");
        diag.report(codeGen.ctx());
        return Result::Error;
    }

    MicroBuilder& builder = codeGen.builder();

    MicroReg beginReg = MicroReg::invalid();
    if (nodeBeginRef.isValid())
    {
        beginReg = materializeParallelBound(codeGen, nodeBeginRef);
    }
    else
    {
        beginReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegImm(beginReg, ApInt(static_cast<uint64_t>(0), 64), MicroOpBits::B64);
    }

    const MicroReg endReg = materializeParallelBound(codeGen, nodeEndRef);
    if (hasFlag(AstParallelForStmtFlagsE::Inclusive))
        builder.emitOpBinaryRegImm(endReg, ApInt(static_cast<uint64_t>(1), 64), MicroOp::Add, MicroOpBits::B64);

    const CodeGenNodePayload& closurePayload = codeGen.payload(codeGen.resolvedNodeRef(nodeClosureRef));
    const MicroReg            args[]         = {beginReg, endReg, closurePayload.reg};
    SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(codeGen, *parallelFn, args));
    if (fallible)
        SWC_RESULT(CodeGenCallHelpers::emitFallibleFailureJumpIfHasError(codeGen));
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
    loopState.bodyLabel     = builder.createLabel();
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
    builder.placeLabel(loopState->bodyLabel);

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
    frame.setCurrentLoopContinueLabel(loopState->bodyLabel);
    frame.setCurrentLoopBreakLabel(loopState->doneLabel);
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
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->bodyLabel);
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
