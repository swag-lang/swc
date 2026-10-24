#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaAccess.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Helpers/SemaTagged.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Assert.h"

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

            if (typeInfo.isIndirectIndexable())
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

    // Leading-dot lookup ranks value subjects (me or with) separately from
    // contextual types (.EnumValue in a typed slot). These lookup sources must
    // not share one precedence chain.
    enum class AutoMemberPlane : uint8_t
    {
        Subject,
        Type,
    };

    struct AutoMemberCandidate
    {
        const SymbolMap* symMap        = nullptr;
        TypeRef          typeRef       = TypeRef::invalid();
        TypeRef          resultTypeRef = TypeRef::invalid();

        const SymbolVariable* symVar      = nullptr;
        AstNodeRef            baseExprRef = AstNodeRef::invalid();

        uint32_t        precedence = UINT32_MAX;
        AutoMemberPlane plane      = AutoMemberPlane::Subject;

        // Inherited caller subjects are not local to this inline body, so they
        // neither determine its innermost subject nor count as shadowed names.
        bool fromCaller = false;
    };

    struct AutoMemberMatch
    {
        AutoMemberCandidate        candidate;
        SmallVector<const Symbol*> symbols;
    };

    SymbolVariable* activeReceiverBinding(Sema& sema)
    {
        const IdentifierRef meId = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);

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

    AstNodeRef makeAutoMemberLeftExpr(Sema& sema, TokenRef tokRef, const SourceCodeRef& autoMemberCodeRef, const AutoMemberCandidate& candidate)
    {
        if (candidate.baseExprRef.isValid())
            return cloneDetachedExpr(sema, candidate.baseExprRef);

        auto [leftRef, leftPtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef);
        leftPtr->setCodeRef(autoMemberCodeRef);
        if (candidate.symVar)
        {
            candidate.symVar->markReferenced();
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

    AstNodeRef makeAutoMemberAccessExpr(Sema& sema, TokenRef tokRef, const SourceCodeRef& autoMemberCodeRef, const AutoMemberCandidate& candidate, AstNodeRef rightRef, AstMemberAccessExpr*& outNode)
    {
        auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(tokRef);
        nodePtr->setCodeRef(autoMemberCodeRef);
        nodePtr->nodeLeftRef = makeAutoMemberLeftExpr(sema, tokRef, autoMemberCodeRef, candidate);

        // Clone the right-hand member name without detached-expression state;
        // stale substitutes from the auto-member source would corrupt left.member.
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
        return typeInfo.tryGetAggregateMemberIndexByName(memberIndex, sema.ctx(), idRef);
    }

    Result addCandidateFromType(Sema& sema, SmallVector4<AutoMemberCandidate>& outCandidates, TypeRef typeRef, const SymbolVariable* symVar, AstNodeRef baseExprRef, uint32_t precedence, AutoMemberPlane plane)
    {
        const TypeRef normalizedTypeRef = normalizeAutoMemberBindingType(sema.ctx(), typeRef);
        if (!normalizedTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& typeInfo = sema.typeMgr().get(normalizedTypeRef);
        TypeRef         resultTypeRef;
        if (typeRef != normalizedTypeRef)
        {
            const TypeInfo& sourceType = sema.typeMgr().get(typeRef);

            // A strict value alias retains its identity on member selection. An alias
            // of a pointer or reference only names indirection: the selected member
            // belongs to its pointee and must not acquire the pointer alias type.
            const TypeRef aliasUnderlyingTypeRef = sourceType.isAlias() ? sourceType.payloadSymAlias().underlyingTypeRef() : TypeRef::invalid();
            const bool    aliasIsIndirection     = aliasUnderlyingTypeRef.isValid() && sema.typeMgr().get(aliasUnderlyingTypeRef).isPointerOrReference();
            if (sourceType.isAlias() && sourceType.payloadSymAlias().isStrict() && !aliasIsIndirection)
                resultTypeRef = typeRef;
        }

        if (typeInfo.isStruct())
        {
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, sema.curNodeRef()));

            outCandidates.push_back(
                {.symMap        = &typeInfo.payloadSymStruct(),
                 .typeRef       = normalizedTypeRef,
                 .resultTypeRef = resultTypeRef,
                 .symVar        = symVar,
                 .baseExprRef   = baseExprRef,
                 .precedence    = precedence,
                 .plane         = plane});
        }
        else if (typeInfo.isEnum())
        {
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, sema.curNodeRef()));

            outCandidates.push_back(
                {.symMap        = &typeInfo.payloadSymEnum(),
                 .typeRef       = normalizedTypeRef,
                 .resultTypeRef = resultTypeRef,
                 .symVar        = symVar,
                 .baseExprRef   = baseExprRef,
                 .precedence    = precedence,
                 .plane         = plane});
        }
        else if (typeInfo.isAggregateStruct())
        {
            outCandidates.push_back(
                {.typeRef       = normalizedTypeRef,
                 .resultTypeRef = resultTypeRef,
                 .symVar        = symVar,
                 .baseExprRef   = baseExprRef,
                 .precedence    = precedence,
                 .plane         = plane});
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

            const AstNodeRef resolvedRef = sema.resolvedNodeRef(exprRef);
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

    // Stop at the first payload that binds me, even when it yields no candidate.
    // outFound distinguishes that binding from a payload that has no receiver.
    Result addCandidateFromInlineReceiverPayload(Sema& sema, const SemaInlinePayload& inlinePayload, SmallVector4<AutoMemberCandidate>& outCandidates, uint32_t& precedence, bool& outFound)
    {
        outFound = false;

        const IdentifierRef meId = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
        for (const SemaClone::ParamBinding& binding : inlinePayload.argMappings)
        {
            if (binding.idRef != meId || binding.exprRef.isInvalid())
                continue;

            outFound = true;

            // Use a bare variable only when it resolves standalone at codegen. Instance
            // fields and macro me parameters need their full receiver expression, cloned
            // for each elided use.
            if (const Symbol* boundSymbol = sema.viewSymbol(binding.exprRef).sym(); boundSymbol && boundSymbol->isVariable())
            {
                const auto& boundVar = boundSymbol->cast<SymbolVariable>();
                if (SemaHelpers::bindingSymbolResolvesStandalone(sema, boundVar))
                {
                    SWC_RESULT(addCandidateFromType(sema, outCandidates, boundVar.typeRef(), &boundVar, AstNodeRef::invalid(), precedence++, AutoMemberPlane::Subject));

                    return Result::Continue;
                }
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

            SWC_RESULT(addCandidateFromType(sema, outCandidates, typeRef, nullptr, binding.exprRef, precedence++, AutoMemberPlane::Subject));

            return Result::Continue;
        }

        return Result::Continue;
    }

    Result addCandidateFromInlineReceiver(Sema& sema, const SemaInlinePayload* effectiveInlinePayload, SmallVector4<AutoMemberCandidate>& outCandidates, uint32_t& precedence)
    {
        // Nested macro payloads may have no me binding. Search outward for the
        // nearest receiver so injected code still sees the enclosing method's me.
        for (const SemaInlinePayload* inlinePayload = effectiveInlinePayload;
             inlinePayload;
             inlinePayload = inlinePayload->parentInlinePayload)
        {
            bool found = false;
            SWC_RESULT(addCandidateFromInlineReceiverPayload(sema, *inlinePayload, outCandidates, precedence, found));
            if (found)
                return Result::Continue;
        }

        return Result::Continue;
    }

    // The caller's bindings predate this inline method and must rank below
    // its receiver. Find the nearest payload that records that receiver.
    const SemaInlinePayload* nearestInlineReceiverPayload(Sema& sema, const SemaInlinePayload* effectiveInlinePayload)
    {
        const IdentifierRef meId = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
        for (const SemaInlinePayload* payload = effectiveInlinePayload; payload; payload = payload->parentInlinePayload)
        {
            for (const SemaClone::ParamBinding& binding : payload->argMappings)
                if (binding.idRef == meId && binding.exprRef.isValid())
                    return payload;
        }

        return nullptr;
    }

    const SemaInlinePayload* nearestInlineReceiverPayload(Sema& sema)
    {
        return nearestInlineReceiverPayload(sema, SemaHelpers::effectiveInlinePayload(sema));
    }

    bool isCallerInheritedBindingVar(const SemaInlinePayload* inlineReceiverPayload, const SymbolVariable* bindingVar)
    {
        if (!inlineReceiverPayload)
            return false;

        for (const SymbolVariable* callerVar : inlineReceiverPayload->callerBindingVars)
            if (callerVar == bindingVar)
                return true;

        return false;
    }

    Result addCandidatesFromAutoMemberBindings(Sema& sema, SmallVector4<AutoMemberCandidate>& outCandidates, std::span<const SemaScope::AutoMemberBinding> autoMemberBindings, uint32_t& precedence)
    {
        for (auto& binding : autoMemberBindings)
        {
            if (binding.typeRef.isValid())
            {
                SWC_RESULT(addCandidateFromType(sema, outCandidates, binding.typeRef, binding.symVar, binding.baseExprRef, precedence++, AutoMemberPlane::Subject));
            }
            else if (binding.symMap)
            {
                outCandidates.push_back(
                    {.symMap      = binding.symMap,
                     .symVar      = binding.symVar,
                     .baseExprRef = binding.baseExprRef,
                     .precedence  = precedence++,
                     .plane       = AutoMemberPlane::Subject});
            }
        }

        return Result::Continue;
    }

    Result collectAutoMemberCandidates(Sema& sema, SmallVector4<AutoMemberCandidate>& outCandidates, bool preferBindingTypes)
    {
        SmallVector<const SymbolVariable*>        bindingVars;
        SmallVector<TypeRef>                      bindingTypes;
        SmallVector<SemaScope::AutoMemberBinding> autoMemberBindings;

        const SemaFrame& frame = sema.frame();

        // Frame state is inherited when pushing nested semantic frames, so the
        // current frame already contains the active auto-scope context.
        for (const SymbolVariable* symVar : frame.bindingVars())
            bindingVars.push_back(symVar);
        // A slot expecting a tagged union lends the dot its tag: '.Circle' names a case.
        for (const TypeRef hintType : frame.bindingTypes())
        {
            const SymbolStruct* tagged = SemaTagged::unionOf(sema.ctx(), hintType);
            bindingTypes.push_back(tagged ? tagged->taggedTypeRef() : hintType);
        }
        for (const SemaScope* scope = sema.lookupScope(); scope; scope = scope->lookupParent())
        {
            for (const auto& binding : scope->autoMemberBindings())
                autoMemberBindings.push_back(binding);
        }

        // Rank this body's subjects first, then by nesting depth. Scope-chain order
        // is insufficient: with scopes precede their frames, and inline bodies also
        // inherit the caller's scopes.
        const SemaInlinePayload* currentInlinePayload = frame.currentInlinePayload();

        const auto subjectIsOwn = [currentInlinePayload](const SemaScope::AutoMemberBinding& binding) {
            return binding.inlinePayload == currentInlinePayload;
        };

        std::ranges::stable_sort(autoMemberBindings, [&](const SemaScope::AutoMemberBinding& a, const SemaScope::AutoMemberBinding& b) {
            if (subjectIsOwn(a) != subjectIsOwn(b))
                return subjectIsOwn(a);

            return a.order > b.order;
        });

        const size_t ownBindingCount = static_cast<size_t>(std::ranges::count_if(autoMemberBindings, subjectIsOwn));
        const auto   ownBindings     = autoMemberBindings.span().subspan(0, ownBindingCount);
        const auto   callerBindings  = autoMemberBindings.span().subspan(ownBindingCount);

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
            // A selected contextual enum type is the nearest intent for `.Foo`, and must win
            // over receiver members or local symbols with the same name.
            for (const auto& bindingType : std::ranges::reverse_view(bindingTypes))
            {
                const TypeRef normalizedTypeRef = normalizeAutoMemberBindingType(sema.ctx(), bindingType);
                if (normalizedTypeRef.isInvalid() || !sema.typeMgr().get(normalizedTypeRef).isEnum())
                    continue;

                SWC_RESULT(addCandidateFromType(sema, outCandidates, bindingType, nullptr, AstNodeRef::invalid(), precedence++, AutoMemberPlane::Type));
            }
        }

        // Match ordinary method ordering: this body's with subjects, then me, then
        // caller-owned subjects. Without inlining every subject belongs to this body
        // and me is a binding variable. Cache the inline context for both receiver
        // ranking and candidate collection; the visit path stays fixed here.
        const SemaInlinePayload* effectiveInlinePayload = SemaHelpers::effectiveInlinePayload(sema);
        const SemaInlinePayload* inlineReceiverPayload  = nearestInlineReceiverPayload(sema, effectiveInlinePayload);

        if (!bindingTypesFirst)
            SWC_RESULT(addCandidatesFromAutoMemberBindings(sema, outCandidates, ownBindings, precedence));

        // A macro's me symbol may not resolve standalone at codegen. Skip such
        // bare-symbol candidates; the inline receiver below retains its expression.
        for (const auto& bindingVar : std::ranges::reverse_view(bindingVars))
        {
            if (!isCallerInheritedBindingVar(inlineReceiverPayload, bindingVar) && SemaHelpers::bindingSymbolResolvesStandalone(sema, *bindingVar))
                SWC_RESULT(addCandidateFromType(sema, outCandidates, bindingVar->typeRef(), bindingVar, AstNodeRef::invalid(), precedence++, AutoMemberPlane::Subject));
        }

        SWC_RESULT(addCandidateFromInlineReceiver(sema, effectiveInlinePayload, outCandidates, precedence));

        const size_t callerCandidateStart = outCandidates.size();
        if (!bindingTypesFirst)
            SWC_RESULT(addCandidatesFromAutoMemberBindings(sema, outCandidates, callerBindings, precedence));

        for (const auto& bindingVar : std::ranges::reverse_view(bindingVars))
        {
            if (isCallerInheritedBindingVar(inlineReceiverPayload, bindingVar) && SemaHelpers::bindingSymbolResolvesStandalone(sema, *bindingVar))
                SWC_RESULT(addCandidateFromType(sema, outCandidates, bindingVar->typeRef(), bindingVar, AstNodeRef::invalid(), precedence++, AutoMemberPlane::Subject));
        }

        for (size_t i = callerCandidateStart; i < outCandidates.size(); ++i)
            outCandidates[i].fromCaller = true;

        if (!bindingTypesFirst)
        {
            for (const auto& bindingType : std::ranges::reverse_view(bindingTypes))
            {
                SWC_RESULT(addCandidateFromType(sema, outCandidates, bindingType, nullptr, AstNodeRef::invalid(), precedence++, AutoMemberPlane::Type));
            }
        }

        if (bindingTypesFirst)
        {
            SWC_RESULT(addCandidatesFromAutoMemberBindings(sema, outCandidates, ownBindings, precedence));
            SWC_RESULT(addCandidatesFromAutoMemberBindings(sema, outCandidates, callerBindings, precedence));
            for (const auto& bindingType : std::ranges::reverse_view(bindingTypes))
            {
                SWC_RESULT(addCandidateFromType(sema, outCandidates, bindingType, nullptr, AstNodeRef::invalid(), precedence++, AutoMemberPlane::Type));
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

    // A leading dot must use the innermost subject. Falling through because
    // that subject lacks the name would silently access an enclosing receiver.
    Result checkAutoScopeIsInnermost(Sema& sema, AstNodeRef nodeRef, IdentifierRef idRef, std::span<const AutoMemberCandidate> candidates, const AutoMemberCandidate& selected)
    {
        if (selected.plane != AutoMemberPlane::Subject || selected.typeRef.isInvalid())
            return Result::Continue;

        const AutoMemberCandidate* innermost = nullptr;
        for (const auto& candidate : candidates)
        {
            if (candidate.plane != AutoMemberPlane::Subject || candidate.fromCaller)
                continue;
            if (!innermost || candidate.precedence < innermost->precedence)
                innermost = &candidate;
        }

        if (!innermost || innermost->precedence == selected.precedence || innermost->typeRef.isInvalid())
            return Result::Continue;

        // Enforce this on source bodies, where the receiver is innermost. Expanded
        // bodies also see caller subjects ranked by expansion. Check that context
        // last to avoid an unnecessary visit-path search for innermost selections.
        if (nearestInlineReceiverPayload(sema))
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_auto_scope_not_innermost, nodeRef);
        diag.addArgument(Diagnostic::ARG_VALUE, sema.idMgr().get(idRef).name);
        diag.addArgument(Diagnostic::ARG_TYPE, innermost->typeRef);
        diag.addNote(DiagnosticId::sema_note_auto_scope_hint);
        diag.last().addArgument(Diagnostic::ARG_TYPE, selected.typeRef);
        diag.report(sema.ctx());

        return Result::Error;
    }

    Result probeAutoMemberCandidates(Sema& sema, const SourceCodeRef& codeRef, IdentifierRef idRef, std::span<const AutoMemberCandidate> candidates, SmallVector2<AutoMemberMatch>& outMatches)
    {
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
            if (lookUpCxt.empty() && candidates.size() > 1 && candidate.symMap->isStruct())
            {
                // Missing candidates can still gain a member from another impl. Settle that
                // publication before choosing a different scope or reporting no match.
                SWC_RESULT(candidate.symMap->cast<SymbolStruct>().waitPendingImplMembers(sema, codeRef));

                // Completion may have raced the first lookup without requiring a pause.
                SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
            }

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
        if (!receiver || !SemaHelpers::bindingSymbolResolvesStandalone(sema, *receiver))
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

    AstNodeRef makeReceiverBoundLocalCallable(Sema& sema, TokenRef tokRef, const SourceCodeRef& autoMemberCodeRef, AstNodeRef rightRef, std::span<const Symbol*> callableSymbols)
    {
        SymbolVariable* receiver = activeReceiverBinding(sema);
        if (!receiver)
            return AstNodeRef::invalid();

        auto [leftRef, leftPtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef);
        leftPtr->setCodeRef(autoMemberCodeRef);
        sema.setSymbol(leftRef, receiver);
        sema.setIsValue(*leftPtr);
        sema.setIsLValue(*leftPtr);

        AstMemberAccessExpr* memberNode = nullptr;
        const AstNodeRef     memberRef  = makeAutoMemberAccessExpr(sema, tokRef, autoMemberCodeRef, {.baseExprRef = leftRef}, rightRef, memberNode);

        sema.setSymbolList(memberRef, callableSymbols);
        sema.setSymbolList(rightRef, callableSymbols);
        sema.setSymbolList(memberNode->nodeRightRef, callableSymbols);
        sema.setIsValue(*memberNode);

        return memberRef;
    }

    Result trySubstituteLocalCallable(Sema& sema, const SourceCodeRef& rightCodeRef, const SourceCodeRef& autoMemberCodeRef, TokenRef tokRef, AstNodeRef rightRef, IdentifierRef idRef, bool allowOverloadSet, bool& outHandled)
    {
        outHandled = false;
        if (!allowOverloadSet)
            return Result::Continue;

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = rightCodeRef;
        lookUpCxt.noWaitOnEmpty = true;
        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));

        SmallVector<const Symbol*> callableSymbols;
        if (!SemaSymbolLookup::appendCallCalleeCandidates(lookUpCxt.symbols().span(), callableSymbols))
            return Result::Continue;

        AstNodeRef nodeRef = AstNodeRef::invalid();
        if (callableSetNeedsReceiver(callableSymbols.span()))
            nodeRef = makeReceiverBoundLocalCallable(sema, tokRef, autoMemberCodeRef, rightRef, callableSymbols.span());
        if (nodeRef.isInvalid())
        {
            auto [identRef, identPtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef);
            identPtr->setCodeRef(rightCodeRef);
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
    const AstNodeRef resolvedRef = sema.resolvedNodeRef(currentRef);
    if (resolvedRef.isValid() && resolvedRef != currentRef)
        return Result::SkipChildren;

    const bool     allowOverloadSet = hasFlag(AstAutoMemberAccessExprFlagsE::CallCallee);
    const AstNode& rightNode        = sema.node(nodeIdentRef);
    SWC_ASSERT(rightNode.is(AstNodeId::Identifier));
    const SourceCodeRef autoMemberCodeRef = codeRef();
    const SourceCodeRef rightCodeRef      = rightNode.codeRef();
    const IdentifierRef idRef             = sema.idMgr().addIdentifier(sema.ctx(), rightCodeRef);

    SmallVector4<AutoMemberCandidate> candidates;

    const bool deferCallArgument  = hasFlag(AstAutoMemberAccessExprFlagsE::CallArgument);
    const bool preferBindingTypes = deferCallArgument || hasFlag(AstAutoMemberAccessExprFlagsE::PreferBindingType);
    SWC_RESULT(collectAutoMemberCandidates(sema, candidates, preferBindingTypes));
    if (candidates.empty())
    {
        // An argument's enum scope may come from the selected overload. With no
        // usable candidate yet, defer until overload resolution supplies that context.
        if (hasFlag(AstAutoMemberAccessExprFlagsE::CallArgument))
            return Result::SkipChildren;

        return raiseCannotComputeAutoScopeMember(sema, sema.curNodeRef(), idRef);
    }

    // Probe candidates without pausing on empty results.
    SmallVector2<AutoMemberMatch> matches;
    SWC_RESULT(probeAutoMemberCandidates(sema, rightCodeRef, idRef, candidates, matches));

    if (matches.empty())
    {
        bool localCallableHandled = false;
        SWC_RESULT(trySubstituteLocalCallable(sema, rightCodeRef, autoMemberCodeRef, rightNode.tokRef(), nodeIdentRef, idRef, allowOverloadSet, localCallableHandled));
        if (localCallableHandled)
            return Result::SkipChildren;

        if (deferCallArgument)
        {
            // The selected overload may add a parameter-type candidate later, even
            // when the currently visible candidates do not match.
            return Result::SkipChildren;
        }

        if (candidates.size() == 1)
        {
            const AutoMemberCandidate& candidate = candidates.front();
            if (!candidate.typeRef.isValid())
                return raiseCannotComputeAutoScopeMember(sema, sema.curNodeRef(), idRef);

            // With one candidate, .member is a qualified access and must wait for
            // pending member publication. The non-blocking probe cannot distinguish
            // absence from a member generated later by a mixin in another impl.
            if (candidate.symMap)
                return sema.waitAutoScopeMember(idRef, candidate.typeRef, rightCodeRef);

            const TypeInfo& typeInfo = sema.typeMgr().get(candidate.typeRef);

            auto diagId = DiagnosticId::sema_err_auto_scope_missing_enum_value;
            if (typeInfo.isStructOrAggregateStruct())
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
    SWC_RESULT(checkAutoScopeIsInnermost(sema, sema.curNodeRef(), idRef, candidates.span(), selected));
    bindCurrentReceiverIfCandidateMatches(sema, selected);

    if (selected.symMap)
    {
        const std::span foundSymbols = matches.front().symbols.span();
        SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, sema.curNodeRef(), allowOverloadSet, foundSymbols));

        // An auto member ('.field') resolves without the regular member-access path, so the
        // member access rule has to be applied here as well.
        for (const Symbol* memberSym : foundSymbols)
            SWC_RESULT(SemaAccess::checkMemberAccess(sema, *memberSym, autoMemberCodeRef));

        AstMemberAccessExpr*     substituteNode = nullptr;
        const AstNodeRef         nodeRef        = makeAutoMemberAccessExpr(sema, tokRef(), autoMemberCodeRef, selected, nodeIdentRef, substituteNode);
        const std::span<Symbol*> symbols        = sema.curViewSymbol().symList();

        sema.setSymbolList(nodeRef, symbols);
        sema.setSymbolList(nodeIdentRef, symbols);
        sema.setSymbolList(substituteNode->nodeRightRef, symbols);

        for (const Symbol* memberSym : symbols)
        {
            if (const auto* fieldVar = memberSym->safeCast<SymbolVariable>())
                SemaAccess::markUnwritableMemberAccess(sema, *fieldVar, nodeRef, autoMemberCodeRef.srcViewRef);
        }

        // '.radius' on a 'me' or 'with' subject is a payload access like 'me.radius'.
        if (symbols.size() == 1 && symbols[0]->isVariable() && selected.plane == AutoMemberPlane::Subject)
            SWC_RESULT(SemaTagged::checkPayloadAccess(sema, nodeRef, substituteNode->nodeLeftRef, selected.typeRef, symbols[0]->cast<SymbolVariable>()));

        AstNodeRef substituteRef = nodeRef;
        if (selected.resultTypeRef.isValid())
            substituteRef = Cast::createCastNode(sema, selected.resultTypeRef, nodeRef);

        sema.setSubstitute(sema.curNodeRef(), substituteRef);

        // .IThing names an implementation scope, so .IThing.method() receives
        // the original subject and never the scope as a value.
        if (!std::ranges::all_of(symbols, [](const Symbol* symbol) { return symbol->isSymMap(); }))
            sema.setIsValue(*substituteNode);

        return Result::SkipChildren;
    }

    // Aggregate structs do not have member symbols, so they must go through
    // the regular member-access semantic path.
    AstMemberAccessExpr* substituteNode = nullptr;
    const AstNodeRef     nodeRef        = makeAutoMemberAccessExpr(sema, tokRef(), autoMemberCodeRef, selected, nodeIdentRef, substituteNode);
    SWC_RESULT(SemaHelpers::resolveMemberAccess(sema, nodeRef, *substituteNode, allowOverloadSet));

    AstNodeRef substituteRef = nodeRef;
    if (selected.resultTypeRef.isValid())
        substituteRef = Cast::createCastNode(sema, selected.resultTypeRef, nodeRef);

    sema.setSubstitute(sema.curNodeRef(), substituteRef);
    return Result::SkipChildren;
}

// '.Circle' alone, in a slot expecting a tagged union, is the value of that case with its default
// payload. In front of braces it names the case being built instead, which the initializer handles.
Result AstAutoMemberAccessExpr::semaPreNode(Sema& sema) const
{
    TypeRef             unionTypeRef = TypeRef::invalid();
    const SymbolStruct* tagged       = nullptr;
    SWC_RESULT(SemaTagged::contextUnion(sema, tagged, unionTypeRef));
    if (!tagged)
        return Result::Continue;

    const AstNodeRef parentRef = sema.visit().parentNodeRef(0);
    if (parentRef.isValid())
    {
        const auto* structInit = sema.node(parentRef).safeCast<AstStructInitializerList>();
        if (structInit && structInit->nodeWhatRef == sema.curNodeRef())
            return Result::Continue;
    }

    const IdentifierRef idRef   = SemaHelpers::resolveIdentifier(sema, sema.node(nodeIdentRef).codeRef());
    ConstantRef         caseRef = ConstantRef::invalid();
    SWC_RESULT(SemaTagged::findCase(sema, caseRef, *tagged, idRef));
    if (caseRef.isInvalid())
        return Result::Continue;

    auto [literalRef, literalNode] = sema.ast().makeNode<AstNodeId::TaggedUnionLiteral>(tokRef());
    literalNode->setCodeRef(codeRef());
    literalNode->unionTypeRef = unionTypeRef;
    literalNode->tagCstRef    = caseRef;

    sema.setSubstitute(sema.curNodeRef(), literalRef);
    sema.restartCurrentNode(literalRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
