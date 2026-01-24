#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Match/Match.h"
#include "Sema/Match/MatchContext.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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

    struct AutoMemberCandidate
    {
        const SymbolMap*      symMap = nullptr;
        const SymbolVariable* symMe  = nullptr; // if set, we substitute `.foo` -> `me.foo`
    };

    struct AutoMemberMatch
    {
        AutoMemberCandidate      candidate;
        SmallVector<const Symbol*> symbols;
    };

    void collectAutoMemberCandidates(Sema& sema, SmallVector<AutoMemberCandidate, 4>& outCandidates)
    {
        outCandidates.clear();

        // 1) Method context: `me` parameter.
        if (const SymbolFunction* symFunc = sema.frame().function())
        {
            if (!symFunc->parameters().empty() && symFunc->parameters()[0]->idRef() == sema.idMgr().nameMe())
            {
                const SymbolVariable* symMe    = symFunc->parameters()[0];
                const TypeInfo&       typeInfo = sema.typeMgr().get(symMe->typeRef());
                SWC_ASSERT(typeInfo.isReference());
                const TypeInfo& pointeeType = sema.typeMgr().get(typeInfo.underlyingTypeRef());
                if (pointeeType.isStruct())
                    outCandidates.push_back({&pointeeType.symStruct(), symMe});
                else if (pointeeType.isEnum())
                    outCandidates.push_back({&pointeeType.symEnum(), symMe});
            }
        }

        // 2) Type-hints from the hierarchy of frames.
        for (const SemaFrame& frame : sema.frames())
        {
            for (const TypeRef hintType : frame.typeHints())
            {
                if (!hintType.isValid())
                    continue;

                const TypeInfo& typeInfo = sema.typeMgr().get(hintType);
                if (typeInfo.isStruct())
                    outCandidates.push_back({&typeInfo.symStruct(), nullptr});
                else if (typeInfo.isEnum())
                    outCandidates.push_back({&typeInfo.symEnum(), nullptr});
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
    }

    Result probeAutoMemberCandidates(Sema& sema,
                                    SourceViewRef srcViewRef,
                                    TokenRef tokNameRef,
                                    IdentifierRef idRef,
                                    std::span<const AutoMemberCandidate> candidates,
                                    SmallVector<AutoMemberMatch, 2>& outMatches)
    {
        outMatches.clear();
        for (const AutoMemberCandidate& cand : candidates)
        {
            MatchContext lookUpCxt;
            lookUpCxt.srcViewRef    = srcViewRef;
            lookUpCxt.tokRef        = tokNameRef;
            lookUpCxt.symMapHint    = cand.symMap;
            lookUpCxt.noWaitOnEmpty = true;

            const Result ret = Match::match(sema, lookUpCxt, idRef);
            RESULT_VERIFY(ret);

            if (!lookUpCxt.empty())
            {
                AutoMemberMatch m;
                m.candidate = cand;
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

Result AstAutoMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef&) const
{
    // Parser tags the callee expression when building a call: `.foo()`.
    const bool allowOverloadSet = hasFlag(AstAutoMemberAccessExprFlagsE::CallCallee);

    SmallVector<AutoMemberCandidate, 4> candidates;
    collectAutoMemberCandidates(sema, candidates);
    if (candidates.empty())
        return SemaError::raise(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, sema.curNodeRef());

    const SemaNodeView  nodeRightView(sema, nodeIdentRef);
    const TokenRef      tokNameRef = nodeRightView.node->tokRef();
    const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);

    // Probe candidates without pausing on empty results.
    SmallVector<AutoMemberMatch, 2> matches;
    RESULT_VERIFY(probeAutoMemberCandidates(sema, srcViewRef(), tokNameRef, idRef, candidates, matches));

    // If nothing matched, retry with the first candidate in normal mode to keep "wait" semantics.
    if (matches.empty())
    {
        MatchContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = candidates.front().symMap;
        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));

        // Bind the symbol list to the auto-member-access node (it gets substituted below).
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));

        AutoMemberMatch mr;
        mr.candidate = candidates.front();
        mr.symbols   = lookUpCxt.symbols();
        matches.push_back(std::move(mr));
    }

    if (matches.size() > 1)
    {
        SmallVector<const Symbol*> all;
        mergeAutoMemberMatches(matches, all);
        return SemaError::raiseAmbiguousSymbol(sema, sema.curNodeRef(), all);
    }

    const AutoMemberCandidate&      selected     = matches.front().candidate;
    const std::span<const Symbol*> foundSymbols = matches.front().symbols;

    // Bind the symbol list to the auto-member-access node (it gets substituted below).
    RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, foundSymbols));

    // Substitute with an AstMemberAccessExpr
    auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(tokRef());
    auto [leftRef, leftPtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef());
    if (selected.symMe)
        sema.setSymbol(leftRef, selected.symMe);
    else
        sema.setSymbol(leftRef, selected.symMap);
    SemaInfo::setIsValue(*leftPtr);

    nodePtr->nodeLeftRef  = leftRef;
    nodePtr->nodeRightRef = nodeIdentRef;

    // Re-bind the resolved list to the substituted member-access node as well,
    // so downstream passes can read from the final node.
    sema.setSymbolList(nodeRef, sema.getSymbolList(sema.curNodeRef()));
    sema.setSymbolList(nodeIdentRef, sema.getSymbolList(nodeRef));

    sema.semaInfo().setSubstitute(sema.curNodeRef(), nodeRef);
    SemaInfo::setIsValue(*nodePtr);

    return Result::SkipChildren;
}

Result AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    if (childRef != nodeRightRef)
        return Result::Continue;

    // Parser tags the callee expression when building a call: `a.foo()`.
    const bool allowOverloadSet = hasFlag(AstMemberAccessExprFlagsE::CallCallee);

    const SemaNodeView nodeLeftView(sema, nodeLeftRef);
    const SemaNodeView nodeRightView(sema, nodeRightRef);
    TokenRef           tokNameRef;

    SWC_ASSERT(nodeRightView.node->is(AstNodeId::Identifier));
    tokNameRef = nodeRightView.node->tokRef();

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);

    // Namespace
    if (nodeLeftView.sym && nodeLeftView.sym->isNamespace())
    {
        const SymbolNamespace& namespaceSym = nodeLeftView.sym->cast<SymbolNamespace>();

        MatchContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &namespaceSym;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));

        // Bind both the RHS identifier and the member-access expr to the (possibly filtered) candidates.
        // First bind for the member-access node (curNodeRef).
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));

        // Then bind the same final list to the RHS identifier node.
        // If you don't have a getter for the stored list, re-run filtering locally:
        if (lookUpCxt.symbols().size() <= 1 || !allowOverloadSet)
        {
            sema.setSymbolList(nodeRightView.nodeRef, lookUpCxt.symbols());
        }
        else
        {
            SmallVector<const Symbol*> callables;
            if (filterCallCalleeCandidates(lookUpCxt.symbols(), callables))
                sema.setSymbolList(nodeRightView.nodeRef, callables);
            else
                sema.setSymbolList(nodeRightView.nodeRef, lookUpCxt.symbols());
        }

        return Result::SkipChildren;
    }

    SWC_ASSERT(nodeLeftView.type);

    // Enum
    if (nodeLeftView.type->isEnum())
    {
        const SymbolEnum& enumSym = nodeLeftView.type->symEnum();
        if (!enumSym.isCompleted())
            return sema.waitCompleted(&enumSym, srcViewRef(), tokNameRef);

        MatchContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &enumSym;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));

        if (lookUpCxt.symbols().size() <= 1 || !allowOverloadSet)
        {
            sema.setSymbolList(nodeRightView.nodeRef, lookUpCxt.symbols());
        }
        else
        {
            SmallVector<const Symbol*> callables;
            if (filterCallCalleeCandidates(lookUpCxt.symbols(), callables))
                sema.setSymbolList(nodeRightView.nodeRef, callables);
            else
                sema.setSymbolList(nodeRightView.nodeRef, lookUpCxt.symbols());
        }

        return Result::SkipChildren;
    }

    // Interface
    if (nodeLeftView.type->isInterface())
    {
        const SymbolInterface& symInterface = nodeLeftView.type->symInterface();
        if (!symInterface.isCompleted())
            return sema.waitCompleted(&symInterface, srcViewRef(), tokNameRef);
        // TODO
        return Result::SkipChildren;
    }

    // Dereference pointer
    const TypeInfo* typeInfo = nodeLeftView.type;
    if (typeInfo->isTypeInfo())
    {
        TypeRef typeInfoRef = sema.typeMgr().structTypeInfo();
        if (typeInfoRef.isInvalid())
            return sema.waitIdentifier(sema.idMgr().nameTypeInfoStruct(), srcViewRef(), tokNameRef);
        typeInfo = &sema.typeMgr().get(typeInfoRef);
    }
    else if (typeInfo->isAnyPointer())
        typeInfo = &sema.typeMgr().get(typeInfo->typeRef());
    else if (typeInfo->isReference())
        typeInfo = &sema.typeMgr().get(typeInfo->typeRef());

    // Struct
    if (typeInfo->isStruct())
    {
        const SymbolStruct& symStruct = typeInfo->symStruct();
        if (!symStruct.isCompleted())
            return sema.waitCompleted(&symStruct, srcViewRef(), tokNameRef);

        MatchContext lookUpCxt;
        lookUpCxt.srcViewRef = srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &symStruct;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));

        // Bind member-access node (curNodeRef) and RHS identifier.
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));

        if (lookUpCxt.symbols().size() <= 1 || !allowOverloadSet)
        {
            sema.setSymbolList(nodeRightRef, lookUpCxt.symbols());
        }
        else
        {
            SmallVector<const Symbol*> callables;
            if (filterCallCalleeCandidates(lookUpCxt.symbols(), callables))
                sema.setSymbolList(nodeRightRef, callables);
            else
                sema.setSymbolList(nodeRightRef, lookUpCxt.symbols());
        }

        // Constant struct member access
        const auto finalSymCount = sema.getSymbolList(nodeRightRef).size(); // if unavailable, see note below.
        if (nodeLeftView.cst && finalSymCount == 1 && sema.getSymbolList(nodeRightRef)[0]->isVariable())
        {
            const SymbolVariable& symVar = sema.getSymbolList(nodeRightRef)[0]->cast<SymbolVariable>();
            RESULT_VERIFY(SemaHelpers::extractConstantStructMember(sema, *nodeLeftView.cst, symVar, sema.curNodeRef(), nodeRightView.nodeRef));
            return Result::SkipChildren;
        }

        if (nodeLeftView.type->isAnyPointer() || nodeLeftView.type->isReference() || SemaInfo::isLValue(sema.node(nodeLeftRef)))
            SemaInfo::setIsLValue(*this);
        return Result::SkipChildren;
    }

    // Pointer/Reference
    if (nodeLeftView.type->isAnyPointer() || nodeLeftView.type->isReference())
    {
        sema.setType(sema.curNodeRef(), nodeLeftView.type->typeRef());
        SemaInfo::setIsValue(*this);
        return Result::SkipChildren;
    }

    // TODO
    sema.setType(sema.curNodeRef(), sema.typeMgr().typeInt(32, TypeInfo::Sign::Signed));
    SemaInfo::setIsValue(*this);
    return Result::SkipChildren;
}

SWC_END_NAMESPACE();
