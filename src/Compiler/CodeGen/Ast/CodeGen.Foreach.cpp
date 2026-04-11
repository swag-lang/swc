#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
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
        uint64_t        valueSize        = 0;
        bool            reverse          = false;
        bool            enumValues       = false;
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
            return CodeGenFunctionHelpers::resolveClosureCapturePayload(codeGen, symVar);

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            if (const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar))
                return *symbolPayload;
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
        {
            if (const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar))
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

    using CodeGenFunctionHelpers::resolveStoredVariablePayload;

    CodeGenNodePayload foreachExprPayload(CodeGen& codeGen, AstNodeRef exprRef)
    {
        if (const auto* payload = codeGen.safePayload(exprRef))
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
                codeGen.variablePayload(symVar) ||
                (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal)))
                return resolveStoredVariablePayload(codeGen, symVar);
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

    const SymbolEnum* foreachExprEnumSymbol(CodeGen& codeGen, AstNodeRef exprRef)
    {
        const SemaNodeView storedTypeView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Type);
        if (storedTypeView.type() && storedTypeView.type()->isEnum())
            return &storedTypeView.type()->payloadSymEnum();

        const SemaNodeView typeView = codeGen.viewType(exprRef);
        if (typeView.type() && typeView.type()->isEnum())
            return &typeView.type()->payloadSymEnum();

        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Symbol);
        if (storedView.sym() && storedView.sym()->isEnum())
            return &storedView.sym()->cast<SymbolEnum>();

        const SemaNodeView symbolView = codeGen.viewSymbol(exprRef);
        if (symbolView.sym() && symbolView.sym()->isEnum())
            return &symbolView.sym()->cast<SymbolEnum>();

        return nullptr;
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

    MicroReg emitForeachValueAddress(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState)
    {
        const MicroReg elementAddressReg = emitForeachElementAddress(codeGen, loopState);
        if (!loopState.enumValues)
            return elementAddressReg;

        const MicroReg valueAddressReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegMem(valueAddressReg, elementAddressReg, offsetof(Runtime::TypeValue, value), MicroOpBits::B64);
        return valueAddressReg;
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

        const MicroReg elementAddressReg = emitForeachValueAddress(codeGen, loopState);
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
            SWC_ASSERT(loopState.valueSize <= std::numeric_limits<uint32_t>::max());
            if (valuePayload.isAddress())
            {
                CodeGenMemoryHelpers::emitMemCopy(codeGen, valuePayload.reg, elementAddressReg, static_cast<uint32_t>(loopState.valueSize));
            }
            else
            {
                SWC_ASSERT(loopState.valueSize == 1 || loopState.valueSize == 2 || loopState.valueSize == 4 || loopState.valueSize == 8);
                builder.emitLoadRegMem(valuePayload.reg, elementAddressReg, 0, microOpBitsFromChunkSize(static_cast<uint32_t>(loopState.valueSize)));
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

    Result emitForeachInit(CodeGen& codeGen, const AstForeachStmt& node, ForeachStmtCodeGenPayload& loopState)
    {
        const AstNodeRef exprRef = node.nodeExprRef;
        MicroBuilder&    builder = codeGen.builder();

        loopState.baseReg    = MicroReg::invalid();
        loopState.countReg   = codeGen.nextVirtualIntRegister();
        loopState.indexReg   = codeGen.nextVirtualIntRegister();
        loopState.enumValues = false;

        if (const SymbolEnum* symEnum = foreachExprEnumSymbol(codeGen, exprRef))
        {
            MicroReg typeInfoReg = MicroReg::invalid();
            SWC_RESULT(CodeGenConstantHelpers::loadTypeInfoConstantReg(typeInfoReg, codeGen, symEnum->typeRef()));

            loopState.enumValues  = true;
            loopState.elementSize = sizeof(Runtime::TypeValue);
            loopState.valueSize   = codeGen.typeMgr().get(symEnum->typeRef()).sizeOf(codeGen.ctx());
            SWC_ASSERT(loopState.elementSize > 0);
            SWC_ASSERT(loopState.valueSize > 0);

            loopState.baseReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(loopState.baseReg, typeInfoReg, offsetof(Runtime::TypeInfoEnum, values.ptr), MicroOpBits::B64);
            builder.emitLoadRegMem(loopState.countReg, typeInfoReg, offsetof(Runtime::TypeInfoEnum, values.count), MicroOpBits::B64);
        }
        else
        {
            const SemaNodeView       exprView    = foreachExprView(codeGen, exprRef);
            const CodeGenNodePayload exprPayload = foreachExprPayload(codeGen, exprRef);
            const TypeInfo&          exprType    = *(exprView.type());

            if (exprType.isArray())
            {
                const TypeInfo& elementType = codeGen.typeMgr().get(exprType.payloadArrayElemTypeRef());
                loopState.elementSize       = elementType.sizeOf(codeGen.ctx());
                loopState.valueSize         = loopState.elementSize;
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
                loopState.valueSize       = loopState.elementSize;

                const MicroReg sourceAddressReg = materializeForeachSourceAddress(codeGen, loopState, exprPayload, exprType);
                loopState.baseReg               = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(loopState.baseReg, sourceAddressReg, offsetof(Runtime::Slice<std::byte>, ptr), MicroOpBits::B64);
                builder.emitLoadRegMem(loopState.countReg, sourceAddressReg, countOffset, MicroOpBits::B64);
            }
        }

        if (loopState.reverse)
            builder.emitLoadRegReg(loopState.indexReg, loopState.countReg, MicroOpBits::B64);
        else
            builder.emitLoadRegImm(loopState.indexReg, ApInt(0, 64), MicroOpBits::B64);

        emitForeachStoreLoopState(codeGen, loopState);
        return Result::Continue;
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
    codeGen.pushDeferScope(AstNodeRef::invalid(), codeGen.curNodeRef());
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
        SWC_RESULT(emitForeachInit(codeGen, *this, *loopState));
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
        SWC_RESULT(codeGen.popDeferScope());

        if (codeGen.currentInstructionBlocksFallthrough() && !codeGen.frame().currentLoopHasContinueJump())
        {
            codeGen.popFrame();
            return Result::Continue;
        }

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
