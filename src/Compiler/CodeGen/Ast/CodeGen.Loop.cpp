#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
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

    struct LoopStmtCodeGenPayload
    {
        MicroLabelRef continueLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel     = MicroLabelRef::invalid();
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

    AstNodeRef resolvedNodeRef(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.viewZero(nodeRef).nodeRef();
    }

    LoopStmtCodeGenPayload* loopStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        if (nodeRef.isInvalid())
            return nullptr;
        return codeGen.sema().codeGenPayload<LoopStmtCodeGenPayload>(nodeRef);
    }

    LoopStmtCodeGenPayload& setLoopStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const LoopStmtCodeGenPayload& payloadValue)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        SWC_ASSERT(nodeRef.isValid());

        auto* payload = codeGen.sema().codeGenPayload<LoopStmtCodeGenPayload>(nodeRef);
        if (!payload)
        {
            payload = codeGen.compiler().allocate<LoopStmtCodeGenPayload>();
            codeGen.sema().setCodeGenPayload(nodeRef, payload);
        }

        *payload = payloadValue;
        return *payload;
    }

    void eraseLoopStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        LoopStmtCodeGenPayload* payload = loopStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    ForeachStmtCodeGenPayload* foreachStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        if (nodeRef.isInvalid())
            return nullptr;
        return codeGen.sema().codeGenPayload<ForeachStmtCodeGenPayload>(nodeRef);
    }

    ForeachStmtCodeGenPayload& setForeachStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const ForeachStmtCodeGenPayload& payloadValue)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        SWC_ASSERT(nodeRef.isValid());

        auto* payload = codeGen.sema().codeGenPayload<ForeachStmtCodeGenPayload>(nodeRef);
        if (!payload)
        {
            payload = codeGen.compiler().allocate<ForeachStmtCodeGenPayload>();
            codeGen.sema().setCodeGenPayload(nodeRef, payload);
        }

        *payload = payloadValue;
        return *payload;
    }

    void eraseForeachStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        ForeachStmtCodeGenPayload* payload = foreachStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    MicroOpBits conditionOpBits(const TypeInfo* typeInfo, TaskContext& ctx)
    {
        if (!typeInfo)
            return MicroOpBits::B64;

        switch (typeInfo->sizeOf(ctx))
        {
            case 1:
                return MicroOpBits::B8;
            case 2:
                return MicroOpBits::B16;
            case 4:
                return MicroOpBits::B32;
            case 8:
                return MicroOpBits::B64;
            default:
                return MicroOpBits::B64;
        }
    }

    void emitConditionFalseJump(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef typeRef, MicroLabelRef falseLabel)
    {
        const TypeInfo&   typeInfo = codeGen.typeMgr().get(typeRef);
        const MicroOpBits condBits = conditionOpBits(&typeInfo, codeGen.ctx());
        const MicroReg    condReg  = codeGen.nextVirtualIntRegister();

        MicroBuilder& builder = codeGen.builder();
        if (payload.isAddress())
            builder.emitLoadRegMem(condReg, payload.reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, payload.reg, condBits);

        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, falseLabel);
    }

    CodeGenNodePayload resolveForeachVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar);

    MicroReg materializeForeachSourceAddress(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState, const CodeGenNodePayload& sourcePayload, const TypeInfo& sourceType)
    {
        if (sourcePayload.isAddress())
            return sourcePayload.reg;

        const uint64_t sizeOfValue = sourceType.sizeOf(codeGen.ctx());
        if (sizeOfValue != 1 && sizeOfValue != 2 && sizeOfValue != 4 && sizeOfValue != 8)
            return sourcePayload.reg;

        SWC_ASSERT(loopState.sourceSpillSym != nullptr);
        const CodeGenNodePayload spillPayload = resolveForeachVariablePayload(codeGen, *SWC_NOT_NULL(loopState.sourceSpillSym));
        SWC_ASSERT(spillPayload.isAddress());

        MicroBuilder&  builder      = codeGen.builder();
        const MicroReg spillAddrReg = spillPayload.reg;
        builder.emitLoadMemReg(spillAddrReg, 0, sourcePayload.reg, microOpBitsFromChunkSize(static_cast<uint32_t>(sizeOfValue)));
        return spillAddrReg;
    }

    CodeGenNodePayload resolveForeachVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar))
                return *symbolPayload;
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
        {
            if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar))
                return *symbolPayload;
            SWC_ASSERT(codeGen.localStackBaseReg().isValid());

            CodeGenNodePayload localPayload;
            localPayload.typeRef = symVar.typeRef();
            localPayload.setIsAddress();
            if (!symVar.offset())
            {
                localPayload.reg = codeGen.localStackBaseReg();
            }
            else
            {
                MicroBuilder& builder = codeGen.builder();
                localPayload.reg      = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(localPayload.reg, codeGen.localStackBaseReg(), MicroOpBits::B64);
                builder.emitOpBinaryRegImm(localPayload.reg, ApInt(symVar.offset(), 64), MicroOp::Add, MicroOpBits::B64);
            }

            codeGen.setVariablePayload(symVar, localPayload);
            return localPayload;
        }

        // Foreach aliases are not guaranteed to be part of function local-variable reset,
        // so always refresh their payload instead of reusing any cached symbol payload.
        CodeGenNodePayload regPayload;
        regPayload.typeRef = symVar.typeRef();
        regPayload.setIsValue();
        regPayload.reg = codeGen.nextVirtualRegisterForType(symVar.typeRef());
        codeGen.setVariablePayload(symVar, regPayload);
        return regPayload;
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
        const CodeGenNodePayload statePayload = resolveForeachVariablePayload(codeGen, *SWC_NOT_NULL(loopState.stateSym));
        SWC_ASSERT(statePayload.isAddress());
        return statePayload.reg;
    }

    void emitForeachStoreLoopState(CodeGen& codeGen, const ForeachStmtCodeGenPayload& loopState)
    {
        SWC_ASSERT(loopState.baseReg.isValid());
        SWC_ASSERT(loopState.countReg.isValid());
        SWC_ASSERT(loopState.indexReg.isValid());

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
                CodeGenHelpers::emitMemCopy(codeGen, valuePayload.reg, elementAddressReg, static_cast<uint32_t>(loopState.elementSize));
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
        const AstNodeRef          exprRef     = resolvedNodeRef(codeGen, node.nodeExprRef);
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const TypeInfo&           exprType    = *SWC_NOT_NULL(exprView.type());
        MicroBuilder&             builder     = codeGen.builder();

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

    loopState.loopLabel     = codeGen.builder().createLabel();
    loopState.continueLabel = codeGen.builder().createLabel();
    loopState.doneLabel     = codeGen.builder().createLabel();
    loopState.reverse       = modifierFlags.has(AstModifierFlagsE::Reverse);
    setForeachStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstForeachStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef bodyRef = resolvedNodeRef(codeGen, nodeBodyRef);
    if (childRef != bodyRef)
        return Result::Continue;

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
    frame.setCurrentLoopContinueLabel(loopState->continueLabel);
    frame.setCurrentLoopBreakLabel(loopState->doneLabel);
    codeGen.pushFrame(frame);
    return Result::Continue;
}

Result AstForeachStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef  = resolvedNodeRef(codeGen, nodeExprRef);
    const AstNodeRef whereRef = resolvedNodeRef(codeGen, nodeWhereRef);
    const AstNodeRef bodyRef  = resolvedNodeRef(codeGen, nodeBodyRef);

    if (childRef == exprRef)
    {
        emitForeachInit(codeGen, *this, *loopState);
        codeGen.builder().placeLabel(loopState->loopLabel);
        emitForeachLoadLoopState(codeGen, *loopState);
        codeGen.builder().emitCmpRegImm(loopState->countReg, ApInt(0, 64), MicroOpBits::B64);
        codeGen.builder().emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, loopState->doneLabel);
        if (loopState->reverse)
        {
            codeGen.builder().emitLoadRegReg(loopState->indexReg, loopState->countReg, MicroOpBits::B64);
            codeGen.builder().emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        }
        emitForeachBindSymbols(codeGen, *this, *loopState);
        return Result::Continue;
    }

    if (childRef == whereRef)
    {
        const CodeGenNodePayload& wherePayload = codeGen.payload(whereRef);
        const SemaNodeView        whereView    = codeGen.viewType(whereRef);
        emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), loopState->continueLabel);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        codeGen.builder().placeLabel(loopState->continueLabel);
        emitForeachLoadLoopState(codeGen, *loopState);
        if (!loopState->reverse)
            codeGen.builder().emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        codeGen.builder().emitOpBinaryRegImm(loopState->countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        emitForeachStoreLoopState(codeGen, *loopState);
        codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->loopLabel);
        codeGen.popFrame();
        return Result::Continue;
    }

    return Result::Continue;
}

Result AstForeachStmt::codeGenPostNode(CodeGen& codeGen) const
{
    const ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    codeGen.builder().placeLabel(loopState->doneLabel);
    eraseForeachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstWhileStmt::codeGenPreNode(CodeGen& codeGen) const
{
    LoopStmtCodeGenPayload loopState;
    loopState.continueLabel = codeGen.builder().createLabel();
    loopState.doneLabel     = codeGen.builder().createLabel();
    setLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstWhileStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    const AstNodeRef exprRef = resolvedNodeRef(codeGen, nodeExprRef);
    const AstNodeRef bodyRef = resolvedNodeRef(codeGen, nodeBodyRef);

    if (childRef == exprRef)
    {
        codeGen.builder().placeLabel(loopState->continueLabel);
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

    const AstNodeRef exprRef = resolvedNodeRef(codeGen, nodeExprRef);
    const AstNodeRef bodyRef = resolvedNodeRef(codeGen, nodeBodyRef);

    if (childRef == exprRef)
    {
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        emitConditionFalseJump(codeGen, exprPayload, exprView.typeRef(), loopState->doneLabel);
        return Result::Continue;
    }

    if (childRef == bodyRef)
    {
        codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->continueLabel);
        codeGen.popFrame();
    }

    return Result::Continue;
}

Result AstWhileStmt::codeGenPostNode(CodeGen& codeGen) const
{
    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    codeGen.builder().placeLabel(loopState->doneLabel);
    eraseLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPreNode(CodeGen& codeGen) const
{
    LoopStmtCodeGenPayload loopState;
    loopState.continueLabel = codeGen.builder().createLabel();
    loopState.doneLabel     = codeGen.builder().createLabel();
    setLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != resolvedNodeRef(codeGen, nodeBodyRef))
        return Result::Continue;

    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    codeGen.builder().placeLabel(loopState->continueLabel);

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
    frame.setCurrentLoopContinueLabel(loopState->continueLabel);
    frame.setCurrentLoopBreakLabel(loopState->doneLabel);
    codeGen.pushFrame(frame);
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != resolvedNodeRef(codeGen, nodeBodyRef))
        return Result::Continue;

    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopState->continueLabel);
    codeGen.popFrame();
    return Result::Continue;
}

Result AstInfiniteLoopStmt::codeGenPostNode(CodeGen& codeGen) const
{
    const LoopStmtCodeGenPayload* loopState = loopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(loopState != nullptr);

    codeGen.builder().placeLabel(loopState->doneLabel);
    eraseLoopStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstContinueStmt::codeGenPostNode(CodeGen& codeGen)
{
    if (codeGen.frame().currentBreakableKind() != CodeGenFrame::BreakContextKind::Loop)
        return Result::Continue;

    const MicroLabelRef continueLabel = codeGen.frame().currentLoopContinueLabel();
    if (continueLabel == MicroLabelRef::invalid())
        return Result::Continue;

    codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, continueLabel);
    return Result::Continue;
}

SWC_END_NAMESPACE();
