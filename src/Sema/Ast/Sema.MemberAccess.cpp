#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Match/Match.h"
#include "Sema/Match/MatchContext.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Symbol/Symbol.Impl.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"

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

    Result collectAutoMemberCandidates(Sema& sema, SmallVector<AutoMemberCandidate, 4>& outCandidates)
    {
        outCandidates.clear();

        auto addCandidate = [&](const TypeInfo* typeInfo, const SymbolVariable* symVar) -> Result {
            if (typeInfo->isStruct())
            {
                if (!typeInfo->isCompleted(sema.ctx()))
                    return sema.waitCompleted(typeInfo, sema.curNodeRef());
                outCandidates.push_back({.symMap = &typeInfo->symStruct(), .symVar = symVar});
            }
            else if (typeInfo->isEnum())
            {
                if (!typeInfo->isCompleted(sema.ctx()))
                    return sema.waitCompleted(typeInfo, sema.curNodeRef());
                outCandidates.push_back({.symMap = &typeInfo->symEnum(), .symVar = symVar});
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

                const TypeInfo& pointeeType = sema.typeMgr().get(typeInfo.underlyingTypeRef());
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

    Result probeAutoMemberCandidates(Sema&                                sema,
                                     SourceViewRef                        srcViewRef,
                                     TokenRef                             tokNameRef,
                                     IdentifierRef                        idRef,
                                     std::span<const AutoMemberCandidate> candidates,
                                     SmallVector<AutoMemberMatch, 2>&     outMatches)
    {
        outMatches.clear();
        for (const AutoMemberCandidate& candidate : candidates)
        {
            MatchContext lookUpCxt;
            lookUpCxt.srcViewRef    = srcViewRef;
            lookUpCxt.tokRef        = tokNameRef;
            lookUpCxt.noWaitOnEmpty = true;

            // The same rationale as in `semaStruct`: if we're inside an `impl Interface for Struct`
            // scope and a candidate points to that struct, member lookup must also see symbols
            // declared in the interface-impl block.
            lookUpCxt.symMapHint = candidate.symMap;
            if (const auto* structSym = candidate.symMap->safeCast<SymbolStruct>())
            {
                if (const SymbolImpl* symImpl = sema.frame().impl())
                {
                    if (symImpl->isForStruct() && symImpl->symStruct() == structSym && symImpl->idRef() != structSym->idRef())
                        lookUpCxt.symMapHint = symImpl->asSymMap();
                }
            }

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

    void bindMemberSymbols(Sema& sema, AstNodeRef nodeRef, bool allowOverloadSet, std::span<const Symbol*> symbols)
    {
        if (symbols.size() <= 1 || !allowOverloadSet)
        {
            sema.setSymbolList(nodeRef, symbols);
        }
        else
        {
            SmallVector<const Symbol*> callables;
            if (filterCallCalleeCandidates(symbols, callables))
                sema.setSymbolList(nodeRef, callables);
            else
                sema.setSymbolList(nodeRef, symbols);
        }
    }
}

Result AstAutoMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef&) const
{
    // Parser tags the callee expression when building a call: `.foo()`.
    const bool allowOverloadSet = hasFlag(AstAutoMemberAccessExprFlagsE::CallCallee);

    SmallVector<AutoMemberCandidate, 4> candidates;
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

    const SemaNodeView  nodeRightView(sema, nodeIdentRef);
    const TokenRef      tokNameRef = nodeRightView.node->tokRef();
    const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);
    SWC_ASSERT(nodeRightView.node->is(AstNodeId::Identifier));

    // Probe candidates without pausing on empty results.
    SmallVector<AutoMemberMatch, 2> matches;
    RESULT_VERIFY(probeAutoMemberCandidates(sema, srcViewRef(), tokNameRef, idRef, candidates, matches));

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

namespace
{
    Result semaNamespace(Sema& sema, const AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolNamespace& namespaceSym = nodeLeftView.sym->cast<SymbolNamespace>();

        MatchContext lookUpCxt;
        lookUpCxt.srcViewRef = node->srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &namespaceSym;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));

        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));
        bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, lookUpCxt.symbols());

        return Result::SkipChildren;
    }

    Result semaEnum(Sema& sema, const AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolEnum& enumSym = nodeLeftView.type->symEnum();
        if (!enumSym.isCompleted())
            return sema.waitCompleted(&enumSym, node->srcViewRef(), tokNameRef);

        MatchContext lookUpCxt;
        lookUpCxt.srcViewRef = node->srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = &enumSym;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));
        bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, lookUpCxt.symbols());

        return Result::SkipChildren;
    }

    Result semaInterface(Sema& sema, const AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolInterface& symInterface = nodeLeftView.type->symInterface();
        if (!symInterface.isCompleted())
            return sema.waitCompleted(&symInterface, node->srcViewRef(), tokNameRef);

        MatchContext lookUpCxt;
        lookUpCxt.srcViewRef = node->srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;
        lookUpCxt.symMapHint = nodeLeftView.sym->asSymMap();

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));
        bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, lookUpCxt.symbols());

        return Result::SkipChildren;
    }

    Result semaStruct(Sema& sema, AstMemberAccessExpr* node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet, const TypeInfo* typeInfo)
    {
        const SymbolStruct& symStruct = typeInfo->symStruct();
        if (!symStruct.isCompleted())
            return sema.waitCompleted(&symStruct, node->srcViewRef(), tokNameRef);

        MatchContext lookUpCxt;
        lookUpCxt.srcViewRef = node->srcViewRef();
        lookUpCxt.tokRef     = tokNameRef;

        // When resolving members on a struct while we are *inside* an `impl Interface for Struct`
        // block, we must also consider the current interface-impl scope, otherwise we won't find
        // `mtd impl ...` symbols declared there (ex: `me.toto()` inside the impl).
        //
        // Note: we only use the impl scope as the hint when it targets the same struct and
        // doesn't look like a regular `impl Struct` (where `Match` already sees `struct.impls()`).
        lookUpCxt.symMapHint = &symStruct;
        if (const SymbolImpl* symImpl = sema.frame().impl())
        {
            if (symImpl->isForStruct() && symImpl->symStruct() == &symStruct && symImpl->idRef() != symStruct.idRef())
                lookUpCxt.symMapHint = symImpl->asSymMap();
        }

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));

        // Bind member-access node (curNodeRef) and RHS identifier.
        RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));
        bindMemberSymbols(sema, node->nodeRightRef, allowOverloadSet, lookUpCxt.symbols());

        // Constant struct member access
        const auto finalSymCount = sema.getSymbolList(node->nodeRightRef).size();
        if (nodeLeftView.cst && finalSymCount == 1 && sema.getSymbolList(node->nodeRightRef)[0]->isVariable())
        {
            const SymbolVariable& symVar = sema.getSymbolList(node->nodeRightRef)[0]->cast<SymbolVariable>();
            RESULT_VERIFY(SemaHelpers::extractConstantStructMember(sema, *nodeLeftView.cst, symVar, sema.curNodeRef(), node->nodeRightRef));
            return Result::SkipChildren;
        }

        if (nodeLeftView.type->isAnyPointer() || nodeLeftView.type->isReference() || SemaInfo::isLValue(sema.node(node->nodeLeftRef)))
            SemaInfo::setIsLValue(*node);
        return Result::SkipChildren;
    }
}

Result AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    if (childRef != nodeRightRef)
        return Result::Continue;

    // Parser tags the callee expression when building a call: `a.foo()`.
    const bool allowOverloadSet = hasFlag(AstMemberAccessExprFlagsE::CallCallee);

    SemaNodeView        nodeLeftView(sema, nodeLeftRef);
    const SemaNodeView  nodeRightView(sema, nodeRightRef);
    const TokenRef      tokNameRef = nodeRightView.node->tokRef();
    const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);
    SWC_ASSERT(nodeRightView.node->is(AstNodeId::Identifier));

    // Namespace
    if (nodeLeftView.sym && nodeLeftView.sym->isNamespace())
        return semaNamespace(sema, this, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    SWC_ASSERT(nodeLeftView.type);

    // Enum
    if (nodeLeftView.type->isEnum())
        return semaEnum(sema, this, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Interface
    if (nodeLeftView.type->isInterface())
        return semaInterface(sema, this, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Dereference pointer
    const TypeInfo* typeInfo = nodeLeftView.type;
    if (typeInfo->isTypeValue())
    {
        const TypeRef typeInfoRef = sema.typeMgr().typeTypeInfo();
        RESULT_VERIFY(Cast::cast(sema, nodeLeftView, typeInfoRef, CastKind::Explicit));
        typeInfo = &sema.typeMgr().get(sema.typeMgr().structTypeInfo());
    }
    else if (typeInfo->isTypeInfo())
    {
        const TypeRef typeInfoRef = sema.typeMgr().structTypeInfo();
        if (typeInfoRef.isInvalid())
            return sema.waitIdentifier(sema.idMgr().nameTypeInfo(), srcViewRef(), tokNameRef);
        typeInfo = &sema.typeMgr().get(typeInfoRef);
    }
    else if (typeInfo->isAnyPointer() || typeInfo->isReference())
    {
        typeInfo = &sema.typeMgr().get(typeInfo->typeRef());
    }

    // Struct
    if (typeInfo->isStruct())
        return semaStruct(sema, this, nodeLeftView, idRef, tokNameRef, allowOverloadSet, typeInfo);

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
