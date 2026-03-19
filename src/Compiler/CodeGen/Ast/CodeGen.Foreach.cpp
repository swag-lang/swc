#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ForeachLoopRuntimeState
    {
        uint64_t base  = 0;
        uint64_t count = 0;
        uint64_t index = 0;
    };

    struct ForeachStmtCodeGenPayload
    {
        MicroLabelRef   loopLabel        = MicroLabelRef::invalid();
        MicroLabelRef   continueLabel    = MicroLabelRef::invalid();
        MicroLabelRef   doneLabel        = MicroLabelRef::invalid();
        MicroReg        baseReg          = MicroReg::invalid();
        MicroReg        countReg         = MicroReg::invalid();
        MicroReg        indexReg         = MicroReg::invalid();
        uint32_t        aliasSymbolCount = 0;
        SymbolVariable* stateSym         = nullptr;
        SymbolVariable* sourceSpillSym   = nullptr;
        uint64_t        elementSize      = 0;
        bool            reverse          = false;
    };

    ForeachStmtCodeGenPayload* foreachStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<ForeachStmtCodeGenPayload>(nodeRef);
    }

    ForeachStmtCodeGenPayload& setForeachStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const ForeachStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseForeachStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        ForeachStmtCodeGenPayload* payload = foreachStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    CodeGenNodePayload resolveForeachVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar);

    CodeGenNodePayload resolveClosureCapturePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar))
            return *symbolPayload;

        SWC_ASSERT(codeGen.currentFunctionClosureContextReg().isValid());

        CodeGenNodePayload capturePayload;
        capturePayload.typeRef = symVar.typeRef();
        capturePayload.setIsAddress();

        const MicroReg captureReg = codeGen.offsetAddressReg(codeGen.currentFunctionClosureContextReg(), symVar.closureCaptureOffset());
        if (symVar.closureCaptureByRef())
        {
            capturePayload.reg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegMem(capturePayload.reg, captureReg, 0, MicroOpBits::B64);
        }
        else
        {
            capturePayload.reg = captureReg;
        }

        codeGen.setVariablePayload(symVar, capturePayload);
        return capturePayload;
    }

    MicroReg materializeForeachInternalStackAddress(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        SWC_ASSERT(symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());
        return codeGen.offsetAddressReg(codeGen.localStackBaseReg(), symVar.offset());
    }

    MicroReg materializeForeachSourceAddress(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState, const CodeGenNodePayload& sourcePayload, const TypeInfo& sourceType)
    {
        if (sourcePayload.isAddress())
            return sourcePayload.reg;

        const uint64_t sizeOfValue = sourceType.sizeOf(codeGen.ctx());
        if (sizeOfValue != 1 && sizeOfValue != 2 && sizeOfValue != 4 && sizeOfValue != 8)
            return sourcePayload.reg;

        SWC_ASSERT(loopState.sourceSpillSym != nullptr);

        // Foreach needs a stable base pointer across iterations, so spill small by-value sources into the
        // hidden storage symbol reserved for the loop state.
        MicroBuilder&  builder      = codeGen.builder();
        const MicroReg spillAddrReg = materializeForeachInternalStackAddress(codeGen, *(loopState.sourceSpillSym));
        builder.emitLoadMemReg(spillAddrReg, 0, sourcePayload.reg, microOpBitsFromChunkSize(static_cast<uint32_t>(sizeOfValue)));
        return spillAddrReg;
    }

    CodeGenNodePayload resolveForeachVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.isClosureCapture())
            return resolveClosureCapturePayload(codeGen, symVar);

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar))
                return *symbolPayload;
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
        {
            if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar))
                return *symbolPayload;
            return codeGen.resolveLocalStackPayload(symVar);
        }

        if (symVar.hasGlobalStorage())
        {
            CodeGenNodePayload symbolPayload;
            symbolPayload.typeRef = symVar.typeRef();
            symbolPayload.setIsAddress();
            symbolPayload.reg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegDataSegmentReloc(symbolPayload.reg, symVar.globalStorageKind(), symVar.offset());
            codeGen.setVariablePayload(symVar, symbolPayload);
            return symbolPayload;
        }

        if (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            return codeGen.resolveLocalStackPayload(symVar);

        // Foreach aliases are not guaranteed to be part of function-local-variable reset,
        // so always refresh their payload instead of reusing any cached symbol payload.
        CodeGenNodePayload regPayload;
        regPayload.typeRef = symVar.typeRef();
        regPayload.setIsValue();
        regPayload.reg = codeGen.nextVirtualRegisterForType(symVar.typeRef());
        codeGen.setVariablePayload(symVar, regPayload);
        return regPayload;
    }

    CodeGenNodePayload resolveForeachStoredVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.isClosureCapture())
            return resolveClosureCapturePayload(codeGen, symVar);

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar))
            return *symbolPayload;

        if (symVar.hasGlobalStorage())
        {
            CodeGenNodePayload globalPayload;
            globalPayload.typeRef = symVar.typeRef();
            globalPayload.setIsAddress();
            globalPayload.reg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegDataSegmentReloc(globalPayload.reg, symVar.globalStorageKind(), symVar.offset());
            return globalPayload;
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            return codeGen.resolveLocalStackPayload(symVar);

        if (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            return codeGen.resolveLocalStackPayload(symVar);

        SWC_UNREACHABLE();
    }

    CodeGenNodePayload foreachExprPayload(CodeGen& codeGen, AstNodeRef exprRef)
    {
        if (const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(exprRef))
        {
            if (payload->reg.isValid())
                return *payload;
        }

        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Symbol);
        if (storedView.sym() && storedView.sym()->isVariable())
        {
            const auto& symVar = storedView.sym()->cast<SymbolVariable>();
            if (symVar.isClosureCapture() ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) ||
                symVar.hasGlobalStorage() ||
                CodeGen::variablePayload(symVar) ||
                (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal)))
                return resolveForeachStoredVariablePayload(codeGen, symVar);
        }

        return codeGen.payload(exprRef);
    }

    SemaNodeView foreachExprView(CodeGen& codeGen, AstNodeRef exprRef)
    {
        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Type);
        if (storedView.type() != nullptr)
            return storedView;
        return codeGen.viewType(exprRef);
    }

    MicroReg emitForeachElementAddress(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState)
    {
        SWC_ASSERT(loopState.baseReg.isValid());
        SWC_ASSERT(loopState.indexReg.isValid());
        SWC_ASSERT(loopState.elementSize > 0);

        const MicroReg elementAddressReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadAddressAmcRegMem(elementAddressReg, MicroOpBits::B64, loopState.baseReg, loopState.indexReg, loopState.elementSize, 0, MicroOpBits::B64);
        return elementAddressReg;
    }

    MicroReg emitForeachStateAddressReg(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState)
    {
        SWC_ASSERT(loopState.stateSym != nullptr);
        return materializeForeachInternalStackAddress(codeGen, *(loopState.stateSym));
    }

    void emitForeachStoreLoopState(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState)
    {
        SWC_ASSERT(loopState.baseReg.isValid());
        SWC_ASSERT(loopState.countReg.isValid());
        SWC_ASSERT(loopState.indexReg.isValid());

        // Persist progress in the hidden state slot because loop callbacks and `continue` paths can
        // allocate fresh virtual registers before the next iteration.
        MicroBuilder&  builder         = codeGen.builder();
        const MicroReg stateAddressReg = emitForeachStateAddressReg(codeGen, loopState);
        builder.emitLoadMemReg(stateAddressReg, offsetof(ForeachLoopRuntimeState, base), loopState.baseReg, MicroOpBits::B64);
        builder.emitLoadMemReg(stateAddressReg, offsetof(ForeachLoopRuntimeState, count), loopState.countReg, MicroOpBits::B64);
        builder.emitLoadMemReg(stateAddressReg, offsetof(ForeachLoopRuntimeState, index), loopState.indexReg, MicroOpBits::B64);
    }

    void emitForeachLoadLoopState(CodeGen& codeGen, ForeachStmtCodeGenPayload& loopState)
    {
        MicroBuilder&  builder         = codeGen.builder();
        const MicroReg stateAddressReg = emitForeachStateAddressReg(codeGen, loopState);

        loopState.baseReg  = codeGen.nextVirtualIntRegister();
        loopState.countReg = codeGen.nextVirtualIntRegister();
        loopState.indexReg = codeGen.nextVirtualIntRegister();

        builder.emitLoadRegMem(loopState.baseReg, stateAddressReg, offsetof(ForeachLoopRuntimeState, base), MicroOpBits::B64);
        builder.emitLoadRegMem(loopState.countReg, stateAddressReg, offsetof(ForeachLoopRuntimeState, count), MicroOpBits::B64);
        builder.emitLoadRegMem(loopState.indexReg, stateAddressReg, offsetof(ForeachLoopRuntimeState, index), MicroOpBits::B64);
    }

    void emitForeachBindSymbols(CodeGen& codeGen, const AstForeachStmt& node, const ForeachStmtCodeGenPayload& loopState)
    {
        const SemaNodeView symbolsView = codeGen.viewSymbolList(codeGen.curNodeRef());
        const auto         symbols     = symbolsView.symList();
        const size_t       aliasCount  = std::min<size_t>(loopState.aliasSymbolCount, symbols.size());
        if (!aliasCount)
            return;

        const MicroReg elementAddressReg = emitForeachElementAddress(codeGen, loopState);
        MicroBuilder&  builder           = codeGen.builder();

        const SymbolVariable&    valueSym     = symbols[0]->cast<SymbolVariable>();
        const CodeGenNodePayload valuePayload = resolveForeachVariablePayload(codeGen, valueSym);
        if (node.hasFlag(AstForeachStmtFlagsE::ByAddress))
        {
            if (valuePayload.isAddress())
                builder.emitLoadMemReg(valuePayload.reg, 0, elementAddressReg, MicroOpBits::B64);
            else
                builder.emitLoadRegReg(valuePayload.reg, elementAddressReg, MicroOpBits::B64);
        }
        else
        {
            SWC_ASSERT(loopState.elementSize <= std::numeric_limits<uint32_t>::max());
            if (valuePayload.isAddress())
            {
                CodeGenMemoryHelpers::emitMemCopy(codeGen, valuePayload.reg, elementAddressReg, static_cast<uint32_t>(loopState.elementSize));
            }
            else
            {
                SWC_ASSERT(loopState.elementSize == 1 || loopState.elementSize == 2 || loopState.elementSize == 4 || loopState.elementSize == 8);
                builder.emitLoadRegMem(valuePayload.reg, elementAddressReg, 0, microOpBitsFromChunkSize(static_cast<uint32_t>(loopState.elementSize)));
            }
        }

        if (aliasCount < 2)
            return;

        const SymbolVariable&    indexSym     = symbols[1]->cast<SymbolVariable>();
        const CodeGenNodePayload indexPayload = resolveForeachVariablePayload(codeGen, indexSym);
        if (indexPayload.isAddress())
            builder.emitLoadMemReg(indexPayload.reg, 0, loopState.indexReg, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(indexPayload.reg, loopState.indexReg, MicroOpBits::B64);
    }

    void emitForeachInit(CodeGen& codeGen, const AstForeachStmt& node, ForeachStmtCodeGenPayload& loopState)
    {
        const AstNodeRef         exprRef     = node.nodeExprRef;
        const SemaNodeView       exprView    = foreachExprView(codeGen, exprRef);
        const CodeGenNodePayload exprPayload = foreachExprPayload(codeGen, exprRef);
        const TypeInfo&          exprType    = *(exprView.type());
        MicroBuilder&            builder     = codeGen.builder();

        loopState.baseReg  = MicroReg::invalid();
        loopState.countReg = codeGen.nextVirtualIntRegister();
        loopState.indexReg = codeGen.nextVirtualIntRegister();

        if (exprType.isArray())
        {
            const TypeInfo& elementType = codeGen.typeMgr().get(exprType.payloadArrayElemTypeRef());
            loopState.elementSize       = elementType.sizeOf(codeGen.ctx());
            SWC_ASSERT(loopState.elementSize > 0);

            const uint64_t totalSize  = exprType.sizeOf(codeGen.ctx());
            const uint64_t totalCount = totalSize / loopState.elementSize;
            loopState.baseReg         = materializeForeachSourceAddress(codeGen, loopState, exprPayload, exprType);
            builder.emitLoadRegImm(loopState.countReg, ApInt(totalCount, 64), MicroOpBits::B64);
        }
        else
        {
            TypeRef  valueTypeRef = TypeRef::invalid();
            uint64_t countOffset  = offsetof(Runtime::Slice<std::byte>, count);
            if (exprType.isSlice())
                valueTypeRef = exprType.payloadTypeRef();
            else if (exprType.isString())
            {
                valueTypeRef = codeGen.typeMgr().typeU8();
                countOffset  = offsetof(Runtime::String, length);
            }
            else if (exprType.isVariadic())
                valueTypeRef = codeGen.typeMgr().typeAny();
            else if (exprType.isTypedVariadic())
                valueTypeRef = exprType.payloadTypeRef();
            else
                SWC_UNREACHABLE();

            const TypeInfo& valueType = codeGen.typeMgr().get(valueTypeRef);
            loopState.elementSize     = valueType.sizeOf(codeGen.ctx());

            const MicroReg sourceAddressReg = materializeForeachSourceAddress(codeGen, loopState, exprPayload, exprType);
            loopState.baseReg               = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(loopState.baseReg, sourceAddressReg, offsetof(Runtime::Slice<std::byte>, ptr), MicroOpBits::B64);
            builder.emitLoadRegMem(loopState.countReg, sourceAddressReg, countOffset, MicroOpBits::B64);
        }

        if (loopState.reverse)
            builder.emitLoadRegReg(loopState.indexReg, loopState.countReg, MicroOpBits::B64);
        else
            builder.emitLoadRegImm(loopState.indexReg, ApInt(0, 64), MicroOpBits::B64);

        emitForeachStoreLoopState(codeGen, loopState);
    }
}

Result AstForeachStmt::codeGenPreNode(CodeGen& codeGen) const
{
    ForeachStmtCodeGenPayload loopState;
    const SemaNodeView        symbolsView = codeGen.viewSymbolList(codeGen.curNodeRef());
    const auto                symbols     = symbolsView.symList();
    SWC_ASSERT(symbols.size() >= 2);
    if (symbols.size() >= 2)
    {
        const size_t stateIndex    = symbols.size() - 2;
        const size_t spillIndex    = symbols.size() - 1;
        loopState.aliasSymbolCount = static_cast<uint32_t>(std::min<size_t>(2, stateIndex));
        loopState.stateSym         = &symbols[stateIndex]->cast<SymbolVariable>();
        loopState.sourceSpillSym   = &symbols[spillIndex]->cast<SymbolVariable>();
    }

    MicroBuilder& builder   = codeGen.builder();
    loopState.loopLabel     = builder.createLabel();
    loopState.continueLabel = builder.createLabel();
    loopState.doneLabel     = builder.createLabel();
    loopState.reverse       = modifierFlags.has(AstModifierFlagsE::Reverse);
    setForeachStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstForeachStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef whereRef = codeGen.resolvedNodeRef(nodeWhereRef);
    const AstNodeRef bodyRef  = codeGen.resolvedNodeRef(nodeBodyRef);
    if (childRef != whereRef && !(childRef == bodyRef && whereRef.isInvalid()))
        return Result::Continue;

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
    frame.setCurrentLoopContinueLabel(loopState->continueLabel);
    frame.setCurrentLoopBreakLabel(loopState->doneLabel);
    frame.setCurrentLoopIndex(loopState->indexReg, codeGen.typeMgr().typeU64());
    codeGen.pushFrame(frame);
    return Result::Continue;
}

Result AstForeachStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef  = codeGen.resolvedNodeRef(nodeExprRef);
    const AstNodeRef whereRef = codeGen.resolvedNodeRef(nodeWhereRef);
    const AstNodeRef bodyRef  = codeGen.resolvedNodeRef(nodeBodyRef);

    MicroBuilder& builder = codeGen.builder();

    if (childRef == exprRef)
    {
        emitForeachInit(codeGen, *this, *loopState);
        builder.placeLabel(loopState->loopLabel);
        // The loop head always reloads the persisted state because the previous iteration may have crossed
        // callbacks that invalidated the current virtual register assignments.
        emitForeachLoadLoopState(codeGen, *loopState);
        builder.emitCmpRegImm(loopState->countReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, loopState->doneLabel);
        if (loopState->reverse)
        {
            builder.emitLoadRegReg(loopState->indexReg, loopState->countReg, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        }
        emitForeachBindSymbols(codeGen, *this, *loopState);
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
        builder.setCurrentDebugSourceCodeRef(codeGen.node(codeGen.curNodeRef()).codeRef());
        builder.setCurrentDebugNoStep(false);
        builder.placeLabel(loopState->continueLabel);
        emitForeachLoadLoopState(codeGen, *loopState);
        if (!loopState->reverse)
            builder.emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(loopState->countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        emitForeachStoreLoopState(codeGen, *loopState);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->loopLabel);
        codeGen.popFrame();
        return Result::Continue;
    }

    return Result::Continue;
}

Result AstForeachStmt::codeGenPostNode(CodeGen& codeGen)
{
    const ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(loopState->doneLabel);
    eraseForeachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
