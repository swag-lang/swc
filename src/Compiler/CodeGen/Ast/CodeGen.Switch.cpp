#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct SwitchCaseCodeGenPayload
    {
        MicroLabelRef testLabel     = MicroLabelRef::invalid();
        MicroLabelRef bodyLabel     = MicroLabelRef::invalid();
        MicroLabelRef nextTestLabel = MicroLabelRef::invalid();
        MicroLabelRef nextBodyLabel = MicroLabelRef::invalid();
        bool          hasNextCase   = false;
    };

    struct SwitchStmtCodeGenPayload
    {
        MicroLabelRef                                            doneLabel          = MicroLabelRef::invalid();
        TypeRef                                                  compareTypeRef     = TypeRef::invalid();
        CodeGenNodePayload                                       switchValuePayload = {};
        MicroReg                                                 switchValueReg;
        MicroOpBits                                              compareOpBits     = MicroOpBits::B64;
        SymbolFunction*                                          stringCmpFunction = nullptr;
        bool                                                     hasExpression     = false;
        bool                                                     useStringCompare  = false;
        bool                                                     useUnsignedCond   = false;
        std::unordered_map<AstNodeRef, SwitchCaseCodeGenPayload> caseStates;
    };

    SwitchStmtCodeGenPayload* switchStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<SwitchStmtCodeGenPayload>(nodeRef);
    }

    SwitchStmtCodeGenPayload& setSwitchStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const SwitchStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseSwitchStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        SwitchStmtCodeGenPayload* payload = switchStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
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

        return CodeGenTypeHelpers::conditionBits(typeInfo, ctx);
    }

    bool isStringCompareType(CodeGen& codeGen, TypeRef typeRef)
    {
        const TypeRef   unwrappedTypeRef = codeGen.typeMgr().get(typeRef).unwrapAliasEnum(codeGen.ctx(), typeRef);
        const TypeInfo& typeInfo         = codeGen.typeMgr().get(unwrappedTypeRef);
        return typeInfo.isString();
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

    void emitConditionTrueJump(CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef typeRef, MicroLabelRef trueLabel)
    {
        const TypeInfo&   typeInfo = codeGen.typeMgr().get(typeRef);
        const MicroOpBits condBits = CodeGenTypeHelpers::conditionBits(typeInfo, codeGen.ctx());
        const MicroReg    condReg  = codeGen.nextVirtualIntRegister();

        MicroBuilder& builder = codeGen.builder();
        if (payload.isAddress())
            builder.emitLoadRegMem(condReg, payload.reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, payload.reg, condBits);

        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, trueLabel);
    }

    void appendPreparedStringCompareArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, const CallConv& callConv, const CodeGenNodePayload& operandPayload, TypeRef argTypeRef)
    {
        const TypeInfo&                        argType       = codeGen.typeMgr().get(argTypeRef);
        const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, argTypeRef, ABITypeNormalize::Usage::Argument);

        ABICall::PreparedArg preparedArg;
        preparedArg.srcReg      = operandPayload.reg;
        preparedArg.kind        = ABICall::PreparedArgKind::Direct;
        preparedArg.isFloat     = normalizedArg.isFloat;
        preparedArg.isAddressed = operandPayload.isAddress() && !normalizedArg.isIndirect && !argType.isReference();
        preparedArg.numBits     = normalizedArg.numBits;
        outArgs.push_back(preparedArg);
    }

    SymbolFunction* runtimeStringCompareFunction(CodeGen& codeGen)
    {
        const IdentifierRef idRef = codeGen.idMgr().predefined(IdentifierManager::PredefinedName::RuntimeStringCmp);
        if (idRef.isInvalid())
            return nullptr;

        return codeGen.compiler().runtimeFunctionSymbol(idRef);
    }

    Result emitStringCompareEqualsJump(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, const CodeGenNodePayload& casePayload, MicroLabelRef successLabel)
    {
        SymbolFunction* stringCmpSymbol = switchState.stringCmpFunction;
        if (!stringCmpSymbol)
            stringCmpSymbol = runtimeStringCompareFunction(codeGen);

        SWC_ASSERT(stringCmpSymbol != nullptr);
        if (!stringCmpSymbol)
            return Result::Error;

        codeGen.function().addCallDependency(stringCmpSymbol);

        auto&                             stringCmpFunction = *stringCmpSymbol;
        const CallConvKind                callConvKind      = stringCmpFunction.callConvKind();
        const CallConv&                   callConv          = CallConv::get(callConvKind);
        const auto&                       params            = stringCmpFunction.parameters();
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(2);

        SWC_ASSERT(params.size() >= 2);
        SWC_ASSERT(params[0] != nullptr);
        SWC_ASSERT(params[1] != nullptr);
        appendPreparedStringCompareArg(preparedArgs, codeGen, callConv, switchState.switchValuePayload, params[0]->typeRef());
        appendPreparedStringCompareArg(preparedArgs, codeGen, callConv, casePayload, params[1]->typeRef());

        MicroBuilder&               builder      = codeGen.builder();
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        if (stringCmpFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &stringCmpFunction, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &stringCmpFunction, preparedCall);

        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, stringCmpFunction.returnTypeRef(), ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!normalizedRet.isVoid);
        SWC_ASSERT(!normalizedRet.isIndirect);
        SWC_ASSERT(normalizedRet.numBits == 8);

        const MicroReg compareReg = codeGen.nextVirtualIntRegister();
        ABICall::materializeReturnToReg(builder, compareReg, callConvKind, normalizedRet);
        builder.emitCmpRegImm(compareReg, ApInt(0, 64), MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, successLabel);
        return Result::Continue;
    }

    Result emitSwitchValueEqualsJump(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, AstNodeRef caseExprRef, MicroLabelRef successLabel)
    {
        const CodeGenNodePayload& casePayload = codeGen.payload(caseExprRef);
        if (switchState.useStringCompare)
            return emitStringCompareEqualsJump(codeGen, switchState, casePayload, successLabel);

        MicroReg caseReg = MicroReg::invalid();
        loadPayloadToRegister(caseReg, codeGen, casePayload, switchState.compareTypeRef, switchState.compareOpBits);

        MicroBuilder& builder = codeGen.builder();
        builder.emitCmpRegReg(switchState.switchValueReg, caseReg, switchState.compareOpBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen,
                                                 codeGen.typeMgr().get(switchState.compareTypeRef),
                                                 {.primaryCond        = MicroCond::Equal,
                                                  .floatUnorderedMode = CodeGenCompareHelpers::FloatUnorderedMode::RequireOrdered},
                                                 successLabel);
        return Result::Continue;
    }

    void emitSwitchRangeFailJumps(CodeGen& codeGen, const SwitchStmtCodeGenPayload& switchState, const AstRangeExpr& rangeExpr, MicroLabelRef failLabel)
    {
        const bool      unsignedOrFloat = switchState.useUnsignedCond;
        const TypeInfo& compareType     = codeGen.typeMgr().get(switchState.compareTypeRef);

        if (rangeExpr.nodeExprDownRef.isValid())
        {
            const CodeGenNodePayload& lowerPayload = codeGen.payload(rangeExpr.nodeExprDownRef);
            MicroReg                  lowerReg     = MicroReg::invalid();
            loadPayloadToRegister(lowerReg, codeGen, lowerPayload, switchState.compareTypeRef, switchState.compareOpBits);

            codeGen.builder().emitCmpRegReg(switchState.switchValueReg, lowerReg, switchState.compareOpBits);
            CodeGenCompareHelpers::emitConditionJump(codeGen,
                                                     compareType,
                                                     {.primaryCond        = CodeGenCompareHelpers::lessCond(unsignedOrFloat),
                                                      .floatUnorderedMode = compareType.isFloat() ? CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered
                                                                                                  : CodeGenCompareHelpers::FloatUnorderedMode::ExcludedByPrimary},
                                                     failLabel);
        }

        if (rangeExpr.nodeExprUpRef.isValid())
        {
            const CodeGenNodePayload& upperPayload = codeGen.payload(rangeExpr.nodeExprUpRef);
            MicroReg                  upperReg     = MicroReg::invalid();
            loadPayloadToRegister(upperReg, codeGen, upperPayload, switchState.compareTypeRef, switchState.compareOpBits);

            codeGen.builder().emitCmpRegReg(switchState.switchValueReg, upperReg, switchState.compareOpBits);
            const MicroCond failCond = rangeExpr.hasFlag(AstRangeExprFlagsE::Inclusive) ? CodeGenCompareHelpers::greaterCond(unsignedOrFloat) : CodeGenCompareHelpers::greaterEqualCond(unsignedOrFloat);
            CodeGenCompareHelpers::emitConditionJump(codeGen,
                                                     compareType,
                                                     {.primaryCond        = failCond,
                                                      .floatUnorderedMode = compareType.isFloat() ? CodeGenCompareHelpers::FloatUnorderedMode::AcceptUnordered
                                                                                                  : CodeGenCompareHelpers::FloatUnorderedMode::ExcludedByPrimary},
                                                     failLabel);
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

Result AstSwitchStmt::codeGenPreNode(CodeGen& codeGen) const
{
    SwitchStmtCodeGenPayload switchState;
    switchState.doneLabel     = codeGen.builder().createLabel();
    switchState.hasExpression = nodeExprRef.isValid();

    // Build the whole case label graph up front so `fallthrough` and "next test" edges are stable before
    // any case body starts emitting code.
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
        const SemaNodeView        exprView         = codeGen.viewType(nodeExprRef);
        const CodeGenNodePayload& exprPayload      = codeGen.payload(nodeExprRef);
        const TypeInfo&           exprType         = codeGen.typeMgr().get(exprView.typeRef());
        const TypeRef             compareTypeRef   = exprType.unwrapAliasEnum(codeGen.ctx(), exprView.typeRef());
        const TypeInfo&           compareType      = codeGen.typeMgr().get(compareTypeRef);
        const MicroOpBits         compareBits      = switchCompareOpBits(compareType, codeGen.ctx());
        const bool                useStringCompare = isStringCompareType(codeGen, compareTypeRef);

        const MicroReg switchValueReg = codeGen.nextVirtualRegisterForType(compareTypeRef);
        if (exprPayload.isAddress())
            codeGen.builder().emitLoadRegMem(switchValueReg, exprPayload.reg, 0, compareBits);
        else
            codeGen.builder().emitLoadRegReg(switchValueReg, exprPayload.reg, compareBits);

        switchState->compareTypeRef     = compareTypeRef;
        switchState->switchValuePayload = exprPayload;
        switchState->switchValueReg     = switchValueReg;
        switchState->compareOpBits      = compareBits;
        switchState->useStringCompare   = useStringCompare;
        switchState->useUnsignedCond    = compareType.usesUnsignedConditions();
        if (useStringCompare)
            switchState->stringCmpFunction = runtimeStringCompareFunction(codeGen);
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
    const MicroLabelRef             failLabel = caseState.hasNextCase ? caseState.nextTestLabel : switchState->doneLabel;

    MicroBuilder& builder = codeGen.builder();

    if (switchState->hasExpression)
    {
        if (spanExprRef.isValid())
        {
            SmallVector<AstNodeRef> caseExprRefs;
            codeGen.ast().appendNodes(caseExprRefs, spanExprRef);

            const bool          hasWhere   = nodeWhereRef.isValid();
            // A `where` clause only runs after one case expression matched, so all successful tests funnel
            // through a shared label before entering the body.
            const MicroLabelRef matchLabel = hasWhere ? builder.createLabel() : caseState.bodyLabel;
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
                    SWC_RESULT(emitSwitchValueEqualsJump(codeGen, *switchState, caseExprRef, matchLabel));
                }
            }

            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, failLabel);
            if (hasWhere)
            {
                builder.placeLabel(matchLabel);
                const CodeGenNodePayload& wherePayload = codeGen.payload(nodeWhereRef);
                const SemaNodeView        whereView    = codeGen.viewType(nodeWhereRef);
                CodeGenCompareHelpers::emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), failLabel);
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, caseState.bodyLabel);
            }
        }
        else
        {
            if (nodeWhereRef.isValid())
            {
                const CodeGenNodePayload& wherePayload = codeGen.payload(nodeWhereRef);
                const SemaNodeView        whereView    = codeGen.viewType(nodeWhereRef);
                CodeGenCompareHelpers::emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), failLabel);
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

            const bool          hasWhere   = nodeWhereRef.isValid();
            const MicroLabelRef matchLabel = hasWhere ? builder.createLabel() : caseState.bodyLabel;
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
                CodeGenCompareHelpers::emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), failLabel);
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, caseState.bodyLabel);
            }
        }
        else
        {
            if (nodeWhereRef.isValid())
            {
                const CodeGenNodePayload& wherePayload = codeGen.payload(nodeWhereRef);
                const SemaNodeView        whereView    = codeGen.viewType(nodeWhereRef);
                CodeGenCompareHelpers::emitConditionFalseJump(codeGen, wherePayload, whereView.typeRef(), failLabel);
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

    // Only non-fallthrough cases jump to the switch exit; explicit `fallthrough` leaves control to the
    // next case's test/body sequence.
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
        const MicroLabelRef breakLabel = codeGen.frame().currentLoopBreakLabel();
        if (breakLabel != MicroLabelRef::invalid())
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
