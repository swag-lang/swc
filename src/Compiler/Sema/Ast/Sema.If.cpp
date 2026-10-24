#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaTagged.h"
#include "Compiler/Sema/Helpers/SemaVarDeclHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Constant.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct IfSemaPayload
    {
        Symbol*     maskedConditionSymbol = nullptr;
        ConstantRef maskedConditionCstRef = ConstantRef::invalid();

        // Restore the false branch's starting facts after true-branch kills have
        // propagated to the surrounding live frames.
        uint32_t narrowFactsAtThen = UINT32_MAX;
    };

    ConstantRef conditionSymbolConstantRef(const Symbol& symbol)
    {
        if (const auto* symVar = symbol.safeCast<SymbolVariable>())
            return symVar->cstRef();
        if (const auto* symConst = symbol.safeCast<SymbolConstant>())
            return symConst->cstRef();

        return ConstantRef::invalid();
    }

    void setConditionSymbolConstantRef(Symbol& symbol, ConstantRef cstRef)
    {
        if (auto* symVar = symbol.safeCast<SymbolVariable>())
        {
            symVar->setCstRef(cstRef);
            return;
        }

        if (auto* symConst = symbol.safeCast<SymbolConstant>())
        {
            symConst->setCstRef(cstRef);
            return;
        }

        SWC_UNREACHABLE();
    }

    bool ifVarDeclUsesLetBinding(Sema& sema, AstNodeRef varDeclRef)
    {
        const AstNodeRef declRef = SemaVarDeclHelpers::singleDeclarationRef(sema, varDeclRef);
        if (declRef.isInvalid())
            return false;

        const AstNode& declNode = sema.node(declRef);
        if (const auto* singleDecl = declNode.safeCast<AstSingleVarDecl>())
            return singleDecl->hasFlag(AstVarDeclFlagsE::Let);
        if (const auto* multiDecl = declNode.safeCast<AstMultiVarDecl>())
            return multiDecl->hasFlag(AstVarDeclFlagsE::Let);

        return false;
    }

    bool singleIfVarDeclConditionSymbol(Sema& sema, AstNodeRef varDeclRef, Symbol*& outSym)
    {
        outSym = nullptr;

        const AstNodeRef declRef = SemaVarDeclHelpers::singleDeclarationRef(sema, varDeclRef);
        if (declRef.isInvalid())
            return false;

        const SemaNodeView declView = sema.view(declRef, SemaNodeViewPartE::Symbol);
        Symbol*            symbol   = declView.singleSymbol();
        if (!symbol)
            return false;

        outSym = symbol;
        return true;
    }

    bool ifVarDeclNeedsWhereShortCircuit(Sema& sema, AstNodeRef varDeclRef)
    {
        if (!ifVarDeclUsesLetBinding(sema, varDeclRef))
            return false;

        Symbol* conditionSym = nullptr;
        if (!singleIfVarDeclConditionSymbol(sema, varDeclRef, conditionSym))
            return false;

        const TypeRef typeRef = conditionSym->typeRef();
        if (typeRef.isInvalid())
            return false;

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        return typeInfo.isPointerLikeAliasAware(sema.ctx()) || typeInfo.isNull();
    }

    void restoreMaskedIfVarDeclCondition(const Sema& sema, AstNodeRef nodeRef)
    {
        auto* payload = sema.semaPayload<IfSemaPayload>(nodeRef);
        if (!payload || !payload->maskedConditionSymbol)
            return;

        setConditionSymbolConstantRef(*payload->maskedConditionSymbol, payload->maskedConditionCstRef);
        payload->maskedConditionSymbol = nullptr;
        payload->maskedConditionCstRef = ConstantRef::invalid();
    }

    void maybeMaskIfVarDeclConditionForWhere(Sema& sema, AstNodeRef ifRef, AstNodeRef varDeclRef)
    {
        Symbol* conditionSym = nullptr;
        if (!singleIfVarDeclConditionSymbol(sema, varDeclRef, conditionSym))
            return;

        const ConstantRef conditionCstRef = conditionSymbolConstantRef(*conditionSym);
        if (conditionCstRef.isInvalid())
            return;

        auto& payload = sema.ensureSemaPayload<IfSemaPayload>(ifRef);

        payload.maskedConditionSymbol = conditionSym;
        payload.maskedConditionCstRef = conditionCstRef;
        setConditionSymbolConstantRef(*conditionSym, ConstantRef::invalid());
    }

    TypeRef normalizeWithBindingType(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
            if (typeInfo.isAlias())
            {
                typeRef = typeInfo.payloadSymAlias().underlyingTypeRef();
                continue;
            }

            if (typeInfo.isPointerOrReference())
            {
                typeRef = typeInfo.payloadTypeRef();
                continue;
            }

            break;
        }

        return typeRef;
    }

    AstNodeRef withBindingExprRef(Sema& sema, AstNodeRef exprRef)
    {
        if (exprRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& node = sema.node(exprRef);
        if (node.is(AstNodeId::AssignStmt))
            return node.cast<AstAssignStmt>().nodeLeftRef;

        const AstNodeRef resolvedRef = sema.resolvedNodeRef(exprRef);
        if (!resolvedRef.isValid())
            return exprRef;

        const AstNode& resolvedNode = sema.node(resolvedRef);
        if (resolvedNode.is(AstNodeId::AssignStmt))
            return resolvedNode.cast<AstAssignStmt>().nodeLeftRef;

        // Bind &var directly to its variable. Auto-member resolution would otherwise
        // clone the address expression, whose children codegen never visits because
        // they are outside the original AST.
        if (resolvedNode.is(AstNodeId::UnaryExpr))
        {
            const Token& tok = sema.token(resolvedNode.codeRef());
            if (tok.id == TokenId::SymAmpersand)
                return resolvedNode.cast<AstUnaryExpr>().nodeExprRef;
        }

        return resolvedRef;
    }

    bool singleVariableSymbol(Sema& sema, AstNodeRef nodeRef, SymbolVariable*& outSym)
    {
        outSym = nullptr;

        const SemaNodeView view   = sema.view(nodeRef, SemaNodeViewPartE::Symbol);
        Symbol*            symbol = view.singleSymbol();
        if (!symbol || !symbol->isVariable())
            return false;

        outSym = &symbol->cast<SymbolVariable>();
        return true;
    }

    Result configureWithBindings(Sema& sema, AstNodeRef errorRef, Symbol* symbol, TypeRef rawTypeRef, AstNodeRef baseExprRef, SemaFrame& ioFrame, SemaScope& bodyScope)
    {
        const TypeRef normalizedTypeRef = normalizeWithBindingType(sema.ctx(), rawTypeRef);
        if (!normalizedTypeRef.isValid())
        {
            if (rawTypeRef.isValid())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, errorRef);
                diag.addArgument(Diagnostic::ARG_TYPE, rawTypeRef);
                diag.report(sema.ctx());

                return Result::Error;
            }

            return SemaError::raise(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, errorRef);
        }

        const TypeInfo& typeInfo = sema.typeMgr().get(normalizedTypeRef);
        if (typeInfo.isStructOrAggregateStruct() || typeInfo.isEnum())
        {
            if (typeInfo.isEnum())
                bodyScope.addUsingSymMap(typeInfo.payloadSymEnum().asSymMap());

            const SymbolMap* symMap = nullptr;
            if (typeInfo.isStruct())
                symMap = &typeInfo.payloadSymStruct();
            else if (typeInfo.isEnum())
                symMap = &typeInfo.payloadSymEnum();

            // Rank every with subject by nesting depth. The flat binding-variable
            // list also holds receivers and inherited closure bindings, so it cannot
            // rank nested with subjects on its own.
            SymbolVariable* symVar = symbol ? symbol->safeCast<SymbolVariable>() : nullptr;

            const bool namedVar = symVar &&
                                  (symVar->hasGlobalStorage() ||
                                   symVar->hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                                   symVar->hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
                                   symVar->hasExtraFlag(SymbolVariableFlagsE::RetVal) ||
                                   symVar->isClosureCapture());

            // Named subjects must use their symbols: codegen does not visit cloned
            // expression children. Only unnamed subjects use a base expression.
            const AstNodeRef subjectExprRef = namedVar ? AstNodeRef::invalid() : baseExprRef;
            bodyScope.addAutoMemberBinding(
                {.symMap        = symMap,
                 .typeRef       = normalizedTypeRef,
                 .symVar        = namedVar ? symVar : nullptr,
                 .baseExprRef   = subjectExprRef,
                 .order         = sema.nextAutoMemberOrder(),
                 .inlinePayload = sema.frame().currentInlinePayload()});

            // A named subject stays a binding var too: that is what resolves its bare name inside
            // the block, and the duplicate candidate collapses during collection.
            if (namedVar)
                ioFrame.pushBindingVar(symVar);

            return Result::Continue;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, errorRef);
        diag.addArgument(Diagnostic::ARG_TYPE, normalizedTypeRef);
        diag.report(sema.ctx());

        return Result::Error;
    }

    // A missing `else` is still a path. It proves what the condition settled on its side and
    // nothing more: whatever else it carries, the statement already knew before the `if`.
    void collectMissingElseNarrowFacts(Sema& sema, AstNodeRef conditionRef, SmallVector2<SemaNarrowFact>& out)
    {
        SemaHelpers::NarrowGuards guards;
        SemaHelpers::collectNarrowGuards(sema, conditionRef, guards);
        out = std::move(guards.whenFalse);
    }

    // What one path proves at its end that the statement did not already know.
    void collectBranchNarrowCandidates(Sema& sema, const SmallVector2<SemaNarrowFact>& branchFacts, SmallVector2<SemaNarrowFact>& out)
    {
        for (const SemaNarrowFact& fact : branchFacts)
        {
            if (!fact.holds)
                continue;

            const std::span<const Symbol* const> path{fact.path.data(), fact.path.size()};

            // A tagged union ends the path holding the cases of its newest live fact.
            if (fact.kind == SemaNarrowFactKind::Case)
            {
                if (SemaFrame::findNarrowCases(branchFacts.span(), path) == &fact && !SemaFrame::findNarrowCases(out.span(), path))
                    out.push_back(fact);
                continue;
            }

            // A proof killed further down the same path is not proven where that path ends.
            if (!SemaFrame::queryNarrowFact(branchFacts.span(), path, fact.kind))
                continue;
            if (sema.frame().queryNarrowFact(path, fact.kind))
                continue;
            if (SemaFrame::queryNarrowFact(out.span(), path, fact.kind))
                continue;

            out.push_back(fact);
        }
    }

    void filterBranchNarrowCandidates(Sema& sema, const SmallVector2<SemaNarrowFact>& otherFacts, SmallVector2<SemaNarrowFact>& candidates)
    {
        SmallVector2<SemaNarrowFact> kept;
        for (const SemaNarrowFact& fact : candidates)
        {
            const std::span<const Symbol* const> path{fact.path.data(), fact.path.size()};

            // After the join the union holds a case either path could leave it in.
            if (fact.kind == SemaNarrowFactKind::Case)
            {
                if (const SemaNarrowFact* other = SemaFrame::findNarrowCases(otherFacts.span(), path))
                {
                    SemaNarrowFact& merged = kept.emplace_back(fact);
                    merged.cases           = SemaTagged::unionCases(sema, fact.cases, other->cases);
                }

                continue;
            }

            if (SemaFrame::queryNarrowFact(otherFacts.span(), path, fact.kind))
                kept.push_back(fact);
        }

        candidates = std::move(kept);
    }
}

Result AstIfStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeIfBlockRef || childRef == nodeElseBlockRef)
    {
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);

        // Narrow the nullable paths proven by the condition inside the matching branch.
        SemaHelpers::NarrowGuards guards;
        SemaHelpers::collectNarrowGuards(sema, nodeConditionRef, guards);
        const auto& facts = childRef == nodeIfBlockRef ? guards.whenTrue : guards.whenFalse;

        // A bare do body needs a branch frame to contain the facts it proves.
        // Braced bodies already own a frame; without one, facts leak across paths.
        const bool bodyOwnsFrame = sema.node(childRef).is(AstNodeId::EmbeddedBlock);

        // The false branch starts from the facts that held before the true one, without the kills
        // the true branch recorded on its own path.
        uint32_t factsAtThen = UINT32_MAX;
        if (childRef == nodeIfBlockRef)
            sema.ensureSemaPayload<IfSemaPayload>(sema.curNodeRef()).narrowFactsAtThen = sema.frame().narrowFactCount();
        else if (const auto* payload = sema.semaPayload<IfSemaPayload>(sema.curNodeRef()); payload && payload->narrowFactsAtThen < sema.frame().narrowFactCount())
            factsAtThen = payload->narrowFactsAtThen;

        if (!facts.empty() || !bodyOwnsFrame || factsAtThen != UINT32_MAX)
        {
            SemaFrame frame = sema.frame();
            if (factsAtThen != UINT32_MAX)
                frame.truncateNarrowFacts(factsAtThen);
            SemaHelpers::addNarrowFacts(frame, {facts.data(), facts.size()});
            sema.pushFramePopOnPostChild(std::move(frame), childRef);
        }

        // Capture braced bodies before their own frame disappears. A do body's
        // branch frame remains active until semaPostNodeChild captures it.
        if (bodyOwnsFrame)
            sema.armNarrowFactCapture(childRef);
    }

    if (childRef == nodeIfBlockRef)
        sema.pushEscapeBranch();

    return Result::Continue;
}

Result AstIfStmt::semaPostNode(Sema& sema) const
{
    // Take back what each branch published at its end, before anything else: an early return
    // must not leave a capture behind.
    SmallVector2<SemaNarrowFact> thenFacts;
    SmallVector2<SemaNarrowFact> elseFacts;
    sema.takeNarrowFactCapture(nodeIfBlockRef, thenFacts);
    sema.takeNarrowFactCapture(nodeElseBlockRef, elseFacts);

    // Only paths that reach the join contribute facts. Intersect surviving paths,
    // or retain the remaining path's facts when the other exits early.
    const bool thenStops = SemaHelpers::stopsLocalFlow(sema, nodeIfBlockRef);
    const bool elseStops = nodeElseBlockRef.isValid() && SemaHelpers::stopsLocalFlow(sema, nodeElseBlockRef);
    if (thenStops && elseStops)
        return Result::Continue;

    if (thenStops && nodeElseBlockRef.isInvalid())
        collectMissingElseNarrowFacts(sema, nodeConditionRef, elseFacts);

    SmallVector2<SemaNarrowFact> merged;
    collectBranchNarrowCandidates(sema, thenStops ? elseFacts : thenFacts, merged);
    if (merged.empty())
        return Result::Continue;

    if (!thenStops && !elseStops)
    {
        if (nodeElseBlockRef.isInvalid())
            collectMissingElseNarrowFacts(sema, nodeConditionRef, elseFacts);

        filterBranchNarrowCandidates(sema, elseFacts, merged);
        if (merged.empty())
            return Result::Continue;
    }

    // Publish in the existing frame: pushing a new one for an elif would block
    // the enclosing branch's region frame from popping. This frame already ends
    // at the enclosing block or branch region that bounds the facts.
    SemaHelpers::addNarrowFacts(sema.frame(), {merged.data(), merged.size()});
    return Result::Continue;
}

Result AstIfStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
    {
        SemaNodeView view = sema.viewNodeTypeConstant(nodeConditionRef);
        SWC_RESULT(SemaCheck::castToBool(sema, view));
    }

    // A "do" body owns no frame of its own, so what it proved is still in the region frame
    // pushed for the branch. That frame pops right after this call, hence the snapshot here.
    if (childRef.isValid() && (childRef == nodeIfBlockRef || childRef == nodeElseBlockRef) && !sema.node(childRef).is(AstNodeId::EmbeddedBlock))
        sema.captureNarrowFacts(childRef);

    if (childRef == nodeIfBlockRef)
    {
        // Each alternative starts from the entry borrow state; without an 'else' the
        // fall-through entry state is one of the alternatives.
        if (nodeElseBlockRef.isValid())
            sema.nextEscapeBranchAlternative();
        else
            sema.popEscapeBranch(true);
    }
    else if (childRef.isValid() && childRef == nodeElseBlockRef)
        sema.popEscapeBranch(false);

    return Result::Continue;
}

Result AstIfVarDecl::semaPreNode(Sema& sema)
{
    const auto& node = sema.node(sema.curNodeRef()).cast<AstIfVarDecl>();

    // A type-pattern name exists only after the match. Ordinary 'if let' keeps
    // its existing nullable binding in the else branch.
    if (sema.token(sema.node(node.nodeVarRef).codeRef()).is(TokenId::KwdIs))
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, node.nodeIfBlockRef);
    else
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);

    return Result::Continue;
}

Result AstIfVarDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeIfBlockRef || childRef == nodeElseBlockRef)
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);

    // `if let x = expr { ... }` only enters the block when `x` is truthy: a nullable
    // binding is proven non-null inside it. The `where` clause short-circuits the
    // same way, so it sees the proven binding too.
    if (childRef == nodeIfBlockRef || childRef == nodeWhereRef)
    {
        Symbol* conditionSym = nullptr;
        if (singleIfVarDeclConditionSymbol(sema, nodeVarRef, conditionSym) && conditionSym && conditionSym->isVariable())
        {
            TypeRef bindingTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), conditionSym->typeRef());
            if (bindingTypeRef.isInvalid())
                bindingTypeRef = conditionSym->typeRef();

            if (bindingTypeRef.isValid() && sema.typeMgr().get(bindingTypeRef).isNullable())
            {
                const std::array<const Symbol*, 1> path = {conditionSym};

                SemaFrame frame = sema.frame();
                frame.addNarrowFact({path.data(), path.size()}, SemaNarrowFactKind::NonNull);
                sema.pushFramePopOnPostChild(std::move(frame), childRef);
            }
        }
    }

    return Result::Continue;
}

Result AstIfVarDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeVarRef)
    {
        SWC_RESULT(SemaCheck::conditionBinding(sema, nodeVarRef));

        const bool usesConditionBinding = nodeWhereRef.isValid() && ifVarDeclNeedsWhereShortCircuit(sema, nodeVarRef);

        SemaHelpers::ensureCodeGenLoweringPayload(sema, sema.curNodeRef()).ifVarDeclWhereUsesConditionBinding = usesConditionBinding;
        if (usesConditionBinding)
        {
            maybeMaskIfVarDeclConditionForWhere(sema, sema.curNodeRef(), nodeVarRef);
        }
    }

    if (childRef == nodeWhereRef)
    {
        SemaNodeView view   = sema.viewNodeTypeConstant(nodeWhereRef);
        const Result result = SemaCheck::castToBool(sema, view);

        restoreMaskedIfVarDeclCondition(sema, sema.curNodeRef());
        return result;
    }

    return Result::Continue;
}

Result AstElseStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstElseIfStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstWithStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    const AstNodeRef   baseExprRef = withBindingExprRef(sema, nodeExprRef);
    const SemaNodeView exprView    = sema.viewNodeTypeSymbol(baseExprRef);

    // with requires a value subject. Type and namespace scopes belong to using;
    // accepting both would give auto-member lookup unrelated subjects to rank.
    const Symbol* subjectSym = exprView.sym();
    if (subjectSym && subjectSym->isSymMap())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_with_scope_subject, nodeExprRef);
        diag.addArgument(Diagnostic::ARG_SYM, subjectSym->getFullScopedName(sema.ctx()));
        diag.report(sema.ctx());

        return Result::Error;
    }

    // Require an existing place because each .member reuses the subject expression.
    // A computed subject would run again per member and lose its original value.
    if (baseExprRef.isValid() && !sema.isLValue(baseExprRef))
        return SemaError::raise(sema, DiagnosticId::sema_err_with_needs_a_place, baseExprRef);

    auto       scopedFrame = sema.frame();
    SemaScope* bodyScope   = sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    SWC_RESULT(configureWithBindings(sema, nodeExprRef, exprView.sym(), exprView.typeRef(), baseExprRef, scopedFrame, *bodyScope));
    sema.pushFramePopOnPostChild(std::move(scopedFrame), childRef);

    return Result::Continue;
}

Result AstWithVarDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    SymbolVariable* symVar = nullptr;
    if (!singleVariableSymbol(sema, nodeVarRef, symVar))
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, nodeVarRef);

    auto       scopedFrame = sema.frame();
    SemaScope* bodyScope   = sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    SWC_RESULT(configureWithBindings(sema, nodeVarRef, symVar, symVar->typeRef(), AstNodeRef::invalid(), scopedFrame, *bodyScope));
    sema.pushFramePopOnPostChild(std::move(scopedFrame), childRef);

    return Result::Continue;
}

SWC_END_NAMESPACE();
