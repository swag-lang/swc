#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.MemberAccess.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef normalizeAutoMemberBindingType(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
            if (typeInfo.isAlias())
            {
                typeRef = typeInfo.payloadSymAlias().underlyingTypeRef();
                continue;
            }

            if (typeInfo.isReference() || typeInfo.isAnyPointer() || typeInfo.isSlice() || typeInfo.isTypedVariadic())
            {
                typeRef = typeInfo.payloadTypeRef();
                continue;
            }

            // Array literals inherit the binding type from their parent expression.
            // Drill through nested array layers so `.EnumValue` can bind to the element enum.
            if (typeInfo.isArray())
            {
                typeRef = typeInfo.payloadArrayElemTypeRef();
                continue;
            }

            break;
        }

        return typeRef;
    }

    struct AutoMemberCandidate
    {
        const SymbolMap*      symMap      = nullptr;
        TypeRef               typeRef     = TypeRef::invalid();
        const SymbolVariable* symVar      = nullptr;
        AstNodeRef            baseExprRef = AstNodeRef::invalid();
    };

    struct AutoMemberMatch
    {
        AutoMemberCandidate        candidate;
        SmallVector<const Symbol*> symbols;
    };

    void copyDetachedExprState(Sema& sema, AstNodeRef sourceRef, AstNodeRef clonedRef);

    // `with` rewrites must not reuse an existing resolved expression subtree directly,
    // otherwise several rewritten auto-members can end up sharing AST nodes.
    AstNodeRef cloneDetachedExpr(Sema& sema, AstNodeRef sourceRef)
    {
        SWC_ASSERT(sourceRef.isValid());
        const SemaClone::CloneContext cloneContext{std::span<const SemaClone::ParamBinding>{}};
        const AstNodeRef              clonedRef = SemaClone::cloneAst(sema, sourceRef, cloneContext);
        SWC_ASSERT(clonedRef.isValid());
        copyDetachedExprState(sema, sourceRef, clonedRef);
        return clonedRef;
    }

    void copyDetachedExprState(Sema& sema, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
        SWC_ASSERT(sourceRef.isValid());
        SWC_ASSERT(clonedRef.isValid());

        sema.inheritPayload(sema.node(clonedRef), sourceRef);

        SmallVector<AstNodeRef> sourceChildren;
        SmallVector<AstNodeRef> clonedChildren;
        sema.node(sourceRef).collectChildrenFromAst(sourceChildren, sema.ast());
        sema.node(clonedRef).collectChildrenFromAst(clonedChildren, sema.ast());
        SWC_ASSERT(sourceChildren.size() == clonedChildren.size());

        for (size_t i = 0; i < sourceChildren.size(); ++i)
        {
            const AstNodeRef sourceChildRef = sourceChildren[i];
            const AstNodeRef clonedChildRef = clonedChildren[i];
            if (sourceChildRef.isInvalid() || clonedChildRef.isInvalid())
                continue;

            sema.inheritPayload(sema.node(clonedChildRef), sourceChildRef);

            const AstNodeRef resolvedChildRef = sema.viewZero(sourceChildRef).nodeRef();
            if (resolvedChildRef.isValid() && resolvedChildRef != sourceChildRef)
            {
                const AstNodeRef clonedResolvedChildRef = cloneDetachedExpr(sema, resolvedChildRef);
                sema.setSubstitute(clonedChildRef, clonedResolvedChildRef);
                continue;
            }

            copyDetachedExprState(sema, sourceChildRef, clonedChildRef);
        }
    }

    AstNodeRef makeAutoMemberLeftExpr(Sema& sema, TokenRef tokRef, const AutoMemberCandidate& candidate)
    {
        if (candidate.baseExprRef.isValid())
            return cloneDetachedExpr(sema, candidate.baseExprRef);

        auto [leftRef, leftPtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef);
        if (candidate.symVar)
        {
            sema.setSymbol(leftRef, candidate.symVar);
            sema.setIsLValue(*leftPtr);
        }
        else if (candidate.symMap)
        {
            sema.setSymbol(leftRef, candidate.symMap);
        }
        else if (candidate.typeRef.isValid())
        {
            sema.setType(leftRef, candidate.typeRef);
        }

        sema.setIsValue(*leftPtr);
        return leftRef;
    }

    AstNodeRef makeAutoMemberAccessExpr(Sema& sema, TokenRef tokRef, const AutoMemberCandidate& candidate, AstNodeRef rightRef, AstMemberAccessExpr*& outNode)
    {
        auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(tokRef);
        nodePtr->nodeLeftRef    = makeAutoMemberLeftExpr(sema, tokRef, candidate);
        nodePtr->nodeRightRef   = rightRef;
        outNode                 = nodePtr;
        return nodeRef;
    }

    bool sameCandidate(const AutoMemberCandidate& lhs, const AutoMemberCandidate& rhs)
    {
        return lhs.symMap == rhs.symMap &&
               lhs.typeRef == rhs.typeRef &&
               lhs.symVar == rhs.symVar &&
               lhs.baseExprRef == rhs.baseExprRef;
    }

    uint32_t candidateSpecificity(const AutoMemberCandidate& candidate)
    {
        uint32_t score = 0;
        if (candidate.baseExprRef.isValid())
            score += 2;
        if (candidate.symVar)
            score += 1;
        return score;
    }

    bool canCollapseEquivalentCandidates(const AutoMemberCandidate& lhs, const AutoMemberCandidate& rhs)
    {
        if (lhs.symMap != rhs.symMap)
            return false;
        if (lhs.typeRef != rhs.typeRef)
            return false;
        if (lhs.baseExprRef != rhs.baseExprRef)
            return false;

        // Distinct bound variables remain ambiguous on purpose.
        if (lhs.symVar && rhs.symVar && lhs.symVar != rhs.symVar)
            return false;

        return true;
    }

    bool aggregateHasMember(Sema& sema, TypeRef typeRef, IdentifierRef idRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (!typeInfo.isAggregateStruct())
            return false;

        size_t memberIndex = 0;
        return SemaMemberAccess::resolveAggregateMemberIndex(sema, typeInfo, idRef, memberIndex);
    }

    Result addCandidateFromType(Sema& sema, SmallVector4<AutoMemberCandidate>& outCandidates, TypeRef typeRef, const SymbolVariable* symVar, AstNodeRef baseExprRef)
    {
        const TypeRef normalizedTypeRef = normalizeAutoMemberBindingType(sema.ctx(), typeRef);
        if (!normalizedTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& typeInfo = sema.typeMgr().get(normalizedTypeRef);
        if (typeInfo.isStruct())
        {
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, sema.curNodeRef()));
            outCandidates.push_back({.symMap = &typeInfo.payloadSymStruct(), .typeRef = normalizedTypeRef, .symVar = symVar, .baseExprRef = baseExprRef});
        }
        else if (typeInfo.isEnum())
        {
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, sema.curNodeRef()));
            outCandidates.push_back({.symMap = &typeInfo.payloadSymEnum(), .typeRef = normalizedTypeRef, .symVar = symVar, .baseExprRef = baseExprRef});
        }
        else if (typeInfo.isAggregateStruct())
        {
            outCandidates.push_back({.typeRef = normalizedTypeRef, .symVar = symVar, .baseExprRef = baseExprRef});
        }

        return Result::Continue;
    }

    Result collectAutoMemberCandidates(Sema& sema, SmallVector4<AutoMemberCandidate>& outCandidates)
    {
        outCandidates.clear();

        SmallVector<const SymbolVariable*>        bindingVars;
        SmallVector<TypeRef>                      bindingTypes;
        SmallVector<SemaScope::AutoMemberBinding> autoMemberBindings;
        const SemaFrame&                          frame = sema.frame();

        // Frame state is inherited when pushing nested semantic frames, so the
        // current frame already contains the active auto-scope context.
        for (const SymbolVariable* symVar : frame.bindingVars())
            bindingVars.push_back(symVar);
        for (const TypeRef hintType : frame.bindingTypes())
            bindingTypes.push_back(hintType);
        for (const SemaScope* scope = &sema.curScope(); scope; scope = scope->parent())
        {
            for (const auto& binding : scope->autoMemberBindings())
                autoMemberBindings.push_back(binding);
        }

        for (const SymbolVariable* symVar : bindingVars)
        {
            SWC_RESULT(addCandidateFromType(sema, outCandidates, symVar->typeRef(), symVar, AstNodeRef::invalid()));
        }

        for (const TypeRef hintType : bindingTypes)
        {
            SWC_RESULT(addCandidateFromType(sema, outCandidates, hintType, nullptr, AstNodeRef::invalid()));
        }

        for (const auto& binding : autoMemberBindings)
        {
            if (binding.typeRef.isValid())
            {
                SWC_RESULT(addCandidateFromType(sema, outCandidates, binding.typeRef, binding.symVar, binding.baseExprRef));
            }
            else if (binding.symMap)
            {
                outCandidates.push_back({.symMap = binding.symMap, .symVar = binding.symVar, .baseExprRef = binding.baseExprRef});
            }
        }

        // Remove exact duplicates introduced by inherited frame state.
        for (size_t i = 0; i < outCandidates.size(); ++i)
        {
            for (size_t j = i + 1; j < outCandidates.size();)
            {
                if (sameCandidate(outCandidates[i], outCandidates[j]))
                {
                    outCandidates.erase(outCandidates.begin() + j);
                }
                else if (canCollapseEquivalentCandidates(outCandidates[i], outCandidates[j]))
                {
                    if (candidateSpecificity(outCandidates[j]) > candidateSpecificity(outCandidates[i]))
                        outCandidates[i] = outCandidates[j];
                    outCandidates.erase(outCandidates.begin() + j);
                }
                else
                {
                    ++j;
                }
            }
        }

        return Result::Continue;
    }

    Result probeAutoMemberCandidates(Sema& sema, const SourceCodeRef& codeRef, IdentifierRef idRef, std::span<const AutoMemberCandidate> candidates, SmallVector2<AutoMemberMatch>& outMatches)
    {
        outMatches.clear();
        for (const AutoMemberCandidate& candidate : candidates)
        {
            if (!candidate.symMap)
            {
                if (aggregateHasMember(sema, candidate.typeRef, idRef))
                {
                    AutoMemberMatch m;
                    m.candidate = candidate;
                    outMatches.push_back(std::move(m));
                }

                continue;
            }

            MatchContext lookUpCxt;
            lookUpCxt.codeRef       = codeRef;
            lookUpCxt.noWaitOnEmpty = true;
            lookUpCxt.symMapHint    = candidate.symMap;

            SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
            if (!lookUpCxt.empty())
            {
                AutoMemberMatch m;
                m.candidate = candidate;
                m.symbols   = lookUpCxt.symbols();
                outMatches.push_back(std::move(m));
            }
        }

        return Result::Continue;
    }

    void mergeAutoMemberMatches(std::span<const AutoMemberMatch> matches, SmallVector<const Symbol*>& outSymbols)
    {
        outSymbols.clear();
        for (const auto& m : matches)
        {
            for (const Symbol* s : m.symbols)
                outSymbols.push_back(s);
        }
    }
}

Result AstAutoMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    SWC_UNUSED(childRef);
    const AstNodeRef currentRef  = sema.curNodeRef();
    const AstNodeRef resolvedRef = sema.viewZero(currentRef).nodeRef();
    if (resolvedRef.isValid() && resolvedRef != currentRef)
        return Result::SkipChildren;

    // Parser tags the callee expression when building a call: `.foo()`.
    const bool allowOverloadSet = hasFlag(AstAutoMemberAccessExprFlagsE::CallCallee);

    SmallVector4<AutoMemberCandidate> candidates;
    SWC_RESULT(collectAutoMemberCandidates(sema, candidates));
    if (candidates.empty())
    {
        // In a call-argument position, `.EnumValue` might need the selected overload's
        // parameter type (enum scope) to be resolved. Defer resolution until overload
        // resolution can provide that context.
        if (hasFlag(AstAutoMemberAccessExprFlagsE::CallArgument))
            return Result::SkipChildren;
        return SemaError::raise(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, sema.curNodeRef());
    }

    const SemaNodeView  nodeRightView = sema.viewNode(nodeIdentRef);
    const SourceCodeRef codeRef       = nodeRightView.node()->codeRef();
    const IdentifierRef idRef         = sema.idMgr().addIdentifier(sema.ctx(), codeRef);
    SWC_ASSERT(nodeRightView.node()->is(AstNodeId::Identifier));

    // Probe candidates without pausing on empty results.
    SmallVector2<AutoMemberMatch> matches;
    SWC_RESULT(probeAutoMemberCandidates(sema, codeRef, idRef, candidates, matches));

    // If nothing matched, report a smart error.
    if (matches.empty())
    {
        if (hasFlag(AstAutoMemberAccessExprFlagsE::CallArgument))
        {
            // If we have candidates but none matched, we still want to try to defer if this is a function argument.
            // This is because another candidate (the function argument type itself) might be available later
            // during overload resolution.
            return Result::SkipChildren;
        }

        if (candidates.size() == 1)
        {
            const AutoMemberCandidate& candidate = candidates.front();
            if (!candidate.typeRef.isValid())
                return SemaError::raise(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, sema.curNodeRef());

            const TypeInfo& typeInfo = sema.typeMgr().get(candidate.typeRef);

            auto diagId = DiagnosticId::sema_err_auto_scope_missing_enum_value;
            if (typeInfo.isStruct() || typeInfo.isAggregateStruct())
                diagId = DiagnosticId::sema_err_auto_scope_missing_struct_member;

            auto diag = SemaError::report(sema, diagId, sema.curNodeRef());
            diag.addArgument(Diagnostic::ARG_VALUE, sema.idMgr().get(idRef).name);
            diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, candidate.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, sema.curNodeRef());
        for (const auto& candidate : candidates)
        {
            if (!candidate.typeRef.isValid())
                continue;
            diag.addNote(DiagnosticId::sema_note_auto_scope_hint);
            diag.last().addArgument(Diagnostic::ARG_TYPE, candidate.typeRef);
        }
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (matches.size() > 1)
    {
        SmallVector<const Symbol*> all;
        mergeAutoMemberMatches(matches, all);
        if (!all.empty())
            return SemaError::raiseAmbiguousSymbol(sema, sema.curNodeRef(), all);
        return SemaError::raise(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, sema.curNodeRef());
    }

    const AutoMemberCandidate& selected = matches.front().candidate;

    // Symbol-backed auto-members keep the original lightweight substitution path.
    // This preserves existing auto-scope behavior (`me`, enum auto-scope, etc.)
    // while allowing `with` to provide an alternate left expression.
    if (selected.symMap)
    {
        const std::span foundSymbols = matches.front().symbols.span();

        SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, sema.curNodeRef(), allowOverloadSet, foundSymbols));

        AstMemberAccessExpr*     substituteNode = nullptr;
        const AstNodeRef         nodeRef        = makeAutoMemberAccessExpr(sema, tokRef(), selected, nodeIdentRef, substituteNode);
        const std::span<Symbol*> symbols        = sema.curViewSymbolList().symList();
        sema.setSymbolList(nodeRef, symbols);
        sema.setSymbolList(nodeIdentRef, symbols);

        sema.setSubstitute(sema.curNodeRef(), nodeRef);
        sema.setIsValue(*substituteNode);
        return Result::SkipChildren;
    }

    // Aggregate structs do not have member symbols, so they must go through
    // the regular member-access semantic path.
    AstMemberAccessExpr* substituteNode = nullptr;
    const AstNodeRef     nodeRef        = makeAutoMemberAccessExpr(sema, tokRef(), selected, nodeIdentRef, substituteNode);
    SWC_RESULT(SemaMemberAccess::resolve(sema, nodeRef, *substituteNode, allowOverloadSet));

    sema.setSubstitute(sema.curNodeRef(), nodeRef);
    return Result::SkipChildren;
}

SWC_END_NAMESPACE();
