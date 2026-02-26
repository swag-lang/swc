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
    struct IfStmtCodeGenPayload
    {
        MicroLabelRef falseLabel   = MicroLabelRef::invalid();
        MicroLabelRef doneLabel    = MicroLabelRef::invalid();
        bool          hasElseBlock = false;
    };

    struct LoopStmtCodeGenPayload
    {
        MicroLabelRef continueLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel     = MicroLabelRef::invalid();
    };

    struct ForeachStmtCodeGenPayload
    {
        MicroLabelRef loopLabel     = MicroLabelRef::invalid();
        MicroLabelRef continueLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel     = MicroLabelRef::invalid();
        MicroReg      baseReg       = MicroReg::invalid();
        MicroReg      countReg      = MicroReg::invalid();
        MicroReg      indexReg      = MicroReg::invalid();
        uint64_t      elementSize   = 0;
        bool          reverse       = false;
    };

    AstNodeRef resolvedNodeRef(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.viewZero(nodeRef).nodeRef();
    }

    IfStmtCodeGenPayload* ifStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        if (nodeRef.isInvalid())
            return nullptr;
        return codeGen.sema().codeGenPayload<IfStmtCodeGenPayload>(nodeRef);
    }

    IfStmtCodeGenPayload& setIfStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const IfStmtCodeGenPayload& payloadValue)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        SWC_ASSERT(nodeRef.isValid());

        auto* payload = codeGen.sema().codeGenPayload<IfStmtCodeGenPayload>(nodeRef);
        if (!payload)
        {
            payload = codeGen.compiler().allocate<IfStmtCodeGenPayload>();
            codeGen.sema().setCodeGenPayload(nodeRef, payload);
        }

        *payload = payloadValue;
        return *payload;
    }

    void eraseIfStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        IfStmtCodeGenPayload* payload = ifStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
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

    MicroReg materializeForeachSourceAddress(CodeGen& codeGen, const CodeGenNodePayload& sourcePayload, const TypeInfo& sourceType)
    {
        if (sourcePayload.isAddress())
            return sourcePayload.reg;

        const uint64_t sizeOfValue = sourceType.sizeOf(codeGen.ctx());
        SWC_ASSERT(sizeOfValue > 0);
        if (sizeOfValue != 1 && sizeOfValue != 2 && sizeOfValue != 4 && sizeOfValue != 8)
            return sourcePayload.reg;

        auto* spillData = codeGen.compiler().allocateArray<std::byte>(sizeOfValue);
        std::memset(spillData, 0, sizeOfValue);

        MicroBuilder&  builder      = codeGen.builder();
        const MicroReg spillAddrReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrImm(spillAddrReg, reinterpret_cast<uint64_t>(spillData));
        builder.emitLoadMemReg(spillAddrReg, 0, sourcePayload.reg, microOpBitsFromChunkSize(static_cast<uint32_t>(sizeOfValue)));
        return spillAddrReg;
    }

    CodeGenNodePayload resolveForeachVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar);
        if (symbolPayload)
            return *symbolPayload;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(symVar.typeRef());
        const uint64_t  sizeOf   = typeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(sizeOf > 0);

        auto* spillData = codeGen.compiler().allocateArray<std::byte>(sizeOf);
        std::memset(spillData, 0, sizeOf);

        CodeGenNodePayload spillPayload;
        spillPayload.typeRef = symVar.typeRef();
        spillPayload.setIsAddress();
        spillPayload.reg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegPtrImm(spillPayload.reg, reinterpret_cast<uint64_t>(spillData));
        codeGen.setVariablePayload(symVar, spillPayload);
        return spillPayload;
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

    void emitForeachBindSymbols(CodeGen& codeGen, const AstForeachStmt& node, const ForeachStmtCodeGenPayload& loopState)
    {
        const SemaNodeView symbolsView = codeGen.viewSymbolList(codeGen.curNodeRef());
        const auto         symbols     = symbolsView.symList();
        if (symbols.empty())
            return;

        const MicroReg elementAddressReg = emitForeachElementAddress(codeGen, loopState);
        MicroBuilder&  builder           = codeGen.builder();

        const SymbolVariable&    valueSym     = symbols.front()->cast<SymbolVariable>();
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

        if (symbols.size() < 2)
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
            loopState.baseReg         = materializeForeachSourceAddress(codeGen, exprPayload, exprType);
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

            const MicroReg sourceAddressReg = materializeForeachSourceAddress(codeGen, exprPayload, exprType);
            loopState.baseReg               = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(loopState.baseReg, sourceAddressReg, offsetof(Runtime::Slice<std::byte>, ptr), MicroOpBits::B64);
            builder.emitLoadRegMem(loopState.countReg, sourceAddressReg, countOffset, MicroOpBits::B64);
        }

        if (loopState.reverse)
            builder.emitLoadRegReg(loopState.indexReg, loopState.countReg, MicroOpBits::B64);
        else
            builder.emitLoadRegImm(loopState.indexReg, ApInt(0, 64), MicroOpBits::B64);
    }
}

Result AstParenExpr::codeGenPostNode(CodeGen& codeGen) const
{
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeExprRef, codeGen.curViewType().typeRef());
    return Result::Continue;
}

Result AstNamedArgument::codeGenPostNode(CodeGen& codeGen) const
{
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeArgRef, codeGen.curViewType().typeRef());
    return Result::Continue;
}

Result AstIfStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    MicroBuilder&    builder = codeGen.builder();
    const AstNodeRef ifRef   = codeGen.curNodeRef();

    if (childRef == nodeConditionRef)
    {
        const CodeGenNodePayload& conditionPayload = codeGen.payload(nodeConditionRef);
        const SemaNodeView        conditionView    = codeGen.viewType(nodeConditionRef);
        const MicroOpBits         condBits         = conditionOpBits(conditionView.type(), codeGen.ctx());
        const MicroReg            condReg          = codeGen.nextVirtualIntRegister();

        if (conditionPayload.isAddress())
            builder.emitLoadRegMem(condReg, conditionPayload.reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, conditionPayload.reg, condBits);

        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);

        IfStmtCodeGenPayload state;
        state.falseLabel   = builder.createLabel();
        state.doneLabel    = builder.createLabel();
        state.hasElseBlock = nodeElseBlockRef.isValid();
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, state.falseLabel);
        setIfStmtCodeGenPayload(codeGen, ifRef, state);

        return Result::Continue;
    }

    const IfStmtCodeGenPayload* state = ifStmtCodeGenPayload(codeGen, ifRef);
    SWC_ASSERT(state != nullptr);

    if (childRef == nodeIfBlockRef)
    {
        if (state->hasElseBlock)
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, state->doneLabel);

        builder.placeLabel(state->falseLabel);

        if (!state->hasElseBlock)
            eraseIfStmtCodeGenPayload(codeGen, ifRef);

        return Result::Continue;
    }

    if (childRef == nodeElseBlockRef)
    {
        builder.placeLabel(state->doneLabel);
        eraseIfStmtCodeGenPayload(codeGen, ifRef);
    }

    return Result::Continue;
}

Result AstForeachStmt::codeGenPreNode(CodeGen& codeGen) const
{
    ForeachStmtCodeGenPayload loopState;
    loopState.loopLabel     = codeGen.builder().createLabel();
    loopState.continueLabel = codeGen.builder().createLabel();
    loopState.doneLabel     = codeGen.builder().createLabel();
    loopState.reverse       = modifierFlags.has(AstModifierFlagsE::Reverse);
    setForeachStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), loopState);
    return Result::Continue;
}

Result AstForeachStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const ForeachStmtCodeGenPayload* loopState = foreachStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
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
        codeGen.builder().emitCmpRegImm(loopState->countReg, ApInt(0, 64), MicroOpBits::B64);
        codeGen.builder().emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, loopState->doneLabel);
        if (loopState->reverse)
            codeGen.builder().emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
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
        if (!loopState->reverse)
            codeGen.builder().emitOpBinaryRegImm(loopState->indexReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        codeGen.builder().emitOpBinaryRegImm(loopState->countReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
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
