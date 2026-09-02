#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
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
    struct IfVarDeclWhereSemaPayload
    {
        Symbol*     maskedConditionSymbol = nullptr;
        ConstantRef maskedConditionCstRef = ConstantRef::invalid();
    };

    IfVarDeclWhereSemaPayload& ensureIfVarDeclWhereSemaPayload(Sema& sema, AstNodeRef nodeRef)
    {
        if (auto* payload = sema.semaPayload<IfVarDeclWhereSemaPayload>(nodeRef))
            return *payload;

        auto* payload = sema.compiler().allocate<IfVarDeclWhereSemaPayload>();
        sema.setSemaPayload(nodeRef, payload);
        return *payload;
    }

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

    AstNodeRef singleIfVarDeclDeclRef(Sema& sema, AstNodeRef varDeclRef)
    {
        AstNodeRef     declRef = varDeclRef;
        const AstNode& varNode = sema.node(varDeclRef);
        if (varNode.is(AstNodeId::VarDeclList))
        {
            const auto&             list = varNode.cast<AstVarDeclList>();
            SmallVector<AstNodeRef> decls;
            sema.ast().appendNodes(decls, list.spanChildrenRef);
            if (decls.size() != 1)
                return AstNodeRef::invalid();
            declRef = decls.front();
        }

        return declRef;
    }

    bool ifVarDeclUsesLetBinding(Sema& sema, AstNodeRef varDeclRef)
    {
        const AstNodeRef declRef = singleIfVarDeclDeclRef(sema, varDeclRef);
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

        const AstNodeRef declRef = singleIfVarDeclDeclRef(sema, varDeclRef);
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
        auto* payload = sema.semaPayload<IfVarDeclWhereSemaPayload>(nodeRef);
        if (!payload || !payload->maskedConditionSymbol)
            return;

        setConditionSymbolConstantRef(*payload->maskedConditionSymbol, payload->maskedConditionCstRef);
        *payload = {};
    }

    void maybeMaskIfVarDeclConditionForWhere(Sema& sema, AstNodeRef ifRef, AstNodeRef varDeclRef)
    {
        Symbol* conditionSym = nullptr;
        if (!singleIfVarDeclConditionSymbol(sema, varDeclRef, conditionSym))
            return;

        const ConstantRef conditionCstRef = conditionSymbolConstantRef(*conditionSym);
        if (conditionCstRef.isInvalid())
            return;

        auto& payload                 = ensureIfVarDeclWhereSemaPayload(sema, ifRef);
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

            if (typeInfo.isReference() || typeInfo.isAnyPointer())
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

        const AstNodeRef resolvedRef = sema.viewZero(exprRef).nodeRef();
        if (!resolvedRef.isValid())
            return exprRef;

        const AstNode& resolvedNode = sema.node(resolvedRef);
        if (resolvedNode.is(AstNodeId::AssignStmt))
            return resolvedNode.cast<AstAssignStmt>().nodeLeftRef;

        // When the `with` expression is an address-of (`&var`), unwrap to the underlying
        // variable so that configureWithBindings can use the direct variable binding path.
        // Without this, the address-of expression would be stored as a baseExprRef and
        // cloned during auto-member resolution, but the clone's children are never visited
        // by the codegen walker (they are not part of the original AST tree).
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
        if (typeInfo.isStruct() || typeInfo.isAggregateStruct() || typeInfo.isEnum())
        {
            if (typeInfo.isEnum())
                bodyScope.addUsingSymMap(typeInfo.payloadSymEnum().asSymMap());

            const SymbolMap* symMap = nullptr;
            if (typeInfo.isStruct())
                symMap = &typeInfo.payloadSymStruct();
            else if (typeInfo.isEnum())
                symMap = &typeInfo.payloadSymEnum();

            // Every 'with' subject is recorded as an auto-member binding, whatever shape it has,
            // and carries the rank that says how deeply it is nested. A binding var cannot answer
            // that question: they are one flat list, shared with the receiver and with the frames a
            // closure inherits, so a nested 'with' would not be ranked against an enclosing one.
            SymbolVariable* symVar   = symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
            const bool      namedVar = symVar &&
                                  (symVar->hasGlobalStorage() ||
                                   symVar->hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                                   symVar->hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
                                   symVar->hasExtraFlag(SymbolVariableFlagsE::RetVal) ||
                                   symVar->isClosureCapture());

            // A subject that has a name is reached through its symbol; anything else is reached by
            // re-evaluating the place the header wrote. Keeping the two shapes apart matters at
            // code generation: a cloned expression's children are not walked, so a named subject
            // must not be turned into a cloned expression.
            const AstNodeRef subjectExprRef = namedVar ? AstNodeRef::invalid() : baseExprRef;
            bodyScope.addAutoMemberBinding({.symMap = symMap, .typeRef = normalizedTypeRef, .symVar = namedVar ? symVar : nullptr, .baseExprRef = subjectExprRef, .order = sema.nextAutoMemberOrder(), .inlinePayload = sema.frame().currentInlinePayload()});

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

    // Drop every candidate the other path does not prove as well.
    void filterBranchNarrowCandidates(const SmallVector2<SemaNarrowFact>& otherFacts, SmallVector2<SemaNarrowFact>& candidates)
    {
        SmallVector2<SemaNarrowFact> kept;
        for (const SemaNarrowFact& fact : candidates)
        {
            if (SemaFrame::queryNarrowFact(otherFacts.span(), {fact.path.data(), fact.path.size()}, fact.kind))
                kept.push_back(fact);
        }

        candidates = std::move(kept);
    }

    Result checkIfVarDeclCondition(Sema& sema, AstNodeRef varDeclRef)
    {
        AstNodeRef     declRef = varDeclRef;
        const AstNode& varNode = sema.node(varDeclRef);
        if (varNode.is(AstNodeId::VarDeclList))
        {
            const auto&             list = varNode.cast<AstVarDeclList>();
            SmallVector<AstNodeRef> decls;
            sema.ast().appendNodes(decls, list.spanChildrenRef);
            if (decls.size() != 1)
                return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, varDeclRef);
            declRef = decls.front();
        }

        const SemaNodeView declView = sema.view(declRef, SemaNodeViewPartE::Symbol);
        const Symbol*      sym      = declView.singleSymbol();
        if (!sym)
            return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, declRef);

        const TypeRef typeRef = sym->typeRef();
        if (typeRef.isInvalid())
            return Result::Continue;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isConvertibleToBoolAliasAware(sema.ctx()))
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cannot_cast, sym->codeRef());
        diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, sema.typeMgr().typeBool());
        diag.report(sema.ctx());
        return Result::Error;
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

        // A branch is also a narrowing region for the facts its own body proves: an assignment
        // inside it holds only while that branch runs, because the other path never made it. A
        // braced body already owns the frame every block gets at node entry; a "do" body is a
        // bare statement, so the region frame is pushed here, or its fact outlives the branch
        // and narrows code the other path reaches.
        const bool bodyOwnsFrame = sema.node(childRef).is(AstNodeId::EmbeddedBlock);
        if (!facts.empty() || !bodyOwnsFrame)
        {
            SemaFrame frame = sema.frame();
            SemaHelpers::addNarrowFacts(frame, {facts.data(), facts.size()});
            sema.pushFramePopOnPostChild(frame, childRef);
        }

        // What this branch proves at its end is one half of what holds after the 'if'. A braced
        // body proves it in the frame that block owns, which is popped before the branch comes
        // back to semaPostNodeChild, so the set is snapshotted at the block's own post-node; a
        // "do" body proves it in the region frame just pushed, still current at that point.
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

    // What holds after the `if` is what BOTH paths prove. A path that terminates the local flow
    // is not one of them, which is the guard-style early exit: the surviving path's facts hold
    // alone for the remainder of the enclosing block. When both terminate, no code after this
    // statement is reachable and there is nothing to publish.
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
        filterBranchNarrowCandidates(elseFacts, merged);
        if (merged.empty())
            return Result::Continue;
    }

    // Mutate the current frame instead of pushing one anchored at the parent: an `elif` is an
    // `if` in the else slot of another, so its publication would sit on top of the enclosing
    // branch's region frame and keep that frame from popping on schedule. The frame reached
    // here is the one the statement started in, and it already ends where the facts stop
    // holding — the enclosing block, or the branch region of the `if` this one chains from.
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
                const std::array<const Symbol*, 1> path  = {conditionSym};
                SemaFrame                          frame = sema.frame();
                frame.addNarrowFact({path.data(), path.size()}, SemaNarrowFactKind::NonNull);
                sema.pushFramePopOnPostChild(frame, childRef);
            }
        }
    }

    return Result::Continue;
}

Result AstIfVarDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeVarRef)
    {
        SWC_RESULT(checkIfVarDeclCondition(sema, nodeVarRef));
        const bool usesConditionBinding                                                                       = nodeWhereRef.isValid() && ifVarDeclNeedsWhereShortCircuit(sema, nodeVarRef);
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

    // The subject of a 'with' is a value. A namespace, an enum, or a struct type names a scope
    // instead, and 'using' is what brings a scope into the current context; letting 'with' take
    // both would give the leading dot a second, unrelated subject to be ranked against.
    const Symbol* subjectSym = exprView.sym();
    if (subjectSym && subjectSym->isSymMap())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_with_scope_subject, nodeExprRef);
        diag.addArgument(Diagnostic::ARG_SYM, subjectSym->getFullScopedName(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    // The block reaches the subject by writing it out again for every '.member' it holds. That is
    // exact for a place — a variable, a field, an element — and wrong for anything computed: a
    // call would run once more per member the block touches, on a different value each time, and
    // the value the statement itself produced would be dropped.
    if (baseExprRef.isValid() && !sema.isLValue(baseExprRef))
        return SemaError::raise(sema, DiagnosticId::sema_err_with_needs_a_place, baseExprRef);

    auto       scopedFrame = sema.frame();
    SemaScope* bodyScope   = sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    SWC_RESULT(configureWithBindings(sema, nodeExprRef, exprView.sym(), exprView.typeRef(), baseExprRef, scopedFrame, *bodyScope));
    sema.pushFramePopOnPostChild(scopedFrame, childRef);
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
    sema.pushFramePopOnPostChild(scopedFrame, childRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
