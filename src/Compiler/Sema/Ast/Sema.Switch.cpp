#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Switch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result ensureSwitchRuntimePanicSymbol(Sema& sema, SwitchPayload& payload, const SourceCodeRef& codeRef)
    {
        if (payload.runtimePanicSymbol != nullptr)
            return Result::Continue;

        SymbolFunction* panicFn = nullptr;
        SWC_RESULT(SemaHelpers::requireRuntimeSafetyPanicDependency(panicFn, sema, codeRef));
        payload.runtimePanicSymbol = panicFn;
        return Result::Continue;
    }

    Result setupSwitchRuntimeSafety(Sema& sema, SwitchPayload& payload, const SourceCodeRef& codeRef)
    {
        if (!payload.isComplete)
            return Result::Continue;

        if (!sema.frame().currentAttributes().hasRuntimeSafety(sema.buildCfg().safetyGuards, Runtime::SafetyWhat::Switch))
            return Result::Continue;

        if (!sema.isCurrentFunction())
            return Result::Continue;

        SWC_RESULT(ensureSwitchRuntimePanicSymbol(sema, payload, codeRef));

        // Only expose runtime switch safety to codegen once the panic helper is
        // attached. This avoids leaving a partially initialized payload behind
        // when semantic analysis pauses on the runtime dependency.
        SWC_ASSERT(payload.runtimePanicSymbol != nullptr);
        payload.hasRuntimeSwitchSafety = true;
        return Result::Continue;
    }

    bool isDynamicStructSwitchType(Sema& sema, TypeRef typeRef)
    {
        const TypeRef   unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        const TypeInfo& typeInfo         = sema.typeMgr().get(unwrappedTypeRef);
        return typeInfo.isInterface() || typeInfo.isAny();
    }

    TypeRef switchEnumTypeRef(Sema& sema, TypeRef typeRef)
    {
        const TypeRef enumTypeRef = sema.typeMgr().get(typeRef).unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
        if (sema.typeMgr().get(enumTypeRef).isEnum())
            return enumTypeRef;
        return TypeRef::invalid();
    }

    TypeRef switchCaseCastTypeRef(Sema& sema, TypeRef switchTypeRef)
    {
        const TypeRef enumTypeRef = switchEnumTypeRef(sema, switchTypeRef);
        if (enumTypeRef.isValid())
            return enumTypeRef;
        return switchTypeRef;
    }

    TypeRef switchExprUltimateTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        return sema.typeMgr().get(typeRef).unwrap(sema.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    }

    Result normalizeSwitchExprTypeInfoIfNeeded(Sema& sema, AstNodeRef exprRef, SemaNodeView& exprView)
    {
        const TypeRef   initialUltimateTypeRef = switchExprUltimateTypeRef(sema, exprView.typeRef());
        const TypeInfo& initialFinalType       = sema.typeMgr().get(initialUltimateTypeRef);
        if (!initialFinalType.isTypeValue())
            return Result::Continue;

        SWC_RESULT(Cast::cast(sema, exprView, sema.typeMgr().typeTypeInfo(), CastKind::Implicit));
        exprView = sema.viewNodeTypeConstant(exprRef);
        return Result::Continue;
    }

    Result validateSwitchExprType(Sema& sema, AstNodeRef exprRef, TypeRef exprTypeRef)
    {
        const TypeRef   ultimateTypeRef = switchExprUltimateTypeRef(sema, exprTypeRef);
        const TypeInfo& finalType       = sema.typeMgr().get(ultimateTypeRef);
        if (finalType.isIntLike() || finalType.isFloat() || finalType.isBool() || finalType.isString() || finalType.isAnyTypeInfo(sema.ctx()) || finalType.isInterface() || finalType.isAny())
            return Result::Continue;

        return SemaError::raise(sema, DiagnosticId::sema_err_switch_invalid_type, exprRef);
    }

    Result attachSwitchExprRuntimeDependencies(Sema& sema, SwitchPayload& payload, TypeRef exprTypeRef, const SourceCodeRef& codeRef)
    {
        const TypeRef   ultimateTypeRef = switchExprUltimateTypeRef(sema, exprTypeRef);
        const TypeInfo& finalType       = sema.typeMgr().get(ultimateTypeRef);
        if (finalType.isString())
            SWC_RESULT(SemaHelpers::requireRuntimeStringCmpDependency(sema, codeRef));

        return setupSwitchRuntimeSafety(sema, payload, codeRef);
    }

    TypeRef dynamicStructSwitchExprTypeRef(Sema& sema, AstNodeRef switchRef)
    {
        if (!switchRef.isValid() || sema.node(switchRef).isNot(AstNodeId::SwitchStmt))
            return TypeRef::invalid();

        if (const auto* payload = sema.semaPayload<SwitchPayload>(switchRef))
        {
            if (payload->exprTypeRef.isValid())
                return payload->exprTypeRef;
        }

        const auto& switchNode = sema.node(switchRef).cast<AstSwitchStmt>();
        if (!switchNode.nodeExprRef.isValid())
            return TypeRef::invalid();

        return sema.viewType(switchNode.nodeExprRef).typeRef();
    }

    bool isDynamicStructSwitchCase(Sema& sema, AstNodeRef switchRef)
    {
        return isDynamicStructSwitchType(sema, dynamicStructSwitchExprTypeRef(sema, switchRef));
    }

    DynamicStructSwitchCasePayload& ensureDynamicStructSwitchCasePayload(Sema& sema, AstNodeRef caseRef)
    {
        auto* payload = sema.semaPayload<DynamicStructSwitchCasePayload>(caseRef);
        if (payload)
            return *payload;

        payload = sema.compiler().allocate<DynamicStructSwitchCasePayload>();
        sema.setSemaPayload(caseRef, payload);
        return *payload;
    }

    void markDynamicStructSwitchAsCaseExpr(Sema& sema, AstNodeRef nodeRef)
    {
        if (sema.semaPayload<DynamicStructSwitchAsCastPayload>(nodeRef))
            return;

        auto* payload = sema.compiler().allocate<DynamicStructSwitchAsCastPayload>();
        sema.setSemaPayload(nodeRef, payload);
    }

    Result raiseDynamicStructSwitchCaseSyntaxError(Sema& sema, AstNodeRef nodeRef)
    {
        return SemaError::raise(sema, DiagnosticId::sema_err_switch_dynamic_case, nodeRef);
    }

    bool whereClauseIsUnconditionalTrue(Sema& sema, AstNodeRef whereRef)
    {
        if (!whereRef.isValid())
            return true;

        const SemaNodeView whereView = sema.viewConstant(whereRef);
        return whereView.cstRef().isValid() && whereView.cstRef() == sema.cstMgr().cstTrue();
    }

    SmallVector<AstNodeRef> collectSwitchCaseExprRefs(Sema& sema, const AstSwitchCaseStmt& caseStmt)
    {
        SmallVector<AstNodeRef> exprRefs;
        if (caseStmt.spanExprRef.isValid())
            sema.ast().appendNodes(exprRefs, caseStmt.spanExprRef);
        return exprRefs;
    }

    SmallVector<AstNodeRef> collectSwitchStmtCaseRefs(Sema& sema, const AstSwitchStmt& switchStmt)
    {
        SmallVector<AstNodeRef> caseRefs;
        if (switchStmt.spanChildrenRef.isValid())
            sema.ast().appendNodes(caseRefs, switchStmt.spanChildrenRef);
        return caseRefs;
    }

    SmallVector<AstNodeRef> collectSwitchCaseBodyStmtRefs(Sema& sema, const AstSwitchCaseStmt& caseStmt)
    {
        SmallVector<AstNodeRef> stmtRefs;
        const auto&             caseBody = sema.node(caseStmt.nodeBodyRef).cast<AstSwitchCaseBody>();
        if (caseBody.spanChildrenRef.isValid())
            sema.ast().appendNodes(stmtRefs, caseBody.spanChildrenRef);
        return stmtRefs;
    }

    AstNodeRef dynamicStructSwitchBindingIdentRef(Sema& sema, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid() || sema.node(nodeRef).isNot(AstNodeId::NamedType))
            return AstNodeRef::invalid();

        const auto& namedType = sema.node(nodeRef).cast<AstNamedType>();
        if (!namedType.nodeIdentRef.isValid() || sema.node(namedType.nodeIdentRef).isNot(AstNodeId::Identifier))
            return AstNodeRef::invalid();

        return namedType.nodeIdentRef;
    }

    void registerDynamicStructSwitchCaseExpr(Sema& sema, AstNodeRef caseRef, AstNodeRef caseExprRef, AstNodeRef typeExprRef)
    {
        auto& payload = ensureDynamicStructSwitchCasePayload(sema, caseRef);
        for (auto& expr : payload.expressions)
        {
            if (expr.caseExprRef != caseExprRef)
                continue;

            expr.typeExprRef = typeExprRef;
            return;
        }

        payload.expressions.push_back({caseExprRef, typeExprRef});
    }

    Result registerDynamicStructSwitchBinding(Sema& sema, AstNodeRef caseRef, AstNodeRef caseExprRef, AstNodeRef identRef, TypeRef switchTypeRef, TypeRef targetTypeRef)
    {
        auto& payload = ensureDynamicStructSwitchCasePayload(sema, caseRef);
        if (payload.bindingSymbol != nullptr)
            return Result::Continue;

        if (!identRef.isValid())
            return raiseDynamicStructSwitchCaseSyntaxError(sema, caseExprRef);

        TaskContext&        ctx       = sema.ctx();
        const AstNode&      identNode = sema.node(identRef);
        const IdentifierRef idRef     = SemaHelpers::resolveIdentifier(sema, identNode.codeRef());
        const SymbolFlags   flags     = sema.frame().flagsForCurrentAccess();

        auto* sym = Symbol::make<SymbolVariable>(ctx, &sema.node(caseRef), identNode.tokRef(), idRef, flags);
        if (SemaHelpers::currentLocalSymbolScope(sema))
            SemaHelpers::addCurrentScopeSymbol(sema, sym);
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            SWC_ASSERT(symMap != nullptr);
            symMap->addSymbol(ctx, sym, true);
        }

        TypeInfoFlags bindingFlags = TypeInfoFlagsE::Zero;
        const TypeRef sourceType   = sema.typeMgr().unwrapAliasEnum(sema.ctx(), switchTypeRef);
        if (sema.typeMgr().get(sourceType).isConst() || sema.typeMgr().get(targetTypeRef).isConst())
            bindingFlags.add(TypeInfoFlagsE::Const);

        const TypeRef   resolvedTargetTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), targetTypeRef);
        const TypeInfo& resolvedTargetType    = sema.typeMgr().get(resolvedTargetTypeRef);
        const bool      bindAsPointer         = !sema.typeMgr().get(sourceType).isAny() || resolvedTargetType.isStruct();

        TypeRef bindingTypeRef = targetTypeRef;
        if (bindAsPointer)
            bindingTypeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(targetTypeRef, bindingFlags));

        sym->registerAttributes(sema);
        sym->setDeclared(ctx);
        sym->addExtraFlag(SymbolVariableFlagsE::Initialized);
        sym->setTypeRef(bindingTypeRef);
        SWC_RESULT(SemaHelpers::addCurrentFunctionLocalVariable(sema, *sym, bindingTypeRef));
        sym->setTyped(ctx);
        sym->setSemaCompleted(ctx);

        payload.bindingSymbol = sym;
        return Result::Continue;
    }

    Result checkDuplicateDynamicCaseType(Sema& sema, AstNodeRef switchRef, TypeRef targetStructTypeRef, AstNodeRef caseExprRef, AstNodeRef whereRef)
    {
        if (!whereClauseIsUnconditionalTrue(sema, whereRef))
            return Result::Continue;

        auto* seenSet = sema.semaPayload<SwitchPayload>(switchRef);
        SWC_ASSERT(seenSet);

        const auto it = seenSet->seenDynamicTypes.find(targetStructTypeRef);
        if (it == seenSet->seenDynamicTypes.end())
        {
            seenSet->seenDynamicTypes.emplace(targetStructTypeRef, caseExprRef);
            return Result::Continue;
        }
        if (it->second == caseExprRef)
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_case_duplicate, caseExprRef);
        diag.addArgument(Diagnostic::ARG_VALUE, sema.typeMgr().get(targetStructTypeRef).toName(sema.ctx()));
        diag.addNote(DiagnosticId::sema_note_previous_case_value);
        diag.last().addSpan(sema.node(it->second).codeRangeWithChildren(sema.ctx(), sema.ast()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result requireDynamicStructSwitchRuntimeDependencies(Sema& sema, const SourceCodeRef& codeRef)
    {
        SWC_RESULT(SemaHelpers::requireRuntimeAsDependency(sema, codeRef));
        return SemaHelpers::requireRuntimeIsDependency(sema, codeRef);
    }

    Result validateDynamicStructCaseExpr(Sema& sema, AstNodeRef switchRef, AstNodeRef caseRef, AstNodeRef caseExprRef)
    {
        const auto& caseStmt     = sema.node(caseRef).cast<AstSwitchCaseStmt>();
        const auto  caseExprRefs = collectSwitchCaseExprRefs(sema, caseStmt);

        AstNodeRef typeExprRef     = caseExprRef;
        AstNodeRef bindingIdentRef = AstNodeRef::invalid();
        if (sema.node(caseExprRef).is(AstNodeId::AsCastExpr))
        {
            if (caseExprRefs.size() != 1)
                return raiseDynamicStructSwitchCaseSyntaxError(sema, caseExprRef);

            const auto& asExpr = sema.node(caseExprRef).cast<AstAsCastExpr>();
            typeExprRef        = asExpr.nodeExprRef;
            bindingIdentRef    = dynamicStructSwitchBindingIdentRef(sema, asExpr.nodeTypeRef);
            if (!bindingIdentRef.isValid())
                return raiseDynamicStructSwitchCaseSyntaxError(sema, caseExprRef);
        }
        else if (sema.node(caseExprRef).is(AstNodeId::RangeExpr))
        {
            return raiseDynamicStructSwitchCaseSyntaxError(sema, caseExprRef);
        }

        const SemaNodeView typeView = sema.viewType(typeExprRef);
        if (sema.isValue(typeExprRef) || typeView.typeRef().isInvalid())
            return raiseDynamicStructSwitchCaseSyntaxError(sema, caseExprRef);

        const TypeRef   switchTypeRef       = dynamicStructSwitchExprTypeRef(sema, switchRef);
        const TypeRef   unwrappedSwitchRef  = sema.typeMgr().unwrapAliasEnum(sema.ctx(), switchTypeRef);
        const TypeInfo& switchType          = sema.typeMgr().get(unwrappedSwitchRef);
        const TypeRef   targetTypeRef       = typeView.typeRef();
        const TypeRef   targetStructTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), targetTypeRef);
        const TypeInfo& targetStructType    = sema.typeMgr().get(targetStructTypeRef);

        // For 'any', case types can be any concrete type.
        // For interfaces, case types must be structs.
        if (!switchType.isAny() && !targetStructType.isStruct())
            return SemaError::raiseCannotCast(sema, caseExprRef, switchTypeRef, targetTypeRef);

        registerDynamicStructSwitchCaseExpr(sema, caseRef, caseExprRef, typeExprRef);
        if (bindingIdentRef.isValid())
            SWC_RESULT(registerDynamicStructSwitchBinding(sema, caseRef, caseExprRef, bindingIdentRef, switchTypeRef, targetTypeRef));

        SWC_RESULT(checkDuplicateDynamicCaseType(sema, switchRef, targetStructTypeRef, caseExprRef, caseStmt.nodeWhereRef));
        return requireDynamicStructSwitchRuntimeDependencies(sema, sema.node(caseExprRef).codeRef());
    }

    Result validateDefaultSwitchCase(Sema& sema, AstNodeRef switchRef, AstNodeRef caseRef)
    {
        auto* switchPayload = sema.semaPayload<SwitchPayload>(switchRef);
        SWC_ASSERT(switchPayload);

        if (switchPayload->isComplete)
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_complete_has_default, caseRef);

        if (!switchPayload->firstDefaultRef.isValid())
        {
            switchPayload->firstDefaultRef = caseRef;
            return Result::Continue;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_multiple_default, caseRef);
        diag.addNote(DiagnosticId::sema_note_previous_default_case);
        diag.last().addSpan(sema.node(switchPayload->firstDefaultRef).codeRangeWithChildren(sema.ctx(), sema.ast()));
        diag.report(sema.ctx());
        return Result::Error;
    }
}

Result AstSwitchStmt::semaPreNode(Sema& sema) const
{
    const bool isComplete = sema.frame().currentAttributes().hasRtFlag(RtAttributeFlagsE::Complete);

    // A switch can be marked with the 'Complete' attribute, except if it does not have an expression.
    if (isComplete)
    {
        if (!nodeExprRef.isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_complete_no_expr, sema.curNodeRef());
    }

    // A switch can be marked with the 'Incomplete' attribute, except if it does not have an expression.
    if (sema.frame().currentAttributes().hasRtFlag(RtAttributeFlagsE::Incomplete))
    {
        if (!nodeExprRef.isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_incomplete_no_expr, sema.curNodeRef());
    }

    // Register switch
    SemaFrame frame = sema.frame();
    frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Switch);
    frame.setCurrentSwitch(sema.curNodeRef());
    sema.pushFramePopOnPostNode(frame);

    auto* payload       = sema.compiler().allocate<SwitchPayload>();
    payload->isComplete = isComplete;
    sema.setSemaPayload(sema.curNodeRef(), payload);
    return Result::Continue;
}

Result AstSwitchStmt::semaPostNode(Sema& sema)
{
    const SwitchPayload* payload = sema.semaPayload<SwitchPayload>(sema.curNodeRef());
    SWC_ASSERT(payload != nullptr);
    if (!payload->isComplete || payload->exprTypeRef.isInvalid())
        return Result::Continue;

    const TypeRef enumTypeRef = switchEnumTypeRef(sema, payload->exprTypeRef);
    if (enumTypeRef.isInvalid())
        return Result::Continue;

    const TypeInfo& enumType = sema.typeMgr().get(enumTypeRef);
    if (!enumType.isEnum())
        return Result::Continue;

    std::vector<const Symbol*> symbols;
    enumType.payloadSymEnum().getAllSymbols(symbols);

    for (const Symbol* sym : symbols)
    {
        SWC_ASSERT(sym != nullptr);
        if (!sym->isEnumValue())
            continue;
        const auto&       value  = sym->cast<SymbolEnumValue>();
        const ConstantRef cstRef = value.cstRef();
        if (cstRef.isInvalid())
            continue;

        if (!payload->seen.contains(cstRef))
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_complete_enum_not_exhaustive, sema.curNodeRef());
            diag.addArgument(Diagnostic::ARG_TYPE, enumTypeRef);

            diag.addNote(DiagnosticId::sema_note_switch_missing_enum_value);
            diag.last().addArgument(Diagnostic::ARG_VALUE, value.getFullScopedName(sema.ctx()));
            diag.addNote(DiagnosticId::sema_note_switch_missing_enum_value_here);
            diag.last().addSpan(sym->codeRange(sema.ctx()));
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    return Result::Continue;
}

Result AstSwitchStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    if (sema.node(childRef).is(AstNodeId::SwitchCaseStmt))
    {
        SemaFrame frame = sema.frame();
        frame.setCurrentSwitchCase(childRef);
        sema.pushFramePopOnPostChild(frame, childRef);
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    }

    return Result::Continue;
}

Result AstSwitchStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
    {
        SemaNodeView exprView = sema.viewNodeTypeConstant(nodeExprRef);
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, exprView));
        SWC_RESULT(normalizeSwitchExprTypeInfoIfNeeded(sema, nodeExprRef, exprView));
        SWC_RESULT(validateSwitchExprType(sema, nodeExprRef, exprView.typeRef()));

        auto* payload        = sema.semaPayload<SwitchPayload>(sema.curNodeRef());
        payload->exprTypeRef = exprView.typeRef();
        SWC_RESULT(attachSwitchExprRuntimeDependencies(sema, *payload, exprView.typeRef(), sema.node(sema.curNodeRef()).codeRef()));

        const TypeRef enumTypeRef = switchEnumTypeRef(sema, exprView.typeRef());
        if (enumTypeRef.isValid())
        {
            SemaFrame frame = sema.frame();
            frame.pushBindingType(enumTypeRef);
            sema.pushFramePopOnPostNode(frame);
        }
    }

    return Result::Continue;
}

Result AstSwitchCaseStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstSwitchCaseStmt::semaPreNodeChild(Sema& sema, AstNodeRef& childRef) const
{
    const AstNodeRef switchRef = sema.frame().currentSwitch();
    SWC_ASSERT(switchRef.isValid());

    const SwitchPayload* payload = sema.semaPayload<SwitchPayload>(switchRef);
    SWC_ASSERT(payload != nullptr);
    const TypeRef switchTypeRef = payload->exprTypeRef;
    if (switchTypeRef.isInvalid())
        return Result::Continue;

    // This is a 'default' case (no expressions). Validate default-specific rules once.
    if (!spanExprRef.isValid() && childRef == nodeBodyRef)
    {
        // A 'default' with a 'where' clause is always conditional and does not
        // participate in duplicate-default checks.
        if (nodeWhereRef.isValid())
            return Result::Continue;

        return validateDefaultSwitchCase(sema, switchRef, sema.frame().currentSwitchCase());
    }

    // Only touch case expressions (not the statements in the case body).
    if (!spanExprRef.isValid())
        return Result::Continue;

    const auto expressions = collectSwitchCaseExprRefs(sema, *this);
    const bool isExprChild = std::ranges::find(expressions, childRef) != expressions.end();
    if (!isExprChild)
        return Result::Continue;

    if (isDynamicStructSwitchCase(sema, switchRef) && sema.node(childRef).is(AstNodeId::AsCastExpr))
        markDynamicStructSwitchAsCaseExpr(sema, childRef);

    // If the switch is on an enum, allow shorthand by rewriting it to an
    // auto-member-access expression (equivalent to `.Value`), which will resolve in the
    // enum scope provided by the binding type pushed from the parent switch.
    const TypeRef enumTypeRef = switchEnumTypeRef(sema, switchTypeRef);
    if (enumTypeRef.isValid() && sema.node(childRef).is(AstNodeId::Identifier))
    {
        auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::AutoMemberAccessExpr>(sema.node(childRef).tokRef());
        nodePtr->nodeIdentRef   = childRef;
        childRef                = nodeRef;
    }

    return Result::Continue;
}

namespace
{
    Result castCaseToSwitch(Sema& sema, AstNodeRef nodeRef, TypeRef switchTypeRef)
    {
        SemaNodeView view = sema.viewNodeTypeConstant(nodeRef);
        return Cast::cast(sema, view, switchCaseCastTypeRef(sema, switchTypeRef), CastKind::Implicit);
    }

    Result checkCaseExprIsConst(Sema& sema, const AstNodeRef& exprRef)
    {
        const SemaNodeView exprView = sema.viewConstant(exprRef);
        if (exprView.cstRef().isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_case_not_const, exprRef);
        return Result::Continue;
    }

    Result handleRangeCaseExpr(Sema& sema, const AstNodeRef& rangeRef, TypeRef switchTypeRef)
    {
        const AstRangeExpr& range = sema.node(rangeRef).cast<AstRangeExpr>();
        if (range.nodeExprDownRef.isValid())
            SWC_RESULT(castCaseToSwitch(sema, range.nodeExprDownRef, switchTypeRef));
        if (range.nodeExprUpRef.isValid())
            SWC_RESULT(castCaseToSwitch(sema, range.nodeExprUpRef, switchTypeRef));

        if (range.nodeExprDownRef.isValid())
            SWC_RESULT(checkCaseExprIsConst(sema, range.nodeExprDownRef));
        if (range.nodeExprUpRef.isValid())
            SWC_RESULT(checkCaseExprIsConst(sema, range.nodeExprUpRef));

        return Result::Continue;
    }

    Result checkDuplicateConstCaseValue(Sema& sema, AstNodeRef switchRef, AstNodeRef caseExprRef, AstNodeRef whereRef)
    {
        // A case expression with a 'where' clause is not tested for duplicates, except
        // if the where clause if a 'true' constant.
        if (!whereClauseIsUnconditionalTrue(sema, whereRef))
            return Result::Continue;

        auto* seenSet = sema.semaPayload<SwitchPayload>(switchRef);
        SWC_ASSERT(seenSet);

        const SemaNodeView exprView = sema.viewConstant(caseExprRef);

        const auto it = seenSet->seen.find(exprView.cstRef());
        if (it == seenSet->seen.end())
        {
            seenSet->seen.emplace(exprView.cstRef(), caseExprRef);
            return Result::Continue;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_case_duplicate, caseExprRef);
        diag.addArgument(Diagnostic::ARG_VALUE, sema.cstMgr().get(exprView.cstRef()).toString(sema.ctx()));
        diag.addNote(DiagnosticId::sema_note_previous_case_value);
        diag.last().addSpan(sema.node(it->second).codeRangeWithChildren(sema.ctx(), sema.ast()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkDuplicateCaseValuesAfterWhere(Sema& sema, AstNodeRef switchRef, AstNodeRef caseRef)
    {
        const auto& caseStmt = sema.node(caseRef).cast<AstSwitchCaseStmt>();
        if (!caseStmt.nodeWhereRef.isValid() || !whereClauseIsUnconditionalTrue(sema, caseStmt.nodeWhereRef))
            return Result::Continue;

        if (isDynamicStructSwitchCase(sema, switchRef))
        {
            const auto* casePayload = sema.semaPayload<DynamicStructSwitchCasePayload>(caseRef);
            if (!casePayload)
                return Result::Continue;

            for (const auto& expr : casePayload->expressions)
            {
                const TypeRef targetTypeRef = sema.viewType(expr.typeExprRef).typeRef();
                SWC_ASSERT(targetTypeRef.isValid());

                const TypeRef targetStructTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), targetTypeRef);
                SWC_RESULT(checkDuplicateDynamicCaseType(sema, switchRef, targetStructTypeRef, expr.caseExprRef, caseStmt.nodeWhereRef));
            }

            return Result::Continue;
        }

        const auto expressions = collectSwitchCaseExprRefs(sema, caseStmt);
        for (const AstNodeRef exprRef : expressions)
        {
            if (sema.node(exprRef).is(AstNodeId::RangeExpr))
                continue;

            SWC_RESULT(checkDuplicateConstCaseValue(sema, switchRef, exprRef, caseStmt.nodeWhereRef));
        }

        return Result::Continue;
    }

    Result validateFallthroughStatementPosition(Sema& sema, AstNodeRef caseRef, AstNodeRef stmtRef)
    {
        const auto  statements = collectSwitchCaseBodyStmtRefs(sema, sema.node(caseRef).cast<AstSwitchCaseStmt>());
        const auto* itStmt     = std::ranges::find(statements, stmtRef);
        if (itStmt == statements.end())
            return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, stmtRef);
        if (itStmt + 1 != statements.end())
            return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_not_last_stmt, stmtRef);

        return Result::Continue;
    }

    Result validateFallthroughHasNextCase(Sema& sema, AstNodeRef switchRef, AstNodeRef caseRef, AstNodeRef stmtRef)
    {
        const auto  cases  = collectSwitchStmtCaseRefs(sema, sema.node(switchRef).cast<AstSwitchStmt>());
        const auto* itCase = std::ranges::find(cases, caseRef);
        if (itCase == cases.end())
            return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, stmtRef);
        if (itCase + 1 == cases.end())
            return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_in_last_case, stmtRef);

        return Result::Continue;
    }
}

Result AstSwitchCaseStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeWhereRef)
    {
        SemaNodeView view = sema.viewNodeTypeConstant(nodeWhereRef);
        SWC_RESULT(SemaCheck::castToBool(sema, view));

        const AstNodeRef switchRef = sema.frame().currentSwitch();
        SWC_ASSERT(switchRef.isValid());
        return checkDuplicateCaseValuesAfterWhere(sema, switchRef, sema.curNodeRef());
    }

    // Be sure this is a case expression
    if (!spanExprRef.isValid())
        return Result::Continue;
    const bool isExprChild = childRef != nodeWhereRef && childRef != nodeBodyRef;
    if (!isExprChild)
        return Result::Continue;

    const AstNodeRef switchRef = sema.frame().currentSwitch();
    SWC_ASSERT(switchRef.isValid());

    const SwitchPayload* payload       = sema.semaPayload<SwitchPayload>(switchRef);
    const TypeRef        switchTypeRef = payload->exprTypeRef;

    // This is a switch without an expression
    if (switchTypeRef.isInvalid())
    {
        SemaNodeView view = sema.viewNodeTypeConstant(childRef);
        SWC_RESULT(SemaCheck::castToBool(sema, view));
        return Result::Continue;
    }

    if (isDynamicStructSwitchCase(sema, switchRef))
        return validateDynamicStructCaseExpr(sema, switchRef, sema.curNodeRef(), childRef);

    // Range expression
    if (sema.node(childRef).is(AstNodeId::RangeExpr))
        return handleRangeCaseExpr(sema, childRef, switchTypeRef);

    // Be sure it's a value
    SemaNodeView exprView = sema.viewTypeConstant(childRef);
    SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, exprView));

    SWC_RESULT(castCaseToSwitch(sema, childRef, switchTypeRef));
    SWC_RESULT(checkCaseExprIsConst(sema, childRef));
    SWC_RESULT(checkDuplicateConstCaseValue(sema, switchRef, childRef, nodeWhereRef));

    return Result::Continue;
}

Result AstFallThroughStmt::semaPreNode(Sema& sema)
{
    if (sema.frame().currentBreakableKind() != SemaFrame::BreakContextKind::Switch)
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());

    const AstNodeRef caseRef = sema.frame().currentSwitchCase();
    if (caseRef.isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());
    SWC_RESULT(validateFallthroughStatementPosition(sema, caseRef, sema.curNodeRef()));

    const AstNodeRef     switchRef  = sema.frame().currentSwitch();
    const AstSwitchStmt& switchStmt = sema.node(switchRef).cast<AstSwitchStmt>();
    if (!switchStmt.spanChildrenRef.isValid())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());
    return validateFallthroughHasNextCase(sema, switchRef, caseRef, sema.curNodeRef());
}

SWC_END_NAMESPACE();
