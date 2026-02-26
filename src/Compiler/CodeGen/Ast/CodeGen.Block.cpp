#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct IfStmtCodeGenPayload
    {
        Ref  falseLabel   = INVALID_REF;
        Ref  doneLabel    = INVALID_REF;
        bool hasElseBlock = false;
    };

    struct SwitchCaseCodeGenPayload
    {
        Ref  testLabel     = INVALID_REF;
        Ref  bodyLabel     = INVALID_REF;
        Ref  nextTestLabel = INVALID_REF;
        Ref  nextBodyLabel = INVALID_REF;
        bool hasNextCase   = false;
    };

    struct SwitchStmtCodeGenPayload
    {
        Ref                                                      doneLabel      = INVALID_REF;
        TypeRef                                                  compareTypeRef = TypeRef::invalid();
        MicroReg                                                 switchValueReg;
        MicroOpBits                                              compareOpBits   = MicroOpBits::B64;
        bool                                                     hasExpression   = false;
        bool                                                     useUnsignedCond = false;
        std::unordered_map<AstNodeRef, SwitchCaseCodeGenPayload> caseStates;
    };

    struct LoopStmtCodeGenPayload
    {
        Ref continueLabel = INVALID_REF;
        Ref doneLabel     = INVALID_REF;
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

    SwitchStmtCodeGenPayload* switchStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        if (nodeRef.isInvalid())
            return nullptr;
        return codeGen.sema().codeGenPayload<SwitchStmtCodeGenPayload>(nodeRef);
    }

    SwitchStmtCodeGenPayload& setSwitchStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const SwitchStmtCodeGenPayload& payloadValue)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        SWC_ASSERT(nodeRef.isValid());

        auto* payload = codeGen.sema().codeGenPayload<SwitchStmtCodeGenPayload>(nodeRef);
        if (!payload)
        {
            payload = codeGen.compiler().allocate<SwitchStmtCodeGenPayload>();
            codeGen.sema().setCodeGenPayload(nodeRef, payload);
        }

        *payload = payloadValue;
        return *payload;
    }

    void eraseSwitchStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        SwitchStmtCodeGenPayload* payload = switchStmtCodeGenPayload(codeGen, nodeRef);
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

    MicroOpBits switchCompareOpBits(const TypeInfo& typeInfo, TaskContext& ctx)
    {
        if (typeInfo.isFloat())
        {
            uint32_t bits = typeInfo.payloadFloatBits();
            if (!bits)
                bits = static_cast<uint32_t>(typeInfo.sizeOf(ctx) * 8);
            if (!bits)
                bits = 64;
            return microOpBitsFromBitWidth(bits);
        }

        return conditionOpBits(&typeInfo, ctx);
    }

    bool switchUseUnsignedConditions(const TypeInfo& typeInfo)
    {
        return typeInfo.isFloat() || typeInfo.isIntLikeUnsigned() || typeInfo.isPointerLike() || typeInfo.isBool() || typeInfo.isEnum();
    }

    void loadPayloadToRegister(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef regTypeRef, MicroOpBits opBits)
    {
        outReg = codeGen.nextVirtualRegisterForType(regTypeRef);

        MicroBuilder& builder = codeGen.builder();
        if (payload.isAddress())
            builder.emitLoadRegMem(outReg, payload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, payload.reg, opBits);
    }

    void emitConditionFalseJump(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef typeRef, Ref falseLabel)
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

    void emitConditionTrueJump(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef typeRef, Ref trueLabel)
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
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, trueLabel);
    }

    void emitSwitchValueEqualsJump(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, AstNodeRef caseExprRef, Ref successLabel)
    {
        const CodeGenNodePayload& casePayload = codeGen.payload(caseExprRef);
        MicroReg                  caseReg     = MicroReg::invalid();
        loadPayloadToRegister(caseReg, codeGen, casePayload, switchState.compareTypeRef, switchState.compareOpBits);

        MicroBuilder& builder = codeGen.builder();
        builder.emitCmpRegReg(switchState.switchValueReg, caseReg, switchState.compareOpBits);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, successLabel);
    }

    void emitSwitchRangeFailJumps(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, const AstRangeExpr& rangeExpr, Ref failLabel)
    {
        const bool unsignedOrFloat = switchState.useUnsignedCond;

        if (rangeExpr.nodeExprDownRef.isValid())
        {
            const CodeGenNodePayload& lowerPayload = codeGen.payload(rangeExpr.nodeExprDownRef);
            MicroReg                  lowerReg     = MicroReg::invalid();
            loadPayloadToRegister(lowerReg, codeGen, lowerPayload, switchState.compareTypeRef, switchState.compareOpBits);

            codeGen.builder().emitCmpRegReg(switchState.switchValueReg, lowerReg, switchState.compareOpBits);
            codeGen.builder().emitJumpToLabel(unsignedOrFloat ? MicroCond::Below : MicroCond::Less, MicroOpBits::B32, failLabel);
        }

        if (rangeExpr.nodeExprUpRef.isValid())
        {
            const CodeGenNodePayload& upperPayload = codeGen.payload(rangeExpr.nodeExprUpRef);
            MicroReg                  upperReg     = MicroReg::invalid();
            loadPayloadToRegister(upperReg, codeGen, upperPayload, switchState.compareTypeRef, switchState.compareOpBits);

            codeGen.builder().emitCmpRegReg(switchState.switchValueReg, upperReg, switchState.compareOpBits);
            const MicroCond failCond = rangeExpr.hasFlag(AstRangeExprFlagsE::Inclusive) ? (unsignedOrFloat ? MicroCond::Above : MicroCond::Greater) : (unsignedOrFloat ? MicroCond::AboveOrEqual : MicroCond::GreaterOrEqual);
            codeGen.builder().emitJumpToLabel(failCond, MicroOpBits::B32, failLabel);
        }
    }

    bool caseBodyEndsWithFallthrough(CodeGen& codeGen, const AstSwitchCaseStmt& node)
    {
        SmallVector<AstNodeRef>  statements;
        const AstSwitchCaseBody& caseBody = codeGen.node(node.nodeBodyRef).cast<AstSwitchCaseBody>();
        codeGen.ast().appendNodes(statements, caseBody.spanChildrenRef);
        if (statements.empty())
            return false;

        return codeGen.node(statements.back()).is(AstNodeId::FallThroughStmt);
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

Result AstSwitchStmt::codeGenPreNode(CodeGen& codeGen) const
{
    SwitchStmtCodeGenPayload switchState;
    switchState.doneLabel     = codeGen.builder().createLabel();
    switchState.hasExpression = nodeExprRef.isValid();

    SmallVector<AstNodeRef> caseRefs;
    codeGen.ast().appendNodes(caseRefs, spanChildrenRef);
    for (const AstNodeRef caseRef : caseRefs)
    {
        SwitchCaseCodeGenPayload caseState;
        caseState.testLabel = codeGen.builder().createLabel();
        caseState.bodyLabel = codeGen.builder().createLabel();
        switchState.caseStates.insert_or_assign(caseRef, caseState);
    }

    for (size_t i = 0; i < caseRefs.size(); ++i)
    {
        const AstNodeRef caseRef = caseRefs[i];
        const auto       itCase  = switchState.caseStates.find(caseRef);
        SWC_ASSERT(itCase != switchState.caseStates.end());

        SwitchCaseCodeGenPayload& caseState = itCase->second;
        if (i + 1 < caseRefs.size())
        {
            const AstNodeRef nextCaseRef = caseRefs[i + 1];
            const auto       itNextCase  = switchState.caseStates.find(nextCaseRef);
            SWC_ASSERT(itNextCase != switchState.caseStates.end());

            caseState.hasNextCase   = true;
            caseState.nextTestLabel = itNextCase->second.testLabel;
            caseState.nextBodyLabel = itNextCase->second.bodyLabel;
        }
    }

    setSwitchStmtCodeGenPayload(codeGen, codeGen.curNodeRef(), switchState);

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Switch);
    frame.setCurrentSwitch(codeGen.curNodeRef());
    frame.setCurrentSwitchCase(AstNodeRef::invalid());
    codeGen.pushFrame(frame);
    return Result::Continue;
}

Result AstSwitchStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef)
{
    if (!codeGen.node(childRef).is(AstNodeId::SwitchCaseStmt))
        return Result::Continue;

    SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(switchState != nullptr);

    const auto itCase = switchState->caseStates.find(childRef);
    SWC_ASSERT(itCase != switchState->caseStates.end());

    codeGen.builder().placeLabel(itCase->second.testLabel);

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentSwitchCase(childRef);
    codeGen.pushFrame(frame);
    return Result::Continue;
}

Result AstSwitchStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(switchState != nullptr);

    if (childRef == nodeExprRef)
    {
        const SemaNodeView        exprView       = codeGen.viewType(nodeExprRef);
        const CodeGenNodePayload& exprPayload    = codeGen.payload(nodeExprRef);
        const TypeInfo&           exprType       = codeGen.typeMgr().get(exprView.typeRef());
        const TypeRef             compareTypeRef = exprType.unwrap(codeGen.ctx(), exprView.typeRef(), TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo&           compareType    = codeGen.typeMgr().get(compareTypeRef);
        const MicroOpBits         compareBits    = switchCompareOpBits(compareType, codeGen.ctx());

        const MicroReg switchValueReg = codeGen.nextVirtualRegisterForType(compareTypeRef);
        if (exprPayload.isAddress())
            codeGen.builder().emitLoadRegMem(switchValueReg, exprPayload.reg, 0, compareBits);
        else
            codeGen.builder().emitLoadRegReg(switchValueReg, exprPayload.reg, compareBits);

        switchState->compareTypeRef  = compareTypeRef;
        switchState->switchValueReg  = switchValueReg;
        switchState->compareOpBits   = compareBits;
        switchState->useUnsignedCond = switchUseUnsignedConditions(compareType);
        return Result::Continue;
    }

    if (codeGen.node(childRef).is(AstNodeId::SwitchCaseStmt))
        codeGen.popFrame();

    return Result::Continue;
}

Result AstSwitchStmt::codeGenPostNode(CodeGen& codeGen)
{
    const SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(switchState != nullptr);

    codeGen.builder().placeLabel(switchState->doneLabel);
    codeGen.popFrame();
    eraseSwitchStmtCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstSwitchCaseStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    const AstNodeRef switchRef = codeGen.frame().currentSwitch();
    if (switchRef.isInvalid())
        return Result::Continue;

    SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, switchRef);
    SWC_ASSERT(switchState != nullptr);

    const auto itCase = switchState->caseStates.find(codeGen.curNodeRef());
    SWC_ASSERT(itCase != switchState->caseStates.end());

    const SwitchCaseCodeGenPayload& caseState = itCase->second;
    const Ref                       failLabel = caseState.hasNextCase ? caseState.nextTestLabel : switchState->doneLabel;

    MicroBuilder& builder = codeGen.builder();

    if (switchState->hasExpression)
    {
        if (spanExprRef.isValid())
        {
            SmallVector<AstNodeRef> caseExprRefs;
            codeGen.ast().appendNodes(caseExprRefs, spanExprRef);

            const bool hasWhere   = nodeWhereRef.isValid();
            const Ref  matchLabel = hasWhere ? builder.createLabel() : caseState.bodyLabel;
            for (const AstNodeRef caseExprRef : caseExprRefs)
            {
                if (codeGen.node(caseExprRef).is(AstNodeId::RangeExpr))
                {
                    const AstRangeExpr& rangeExpr = codeGen.node(caseExprRef).cast<AstRangeExpr>();
                    emitSwitchRangeFailJumps(codeGen, *switchState, rangeExpr, failLabel);
                    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, matchLabel);
                }
                else
                {
                    emitSwitchValueEqualsJump(codeGen, *switchState, caseExprRef, matchLabel);
                }
            }

            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, failLabel);
            if (hasWhere)
            {
                builder.placeLabel(matchLabel);
                const CodeGenNodePayload& wherePayload = codeGen.payload(nodeWhereRef);
                const SemaNodeView        whereView    = codeGen.viewType(nodeWhereRef);
                emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), failLabel);
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, caseState.bodyLabel);
            }
        }
        else
        {
            if (nodeWhereRef.isValid())
            {
                const CodeGenNodePayload& wherePayload = codeGen.payload(nodeWhereRef);
                const SemaNodeView        whereView    = codeGen.viewType(nodeWhereRef);
                emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), failLabel);
            }

            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, caseState.bodyLabel);
        }
    }
    else
    {
        if (spanExprRef.isValid())
        {
            SmallVector<AstNodeRef> caseExprRefs;
            codeGen.ast().appendNodes(caseExprRefs, spanExprRef);

            const bool hasWhere   = nodeWhereRef.isValid();
            const Ref  matchLabel = hasWhere ? builder.createLabel() : caseState.bodyLabel;
            for (const AstNodeRef caseExprRef : caseExprRefs)
            {
                const CodeGenNodePayload& exprPayload = codeGen.payload(caseExprRef);
                const SemaNodeView        exprView    = codeGen.viewType(caseExprRef);
                emitConditionTrueJump(codeGen, exprPayload, exprView.typeRef(), matchLabel);
            }

            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, failLabel);
            if (hasWhere)
            {
                builder.placeLabel(matchLabel);
                const CodeGenNodePayload& wherePayload = codeGen.payload(nodeWhereRef);
                const SemaNodeView        whereView    = codeGen.viewType(nodeWhereRef);
                emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), failLabel);
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, caseState.bodyLabel);
            }
        }
        else
        {
            if (nodeWhereRef.isValid())
            {
                const CodeGenNodePayload& wherePayload = codeGen.payload(nodeWhereRef);
                const SemaNodeView        whereView    = codeGen.viewType(nodeWhereRef);
                emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), failLabel);
            }

            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, caseState.bodyLabel);
        }
    }

    builder.placeLabel(caseState.bodyLabel);
    return Result::Continue;
}

Result AstSwitchCaseStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    if (caseBodyEndsWithFallthrough(codeGen, *this))
        return Result::Continue;

    const AstNodeRef switchRef = codeGen.frame().currentSwitch();
    if (switchRef.isInvalid())
        return Result::Continue;

    const SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, switchRef);
    SWC_ASSERT(switchState != nullptr);

    codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, switchState->doneLabel);
    return Result::Continue;
}

Result AstBreakStmt::codeGenPostNode(CodeGen& codeGen)
{
    const CodeGenFrame::BreakContext& breakCtx = codeGen.frame().currentBreakContext();
    if (breakCtx.kind == CodeGenFrame::BreakContextKind::None)
        return Result::Continue;

    if (breakCtx.kind == CodeGenFrame::BreakContextKind::Loop)
    {
        const Ref breakLabel = codeGen.frame().currentLoopBreakLabel();
        if (breakLabel != INVALID_REF)
            codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, breakLabel);
        return Result::Continue;
    }

    const AstNodeRef switchRef = codeGen.frame().currentSwitch();
    SWC_ASSERT(switchRef.isValid());

    const SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, switchRef);
    SWC_ASSERT(switchState != nullptr);
    codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, switchState->doneLabel);
    return Result::Continue;
}

Result AstContinueStmt::codeGenPostNode(CodeGen& codeGen)
{
    if (codeGen.frame().currentBreakableKind() != CodeGenFrame::BreakContextKind::Loop)
        return Result::Continue;

    const Ref continueLabel = codeGen.frame().currentLoopContinueLabel();
    if (continueLabel == INVALID_REF)
        return Result::Continue;

    codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, continueLabel);
    return Result::Continue;
}

Result AstFallThroughStmt::codeGenPostNode(CodeGen& codeGen)
{
    const AstNodeRef switchRef = codeGen.frame().currentSwitch();
    const AstNodeRef caseRef   = codeGen.frame().currentSwitchCase();
    if (switchRef.isInvalid() || caseRef.isInvalid())
        return Result::Continue;

    SwitchStmtCodeGenPayload* switchState = switchStmtCodeGenPayload(codeGen, switchRef);
    SWC_ASSERT(switchState != nullptr);

    const auto itCase = switchState->caseStates.find(caseRef);
    SWC_ASSERT(itCase != switchState->caseStates.end());
    if (!itCase->second.hasNextCase)
        return Result::Continue;

    codeGen.builder().emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, itCase->second.nextBodyLabel);
    return Result::Continue;
}

SWC_END_NAMESPACE();
