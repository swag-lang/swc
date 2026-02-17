#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct AutoMemberCandidate
    {
        const SymbolMap*      symMap = nullptr;
        const SymbolVariable* symVar = nullptr; // if set, we substitute `.foo` -> `me.foo`
    };

    struct AutoMemberMatch
    {
        AutoMemberCandidate        candidate;
        SmallVector<const Symbol*> symbols;
    };

    // A call callee may legitimately bind to an overload set, but only for callable candidates.
    // If at least one callable candidate exists, keep ONLY those callables (ignore non-callables for a call).
    // If no callable candidates exist:
    //   - if there are multiple candidates, it's ambiguous in value space (report here)
    //   - if there is exactly one, bind it and let the call expression report "not callable".
    bool filterCallCalleeCandidates(std::span<const Symbol*> inSymbols, SmallVector<const Symbol*>& outSymbols)
    {
        outSymbols.clear();

        // Currently, "callable" means "function symbol".
        // Extend here later for function pointers/delegates/call-operator types if needed.
        for (const Symbol* s : inSymbols)
        {
            if (s && s->isFunction())
                outSymbols.push_back(s);
        }

        return !outSymbols.empty();
    }

    Result checkAmbiguityAndBindSymbols(Sema& sema, AstNodeRef nodeRef, bool allowOverloadSetForCallCallee, std::span<const Symbol*> foundSymbols)
    {
        const size_t n = foundSymbols.size();

        if (n <= 1)
        {
            sema.setSymbolList(nodeRef, foundSymbols);
            return Result::Continue;
        }

        // Multiple candidates.
        if (!allowOverloadSetForCallCallee)
            return SemaError::raiseAmbiguousSymbol(sema, nodeRef, foundSymbols);

        // Call-callee context: keep only callables if any exist.
        SmallVector<const Symbol*> callables;
        if (filterCallCalleeCandidates(foundSymbols, callables))
        {
            sema.setSymbolList(nodeRef, callables);
            return Result::Continue;
        }

        // No callable candidates and multiple results => true ambiguity (e.g. multiple vars/namespaces/etc.).
        return SemaError::raiseAmbiguousSymbol(sema, nodeRef, foundSymbols);
    }

    Result collectAutoMemberCandidates(Sema& sema, SmallVector4<AutoMemberCandidate>& outCandidates)
    {
        outCandidates.clear();

        auto addCandidate = [&](const TypeInfo* typeInfo, const SymbolVariable* symVar) -> Result {
            if (typeInfo->isStruct())
            {
                RESULT_VERIFY(sema.waitSemaCompleted(typeInfo, sema.curNodeRef()));
                outCandidates.push_back({.symMap = &typeInfo->payloadSymStruct(), .symVar = symVar});
            }
            else if (typeInfo->isEnum())
            {
                RESULT_VERIFY(sema.waitSemaCompleted(typeInfo, sema.curNodeRef()));
                outCandidates.push_back({.symMap = &typeInfo->payloadSymEnum(), .symVar = symVar});
            }
            return Result::Continue;
        };

        for (const SemaFrame& frame : sema.frames())
        {
            // Binding variables.
            for (const SymbolVariable* symVar : frame.bindingVars())
            {
                const TypeInfo& typeInfo = sema.typeMgr().get(symVar->typeRef());
                if (!typeInfo.isReference())
                    continue;

                const TypeInfo& pointeeType = sema.typeMgr().get(typeInfo.payloadTypeRef());
                RESULT_VERIFY(addCandidate(&pointeeType, symVar));
            }

            // Binding types.
            for (const TypeRef hintType : frame.bindingTypes())
            {
                if (!hintType.isValid())
                    continue;

                const TypeInfo& typeInfo = sema.typeMgr().get(hintType);
                RESULT_VERIFY(addCandidate(&typeInfo, nullptr));
            }
        }

        // Remove duplicates by symMap.
        for (size_t i = 0; i < outCandidates.size(); ++i)
        {
            for (size_t j = i + 1; j < outCandidates.size();)
            {
                if (outCandidates[i].symMap == outCandidates[j].symMap)
                    outCandidates.erase(outCandidates.begin() + j);
                else
                    ++j;
            }
        }

        return Result::Continue;
    }

    Result probeAutoMemberCandidates(Sema& sema, const SourceCodeRef& codeRef, IdentifierRef idRef, std::span<const AutoMemberCandidate> candidates, SmallVector2<AutoMemberMatch>& outMatches)
    {
        outMatches.clear();
        for (const AutoMemberCandidate& candidate : candidates)
        {
            MatchContext lookUpCxt;
            lookUpCxt.codeRef       = codeRef;
            lookUpCxt.noWaitOnEmpty = true;
            lookUpCxt.symMapHint    = candidate.symMap;

            RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));
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
    // Parser tags the callee expression when building a call: `.foo()`.
    const bool allowOverloadSet = hasFlag(AstAutoMemberAccessExprFlagsE::CallCallee);

    SmallVector4<AutoMemberCandidate> candidates;
    RESULT_VERIFY(collectAutoMemberCandidates(sema, candidates));
    if (candidates.empty())
    {
        // In a call-argument position, `.EnumValue` might need the selected overload's
        // parameter type (enum scope) to be resolved. Defer resolution until overload
        // resolution can provide that context.
        if (hasFlag(AstAutoMemberAccessExprFlagsE::CallArgument))
            return Result::SkipChildren;
        return SemaError::raise(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, sema.curNodeRef());
    }

    const SemaNodeView  nodeRightView = sema.nodeView(nodeIdentRef);
    const SourceCodeRef codeRef       = nodeRightView.node->codeRef();
    const IdentifierRef idRef         = sema.idMgr().addIdentifier(sema.ctx(), codeRef);
    SWC_ASSERT(nodeRightView.node->is(AstNodeId::Identifier));

    // Probe candidates without pausing on empty results.
    SmallVector2<AutoMemberMatch> matches;
    RESULT_VERIFY(probeAutoMemberCandidates(sema, codeRef, idRef, candidates, matches));

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
            const TypeInfo&            typeInfo  = sema.typeMgr().get(candidate.symMap->typeRef());

            auto diagId = DiagnosticId::sema_err_auto_scope_missing_enum_value;
            if (typeInfo.isStruct())
                diagId = DiagnosticId::sema_err_auto_scope_missing_struct_member;

            auto diag = SemaError::report(sema, diagId, sema.curNodeRef());
            diag.addArgument(Diagnostic::ARG_VALUE, sema.idMgr().get(idRef).name);
            diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, candidate.symMap->typeRef());
            diag.report(sema.ctx());
            return Result::Error;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, sema.curNodeRef());
        for (const auto& candidate : candidates)
        {
            diag.addNote(DiagnosticId::sema_note_auto_scope_hint);
            diag.last().addArgument(Diagnostic::ARG_TYPE, candidate.symMap->typeRef());
        }
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (matches.size() > 1)
    {
        SmallVector<const Symbol*> all;
        mergeAutoMemberMatches(matches, all);
        return SemaError::raiseAmbiguousSymbol(sema, sema.curNodeRef(), all);
    }

    const AutoMemberCandidate& selected     = matches.front().candidate;
    const std::span            foundSymbols = matches.front().symbols;

    // Bind the symbol list to the auto-member-access node (it gets substituted below).
    RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, foundSymbols));

    // Substitute with an AstMemberAccessExpr
    auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(tokRef());
    auto [leftRef, leftPtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef());
    if (selected.symVar)
        sema.setSymbol(leftRef, selected.symVar);
    else
        sema.setSymbol(leftRef, selected.symMap);
    sema.setIsValue(*leftPtr);

    nodePtr->nodeLeftRef  = leftRef;
    nodePtr->nodeRightRef = nodeIdentRef;

    // Re-bind the resolved list to the substituted member-access node as well,
    // so downstream passes can read from the final node.
    sema.setSymbolList(nodeRef, sema.getSymbolList(sema.curNodeRef()));
    sema.setSymbolList(nodeIdentRef, sema.getSymbolList(nodeRef));

    sema.setSubstitute(sema.curNodeRef(), nodeRef);
    sema.setIsValue(*nodePtr);

    return Result::SkipChildren;
}

SWC_END_NAMESPACE();
