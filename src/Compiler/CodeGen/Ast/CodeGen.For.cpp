#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Loop.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ForCStyleStmtCodeGenPayload
    {
        MicroLabelRef loopLabel     = MicroLabelRef::invalid();
        MicroLabelRef bodyLabel     = MicroLabelRef::invalid();
        MicroLabelRef continueLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel     = MicroLabelRef::invalid();
    };

    struct ForStmtCodeGenPayload
    {
        MicroLabelRef   loopLabel     = MicroLabelRef::invalid();
        MicroLabelRef   continueLabel = MicroLabelRef::invalid();
        MicroLabelRef   doneLabel     = MicroLabelRef::invalid();
        MicroReg        indexReg      = MicroReg::invalid();
        MicroReg        boundReg      = MicroReg::invalid();
        TypeRef         indexTypeRef  = TypeRef::invalid();
        SymbolVariable* indexSym      = nullptr;
        bool            reverse       = false;
        bool            inclusive     = false;
        bool            unsignedCmp   = false;
    };

    ForCStyleStmtCodeGenPayload* forCStyleStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<ForCStyleStmtCodeGenPayload>(nodeRef);
    }

    ForCStyleStmtCodeGenPayload& setForCStyleStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const ForCStyleStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseForCStyleStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        ForCStyleStmtCodeGenPayload* payload = forCStyleStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    ForStmtCodeGenPayload* forStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<ForStmtCodeGenPayload>(nodeRef);
    }

    ForStmtCodeGenPayload& setForStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const ForStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseForStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        ForStmtCodeGenPayload* payload = forStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    MicroReg materializeLoopValueReg(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef typeRef)
    {
        const TypeInfo&   typeInfo = codeGen.typeMgr().get(typeRef);
        const MicroOpBits opBits   = CodeGenTypeHelpers::conditionBits(typeInfo, codeGen.ctx());
        const MicroReg    outReg   = codeGen.nextVirtualIntRegister();
        MicroBuilder&     builder  = codeGen.builder();

        if (payload.isAddress())
            builder.emitLoadRegMem(outReg, payload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, payload.reg, opBits);

        return outReg;
    }

    MicroReg materializeLoopZeroReg(CodeGen& codeGen, TypeRef typeRef)
    {
        const TypeInfo&   typeInfo = codeGen.typeMgr().get(typeRef);
        const MicroOpBits opBits   = CodeGenTypeHelpers::conditionBits(typeInfo, codeGen.ctx());
        const MicroReg    outReg   = codeGen.nextVirtualIntRegister();
        MicroBuilder&     builder  = codeGen.builder();
        builder.emitLoadRegImm(outReg, ApInt(0, 64), opBits);
        return outReg;
    }

    MicroReg materializeLoopConstantReg(CodeGen& codeGen, ConstantRef cstRef, TypeRef typeRef)
    {
        const ConstantValue& cst      = codeGen.cstMgr().get(cstRef);
        const TypeInfo&      typeInfo = codeGen.typeMgr().get(typeRef);
        const MicroOpBits    opBits   = CodeGenTypeHelpers::conditionBits(typeInfo, codeGen.ctx());
        const MicroReg       outReg   = codeGen.nextVirtualIntRegister();
        SWC_ASSERT(cst.isInt());
        SWC_ASSERT(cst.getInt().fits64());
        codeGen.builder().emitLoadRegImm(outReg, ApInt(static_cast<uint64_t>(cst.getInt().asI64()), 64), opBits);
        return outReg;
    }

    MicroReg materializeLoopCountOfReg(CodeGen& codeGen, AstNodeRef exprRef, TypeRef resultTypeRef)
    {
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        const TypeInfo&           exprType    = *exprView.type();
        MicroBuilder&             builder     = codeGen.builder();

        if (exprType.isIntUnsigned())
            return materializeLoopValueReg(codeGen, exprPayload, resultTypeRef);

        const MicroReg baseReg   = exprPayload.reg;
        const MicroReg resultReg = codeGen.nextVirtualIntRegister();
        if (exprType.isCString())
        {
            const MicroReg cstrReg = codeGen.nextVirtualIntRegister();
            if (exprPayload.isAddress())
                builder.emitLoadRegMem(cstrReg, baseReg, 0, MicroOpBits::B64);
            else
                builder.emitLoadRegReg(cstrReg, baseReg, MicroOpBits::B64);

            builder.emitClearReg(resultReg, MicroOpBits::B64);

            const MicroLabelRef loopLabel = builder.createLabel();
            const MicroLabelRef doneLabel = builder.createLabel();
            builder.emitCmpRegImm(cstrReg, ApInt(0, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

            const MicroReg scanReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(scanReg, cstrReg, MicroOpBits::B64);
            builder.placeLabel(loopLabel);

            const MicroReg charReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(charReg, scanReg, 0, MicroOpBits::B8);
            builder.emitCmpRegImm(charReg, ApInt(0, 64), MicroOpBits::B8);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
            builder.emitOpBinaryRegImm(scanReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(resultReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopLabel);
            builder.placeLabel(doneLabel);
            return resultReg;
        }

        if (exprType.isString())
        {
            builder.emitLoadRegMem(resultReg, baseReg, offsetof(Runtime::String, length), MicroOpBits::B64);
            return resultReg;
        }

        if (exprType.isSlice() || exprType.isAnyVariadic())
        {
            builder.emitLoadRegMem(resultReg, baseReg, offsetof(Runtime::Slice<std::byte>, count), MicroOpBits::B64);
            return resultReg;
        }

        SWC_UNREACHABLE();
    }

    void emitLoopVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar, MicroReg valueReg)
    {
        CodeGenNodePayload symbolPayload;
        symbolPayload.typeRef = symVar.typeRef();
        symbolPayload.setIsValue();
        symbolPayload.reg = valueReg;
        codeGen.setVariablePayload(symVar, symbolPayload);
    }

    Result emitForInit(CodeGen& codeGen, const AstForStmt& node, ForStmtCodeGenPayload& loopState)
    {
        const AstNodeRef   exprRef  = codeGen.resolvedNodeRef(node.nodeExprRef);
        const SemaNodeView exprView = codeGen.viewType(exprRef);
        MicroBuilder&      builder  = codeGen.builder();

        MicroReg lowerReg = MicroReg::invalid();
        MicroReg upperReg = MicroReg::invalid();
        if (codeGen.node(exprRef).is(AstNodeId::RangeExpr))
        {
            loopState.indexTypeRef        = exprView.typeRef();
            const AstRangeExpr& rangeExpr = codeGen.node(exprRef).cast<AstRangeExpr>();
            loopState.inclusive           = rangeExpr.hasFlag(AstRangeExprFlagsE::Inclusive);

            if (rangeExpr.nodeExprDownRef.isValid())
            {
                const AstNodeRef downRef = codeGen.resolvedNodeRef(rangeExpr.nodeExprDownRef);
                lowerReg                 = materializeLoopValueReg(codeGen, codeGen.payload(downRef), loopState.indexTypeRef);
            }
            else
            {
                lowerReg = materializeLoopZeroReg(codeGen, loopState.indexTypeRef);
            }

            const AstNodeRef upRef = codeGen.resolvedNodeRef(rangeExpr.nodeExprUpRef);
            upperReg               = materializeLoopValueReg(codeGen, codeGen.payload(upRef), loopState.indexTypeRef);
        }
        else
        {
            const auto* semaPayload = codeGen.sema().semaPayload<ForStmtSemaPayload>(codeGen.curNodeRef());
            SWC_ASSERT(semaPayload != nullptr);
            loopState.indexTypeRef = semaPayload->indexTypeRef;
            lowerReg               = materializeLoopZeroReg(codeGen, loopState.indexTypeRef);
            if (semaPayload->countCstRef.isValid())
                upperReg = materializeLoopConstantReg(codeGen, semaPayload->countCstRef, loopState.indexTypeRef);
            else
                upperReg = materializeLoopCountOfReg(codeGen, exprRef, loopState.indexTypeRef);
        }

        const TypeInfo&   indexType = codeGen.typeMgr().get(loopState.indexTypeRef);
        const MicroOpBits opBits    = CodeGenTypeHelpers::conditionBits(indexType, codeGen.ctx());
        loopState.unsignedCmp       = indexType.isIntUnsigned();
        loopState.indexReg          = codeGen.nextVirtualIntRegister();

        if (loopState.reverse)
        {
            loopState.boundReg = lowerReg;
            // Reverse loops start from the upper bound and pre-decrement when the range is exclusive, so
            // the first visible value still belongs to the source interval.
            builder.emitCmpRegReg(upperReg, lowerReg, opBits);
            if (loopState.inclusive)
            {
                builder.emitJumpToLabel(CodeGenCompareHelpers::lessCond(loopState.unsignedCmp), MicroOpBits::B32, loopState.doneLabel);
                builder.emitLoadRegReg(loopState.indexReg, upperReg, opBits);
            }
            else
            {
                builder.emitJumpToLabel(CodeGenCompareHelpers::lessEqualCond(loopState.unsignedCmp), MicroOpBits::B32, loopState.doneLabel);
                builder.emitLoadRegReg(loopState.indexReg, upperReg, opBits);
                builder.emitOpBinaryRegImm(loopState.indexReg, ApInt(1, 64), MicroOp::Subtract, opBits);
            }
        }
        else
        {
            loopState.boundReg = upperReg;
            builder.emitLoadRegReg(loopState.indexReg, lowerReg, opBits);
            builder.emitCmpRegReg(loopState.indexReg, upperReg, opBits);
            const auto cpuCond = loopState.inclusive ? CodeGenCompareHelpers::greaterCond(loopState.unsignedCmp) : CodeGenCompareHelpers::greaterEqualCond(loopState.unsignedCmp);
            builder.emitJumpToLabel(cpuCond, MicroOpBits::B32, loopState.doneLabel);
        }

        if (loopState.indexSym != nullptr)
            emitLoopVariablePayload(codeGen, *loopState.indexSym, loopState.indexReg);

        return Result::Continue;
    }
}

Result AstForCStyleStmt::codeGenPreNode(CodeGen& codeGen)
{
    MicroBuilder&               builder = codeGen.builder();
    ForCStyleStmtCodeGenPayload loopState;
    loopState.loopLabel     = builder.createLabel();
    loopState.bodyLabel     = builder.createLabel();
    loopState.continueLabel = builder.createLabel();
    loopState.doneLabel     = builder.createLabel();
    setForCStyleStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstForCStyleStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForCStyleStmtCodeGenPayload* loopState = forCStyleStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef     = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef postStmtRef = codeGen.resolvedNodeRef(nodePostStmtRef);
    const AstNodeRef bodyRef     = codeGen.resolvedNodeRef(nodeBodyRef);
    MicroBuilder&    builder     = codeGen.builder();

    if (childRef == exprRef)
    {
        builder.placeLabel(loopState->loopLabel);
        return Result::Continue;
    }

    if (childRef == postStmtRef)
    {
        builder.placeLabel(loopState->continueLabel);

        CodeGenFrame frame = codeGen.frame();
        frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
        frame.setCurrentLoopContinueLabel(loopState->loopLabel);
        frame.setCurrentLoopBreakLabel(loopState->doneLabel);
        codeGen.pushFrame(frame);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        builder.placeLabel(loopState->bodyLabel);

        CodeGenFrame frame = codeGen.frame();
        frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
        frame.setCurrentLoopContinueLabel(postStmtRef.isValid() ? loopState->continueLabel : loopState->loopLabel);
        frame.setCurrentLoopBreakLabel(loopState->doneLabel);
        codeGen.pushFrame(frame);
        codeGen.pushDeferScope(AstNodeRef::invalid(), codeGen.curNodeRef());
    }

    return Result::Continue;
}

Result AstForCStyleStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForCStyleStmtCodeGenPayload* loopState = forCStyleStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef     = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef postStmtRef = codeGen.resolvedNodeRef(nodePostStmtRef);
    const AstNodeRef bodyRef     = codeGen.resolvedNodeRef(nodeBodyRef);

    if (childRef == exprRef)
    {
        MicroBuilder&             builder     = codeGen.builder();
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        CodeGenCompareHelpers::emitConditionFalseJump(codeGen, exprPayload, exprView.typeRef(), loopState->doneLabel);
        if (postStmtRef.isValid())
        {
            const ScopedDebugNoStep noStep(builder, true);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->bodyLabel);
        }
        return Result::Continue;
    }

    if (childRef == postStmtRef)
    {
        MicroBuilder& builder = codeGen.builder();
        {
            const ScopedDebugNoStep noStep(builder, true);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->loopLabel);
        }
        codeGen.popFrame();
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        SWC_RESULT(codeGen.popDeferScope());
        MicroBuilder&           builder = codeGen.builder();
        const ScopedDebugNoStep noStep(builder, true);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, postStmtRef.isValid() ? loopState->continueLabel : loopState->loopLabel);
        codeGen.popFrame();
    }

    return Result::Continue;
}

Result AstForCStyleStmt::codeGenPostNode(CodeGen& codeGen)
{
    const ForCStyleStmtCodeGenPayload* loopState = forCStyleStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(loopState->doneLabel);
    eraseForCStyleStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstForStmt::codeGenPreNode(CodeGen& codeGen) const
{
    MicroBuilder&         builder = codeGen.builder();
    ForStmtCodeGenPayload loopState;
    loopState.loopLabel     = builder.createLabel();
    loopState.continueLabel = builder.createLabel();
    loopState.doneLabel     = builder.createLabel();
    loopState.reverse       = modifierFlags.has(AstModifierFlagsE::Reverse);

    if (tokNameRef.isValid())
    {
        const SemaNodeView symbolView = codeGen.curViewSymbol();
        if (symbolView.sym() != nullptr)
            loopState.indexSym = &symbolView.sym()->cast<SymbolVariable>();
    }

    setForStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstForStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForStmtCodeGenPayload* loopState = forStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef whereRef = codeGen.resolvedNodeRef(nodeWhereRef);
    const AstNodeRef bodyRef  = codeGen.resolvedNodeRef(nodeBodyRef);
    if (childRef != whereRef && !(childRef == bodyRef && whereRef.isInvalid()))
        return Result::Continue;

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
    frame.setCurrentLoopContinueLabel(loopState->continueLabel);
    frame.setCurrentLoopBreakLabel(loopState->doneLabel);
    frame.setCurrentLoopIndex(loopState->indexReg, loopState->indexTypeRef);
    codeGen.pushFrame(frame);
    codeGen.pushDeferScope(AstNodeRef::invalid(), codeGen.curNodeRef());
    return Result::Continue;
}

Result AstForStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    ForStmtCodeGenPayload* loopState = forStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef  = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef whereRef = codeGen.resolvedNodeRef(nodeWhereRef);
    const AstNodeRef bodyRef  = codeGen.resolvedNodeRef(nodeBodyRef);

    if (childRef == exprRef)
    {
        SWC_RESULT(emitForInit(codeGen, *this, *loopState));
        MicroBuilder& builder = codeGen.builder();
        builder.placeLabel(loopState->loopLabel);
        return Result::Continue;
    }

    if (childRef == whereRef)
    {
        const CodeGenNodePayload& wherePayload = codeGen.payload(whereRef);
        const SemaNodeView        whereView    = codeGen.viewType(whereRef);
        CodeGenCompareHelpers::emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), loopState->continueLabel);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        SWC_RESULT(codeGen.popDeferScope());

        if (codeGen.currentInstructionBlocksFallthrough() && !codeGen.frame().currentLoopHasContinueJump())
        {
            codeGen.popFrame();
            return Result::Continue;
        }

        const TypeInfo&   indexType = codeGen.typeMgr().get(loopState->indexTypeRef);
        const MicroOpBits opBits    = CodeGenTypeHelpers::conditionBits(indexType, codeGen.ctx());
        MicroBuilder&     builder   = codeGen.builder();
        builder.setCurrentDebugSourceCodeRef(codeGen.node(codeGen.curNodeRef()).codeRef());
        builder.setCurrentDebugNoStep(false);

        builder.placeLabel(loopState->continueLabel);
        if (loopState->reverse)
        {
            builder.emitCmpRegReg(loopState->indexReg, loopState->boundReg, opBits);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, loopState->doneLabel);
            builder.emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Subtract, opBits);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->loopLabel);
        }
        else
        {
            builder.emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Add, opBits);
            builder.emitCmpRegReg(loopState->indexReg, loopState->boundReg, opBits);
            const auto cpuCond = loopState->inclusive ? CodeGenCompareHelpers::lessEqualCond(loopState->unsignedCmp) : CodeGenCompareHelpers::lessCond(loopState->unsignedCmp);
            builder.emitJumpToLabel(cpuCond, MicroOpBits::B32, loopState->loopLabel);
        }

        codeGen.popFrame();
        return Result::Continue;
    }

    return Result::Continue;
}

Result AstForStmt::codeGenPostNode(CodeGen& codeGen)
{
    const ForStmtCodeGenPayload* loopState = forStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(loopState->doneLabel);
    eraseForStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstContinueStmt::codeGenPostNode(CodeGen& codeGen)
{
    const CodeGenFrame::BreakContextKind breakKind = codeGen.frame().currentBreakableKind();
    if (breakKind != CodeGenFrame::BreakContextKind::Loop &&
        breakKind != CodeGenFrame::BreakContextKind::Scope)
        return Result::Continue;

    const AstNodeRef breakRef = codeGen.frame().currentBreakContext().nodeRef;
    if (breakKind == CodeGenFrame::BreakContextKind::Loop)
        codeGen.frame().setCurrentLoopHasContinueJump(true);

    const MicroLabelRef continueLabel = codeGen.frame().currentLoopContinueLabel();
    if (continueLabel == MicroLabelRef::invalid())
        return Result::Continue;

    SWC_RESULT(codeGen.emitDeferredActionsUntilBreakOwner(breakRef));
    MicroBuilder& builder = codeGen.builder();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, continueLabel);
    return Result::Continue;
}

SWC_END_NAMESPACE();
