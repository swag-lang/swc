#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenLoopFrame.h"
#include "Compiler/CodeGen/Core/CodeGenReferenceHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Loop.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ForCStyleStmtCodeGenPayload
    {
        MicroLabelRef loopLabel = MicroLabelRef::invalid();
        MicroLabelRef bodyLabel = MicroLabelRef::invalid();
        MicroLabelRef postLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel = MicroLabelRef::invalid();
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
        bool            inclusive     = false;
        bool            unsignedCmp   = false;
    };

    AstNodeRef preparedChildRef(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        AstNodeRef preparedRef = codeGen.resolvedNodeRef(nodeRef);
        if (preparedRef.isInvalid())
            preparedRef = nodeRef;
        return SemaHelpers::resolveTransparentConditionExprSourceRef(codeGen.sema(), preparedRef);
    }

    bool matchesChildRef(CodeGen& codeGen, AstNodeRef callbackRef, AstNodeRef targetRef)
    {
        if (callbackRef.isInvalid() || targetRef.isInvalid())
            return false;

        return preparedChildRef(codeGen, callbackRef) == preparedChildRef(codeGen, targetRef);
    }

    MicroOpBits loopOperationBits(CodeGen& codeGen, const TypeInfo& compareType)
    {
        if (compareType.isInt())
            return MicroOpBits::B64;
        return CodeGenTypeHelpers::conditionBits(compareType, codeGen.ctx());
    }

    MicroReg materializeLoopValueReg(CodeGen& codeGen, const CodeGenNodePayload& payload, const TypeInfo& compareType)
    {
        const MicroOpBits valueBits = CodeGenTypeHelpers::conditionBits(compareType, codeGen.ctx());
        const MicroReg    outReg    = codeGen.nextVirtualIntRegister();
        MicroBuilder&     builder   = codeGen.builder();

        if (payload.isAddress())
        {
            if (compareType.isInt() && valueBits != MicroOpBits::B64)
            {
                if (compareType.isIntSigned())
                    builder.emitLoadSignedExtendRegMem(outReg, payload.reg, 0, MicroOpBits::B64, valueBits);
                else
                    builder.emitLoadZeroExtendRegMem(outReg, payload.reg, 0, MicroOpBits::B64, valueBits);
            }
            else
            {
                builder.emitLoadRegMem(outReg, payload.reg, 0, valueBits);
            }
        }
        else
        {
            if (compareType.isInt() && valueBits != MicroOpBits::B64)
            {
                if (compareType.isIntSigned())
                    builder.emitLoadSignedExtendRegReg(outReg, payload.reg, MicroOpBits::B64, valueBits);
                else
                    builder.emitLoadZeroExtendRegReg(outReg, payload.reg, MicroOpBits::B64, valueBits);
            }
            else
            {
                builder.emitLoadRegReg(outReg, payload.reg, valueBits);
            }
        }

        return outReg;
    }

    MicroReg materializeLoopZeroReg(CodeGen& codeGen, MicroOpBits opBits)
    {
        const MicroReg outReg  = codeGen.nextVirtualIntRegister();
        MicroBuilder&  builder = codeGen.builder();
        builder.emitLoadRegImm(outReg, ApInt(0, 64), opBits);
        return outReg;
    }

    MicroReg materializeLoopConstantReg(CodeGen& codeGen, ConstantRef cstRef, MicroOpBits opBits)
    {
        const ConstantValue& cst    = codeGen.cstMgr().get(cstRef);
        const MicroReg       outReg = codeGen.nextVirtualIntRegister();
        SWC_ASSERT(cst.isInt());
        SWC_ASSERT(cst.getInt().fits64());
        codeGen.builder().emitLoadRegImm(outReg, ApInt(static_cast<uint64_t>(cst.getInt().asI64()), 64), opBits);
        return outReg;
    }

    Result materializeLoopCountOfReg(MicroReg& outReg, CodeGen& codeGen, AstNodeRef exprRef, const TypeInfo& resultType)
    {
        outReg = MicroReg::invalid();

        const auto* loopPayload = codeGen.sema().semaPayload<LoopSemaPayload>(codeGen.curNodeRef());
        if (loopPayload && loopPayload->countFn != nullptr)
        {
            codeGen.clearNodePayload<CodeGenNodePayload>(codeGen.curNodeRef());
            codeGen.sema().setResolvedCallArguments(codeGen.curNodeRef(), loopPayload->countResolvedArgs);
            codeGen.sema().setIsValue(codeGen.curNodeRef());
            SWC_RESULT(CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid(), loopPayload->countFn));
            const CodeGenNodePayload countPayload = codeGen.payload(codeGen.curNodeRef());
            codeGen.clearNodePayload<CodeGenNodePayload>(codeGen.curNodeRef());

            outReg = materializeLoopValueReg(codeGen, countPayload, resultType);
            return Result::Continue;
        }

        CodeGenNodePayload exprPayload  = codeGen.payload(exprRef);
        TypeRef            exprTypeRef  = exprPayload.typeRef.isValid() ? exprPayload.typeRef : codeGen.viewType(exprRef).typeRef();
        const TypeInfo*    exprTypeInfo = CodeGenReferenceHelpers::unwrapAliasRefPayload(codeGen, exprPayload, exprTypeRef);
        SWC_ASSERT(exprTypeInfo);
        const TypeInfo& exprType = *exprTypeInfo;
        MicroBuilder&   builder  = codeGen.builder();

        if (exprType.isInt())
        {
            outReg = materializeLoopValueReg(codeGen, exprPayload, resultType);
            return Result::Continue;
        }

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
            outReg = resultReg;
            return Result::Continue;
        }

        if (exprType.isString())
        {
            builder.emitLoadRegMem(resultReg, baseReg, offsetof(Runtime::String, length), MicroOpBits::B64);
            outReg = resultReg;
            return Result::Continue;
        }

        if (exprType.isSlice() || exprType.isAnyVariadic())
        {
            builder.emitLoadRegMem(resultReg, baseReg, offsetof(Runtime::Slice<std::byte>, count), MicroOpBits::B64);
            outReg = resultReg;
            return Result::Continue;
        }

        SWC_UNREACHABLE();
    }

    void emitLoopVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar, MicroReg valueReg)
    {
        if (codeGen.localStackBaseReg().isValid() &&
            symVar.hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage) &&
            symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
        {
            const TypeInfo&          typeInfo       = codeGen.typeMgr().get(symVar.typeRef());
            const MicroOpBits        opBits         = CodeGenTypeHelpers::conditionBits(typeInfo, codeGen.ctx());
            const CodeGenNodePayload storagePayload = codeGen.resolveLocalStackPayload(symVar, false);
            codeGen.builder().emitLoadMemReg(storagePayload.reg, 0, valueReg, opBits);
            codeGen.setVariablePayload(symVar, storagePayload);
            return;
        }

        CodeGenNodePayload symbolPayload;
        symbolPayload.typeRef = symVar.typeRef();
        symbolPayload.setIsValue();
        symbolPayload.reg = valueReg;
        codeGen.setVariablePayload(symVar, symbolPayload);
    }

    void emitLoopVariableReg(CodeGen& codeGen, const SymbolVariable& symVar, MicroReg valueReg)
    {
        if (!codeGen.localStackBaseReg().isValid() ||
            !symVar.hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage) ||
            !symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            return;

        const CodeGenNodePayload storagePayload = codeGen.resolveLocalStackPayload(symVar, false);
        const TypeInfo&          typeInfo       = codeGen.typeMgr().get(symVar.typeRef());
        const MicroOpBits        opBits         = CodeGenTypeHelpers::conditionBits(typeInfo, codeGen.ctx());
        codeGen.builder().emitLoadRegMem(valueReg, storagePayload.reg, 0, opBits);
    }

    Result emitForInit(CodeGen& codeGen, const AstForStmt& node, ForStmtCodeGenPayload& loopState)
    {
        const AstNodeRef exprRef = codeGen.resolvedNodeRef(node.nodeExprRef);
        MicroBuilder&    builder = codeGen.builder();

        const auto* semaPayload = codeGen.sema().semaPayload<LoopSemaPayload>(codeGen.curNodeRef());
        SWC_ASSERT(semaPayload != nullptr);

        loopState.indexTypeRef = semaPayload->indexTypeRef;
        loopState.inclusive    = semaPayload->inclusive;

        const TypeInfo&   indexType     = codeGen.typeMgr().get(loopState.indexTypeRef);
        const TypeInfo*   unwrappedType = indexType.unwrapAliasEnumType(codeGen.ctx());
        const TypeInfo&   compareType   = unwrappedType ? *unwrappedType : indexType;
        const MicroOpBits opBits        = loopOperationBits(codeGen, compareType);
        MicroReg          lowerReg      = MicroReg::invalid();
        MicroReg          upperReg      = MicroReg::invalid();
        if (semaPayload->isRangeLoop)
        {
            if (semaPayload->lowerBoundRef.isValid())
            {
                const AstNodeRef downRef = codeGen.resolvedNodeRef(semaPayload->lowerBoundRef);
                lowerReg                 = materializeLoopValueReg(codeGen, codeGen.payload(downRef), compareType);
            }
            else
            {
                lowerReg = materializeLoopZeroReg(codeGen, opBits);
            }

            const AstNodeRef upRef = codeGen.resolvedNodeRef(semaPayload->upperBoundRef);
            upperReg               = materializeLoopValueReg(codeGen, codeGen.payload(upRef), compareType);
        }
        else
        {
            lowerReg = materializeLoopZeroReg(codeGen, opBits);
            if (semaPayload->countCstRef.isValid())
                upperReg = materializeLoopConstantReg(codeGen, semaPayload->countCstRef, opBits);
            else
                SWC_RESULT(materializeLoopCountOfReg(upperReg, codeGen, exprRef, compareType));
        }

        loopState.unsignedCmp = compareType.isIntUnsigned();
        loopState.indexReg    = codeGen.nextVirtualIntRegister();

        SWC_RESULT(CodeGenSafety::emitLoopBoundCheck(codeGen, exprRef, lowerReg, upperReg, compareType));

        loopState.boundReg = upperReg;
        builder.emitLoadRegReg(loopState.indexReg, lowerReg, opBits);
        builder.emitCmpRegReg(loopState.indexReg, upperReg, opBits);
        const auto cpuCond = loopState.inclusive ? CodeGenCompareHelpers::greaterCond(loopState.unsignedCmp) : CodeGenCompareHelpers::greaterEqualCond(loopState.unsignedCmp);
        builder.emitJumpToLabel(cpuCond, MicroOpBits::B32, loopState.doneLabel);

        if (loopState.indexSym != nullptr)
            emitLoopVariablePayload(codeGen, *loopState.indexSym, loopState.indexReg);

        return Result::Continue;
    }
}

Result AstForCStyleStmt::codeGenPreNode(CodeGen& codeGen)
{
    MicroBuilder&               builder = codeGen.builder();
    ForCStyleStmtCodeGenPayload loopState;
    loopState.loopLabel = builder.createLabel();
    loopState.bodyLabel = builder.createLabel();
    loopState.postLabel = builder.createLabel();
    loopState.doneLabel = builder.createLabel();
    codeGen.setNodePayload(codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstForCStyleStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForCStyleStmtCodeGenPayload* loopState = codeGen.safeNodePayload<ForCStyleStmtCodeGenPayload>(codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef = codeGen.resolvedNodeRef(nodeExprRef);
    MicroBuilder&    builder = codeGen.builder();

    if (childRef == exprRef)
    {
        builder.placeLabel(loopState->loopLabel);
        return Result::Continue;
    }

    const AstNodeRef postStmtRef = codeGen.resolvedNodeRef(nodePostStmtRef);
    if (childRef == postStmtRef)
    {
        builder.placeLabel(loopState->postLabel);

        CodeGenFrame frame = codeGen.frame();
        CodeGenLoopFrame::push(codeGen, frame, loopState->loopLabel, loopState->doneLabel);
        return Result::Continue;
    }

    const AstNodeRef bodyRef = codeGen.resolvedNodeRef(nodeBodyRef);
    if (childRef == bodyRef)
    {
        builder.placeLabel(loopState->bodyLabel);

        CodeGenFrame frame = codeGen.frame();
        CodeGenLoopFrame::pushWithDeferScope(codeGen, frame, postStmtRef.isValid() ? loopState->postLabel : loopState->loopLabel, loopState->doneLabel);
    }

    return Result::Continue;
}

Result AstForCStyleStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForCStyleStmtCodeGenPayload* loopState = codeGen.safeNodePayload<ForCStyleStmtCodeGenPayload>(codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef     = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef postStmtRef = codeGen.resolvedNodeRef(nodePostStmtRef);

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

    const AstNodeRef bodyRef = codeGen.resolvedNodeRef(nodeBodyRef);
    if (childRef == bodyRef)
    {
        SWC_RESULT(codeGen.popDeferScope());
        if (codeGen.currentInstructionBlocksFallthrough() && !codeGen.frame().currentLoopHasContinueJump())
        {
            codeGen.popFrame();
            return Result::Continue;
        }

        MicroBuilder&           builder = codeGen.builder();
        const ScopedDebugNoStep noStep(builder, true);
        if (postStmtRef.isValid())
        {
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->postLabel);
        }
        else
        {
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->loopLabel);
        }
        codeGen.popFrame();
    }

    return Result::Continue;
}

Result AstForCStyleStmt::codeGenPostNode(CodeGen& codeGen)
{
    ForCStyleStmtCodeGenPayload* loopState = codeGen.safeNodePayload<ForCStyleStmtCodeGenPayload>(codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(loopState->doneLabel);
    *loopState = {};
    return Result::Continue;
}

Result AstForStmt::codeGenPreNode(CodeGen& codeGen) const
{
    MicroBuilder&         builder = codeGen.builder();
    ForStmtCodeGenPayload loopState;
    loopState.loopLabel     = builder.createLabel();
    loopState.continueLabel = builder.createLabel();
    loopState.doneLabel     = builder.createLabel();

    const SemaNodeView symbolView = codeGen.curViewSymbol();
    if (symbolView.sym() != nullptr && symbolView.sym()->isVariable())
        loopState.indexSym = &symbolView.sym()->cast<SymbolVariable>();

    codeGen.setNodePayload(codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstForStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForStmtCodeGenPayload* loopState = codeGen.safeNodePayload<ForStmtCodeGenPayload>(codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const bool isWhereChild = nodeWhereRef.isValid() && matchesChildRef(codeGen, childRef, nodeWhereRef);
    if (!isWhereChild && !(nodeWhereRef.isInvalid() && nodeBodyRef.isValid() && matchesChildRef(codeGen, childRef, nodeBodyRef)))
        return Result::Continue;

    CodeGenFrame frame = codeGen.frame();
    CodeGenLoopFrame::pushWithDeferScope(codeGen, frame, loopState->continueLabel, loopState->doneLabel);
    return Result::Continue;
}

Result AstForStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    ForStmtCodeGenPayload* loopState = codeGen.safeNodePayload<ForStmtCodeGenPayload>(codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const bool isExprChild = matchesChildRef(codeGen, childRef, nodeExprRef);

    if (isExprChild)
    {
        SWC_RESULT(emitForInit(codeGen, *this, *loopState));
        MicroBuilder& builder = codeGen.builder();
        builder.placeLabel(loopState->loopLabel);
        if (loopState->indexSym != nullptr)
            emitLoopVariablePayload(codeGen, *loopState->indexSym, loopState->indexReg);
        return Result::Continue;
    }

    const bool isWhereChild = nodeWhereRef.isValid() && matchesChildRef(codeGen, childRef, nodeWhereRef);
    if (isWhereChild)
    {
        const CodeGenNodePayload& wherePayload = codeGen.payload(childRef);
        const SemaNodeView        whereView    = codeGen.viewType(childRef);
        CodeGenCompareHelpers::emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), loopState->continueLabel);
        return Result::Continue;
    }

    const bool isBodyChild = nodeBodyRef.isValid() && matchesChildRef(codeGen, childRef, nodeBodyRef);
    if (isBodyChild)
    {
        SWC_RESULT(codeGen.popDeferScope());

        if (nodeWhereRef.isInvalid() && codeGen.currentInstructionBlocksFallthrough() && !codeGen.frame().currentLoopHasContinueJump())
        {
            codeGen.popFrame();
            return Result::Continue;
        }

        const TypeInfo&   indexType     = codeGen.typeMgr().get(loopState->indexTypeRef);
        const TypeInfo*   unwrappedType = indexType.unwrapAliasEnumType(codeGen.ctx());
        const TypeInfo&   compareType   = unwrappedType ? *unwrappedType : indexType;
        const MicroOpBits opBits        = loopOperationBits(codeGen, compareType);
        MicroBuilder&     builder       = codeGen.builder();
        builder.setCurrentDebugSourceCodeRef(codeGen.node(codeGen.curNodeRef()).codeRef());
        builder.setCurrentDebugNoStep(false);

        builder.placeLabel(loopState->continueLabel);
        if (loopState->indexSym != nullptr)
            emitLoopVariableReg(codeGen, *loopState->indexSym, loopState->indexReg);
        if (loopState->inclusive)
        {
            builder.emitCmpRegReg(loopState->indexReg, loopState->boundReg, opBits);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, loopState->doneLabel);
            builder.emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Add, opBits);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->loopLabel);
        }
        else
        {
            builder.emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Add, opBits);
            builder.emitCmpRegReg(loopState->indexReg, loopState->boundReg, opBits);
            builder.emitJumpToLabel(CodeGenCompareHelpers::lessCond(loopState->unsignedCmp), MicroOpBits::B32, loopState->loopLabel);
        }

        codeGen.popFrame();
        return Result::Continue;
    }

    return Result::Continue;
}

Result AstForStmt::codeGenPostNode(CodeGen& codeGen)
{
    ForStmtCodeGenPayload* loopState = codeGen.safeNodePayload<ForStmtCodeGenPayload>(codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(loopState->doneLabel);
    *loopState = {};
    return Result::Continue;
}

Result AstContinueStmt::codeGenPostNode(CodeGen& codeGen)
{
    const CodeGenFrame::BreakContext continueCtx = codeGen.frame().currentContinueContext();
    if (continueCtx.kind != CodeGenFrame::BreakContextKind::Loop)
        return Result::Continue;

    codeGen.frame().setCurrentLoopHasContinueJump(true);

    const MicroLabelRef continueLabel = codeGen.frame().currentLoopContinueLabel();
    if (continueLabel == MicroLabelRef::invalid())
        return Result::Continue;

    SWC_RESULT(codeGen.emitDeferredActionsUntilBreakOwner(continueCtx.nodeRef));
    MicroBuilder& builder = codeGen.builder();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, continueLabel);
    return Result::Continue;
}

SWC_END_NAMESPACE();
