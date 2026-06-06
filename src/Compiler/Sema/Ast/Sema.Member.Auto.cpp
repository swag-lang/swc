#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using SemaError::formatStructMemberList;

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
        const SymbolMap*      symMap        = nullptr;
        TypeRef               typeRef       = TypeRef::invalid();
        TypeRef               resultTypeRef = TypeRef::invalid();
        const SymbolVariable* symVar        = nullptr;
        AstNodeRef            baseExprRef   = AstNodeRef::invalid();
        uint32_t              precedence    = UINT32_MAX;
    };

    struct AutoMemberMatch
    {
        AutoMemberCandidate        candidate;
        SmallVector<const Symbol*> symbols;
    };

    SymbolVariable* activeReceiverBinding(Sema& sema)
    {
        const IdentifierRef                    meId     = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
        const std::span<SymbolVariable* const> bindings = sema.frame().bindingVars();
        for (size_t i = bindings.size(); i > 0; --i)
        {
            SymbolVariable* binding = bindings[i - 1];
            if (binding && binding->idRef() == meId)
                return binding;
        }

        return nullptr;
    }

    // `with` rewrites must not reuse an existing resolved expression subtree directly.
    // A fresh syntax clone lets semantic analysis rebuild substitutes in the new context.
    AstNodeRef cloneDetachedExpr(Sema& sema, AstNodeRef sourceRef)
    {
        SWC_ASSERT(sourceRef.isValid());
        return SemaClone::cloneDetachedExpr(sema, sourceRef);
    }

    AstNodeRef cloneAutoMemberRightExpr(Sema& sema, AstNodeRef sourceRef)
    {
        SWC_ASSERT(sourceRef.isValid());
        const SemaClone::CloneContext noBindings{std::span<const SemaClone::ParamBinding>{}};
        return SemaClone::cloneAst(sema, sourceRef, noBindings);
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
        // The RHS of a synthesized member access is a member name, not an arbitrary expression.
        // Reusing detached-expression clone state there can leak stale substitutes from the
        // auto-member source into the generated `left.member` form.
        nodePtr->nodeRightRef = cloneAutoMemberRightExpr(sema, rightRef);
        outNode               = nodePtr;
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

    bool containsNodeRef(std::span<const AstNodeRef> refs, AstNodeRef target)
    {
        return std::ranges::find(refs, target) != refs.end();
    }

    bool aggregateHasMember(Sema& sema, TypeRef typeRef, IdentifierRef idRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (!typeInfo.isAggregateStruct())
            return false;

        size_t memberIndex = 0;
        return SemaHelpers::resolveAggregateMemberIndex(sema, typeInfo, idRef, memberIndex);
    }

    Result addCandidateFromType(Sema& sema, SmallVector4<AutoMemberCandidate>& outCandidates, TypeRef typeRef, const SymbolVariable* symVar, AstNodeRef baseExprRef, uint32_t precedence)
    {
        const TypeRef normalizedTypeRef = normalizeAutoMemberBindingType(sema.ctx(), typeRef);
        if (!normalizedTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& typeInfo = sema.typeMgr().get(normalizedTypeRef);
        TypeRef         resultTypeRef;
        if (typeRef != normalizedTypeRef)
        {
            const TypeInfo& sourceType = sema.typeMgr().get(typeRef);
            if (sourceType.isAlias() && sourceType.payloadSymAlias().isStrict())
                resultTypeRef = typeRef;
        }

        if (typeInfo.isStruct())
        {
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, sema.curNodeRef()));
            outCandidates.push_back({.symMap = &typeInfo.payloadSymStruct(), .typeRef = normalizedTypeRef, .resultTypeRef = resultTypeRef, .symVar = symVar, .baseExprRef = baseExprRef, .precedence = precedence});
        }
        else if (typeInfo.isEnum())
        {
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, sema.curNodeRef()));
            outCandidates.push_back({.symMap = &typeInfo.payloadSymEnum(), .typeRef = normalizedTypeRef, .resultTypeRef = resultTypeRef, .symVar = symVar, .baseExprRef = baseExprRef, .precedence = precedence});
        }
        else if (typeInfo.isAggregateStruct())
        {
            outCandidates.push_back({.typeRef = normalizedTypeRef, .resultTypeRef = resultTypeRef, .symVar = symVar, .baseExprRef = baseExprRef, .precedence = precedence});
        }

        return Result::Continue;
    }

    bool expressionResolvesToVariable(Sema& sema, AstNodeRef exprRef, const SymbolVariable& variable)
    {
        SmallVector<AstNodeRef> visitedRefs;
        for (uint32_t depth = 0; depth < 8 && exprRef.isValid(); ++depth)
        {
            if (containsNodeRef(visitedRefs.span(), exprRef))
                return false;
            visitedRefs.push_back(exprRef);

            const SemaNodeView storedSymbolView = sema.viewStored(exprRef, SemaNodeViewPartE::Symbol);
            if (storedSymbolView.sym() == &variable)
                return true;

            const AstNode& node = sema.node(exprRef);
            if (const auto* castNode = node.safeCast<AstCastExpr>())
            {
                exprRef = castNode->nodeExprRef;
                continue;
            }

            if (const auto* autoCastNode = node.safeCast<AstAutoCastExpr>())
            {
                exprRef = autoCastNode->nodeExprRef;
                continue;
            }

            if (const auto* asCastNode = node.safeCast<AstAsCastExpr>())
            {
                exprRef = asCastNode->nodeExprRef;
                continue;
            }

            const AstNodeRef resolvedRef = sema.viewZero(exprRef).nodeRef();
            if (resolvedRef.isInvalid())
                return false;
            if (resolvedRef != exprRef)
            {
                exprRef = resolvedRef;
                continue;
            }

            const SemaNodeView symbolView = sema.viewSymbol(exprRef);
            if (symbolView.sym() == &variable)
                return true;

            return false;
        }

        return false;
    }

    Result addCandidateFromInlineReceiver(Sema& sema, SmallVector4<AutoMemberCandidate>& outCandidates, uint32_t& precedence)
    {
        const SemaInlinePayload* inlinePayload = sema.frame().currentInlinePayload();
        if (!inlinePayload)
            return Result::Continue;

        const IdentifierRef meId = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
        for (const SemaClone::ParamBinding& binding : inlinePayload->argMappings)
        {
            if (binding.idRef != meId || binding.exprRef.isInvalid())
                continue;

            if (const Symbol* boundSymbol = sema.viewSymbol(binding.exprRef).sym(); boundSymbol && boundSymbol->isVariable())
            {
                const auto& boundVar = boundSymbol->cast<SymbolVariable>();
                SWC_RESULT(addCandidateFromType(sema, outCandidates, boundVar.typeRef(), &boundVar, AstNodeRef::invalid(), precedence++));
                return Result::Continue;
            }

            if (const SymbolVariable* receiver = activeReceiverBinding(sema))
            {
                if (binding.forceMaterialize)
                    return Result::Continue;
                if (expressionResolvesToVariable(sema, binding.exprRef, *receiver))
                    return Result::Continue;
            }

            TypeRef typeRef = binding.typeRef;
            if (typeRef.isInvalid())
                typeRef = sema.viewType(binding.exprRef).typeRef();
            if (typeRef.isInvalid())
                continue;

            SWC_RESULT(addCandidateFromType(sema, outCandidates, typeRef, nullptr, binding.exprRef, precedence++));
            return Result::Continue;
        }

        return Result::Continue;
    }

    Result addCandidatesFromAutoMemberBindings(Sema& sema, SmallVector4<AutoMemberCandidate>& outCandidates, std::span<const SemaScope::AutoMemberBinding> autoMemberBindings, uint32_t& precedence)
    {
        for (auto& binding : std::ranges::reverse_view(autoMemberBindings))
        {
            if (binding.typeRef.isValid())
            {
                SWC_RESULT(addCandidateFromType(sema, outCandidates, binding.typeRef, binding.symVar, binding.baseExprRef, precedence++));
            }
            else if (binding.symMap)
            {
                outCandidates.push_back({.symMap = binding.symMap, .symVar = binding.symVar, .baseExprRef = binding.baseExprRef, .precedence = precedence++});
            }
        }

        return Result::Continue;
    }

    Result collectAutoMemberCandidates(Sema& sema, SmallVector4<AutoMemberCandidate>& outCandidates, bool preferBindingTypes)
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
        for (const SemaScope* scope = sema.lookupScope(); scope; scope = scope->lookupParent())
        {
            for (const auto& binding : scope->autoMemberBindings())
                autoMemberBindings.push_back(binding);
        }

        const auto hasEnumBindingType = [&] {
            for (const TypeRef bindingTypeRef : bindingTypes)
            {
                const TypeRef normalizedTypeRef = normalizeAutoMemberBindingType(sema.ctx(), bindingTypeRef);
                if (normalizedTypeRef.isValid() && sema.typeMgr().get(normalizedTypeRef).isEnum())
                    return true;
            }

            return false;
        };

        const bool bindingTypesFirst = preferBindingTypes && hasEnumBindingType();
        uint32_t   precedence        = 0;

        if (bindingTypesFirst)
        {
            // In call arguments, the selected/deduced parameter type is the nearest
            // intent for `.Foo`, and should win over receiver members with the same name.
            for (const auto& bindingType : std::ranges::reverse_view(bindingTypes))
            {
                SWC_RESULT(addCandidateFromType(sema, outCandidates, bindingType, nullptr, AstNodeRef::invalid(), precedence++));
            }
        }

        SWC_RESULT(addCandidateFromInlineReceiver(sema, outCandidates, precedence));

        for (const auto& bindingVar : std::ranges::reverse_view(bindingVars))
        {
            SWC_RESULT(addCandidateFromType(sema, outCandidates, bindingVar->typeRef(), bindingVar, AstNodeRef::invalid(), precedence++));
        }

        if (!bindingTypesFirst)
            SWC_RESULT(addCandidatesFromAutoMemberBindings(sema, outCandidates, autoMemberBindings.span(), precedence));

        if (!bindingTypesFirst)
        {
            for (const auto& bindingType : std::ranges::reverse_view(bindingTypes))
            {
                SWC_RESULT(addCandidateFromType(sema, outCandidates, bindingType, nullptr, AstNodeRef::invalid(), precedence++));
            }
        }

        if (bindingTypesFirst)
            SWC_RESULT(addCandidatesFromAutoMemberBindings(sema, outCandidates, autoMemberBindings.span(), precedence));

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
                    if (outCandidates[j].precedence < outCandidates[i].precedence ||
                        (outCandidates[j].precedence == outCandidates[i].precedence &&
                         candidateSpecificity(outCandidates[j]) > candidateSpecificity(outCandidates[i])))
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

    Diagnostic reportCannotComputeAutoScopeMember(Sema& sema, AstNodeRef autoMemberRef, IdentifierRef idRef)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, autoMemberRef);
        diag.addArgument(Diagnostic::ARG_VALUE, sema.idMgr().get(idRef).name);
        return diag;
    }

    Result raiseCannotComputeAutoScopeMember(Sema& sema, AstNodeRef autoMemberRef, IdentifierRef idRef)
    {
        const auto diag = reportCannotComputeAutoScopeMember(sema, autoMemberRef, idRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    SymbolVariable* currentMethodReceiver(Sema& sema)
    {
        if (SymbolVariable* receiver = activeReceiverBinding(sema))
            return receiver;

        SymbolFunction* currentFunction = sema.frame().currentFunction();
        if (!currentFunction)
            return nullptr;

        const auto& params = currentFunction->parameters();
        if (params.empty())
            return nullptr;

        SymbolVariable* receiver = params.front();
        if (!receiver)
            return nullptr;

        if (receiver->idRef() != sema.idMgr().predefined(IdentifierManager::PredefinedName::Me))
            return nullptr;

        return receiver;
    }

    void bindCurrentReceiverIfCandidateMatches(Sema& sema, AutoMemberCandidate& candidate)
    {
        if (candidate.symVar || candidate.baseExprRef.isValid())
            return;

        const SymbolVariable* receiver = currentMethodReceiver(sema);
        if (!receiver)
            return;

        const TypeRef receiverTypeRef = normalizeAutoMemberBindingType(sema.ctx(), receiver->typeRef());
        if (receiverTypeRef.isInvalid())
            return;

        if (candidate.typeRef.isValid())
        {
            if (receiverTypeRef != candidate.typeRef)
                return;
        }
        else
        {
            const TypeInfo& receiverTypeInfo = sema.typeMgr().get(receiverTypeRef);
            if (!receiverTypeInfo.isStruct() || candidate.symMap != &receiverTypeInfo.payloadSymStruct())
                return;
        }

        candidate.symVar = receiver;
    }

    bool callableSetNeedsReceiver(std::span<const Symbol*> symbols)
    {
        for (const Symbol* symbol : symbols)
        {
            if (!symbol || !symbol->isFunction())
                continue;
            if (symbol->cast<SymbolFunction>().isMethod())
                return true;
        }

        return false;
    }

    AstNodeRef makeReceiverBoundLocalCallable(Sema& sema, TokenRef tokRef, AstNodeRef rightRef, std::span<const Symbol*> callableSymbols)
    {
        SymbolVariable* receiver = activeReceiverBinding(sema);
        if (!receiver)
            return AstNodeRef::invalid();

        auto [leftRef, leftPtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef);
        sema.setSymbol(leftRef, receiver);
        sema.setIsValue(*leftPtr);
        sema.setIsLValue(*leftPtr);

        AstMemberAccessExpr* memberNode = nullptr;
        const AstNodeRef     memberRef  = makeAutoMemberAccessExpr(sema, tokRef, {.baseExprRef = leftRef}, rightRef, memberNode);
        sema.setSymbolList(memberRef, callableSymbols);
        sema.setSymbolList(rightRef, callableSymbols);
        sema.setSymbolList(memberNode->nodeRightRef, callableSymbols);
        sema.setIsValue(*memberNode);
        return memberRef;
    }

    Result trySubstituteLocalCallable(Sema& sema, const SourceCodeRef& codeRef, TokenRef tokRef, AstNodeRef rightRef, IdentifierRef idRef, bool allowOverloadSet, bool& outHandled)
    {
        outHandled = false;
        if (!allowOverloadSet)
            return Result::Continue;

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = codeRef;
        lookUpCxt.noWaitOnEmpty = true;
        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));

        SmallVector<const Symbol*> callableSymbols;
        if (!SemaSymbolLookup::filterCallCalleeCandidates(lookUpCxt.symbols().span(), callableSymbols))
            return Result::Continue;

        AstNodeRef nodeRef = AstNodeRef::invalid();
        if (callableSetNeedsReceiver(callableSymbols.span()))
            nodeRef = makeReceiverBoundLocalCallable(sema, tokRef, rightRef, callableSymbols.span());
        if (nodeRef.isInvalid())
        {
            auto [identRef, identPtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef);
            SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, identRef, true, callableSymbols.span()));
            sema.setIsValue(*identPtr);
            nodeRef = identRef;
        }

        sema.setSubstitute(sema.curNodeRef(), nodeRef);
        outHandled = true;
        return Result::Continue;
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
    const bool     allowOverloadSet = hasFlag(AstAutoMemberAccessExprFlagsE::CallCallee);
    const AstNode& rightNode        = sema.node(nodeIdentRef);
    SWC_ASSERT(rightNode.is(AstNodeId::Identifier));
    const SourceCodeRef codeRef = rightNode.codeRef();
    const IdentifierRef idRef   = sema.idMgr().addIdentifier(sema.ctx(), codeRef);

    SmallVector4<AutoMemberCandidate> candidates;
    const bool                        deferCallArgument = hasFlag(AstAutoMemberAccessExprFlagsE::CallArgument);
    SWC_RESULT(collectAutoMemberCandidates(sema, candidates, deferCallArgument));
    if (candidates.empty())
    {
        // In a call-argument position, `.EnumValue` might need the selected overload's
        // parameter type (enum scope) to be resolved. Defer resolution until overload
        // resolution can provide that context. Even if another contextual binding type
        // is active, an empty candidate set means that binding cannot resolve this
        // auto-member right now.
        if (hasFlag(AstAutoMemberAccessExprFlagsE::CallArgument))
            return Result::SkipChildren;
        return raiseCannotComputeAutoScopeMember(sema, sema.curNodeRef(), idRef);
    }

    // Probe candidates without pausing on empty results.
    SmallVector2<AutoMemberMatch> matches;
    SWC_RESULT(probeAutoMemberCandidates(sema, codeRef, idRef, candidates, matches));

    // If nothing matched, report a smart error.
    if (matches.empty())
    {
        bool localCallableHandled = false;
        SWC_RESULT(trySubstituteLocalCallable(sema, codeRef, rightNode.tokRef(), nodeIdentRef, idRef, allowOverloadSet, localCallableHandled));
        if (localCallableHandled)
            return Result::SkipChildren;

        if (deferCallArgument)
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
                return raiseCannotComputeAutoScopeMember(sema, sema.curNodeRef(), idRef);

            const TypeInfo& typeInfo = sema.typeMgr().get(candidate.typeRef);

            auto diagId = DiagnosticId::sema_err_auto_scope_missing_enum_value;
            if (typeInfo.isStruct() || typeInfo.isAggregateStruct())
                diagId = DiagnosticId::sema_err_auto_scope_missing_struct_member;

            auto diag = SemaError::report(sema, diagId, sema.curNodeRef());
            diag.addArgument(Diagnostic::ARG_VALUE, sema.idMgr().get(idRef).name);
            diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, candidate.typeRef);
            if (diagId == DiagnosticId::sema_err_auto_scope_missing_struct_member)
            {
                const Utf8 availableFields = formatStructMemberList(sema, candidate.typeRef);
                if (!availableFields.empty())
                {
                    diag.addNote(DiagnosticId::sema_note_available_struct_fields);
                    diag.last().addArgument(Diagnostic::ARG_VALUES, availableFields);
                }
            }
            else if (diagId == DiagnosticId::sema_err_auto_scope_missing_enum_value)
            {
                const Utf8 availableValues = SemaError::formatEnumValueList(sema.ctx(), typeInfo.payloadSymEnum());
                if (!availableValues.empty())
                {
                    diag.addNote(DiagnosticId::sema_note_available_enum_values);
                    diag.last().addArgument(Diagnostic::ARG_VALUES, availableValues);
                }
            }
            diag.report(sema.ctx());
            return Result::Error;
        }

        auto diag = reportCannotComputeAutoScopeMember(sema, sema.curNodeRef(), idRef);
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
        uint32_t bestPrecedence = UINT32_MAX;
        for (const auto& match : matches)
            bestPrecedence = std::min(bestPrecedence, match.candidate.precedence);

        SmallVector2<AutoMemberMatch> bestMatches;
        for (const auto& match : matches)
        {
            if (match.candidate.precedence == bestPrecedence)
                bestMatches.push_back(match);
        }

        if (bestMatches.size() == 1)
        {
            matches.clear();
            matches.push_back(bestMatches.front());
        }
    }

    if (matches.size() > 1)
    {
        SmallVector<const Symbol*> all;
        mergeAutoMemberMatches(matches, all);
        if (!all.empty())
            return SemaError::raiseAmbiguousSymbol(sema, sema.curNodeRef(), all);
        return raiseCannotComputeAutoScopeMember(sema, sema.curNodeRef(), idRef);
    }

    AutoMemberCandidate selected = matches.front().candidate;
    bindCurrentReceiverIfCandidateMatches(sema, selected);

    if (selected.symMap)
    {
        const std::span foundSymbols = matches.front().symbols.span();
        SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, sema.curNodeRef(), allowOverloadSet, foundSymbols));

        AstMemberAccessExpr*     substituteNode = nullptr;
        const AstNodeRef         nodeRef        = makeAutoMemberAccessExpr(sema, tokRef(), selected, nodeIdentRef, substituteNode);
        const std::span<Symbol*> symbols        = sema.curViewSymbolList().symList();
        sema.setSymbolList(nodeRef, symbols);
        sema.setSymbolList(nodeIdentRef, symbols);
        sema.setSymbolList(substituteNode->nodeRightRef, symbols);

        AstNodeRef substituteRef = nodeRef;
        if (selected.resultTypeRef.isValid())
            substituteRef = Cast::createCastNode(sema, selected.resultTypeRef, nodeRef);
        sema.setSubstitute(sema.curNodeRef(), substituteRef);
        sema.setIsValue(*substituteNode);
        return Result::SkipChildren;
    }

    // Aggregate structs do not have member symbols, so they must go through
    // the regular member-access semantic path.
    AstMemberAccessExpr* substituteNode = nullptr;
    const AstNodeRef     nodeRef        = makeAutoMemberAccessExpr(sema, tokRef(), selected, nodeIdentRef, substituteNode);
    SWC_RESULT(SemaHelpers::resolveMemberAccess(sema, nodeRef, *substituteNode, allowOverloadSet));

    AstNodeRef substituteRef = nodeRef;
    if (selected.resultTypeRef.isValid())
        substituteRef = Cast::createCastNode(sema, selected.resultTypeRef, nodeRef);
    sema.setSubstitute(sema.curNodeRef(), substituteRef);
    return Result::SkipChildren;
}

SWC_END_NAMESPACE();
