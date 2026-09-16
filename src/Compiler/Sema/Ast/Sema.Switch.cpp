#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Ast/Sema.Switch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaEscape.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

bool SemaSwitch::isDynamicType(Sema& sema, TypeRef typeRef)
{
    if (typeRef.isInvalid())
        return false;
    const TypeInfo& type = sema.typeMgr().get(sema.typeMgr().unwrapAlias(sema.ctx(), typeRef));
    if (type.isInterface() || type.isAny())
        return true;
    if (!type.isValuePointer())
        return false;
    const TypeInfo& pointee = sema.typeMgr().get(sema.typeMgr().unwrapAlias(sema.ctx(), type.payloadTypeRef()));
    return pointee.isStruct() && pointee.payloadSymStruct().isDynamic();
}

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

        if (!sema.frame().currentAttributes().hasRuntimeSafety(sema.runtimeSafetyGuards(), Runtime::SafetyWhat::Switch))
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

    TypeRef switchEnumTypeRef(Sema& sema, TypeRef typeRef)
    {
        const TypeRef enumTypeRef = sema.typeMgr().get(typeRef).unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
        if (sema.typeMgr().get(enumTypeRef).isEnum())
            return enumTypeRef;
        return TypeRef::invalid();
    }

    Result waitSwitchEnumCompletionIfNeeded(Sema& sema, TypeRef typeRef, AstNodeRef nodeRef)
    {
        const TypeRef enumTypeRef = switchEnumTypeRef(sema, typeRef);
        if (enumTypeRef.isInvalid())
            return Result::Continue;

        const TypeInfo& enumType = sema.typeMgr().get(enumTypeRef);
        return sema.waitSemaCompleted(&enumType, nodeRef);
    }

    TypeRef switchCaseCastTypeRef(Sema& sema, TypeRef switchTypeRef)
    {
        const TypeRef enumTypeRef = switchEnumTypeRef(sema, switchTypeRef);
        if (enumTypeRef.isValid())
            return enumTypeRef;

        // A switch case only COMPARES against the operand, it never writes through it:
        // like relational comparisons, a non-null pointer operand can be compared with
        // `case null` (statically always false). Case values therefore cast to the
        // nullable form of the operand type. This also keeps compilation independent of
        // inlining: an inlined body whose nullable parameter was materialized from a
        // non-null argument must still accept its `case null`.
        if (switchTypeRef.isValid())
        {
            const TypeInfo& switchType = sema.typeMgr().get(switchTypeRef);
            if (switchType.isAnyPointer() && !switchType.isNullable())
            {
                TypeInfo widenedType = switchType;
                widenedType.addFlag(TypeInfoFlagsE::Nullable);
                return sema.typeMgr().addType(widenedType);
            }
        }

        return switchTypeRef;
    }

    TypeRef switchExprUltimateTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        return sema.typeMgr().get(typeRef).unwrap(sema.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    }

    bool isPointerSwitchType(Sema& sema, TypeRef typeRef)
    {
        const TypeRef ultimateTypeRef = switchExprUltimateTypeRef(sema, typeRef);
        if (!ultimateTypeRef.isValid())
            return false;

        const TypeInfo& ultimateType = sema.typeMgr().get(ultimateTypeRef);
        return ultimateType.isAnyPointer() && !ultimateType.isAnyTypeInfo(sema.ctx());
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
        SWC_RESULT(waitSwitchEnumCompletionIfNeeded(sema, exprTypeRef, exprRef));

        const TypeRef   ultimateTypeRef = switchExprUltimateTypeRef(sema, exprTypeRef);
        const TypeInfo& finalType       = sema.typeMgr().get(ultimateTypeRef);
        if (finalType.isValuePointer())
        {
            const TypeInfo& pointee = sema.typeMgr().get(sema.typeMgr().unwrapAlias(sema.ctx(), finalType.payloadTypeRef()));
            // The dynamic marker belongs to the struct's attributes, which may still
            // be under analysis when a function first switches on its pointer.
            if (pointee.isStruct())
                SWC_RESULT(sema.waitSemaCompleted(&pointee, exprRef));
        }
        if (SemaSwitch::isDynamicType(sema, exprTypeRef) || finalType.isIntLike() || finalType.isFloat() || finalType.isBool() || finalType.isString() || finalType.isAnyPointer() || finalType.isAnyTypeInfo(sema.ctx()))
            return Result::Continue;

        return SemaError::raise(sema, DiagnosticId::sema_err_switch_invalid_type, exprRef);
    }

    Result attachSwitchExprRuntimeDependencies(Sema& sema, SwitchPayload& payload, TypeRef exprTypeRef, const SourceCodeRef& codeRef)
    {
        SWC_RESULT(waitSwitchEnumCompletionIfNeeded(sema, exprTypeRef, sema.curNodeRef()));

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
        return SemaSwitch::isDynamicType(sema, dynamicStructSwitchExprTypeRef(sema, switchRef));
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

        // Duplicate-case detection is a source-level check, but it is re-run when a callee's body
        // is materialized inline. Inlining substitutes the callee parameters with the call-site
        // arguments, so a runtime `case <v> where <param>` clause can fold to a constant `true`
        // (e.g. `#run f(1, true)` makes `where takeFirst` look unconditional) even though the
        // source clause is conditional. The canonical body was already validated before being
        // materialized, so inside an inline context a `where` clause must keep its source meaning
        // (conditional) and never be treated as unconditional, otherwise a later same-value case is
        // falsely reported as a duplicate.
        if (sema.frame().currentInlinePayload() != nullptr)
            return false;

        const SemaNodeView whereView = sema.viewConstant(whereRef);
        return whereView.cstRef().isValid() && whereView.cstRef() == sema.cstMgr().cstTrue();
    }

    size_t switchSpanNodeCount(const Ast& ast, SpanRef spanRef)
    {
        if (spanRef.isInvalid())
            return 0;
        return ast.spanSize(spanRef);
    }

    bool switchSpanContainsNodeRef(const Ast& ast, SpanRef spanRef, AstNodeRef targetRef)
    {
        const size_t count = switchSpanNodeCount(ast, spanRef);
        for (size_t i = 0; i < count; ++i)
        {
            if (ast.nthNode(spanRef, i) == targetRef)
                return true;
        }

        return false;
    }

    AstNodeRef switchSpanNextNodeRef(const Ast& ast, SpanRef spanRef, AstNodeRef currentRef)
    {
        const size_t count = switchSpanNodeCount(ast, spanRef);
        for (size_t i = 0; i < count; ++i)
        {
            if (ast.nthNode(spanRef, i) != currentRef)
                continue;
            if (i + 1 >= count)
                return AstNodeRef::invalid();
            return ast.nthNode(spanRef, i + 1);
        }

        return AstNodeRef::invalid();
    }

    SpanRef fallthroughContainerSpan(const AstNode& node)
    {
        if (const auto* embeddedBlock = node.safeCast<AstEmbeddedBlock>())
            return embeddedBlock->spanChildrenRef;
        if (const auto* elseStmt = node.safeCast<AstElseStmt>())
            return elseStmt->spanChildrenRef;
        if (const auto* elseIfStmt = node.safeCast<AstElseIfStmt>())
            return elseIfStmt->spanChildrenRef;
        return SpanRef::invalid();
    }

    bool isFallthroughIfBranch(const AstNode& node, AstNodeRef childRef)
    {
        if (const auto* ifStmt = node.safeCast<AstIfStmt>())
            return childRef == ifStmt->nodeIfBlockRef || childRef == ifStmt->nodeElseBlockRef;
        if (const auto* ifVarDecl = node.safeCast<AstIfVarDecl>())
            return childRef == ifVarDecl->nodeIfBlockRef || childRef == ifVarDecl->nodeElseBlockRef;
        return false;
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

    Result registerDynamicStructSwitchBinding(Sema& sema, AstNodeRef caseRef, AstNodeRef caseExprRef, AstNodeRef identRef, TypeRef bindingTypeRef)
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

        sym->registerAttributes(sema);
        sym->setDeclared(ctx);
        sym->addExtraFlag(SymbolVariableFlagsE::Initialized);
        sym->addExtraFlag(SymbolVariableFlagsE::Let);
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

        const auto*      binding = sema.node(caseExprRef).safeCast<AstAsCastExpr>();
        const AstNodeRef typeRef = binding ? binding->nodeExprRef : caseExprRef;
        auto             diag    = SemaError::report(sema, DiagnosticId::sema_err_switch_case_duplicate, typeRef);
        diag.addArgument(Diagnostic::ARG_VALUE, sema.typeMgr().get(targetStructTypeRef).toName(sema.ctx()));
        diag.addNote(DiagnosticId::sema_note_previous_case_value);
        diag.last().addSpan(sema.node(it->second).codeRangeWithChildren(sema.ctx(), sema.ast()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result validateDynamicStructCaseExpr(Sema& sema, AstNodeRef switchRef, AstNodeRef caseRef, AstNodeRef caseExprRef)
    {
        const auto& caseStmt = sema.node(caseRef).cast<AstSwitchCaseStmt>();

        AstNodeRef typeExprRef     = caseExprRef;
        AstNodeRef bindingIdentRef = AstNodeRef::invalid();
        if (sema.node(caseExprRef).is(AstNodeId::AsCastExpr))
        {
            if (switchSpanNodeCount(sema.ast(), caseStmt.spanExprRef) != 1)
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

        const TypeRef   switchTypeRef = dynamicStructSwitchExprTypeRef(sema, switchRef);
        const TypeRef   targetTypeRef = typeView.typeRef();
        const TypeInfo& targetType    = sema.typeMgr().get(sema.typeMgr().unwrapAlias(sema.ctx(), targetTypeRef));
        const TypeInfo& sourceType    = sema.typeMgr().get(switchTypeRef);
        TypeInfoFlags   flags         = sourceType.isConst() ? TypeInfoFlagsE::Const : TypeInfoFlagsE::Zero;
        TypeInfo        destination   = targetType.isInterface() ? targetType : TypeInfo::makeValuePointer(targetTypeRef, flags);
        if (sourceType.isConst())
            destination.addFlag(TypeInfoFlagsE::Const);

        // Validate through the same cast as 'is' and '#try', including dynamic metadata
        // requirements and constness. Keep its storage for interface views in codegen.
        auto [castRef, castNode] = sema.ast().makeNode<AstNodeId::CastExpr>(sema.node(caseExprRef).tokRef());
        castNode->nodeExprRef    = sema.node(switchRef).cast<AstSwitchStmt>().nodeExprRef;
        sema.setType(castRef, switchTypeRef);
        SemaNodeView castView = sema.viewNodeTypeConstant(castRef);
        SWC_RESULT(Cast::castDynamic(sema, castView, sema.typeMgr().addType(destination), CastFlagsE::Try));

        registerDynamicStructSwitchCaseExpr(sema, caseRef, caseExprRef, typeExprRef);
        auto& casePayload = ensureDynamicStructSwitchCasePayload(sema, caseRef);
        for (auto& expr : casePayload.expressions)
            if (expr.caseExprRef == caseExprRef)
                expr.castRef = castRef;
        if (bindingIdentRef.isValid())
        {
            TypeInfo bindingType = sema.typeMgr().get(castView.typeRef());
            bindingType.removeFlag(TypeInfoFlagsE::Nullable);
            SWC_RESULT(registerDynamicStructSwitchBinding(sema, caseRef, caseExprRef, bindingIdentRef, sema.typeMgr().addType(bindingType)));
            SWC_RESULT(SemaEscape::checkVariableInitializer(sema, *casePayload.bindingSymbol, castRef, casePayload.bindingSymbol->typeRef()));
        }

        return checkDuplicateDynamicCaseType(sema, switchRef, targetTypeRef, caseExprRef, caseStmt.nodeWhereRef);
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

    Result validateEnumSwitchCaseSyntax(Sema& sema, AstNodeRef caseExprRef, TypeRef enumTypeRef)
    {
        const auto* identifier = sema.node(caseExprRef).safeCast<AstIdentifier>();
        if (!identifier)
            return Result::Continue;

        const IdentifierRef idRef      = SemaHelpers::resolveIdentifier(sema, identifier->codeRef());
        const TypeInfo&     enumType   = sema.typeMgr().get(enumTypeRef);
        const Symbol*       enumMember = enumType.payloadSymEnum().findFirstSymbol(idRef);
        if (!enumMember || !enumMember->isEnumValue())
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_case_enum_value_requires_dot, caseExprRef);
        diag.addArgument(Diagnostic::ARG_SYM, idRef);
        diag.report(sema.ctx());
        return Result::Error;
    }
}

TypeRef SemaSwitch::enumTypeRef(Sema& sema, TypeRef typeRef)
{
    return switchEnumTypeRef(sema, typeRef);
}

TypeRef SemaSwitch::caseCastTypeRef(Sema& sema, TypeRef switchTypeRef)
{
    return switchCaseCastTypeRef(sema, switchTypeRef);
}

Result SemaSwitch::normalizeExprTypeInfoIfNeeded(Sema& sema, AstNodeRef exprRef, SemaNodeView& exprView)
{
    return normalizeSwitchExprTypeInfoIfNeeded(sema, exprRef, exprView);
}

Result SemaSwitch::validateExprType(Sema& sema, AstNodeRef exprRef, TypeRef exprTypeRef)
{
    return validateSwitchExprType(sema, exprRef, exprTypeRef);
}

Result AstSwitchStmt::semaPreNode(Sema& sema) const
{
    constexpr AstModifierFlags allowed = AstModifierFlagsE::Complete;
    SWC_RESULT(SemaCheck::modifiers(sema, *this, modifierFlags, allowed));

    // Exhaustiveness is decided per switch, so '#complete' is a modifier of this statement
    // and not an attribute: there is no symbol to hang an attribute on.
    const bool isComplete = modifierFlags.has(AstModifierFlagsE::Complete);

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
    SwitchPayload* payload = sema.semaPayload<SwitchPayload>(sema.curNodeRef());
    SWC_ASSERT(payload != nullptr);

    if (payload->exprTypeRef.isInvalid())
        SWC_RESULT(setupSwitchRuntimeSafety(sema, *payload, sema.node(sema.curNodeRef()).codeRef()));

    // Close the borrow-flow alternatives; the entry state joins them (a switch may
    // fall through every case).
    if (payload->escapeBranchPushed)
        sema.popEscapeBranch(true);

    if (!payload->isComplete)
        return Result::Continue;

    return SemaSwitch::checkEnumExhaustive(sema, payload->seen, payload->exprTypeRef, sema.curNodeRef());
}

bool SemaSwitch::alwaysMatchesACase(Sema& sema, AstNodeRef switchRef, const AstSwitchStmt& switchStmt)
{
    const auto* payload = sema.semaPayload<SwitchPayload>(switchRef);
    if (payload && (payload->isComplete || payload->firstDefaultRef.isValid()))
        return true;

    SmallVector<AstNodeRef> children;
    Ast::nodeIdInfos(switchStmt.id()).collectChildren(children, sema.ast(), switchStmt);
    for (const AstNodeRef childRef : children)
    {
        if (childRef.isInvalid())
            continue;

        const AstNodeRef caseRef  = sema.viewZero(childRef).nodeRef();
        const AstNodeRef resolved = caseRef.isValid() ? caseRef : childRef;
        if (sema.node(resolved).isNot(AstNodeId::SwitchCaseStmt))
            continue;

        const auto&             caseStmt = sema.node(resolved).cast<AstSwitchCaseStmt>();
        SmallVector<AstNodeRef> matchExprs;
        AstNode::collectChildren(matchExprs, sema.ast(), caseStmt.spanExprRef);
        if (matchExprs.empty() && caseStmt.nodeWhereRef.isInvalid())
            return true;
    }

    return false;
}

Result SemaSwitch::checkEnumExhaustive(Sema& sema, const SwitchSeenCases& seen, TypeRef exprTypeRef, AstNodeRef errorRef)
{
    if (exprTypeRef.isInvalid())
        return Result::Continue;

    const TypeRef enumTypeRef = switchEnumTypeRef(sema, exprTypeRef);
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

        if (!seen.contains(cstRef))
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_complete_enum_not_exhaustive, errorRef);
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

        // Every case is a borrow-flow alternative starting from the switch entry state.
        auto* payload = sema.semaPayload<SwitchPayload>(sema.curNodeRef());
        if (payload && !payload->escapeBranchPushed)
        {
            payload->escapeBranchPushed = true;
            sema.pushEscapeBranch();
        }
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

        // Every case of a switch on an enum names the members bare, in its label and its body.
        const TypeRef enumTypeRef = switchEnumTypeRef(sema, exprView.typeRef());
        if (enumTypeRef.isValid())
        {
            SemaFrame frame = sema.frame();
            frame.pushScopeBindingType(enumTypeRef);
            sema.pushFramePopOnPostNode(frame);
        }
    }

    // Each completed case restarts the borrow flow from the switch entry state.
    if (sema.node(childRef).is(AstNodeId::SwitchCaseStmt))
    {
        const auto* payload = sema.semaPayload<SwitchPayload>(sema.curNodeRef());
        if (payload && payload->escapeBranchPushed)
            sema.nextEscapeBranchAlternative();
    }

    return Result::Continue;
}

Result AstSwitchCaseStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstSwitchCaseStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    const AstNodeRef switchRef = sema.frame().currentSwitch();
    SWC_ASSERT(switchRef.isValid());

    const SwitchPayload* payload = sema.semaPayload<SwitchPayload>(switchRef);
    SWC_ASSERT(payload != nullptr);
    const TypeRef switchTypeRef = payload->exprTypeRef;

    const AstNodeRef bindingRef = conditionBindingRef(sema.ast());
    if (bindingRef.isValid())
    {
        if (switchTypeRef.isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_binding_has_expr, bindingRef);
        if (childRef == nodeWhereRef || childRef == nodeBodyRef)
        {
            const Symbol* symbol = sema.viewSymbol(bindingRef).singleSymbol();
            if (symbol && symbol->isVariable() && symbol->typeInfo(sema.ctx()).isNullable())
            {
                SemaFrame                          frame = sema.frame();
                const std::array<const Symbol*, 1> path  = {symbol};
                frame.addNarrowFact(path, SemaNarrowFactKind::NonNull);
                sema.pushFramePopOnPostChild(frame, childRef);
            }
        }
        return Result::Continue;
    }
    // This is a 'default' case (no expressions). Validate default-specific rules once.
    if (!spanExprRef.isValid() && childRef == nodeBodyRef)
    {
        // A 'default' with a 'where' clause is always conditional and does not
        // participate in duplicate-default checks.
        if (nodeWhereRef.isValid())
            return Result::Continue;

        return validateDefaultSwitchCase(sema, switchRef, sema.frame().currentSwitchCase());
    }

    if (switchTypeRef.isInvalid())
        return Result::Continue;

    // Only touch case expressions (not the statements in the case body).
    if (!spanExprRef.isValid())
        return Result::Continue;

    if (!switchSpanContainsNodeRef(sema.ast(), spanExprRef, childRef))
        return Result::Continue;

    if (isDynamicStructSwitchCase(sema, switchRef) && sema.node(childRef).is(AstNodeId::AsCastExpr))
        markDynamicStructSwitchAsCaseExpr(sema, childRef);

    const TypeRef enumTypeRef = switchEnumTypeRef(sema, switchTypeRef);
    if (enumTypeRef.isValid())
        SWC_RESULT(validateEnumSwitchCaseSyntax(sema, childRef, enumTypeRef));

    return Result::Continue;
}

namespace
{
    Result castCaseToSwitch(Sema& sema, AstNodeRef nodeRef, TypeRef switchTypeRef)
    {
        SemaNodeView view = sema.viewNodeTypeConstant(nodeRef);
        return Cast::cast(sema, view, switchCaseCastTypeRef(sema, switchTypeRef), CastKind::Implicit);
    }

    Result validatePointerSwitchCaseType(Sema& sema, AstNodeRef caseExprRef, TypeRef switchTypeRef)
    {
        const TypeRef sourceTypeRef = sema.viewType(caseExprRef).typeRef();
        if (!sourceTypeRef.isValid())
            return Result::Continue;

        const TypeRef   ultimateSourceTypeRef = switchExprUltimateTypeRef(sema, sourceTypeRef);
        const TypeRef   ultimateSwitchTypeRef = switchExprUltimateTypeRef(sema, switchTypeRef);
        const TypeInfo& sourceType            = sema.typeMgr().get(ultimateSourceTypeRef);
        const TypeInfo& switchType            = sema.typeMgr().get(ultimateSwitchTypeRef);

        if (sourceType.isNull())
            return Result::Continue;

        if (sourceType.isAnyPointer() &&
            switchType.isAnyPointer() &&
            sourceType.kind() == switchType.kind() &&
            sourceType.payloadTypeRef() == switchType.payloadTypeRef())
            return Result::Continue;

        return SemaError::raiseCannotCast(sema, caseExprRef, sourceTypeRef, switchTypeRef);
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
        if (isPointerSwitchType(sema, switchTypeRef))
        {
            if (range.nodeExprDownRef.isValid())
                SWC_RESULT(validatePointerSwitchCaseType(sema, range.nodeExprDownRef, switchTypeRef));
            if (range.nodeExprUpRef.isValid())
                SWC_RESULT(validatePointerSwitchCaseType(sema, range.nodeExprUpRef, switchTypeRef));
        }

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
        const auto* switchPayload = sema.semaPayload<SwitchPayload>(switchRef);
        if (switchPayload->exprTypeRef.isInvalid())
            return Result::Continue;
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
                if (expr.castRef.isInvalid())
                {
                    if (sema.node(expr.caseExprRef).isNot(AstNodeId::RangeExpr))
                        SWC_RESULT(checkDuplicateConstCaseValue(sema, switchRef, expr.caseExprRef, caseStmt.nodeWhereRef));
                    continue;
                }
                const TypeRef targetTypeRef = sema.viewType(expr.typeExprRef).typeRef();
                SWC_ASSERT(targetTypeRef.isValid());

                const TypeRef targetStructTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), targetTypeRef);
                SWC_RESULT(checkDuplicateDynamicCaseType(sema, switchRef, targetStructTypeRef, expr.caseExprRef, caseStmt.nodeWhereRef));
            }

            return Result::Continue;
        }

        const size_t exprCount = switchSpanNodeCount(sema.ast(), caseStmt.spanExprRef);
        for (size_t i = 0; i < exprCount; ++i)
        {
            const AstNodeRef exprRef = sema.ast().nthNode(caseStmt.spanExprRef, i);
            if (sema.node(exprRef).is(AstNodeId::RangeExpr))
                continue;

            SWC_RESULT(checkDuplicateConstCaseValue(sema, switchRef, exprRef, caseStmt.nodeWhereRef));
        }

        return Result::Continue;
    }

    Result validateFallthroughStatementPosition(Sema& sema, AstNodeRef caseRef, AstNodeRef stmtRef)
    {
        const auto& caseStmt   = sema.node(caseRef).cast<AstSwitchCaseStmt>();
        const auto& caseBody   = sema.node(caseStmt.nodeBodyRef).cast<AstSwitchCaseBody>();
        AstNodeRef  currentRef = stmtRef;
        for (size_t up = 0;; ++up)
        {
            const AstNodeRef parentRef = sema.visit().parentNodeRef(up);
            if (parentRef.isInvalid())
                return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, stmtRef);

            if (parentRef == caseStmt.nodeBodyRef)
            {
                if (!switchSpanContainsNodeRef(sema.ast(), caseBody.spanChildrenRef, currentRef))
                    return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, stmtRef);
                if (switchSpanNextNodeRef(sema.ast(), caseBody.spanChildrenRef, currentRef).isValid())
                    return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_not_last_stmt, stmtRef);
                return Result::Continue;
            }

            const AstNode& parentNode = sema.node(parentRef);
            const SpanRef  spanRef    = fallthroughContainerSpan(parentNode);
            if (spanRef.isValid())
            {
                if (!switchSpanContainsNodeRef(sema.ast(), spanRef, currentRef))
                    return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, stmtRef);
                if (switchSpanNextNodeRef(sema.ast(), spanRef, currentRef).isValid())
                    return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_not_last_stmt, stmtRef);
                currentRef = parentRef;
                continue;
            }

            if (isFallthroughIfBranch(parentNode, currentRef))
            {
                currentRef = parentRef;
                continue;
            }

            return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, stmtRef);
        }
    }

    Result validateFallthroughHasNextCase(Sema& sema, AstNodeRef switchRef, AstNodeRef caseRef, AstNodeRef stmtRef)
    {
        const auto& switchStmt = sema.node(switchRef).cast<AstSwitchStmt>();
        if (!switchSpanContainsNodeRef(sema.ast(), switchStmt.spanChildrenRef, caseRef))
            return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, stmtRef);
        if (switchSpanNextNodeRef(sema.ast(), switchStmt.spanChildrenRef, caseRef).isInvalid())
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
        if (childRef == conditionBindingRef(sema.ast()))
            return SemaCheck::conditionBinding(sema, childRef);
        SemaNodeView view = sema.viewNodeTypeConstant(childRef);
        SWC_RESULT(SemaCheck::castToBool(sema, view));
        return Result::Continue;
    }

    const bool dynamicSwitch = isDynamicStructSwitchCase(sema, switchRef);
    const bool rangeCase     = sema.node(childRef).is(AstNodeId::RangeExpr);
    if (dynamicSwitch)
    {
        const TypeInfo& switchType = sema.typeMgr().get(sema.typeMgr().unwrapAlias(sema.ctx(), switchTypeRef));
        // Dynamic pointers keep ordinary pointer comparisons alongside type patterns.
        if (!switchType.isValuePointer() || sema.node(childRef).is(AstNodeId::AsCastExpr) || (!rangeCase && !sema.isValue(childRef)))
            return validateDynamicStructCaseExpr(sema, switchRef, sema.curNodeRef(), childRef);
    }

    // Range expression
    if (rangeCase)
    {
        SWC_RESULT(handleRangeCaseExpr(sema, childRef, switchTypeRef));
        if (dynamicSwitch)
            registerDynamicStructSwitchCaseExpr(sema, sema.curNodeRef(), childRef, AstNodeRef::invalid());
        return Result::Continue;
    }

    // Be sure it's a value
    SemaNodeView exprView = sema.viewTypeConstant(childRef);
    SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, exprView));

    if (isPointerSwitchType(sema, switchTypeRef))
        SWC_RESULT(validatePointerSwitchCaseType(sema, childRef, switchTypeRef));

    SWC_RESULT(castCaseToSwitch(sema, childRef, switchTypeRef));
    SWC_RESULT(checkCaseExprIsConst(sema, childRef));
    SWC_RESULT(checkDuplicateConstCaseValue(sema, switchRef, childRef, nodeWhereRef));
    if (dynamicSwitch)
        registerDynamicStructSwitchCaseExpr(sema, sema.curNodeRef(), childRef, AstNodeRef::invalid());

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
