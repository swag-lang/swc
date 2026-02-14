#include "pch.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class ConvRank
    {
        Exact,    // same type (or identical canonical type)
        Standard, // safe numeric, pointer decay, etc.
        Ellipsis, // varargs fallback (if you support it)
        Bad,
    };

    enum class MatchFailKind
    {
        TooManyArguments,
        TooFewArguments,
        InvalidArgumentType,
    };

    struct MatchFailure
    {
        MatchFailKind kind          = MatchFailKind::InvalidArgumentType;
        CastFailure   castFailure   = {};
        uint32_t      argIndex      = 0; // where it failed (argument index)
        uint32_t      paramIndex    = 0; // where it failed (parameter index)
        uint32_t      expectedCount = 0; // for too many/few
        uint32_t      providedCount = 0; // for too many/few
        bool          hasLocation   = false;
    };

    struct Candidate
    {
        SmallVector<ConvRank> perArg;
        SymbolFunction*       fn           = nullptr;
        uint32_t              usedDefaults = 0;
        bool                  viable       = false;
        bool                  ufcsUsed     = false;
    };

    struct Attempt
    {
        SymbolFunction* fn        = nullptr;
        Candidate       candidate = {};
        MatchFailure    fail      = {};
        bool            viable    = false;
    };

    struct VariadicInfo
    {
        bool isVariadic      = false;
        bool isTypedVariadic = false;

        bool any() const { return isVariadic || isTypedVariadic; }
    };

    struct AutoEnumArgProbe
    {
        bool    matched = false;
        TypeRef typeRef = TypeRef::invalid();
    };

    struct CallArgEntry
    {
        AstNodeRef argRef       = AstNodeRef::invalid();
        uint32_t   callArgIndex = 0;
    };

    struct CallArgMapping
    {
        SmallVector<CallArgEntry> paramArgs;
        SmallVector<CallArgEntry> variadicArgs;
        bool                      hasNamed = false;
    };

    AstNodeRef getCallArg(uint32_t callArgIndex, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        if (ufcsArg.isValid())
        {
            if (callArgIndex == 0)
                return ufcsArg;
            return args[callArgIndex - 1];
        }
        return args[callArgIndex];
    }

    uint32_t countCallArgs(std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        uint32_t n = static_cast<uint32_t>(args.size());
        if (ufcsArg.isValid())
            ++n;
        return n;
    }

    uint32_t callArgIndexFromUserIndex(uint32_t userArgIndex, AstNodeRef ufcsArg)
    {
        return ufcsArg.isValid() ? (userArgIndex + 1) : userArgIndex;
    }

    VariadicInfo getVariadicInfo(Sema& sema, const SymbolFunction& fn)
    {
        VariadicInfo vi;
        const auto&  params = fn.parameters();
        if (params.empty())
            return vi;

        const auto& lastParamTy = params.back()->type(sema.ctx());
        vi.isVariadic           = lastParamTy.isVariadic();
        vi.isTypedVariadic      = lastParamTy.isTypedVariadic();
        return vi;
    }

    void failTooMany(MatchFailure& f, uint32_t expected, uint32_t provided)
    {
        f.kind          = MatchFailKind::TooManyArguments;
        f.expectedCount = expected;
        f.providedCount = provided;
        f.argIndex      = expected; // first extra
        f.paramIndex    = expected;
        f.hasLocation   = true;
    }

    void failTooFew(MatchFailure& f, uint32_t expectedMin, uint32_t provided, uint32_t missingParamIndex)
    {
        f.kind          = MatchFailKind::TooFewArguments;
        f.expectedCount = expectedMin;
        f.providedCount = provided;
        f.argIndex      = provided; // first missing
        f.paramIndex    = missingParamIndex;
        f.hasLocation   = false;
    }

    void failBadType(MatchFailure& f, uint32_t argIndex, uint32_t paramIndex, const CastFailure& cf)
    {
        f.kind        = MatchFailKind::InvalidArgumentType;
        f.argIndex    = argIndex;
        f.paramIndex  = paramIndex;
        f.castFailure = cf;
        f.hasLocation = true;
    }

    bool buildCallArgMapping(Sema& sema, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, CallArgMapping& outMapping, MatchFailure& outFail)
    {
        outMapping = {};

        const auto&    params     = fn.parameters();
        const uint32_t numParams  = static_cast<uint32_t>(params.size());
        const uint32_t paramStart = ufcsArg.isValid() ? 1u : 0u;

        outMapping.paramArgs.resize(numParams);
        for (auto& entry : outMapping.paramArgs)
            entry.callArgIndex = 0;

        if (ufcsArg.isValid() && numParams > 0)
        {
            outMapping.paramArgs[0].argRef       = ufcsArg;
            outMapping.paramArgs[0].callArgIndex = 0;
        }

        bool     seenNamed = false;
        uint32_t nextPos   = paramStart;

        const auto setFailure = [&](uint32_t userArgIndex, DiagnosticId diagId, IdentifierRef idRef = IdentifierRef::invalid()) {
            CastFailure cf{};
            cf.diagId = diagId;
            if (idRef.isValid())
                cf.valueStr = Utf8{sema.idMgr().get(idRef).name};
            const uint32_t callArgIndex = callArgIndexFromUserIndex(userArgIndex, ufcsArg);
            failBadType(outFail, callArgIndex, callArgIndex, cf);
        };

        for (uint32_t userIndex = 0; userIndex < args.size(); ++userIndex)
        {
            const AstNodeRef argRef  = args[userIndex];
            const AstNode&   argNode = sema.node(argRef);

            if (argNode.is(AstNodeId::NamedArgument))
            {
                seenNamed           = true;
                outMapping.hasNamed = true;

                const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), argNode.codeRef());

                int32_t found = -1;
                for (uint32_t i = paramStart; i < numParams; ++i)
                {
                    if (params[i]->idRef() == idRef)
                    {
                        found = static_cast<int32_t>(i);
                        break;
                    }
                }

                if (found < 0)
                {
                    setFailure(userIndex, DiagnosticId::sema_err_named_argument_unknown, idRef);
                    return false;
                }

                if (outMapping.paramArgs[found].argRef.isValid())
                {
                    setFailure(userIndex, DiagnosticId::sema_err_named_argument_duplicate, idRef);
                    return false;
                }

                outMapping.paramArgs[found].argRef       = argRef;
                outMapping.paramArgs[found].callArgIndex = callArgIndexFromUserIndex(userIndex, ufcsArg);
                continue;
            }

            if (seenNamed)
            {
                setFailure(userIndex, DiagnosticId::sema_err_unnamed_parameter);
                return false;
            }

            while (nextPos < numParams && outMapping.paramArgs[nextPos].argRef.isValid())
                ++nextPos;

            if (nextPos < numParams)
            {
                outMapping.paramArgs[nextPos].argRef       = argRef;
                outMapping.paramArgs[nextPos].callArgIndex = callArgIndexFromUserIndex(userIndex, ufcsArg);
                ++nextPos;
                continue;
            }

            CallArgEntry entry;
            entry.argRef       = argRef;
            entry.callArgIndex = callArgIndexFromUserIndex(userIndex, ufcsArg);
            outMapping.variadicArgs.push_back(entry);
        }

        return true;
    }

    DiagnosticId addCastFailureArgs(DiagnosticElement& e, const CastFailure& cf)
    {
        cf.applyArguments(e);
        return cf.noteId;
    }

    Result errorNotCallable(Sema& sema, const SemaNodeView& nodeCallee)
    {
        const auto diag = SemaError::report(sema, DiagnosticId::sema_err_not_callable, nodeCallee.nodeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    void fillMatchDiagnostic(Sema& sema, DiagnosticElement& diagElement, Diagnostic& diag, const SymbolFunction& fn, const MatchFailure& fail, std::span<AstNodeRef> args, AstNodeRef ufcsArg, bool isNote)
    {
        const auto&    ctx     = sema.ctx();
        const uint32_t numArgs = countCallArgs(args, ufcsArg);

        switch (fail.kind)
        {
            case MatchFailKind::TooManyArguments:
                if (isNote)
                    diagElement.addArgument(Diagnostic::ARG_WHAT, Diagnostic::diagIdMessage(DiagnosticId::sema_note_too_many_arguments));
                diagElement.addArgument(Diagnostic::ARG_COUNT, fail.expectedCount);
                diagElement.addArgument(Diagnostic::ARG_VALUE, fail.providedCount);
                break;

            case MatchFailKind::TooFewArguments:
                if (isNote)
                    diagElement.addArgument(Diagnostic::ARG_WHAT, Diagnostic::diagIdMessage(DiagnosticId::sema_note_too_few_arguments));
                diagElement.addArgument(Diagnostic::ARG_COUNT, fail.expectedCount);
                diagElement.addArgument(Diagnostic::ARG_VALUE, fail.providedCount);
                break;

            case MatchFailKind::InvalidArgumentType:
                if (fail.castFailure.diagId != DiagnosticId::None)
                {
                    if (isNote)
                        diagElement.addArgument(Diagnostic::ARG_WHAT, Diagnostic::diagIdMessage(fail.castFailure.diagId));
                    if (const DiagnosticId nid = addCastFailureArgs(diagElement, fail.castFailure); nid != DiagnosticId::None)
                        diag.addNote(nid);
                }
                else
                {
                    if (isNote)
                        diagElement.addArgument(Diagnostic::ARG_WHAT, Diagnostic::diagIdMessage(DiagnosticId::sema_note_invalid_argument_type));
                    else
                        diagElement.addArgument(Diagnostic::ARG_SYM, fn.name(ctx));
                }
                break;

            default:
                if (isNote)
                    diagElement.addArgument(Diagnostic::ARG_WHAT, Diagnostic::diagIdMessage(DiagnosticId::sema_note_not_viable));
                else
                    diagElement.addArgument(Diagnostic::ARG_SYM, fn.name(ctx));
                break;
        }

        if (fail.hasLocation && fail.argIndex < numArgs)
        {
            const AstNodeRef argRef = getCallArg(fail.argIndex, args, ufcsArg);
            diagElement.addSpan(sema.node(argRef).codeRangeWithChildren(ctx, sema.ast()));
        }
    }

    Result errorBadMatch(Sema& sema, const SemaNodeView& nodeCallee, const SymbolFunction& fn, const MatchFailure& fail, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        DiagnosticId id;
        switch (fail.kind)
        {
            case MatchFailKind::TooManyArguments:
                id = DiagnosticId::sema_err_too_many_arguments;
                break;
            case MatchFailKind::TooFewArguments:
                id = DiagnosticId::sema_err_too_few_arguments;
                break;
            case MatchFailKind::InvalidArgumentType:
                id = fail.castFailure.diagId != DiagnosticId::None ? fail.castFailure.diagId : DiagnosticId::sema_err_bad_function_match;
                break;
            default:
                id = DiagnosticId::sema_err_bad_function_match;
                break;
        }

        auto diag = SemaError::report(sema, id, nodeCallee.nodeRef);
        fillMatchDiagnostic(sema, diag.last(), diag, fn, fail, args, ufcsArg, false);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result errorNoOverloadMatch(Sema& sema, const SemaNodeView& nodeCallee, const SmallVector<Attempt>& attempts, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        auto& ctx = sema.ctx();

        struct SortedAttempt
        {
            const Attempt* a;
            uint32_t       rank;
        };

        struct SortedAttemptByRankDesc
        {
            bool operator()(const SortedAttempt& a, const SortedAttempt& b) const
            {
                return a.rank > b.rank;
            }
        };

        SmallVector<SortedAttempt> sorted;
        for (const Attempt& a : attempts)
        {
            if (!a.fn || a.viable)
                continue;

            uint32_t rank = 0;
            switch (a.fail.kind)
            {
                case MatchFailKind::InvalidArgumentType:
                    rank = 2000 + a.fail.argIndex;
                    break;
                case MatchFailKind::TooFewArguments:
                    rank = 1000 + a.fail.providedCount;
                    break;
                case MatchFailKind::TooManyArguments:
                    rank = 500 + a.fail.expectedCount;
                    break;
                default:
                    rank = 0;
                    break;
            }

            sorted.push_back({.a = &a, .rank = rank});
        }

        std::ranges::sort(sorted, SortedAttemptByRankDesc{});

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_no_overload_match, nodeCallee.nodeRef);

        // One note per overload attempt describing why it failed (and where when possible).
        int count = 0;
        for (const auto& sa : sorted)
        {
            if (count >= 5)
            {
                diag.addNote(DiagnosticId::sema_note_too_many_overloads);
                diag.last().addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(sorted.size() - count));
                break;
            }

            count++;
            const Attempt& a = *sa.a;

            diag.addNote(DiagnosticId::sema_note_overload_candidate_failed);
            diag.last().addArgument(Diagnostic::ARG_SYM, a.fn->type(ctx).toName(ctx));
            fillMatchDiagnostic(sema, diag.last(), diag, *a.fn, a.fail, args, ufcsArg, true);
        }

        diag.report(sema.ctx());
        return Result::Error;
    }

    // Probes if an implicit conversion from 'from' to 'to' is possible, and returns its rank.
    Result probeImplicitConversion(Sema& sema, ConvRank& outRank, AstNodeRef argRef, TypeRef from, TypeRef to, CastFailure& outCastFailure, bool isUfcsArgument)
    {
        outRank = ConvRank::Bad;
        if (from == to)
        {
            outRank = ConvRank::Exact;
            return Result::Continue;
        }

        const SemaNodeView argNodeView(sema, argRef);
        auto               castKind  = CastKind::Parameter;
        CastFlags          castFlags = CastFlagsE::Zero;
        if (const auto* autoCast = argNodeView.node->safeCast<AstAutoCastExpr>())
        {
            castKind = CastKind::Explicit;
            if (autoCast->modifierFlags.has(AstModifierFlagsE::Bit))
                castFlags.add(CastFlagsE::BitCast);
            if (autoCast->modifierFlags.has(AstModifierFlagsE::UnConst))
                castFlags.add(CastFlagsE::UnConst);
        }
        if (argNodeView.cstRef.isValid() && sema.isFoldedTypedConst(argRef))
            castFlags.add(CastFlagsE::FoldedTypedConst);

        CastRequest castRequest(castKind);
        castRequest.flags = castFlags;
        castRequest.setConstantFoldingSrc(argNodeView.cstRef);
        if (isUfcsArgument)
            castRequest.flags.add(CastFlagsE::UfcsArgument);
        const Result castResult = Cast::castAllowed(sema, castRequest, from, to);
        if (castResult == Result::Pause)
            return Result::Pause;
        if (castResult == Result::Continue)
        {
            outRank = ConvRank::Standard;
            return Result::Continue;
        }

        outCastFailure = castRequest.failure;
        return Result::Continue;
    }

    Result probeAutoEnumArg(Sema& sema, AstNodeRef argRef, TypeRef paramTy, AutoEnumArgProbe& out, CastFailure& cf)
    {
        out = {};

        // Only handle `.EnumValue` (auto-member) using the overload's parameter enum scope.
        const AstNodeRef argSubRef   = sema.getSubstituteRef(argRef);
        const AstNodeRef finalArgRef = argSubRef.isValid() ? argSubRef : argRef;
        const AstNode&   argNode     = sema.node(finalArgRef);
        const auto*      autoMem     = argNode.safeCast<AstAutoMemberAccessExpr>();
        if (!autoMem)
            return Result::Continue;

        const TypeInfo& paramTypeInfo = sema.typeMgr().get(paramTy);
        if (!paramTypeInfo.isEnum())
            return Result::Continue;

        const SymbolEnum& enumSym = paramTypeInfo.payloadSymEnum();
        RESULT_VERIFY(sema.waitCompleted(&enumSym, argNode.codeRef()));

        const SemaNodeView  nodeRightView(sema, autoMem->nodeIdentRef);
        const TokenRef      tokNameRef = nodeRightView.node->tokRef();
        const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), nodeRightView.node->codeRef());

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = SourceCodeRef{argNode.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint    = &enumSym;
        lookUpCxt.noWaitOnEmpty = true;

        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));
        if (!lookUpCxt.empty())
        {
            out.matched = true;
            out.typeRef = paramTy;
        }
        else
        {
            cf.diagId     = DiagnosticId::sema_err_auto_scope_missing_enum_value;
            cf.srcTypeRef = TypeRef::invalid();
            cf.dstTypeRef = paramTy;
            cf.valueStr   = Utf8{sema.idMgr().get(idRef).name};
            cf.noteId     = DiagnosticId::None;
        }

        return Result::Continue;
    }

    Result resolveAutoEnumArgFinal(Sema& sema, AstNodeRef argRef, TypeRef paramTy)
    {
        const AstNodeRef argSubRef   = sema.getSubstituteRef(argRef);
        const AstNodeRef finalArgRef = argSubRef.isValid() ? argSubRef : argRef;
        const AstNode&   argNode     = sema.node(finalArgRef);
        const auto*      autoMem     = argNode.safeCast<AstAutoMemberAccessExpr>();
        if (!autoMem)
            return Result::Continue;

        const TypeInfo& paramTypeInfo = sema.typeMgr().get(paramTy);
        if (!paramTypeInfo.isEnum())
            return Result::Continue;

        const SymbolEnum& enumSym = paramTypeInfo.payloadSymEnum();
        RESULT_VERIFY(sema.waitCompleted(&enumSym, argNode.codeRef()));

        const SemaNodeView  nodeRightView(sema, autoMem->nodeIdentRef);
        const TokenRef      tokNameRef = nodeRightView.node->tokRef();
        const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), nodeRightView.node->codeRef());

        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{argNode.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &enumSym;

        // Keep normal wait semantics here (noWaitOnEmpty = false) to behave like `Enum.Value`.
        RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));
        if (lookUpCxt.empty())
            return SemaError::raise(sema, DiagnosticId::sema_err_cannot_compute_auto_scope, argRef);

        // Substitute `.Value` -> `Enum.Value` for downstream codegen / semantic checks.
        auto [memberRef, memberPtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(argNode.tokRef());
        auto [leftRef, leftPtr]     = sema.ast().makeNode<AstNodeId::Identifier>(argNode.tokRef());
        sema.setSymbol(leftRef, &enumSym);
        sema.setIsValue(*leftPtr);

        memberPtr->nodeLeftRef  = leftRef;
        memberPtr->nodeRightRef = autoMem->nodeIdentRef;

        sema.setSymbolList(memberRef, lookUpCxt.symbols());
        sema.setSymbolList(autoMem->nodeIdentRef, lookUpCxt.symbols());
        sema.setType(memberRef, paramTy);
        sema.setType(argRef, paramTy);
        sema.setSubstitute(argRef, memberRef);
        sema.setIsValue(*memberPtr);

        return Result::Continue;
    }

    uint32_t minRequiredArgs(const SymbolFunction& fn, bool ignoreVariadicTail)
    {
        const auto&    params = fn.parameters();
        const uint32_t n      = static_cast<uint32_t>(params.size());
        const uint32_t end    = (ignoreVariadicTail && n > 0) ? (n - 1) : n;

        uint32_t required = 0;
        for (uint32_t i = 0; i < end; ++i)
        {
            if (params[i]->hasExtraFlag(SymbolVariableFlagsE::Initialized))
                break; // the first default => remaining are optional
            ++required;
        }

        return required;
    }

    // Try to build a candidate; if it fails, fill out why + where.
    // Evaluate a single function symbol against the provided arguments to see if it's a valid match.
    // It determines conversion ranks, UFCS usage, and handles variadic arguments.
    Result tryBuildCandidate(Sema& sema, SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, Candidate& outCandidate, MatchFailure& outFail)
    {
        const auto&    params    = fn.parameters();
        const uint32_t numParams = static_cast<uint32_t>(params.size());
        const uint32_t numArgs   = countCallArgs(args, ufcsArg);

        outCandidate.fn = &fn;
        outCandidate.perArg.clear();
        outCandidate.usedDefaults = 0;
        outCandidate.viable       = false;
        outCandidate.ufcsUsed     = ufcsArg.isValid();

        auto&              ctx = sema.ctx();
        const VariadicInfo vi  = getVariadicInfo(sema, fn);

        CallArgMapping mapping;
        if (!buildCallArgMapping(sema, fn, args, ufcsArg, mapping, outFail))
            return Result::Continue;

        // Too many args (non-variadic only)
        if (!vi.any() && !mapping.variadicArgs.empty())
        {
            failTooMany(outFail, numParams, numArgs);
            return Result::Continue;
        }

        // Rank each provided argument (excluding the variadic parameter itself when variadic)
        const uint32_t numCommon = (vi.any() && numParams > 0) ? (numParams - 1) : numParams;
        for (uint32_t i = 0; i < numCommon; ++i)
        {
            const AstNodeRef argRef  = mapping.paramArgs[i].argRef;
            const TypeRef    paramTy = params[i]->typeRef();

            if (argRef.isInvalid())
            {
                if (!params[i]->hasExtraFlag(SymbolVariableFlagsE::Initialized))
                {
                    const uint32_t minExpected = minRequiredArgs(fn, vi.any());
                    failTooFew(outFail, minExpected, numArgs, i);
                    return Result::Continue;
                }

                outCandidate.usedDefaults++;
                continue;
            }

            CastFailure cf{};
            TypeRef     argTy = sema.typeRefOf(argRef);
            if (argTy.isInvalid())
            {
                const SemaNodeView argNodeView(sema, argRef);
                if (argNodeView.cstRef.isValid())
                    argTy = sema.cstMgr().get(argNodeView.cstRef).typeRef();
            }

            if (argTy.isInvalid())
            {
                AutoEnumArgProbe probe;
                RESULT_VERIFY(probeAutoEnumArg(sema, argRef, paramTy, probe, cf));
                if (probe.matched)
                    argTy = probe.typeRef;
            }

            if (argTy.isInvalid())
            {
                // Likely an unresolved auto-member (`.Value`) without a type hint.
                // Consider it not viable for this overload.
                if (cf.diagId == DiagnosticId::None)
                {
                    cf.diagId     = DiagnosticId::sema_err_cannot_cast;
                    cf.srcTypeRef = argTy;
                    cf.dstTypeRef = paramTy;
                }
                failBadType(outFail, mapping.paramArgs[i].callArgIndex, i, cf);
                return Result::Continue;
            }

            const bool isUfcsArgument = ufcsArg.isValid() && i == 0;
            ConvRank   r              = ConvRank::Bad;
            RESULT_VERIFY(probeImplicitConversion(sema, r, argRef, argTy, paramTy, cf, isUfcsArgument));
            if (r == ConvRank::Bad)
            {
                if (cf.diagId == DiagnosticId::None)
                {
                    cf.diagId     = DiagnosticId::sema_err_cannot_cast;
                    cf.srcTypeRef = argTy;
                    cf.dstTypeRef = paramTy;
                }
                failBadType(outFail, mapping.paramArgs[i].callArgIndex, i, cf);
                return Result::Continue;
            }
            outCandidate.perArg.push_back(r);
        }

        // Handle variadic tail
        if (vi.any() && numParams > 0 && !mapping.variadicArgs.empty())
        {
            if (vi.isVariadic)
            {
                for ([[maybe_unused]] const auto& entry : mapping.variadicArgs)
                    outCandidate.perArg.push_back(ConvRank::Ellipsis);
            }
            else
            {
                const uint32_t startVariadic = numParams - 1;
                const TypeRef  variadicTy    = params.back()->type(ctx).payloadTypeRef();

                for (const auto& entry : mapping.variadicArgs)
                {
                    const AstNodeRef argRef = entry.argRef;
                    const TypeRef    argTy  = sema.typeRefOf(argRef);
                    CastFailure cf{};
                    ConvRank    r = ConvRank::Bad;
                    RESULT_VERIFY(probeImplicitConversion(sema, r, argRef, argTy, variadicTy, cf, false));
                    if (r == ConvRank::Bad)
                    {
                        if (cf.diagId == DiagnosticId::None)
                        {
                            cf.diagId     = DiagnosticId::sema_err_cannot_cast;
                            cf.srcTypeRef = argTy;
                            cf.dstTypeRef = variadicTy;
                        }
                        // paramIndex points at the variadic parameter
                        failBadType(outFail, entry.callArgIndex, startVariadic, cf);
                        return Result::Continue;
                    }
                    outCandidate.perArg.push_back(r);
                }
            }
        }

        outCandidate.viable = true;
        return Result::Continue;
    }

    // Compares two candidates and returns -1 if 'a' is better than 'b', 1 if 'b' is better, or 0 if they are equivalent.
    // Selection is based on:
    // 1. Better conversion ranks (Exact > Standard > Bad)
    // 2. UFCS usage (non-UFCS is generally preferred)
    // 3. Number of default arguments used (fewer is better)
    int compareCandidates(const Candidate& a, const Candidate& b)
    {
        const uint32_t na = static_cast<uint32_t>(a.perArg.size());
        const uint32_t nb = static_cast<uint32_t>(b.perArg.size());
        const uint32_t n  = std::min(na, nb);

        for (uint32_t i = 0; i < n; ++i)
        {
            if (a.perArg[i] != b.perArg[i])
                return (a.perArg[i] < b.perArg[i]) ? -1 : 1;
        }

        if (na != nb)
            return (na < nb) ? -1 : 1;

        // Tie-breaker: prefer fewer defaults used
        if (a.usedDefaults != b.usedDefaults)
            return (a.usedDefaults < b.usedDefaults) ? -1 : 1;

        return 0;
    }

    // Evaluate each function symbol to see how well it matches the given arguments.
    // This includes checking the number of parameters, types, and potential UFCS usage.
    Result collectAttempts(Sema& sema, SmallVector<Attempt>& outAttempts, SmallVector<SymbolFunction*>& outFunctionSymbols, std::span<Symbol*> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        outAttempts.clear();
        outFunctionSymbols.clear();

        for (Symbol* s : symbols)
        {
            if (!s)
                continue;

            SymbolFunction* fn = nullptr;
            if (s->isFunction())
            {
                fn = &s->cast<SymbolFunction>();
            }
            else if (s->isVariable())
            {
                const auto& type = s->type(sema.ctx());
                if (type.isFunction())
                    fn = &type.payloadSymFunction();
            }

            if (!fn)
                continue;

            outFunctionSymbols.push_back(fn);

            Attempt a;
            a.fn = fn;

            MatchFailure fail;
            Candidate    candidate;

            // First: non-UFCS call shape.
            RESULT_VERIFY(tryBuildCandidate(sema, *fn, args, AstNodeRef::invalid(), candidate, fail));
            if (candidate.viable)
            {
                a.viable    = true;
                a.candidate = std::move(candidate);
            }
            else if (ufcsArg.isValid())
            {
                // Second: UFCS call shape (implicit arg0).
                candidate = {};
                fail      = {};
                RESULT_VERIFY(tryBuildCandidate(sema, *fn, args, ufcsArg, candidate, fail));
                if (candidate.viable)
                {
                    a.viable    = true;
                    a.candidate = std::move(candidate);
                }
                else
                {
                    a.viable = false;
                    a.fail   = fail;
                }
            }
            else
            {
                a.viable = false;
                a.fail   = fail;
            }

            outAttempts.push_back(std::move(a));
        }

        return Result::Continue;
    }
}

namespace
{
    void gatherViableAttempts(const SmallVector<Attempt>& attempts, SmallVector<const Attempt*>& outViable)
    {
        outViable.clear();
        outViable.reserve(attempts.size());
        for (const Attempt& a : attempts)
        {
            if (a.viable)
                outViable.push_back(&a);
        }
    }

    uint32_t numCommonParamsForFinalize(const TypeInfo& fnType, uint32_t numParams)
    {
        if (!fnType.isAnyVariadic())
            return numParams;
        if (numParams == 0)
            return 0;
        return numParams - 1;
    }

    Result finalizeAutoEnumArgs(Sema& sema, const SymbolFunction& selectedFn, const CallArgMapping& mapping)
    {
        const TypeInfo& selectedFnType = selectedFn.type(sema.ctx());
        const auto&     params         = selectedFn.parameters();
        const uint32_t  numParams      = static_cast<uint32_t>(params.size());
        const uint32_t  commonParams   = numCommonParamsForFinalize(selectedFnType, numParams);

        for (uint32_t i = 0; i < commonParams; ++i)
        {
            const AstNodeRef argRef  = mapping.paramArgs[i].argRef;
            const TypeRef    paramTy = params[i]->typeRef();
            if (argRef.isValid())
                RESULT_VERIFY(resolveAutoEnumArgFinal(sema, argRef, paramTy));
        }

        return Result::Continue;
    }

    Result raiseAmbiguousBest(Sema& sema, AstNodeRef calleeRef, const SmallVector<const Attempt*>& viable, const Candidate& best)
    {
        SmallVector<const Symbol*> ambiguousSymbols;
        for (const Attempt* a : viable)
        {
            if (compareCandidates(a->candidate, best) == 0)
                ambiguousSymbols.push_back(a->candidate.fn);
        }

        return SemaError::raiseAmbiguousSymbol(sema, calleeRef, ambiguousSymbols);
    }

    Result raiseNoSelection(Sema& sema, const SemaNodeView& nodeCallee, const SmallVector<SymbolFunction*>& functions, const SmallVector<Attempt>& attempts, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        if (functions.empty())
            return errorNotCallable(sema, nodeCallee);
        if (functions.size() == 1)
            return errorBadMatch(sema, nodeCallee, *attempts.front().fn, attempts.front().fail, args, ufcsArg);
        return errorNoOverloadMatch(sema, nodeCallee, attempts, args, ufcsArg);
    }

    // From a list of viable candidates, select the single best one based on conversion ranks
    // and other criteria. If there's no clear winner (ambiguity), or no viable candidate,
    // it raises the appropriate error.
    Result selectBestAttempt(Sema& sema, const SemaNodeView& nodeCallee, const SmallVector<const Attempt*>& viable, const SmallVector<SymbolFunction*>& functions, const SmallVector<Attempt>& attempts, std::span<AstNodeRef> args, AstNodeRef ufcsArg, const Attempt*& outSelected)
    {
        if (viable.empty())
            return raiseNoSelection(sema, nodeCallee, functions, attempts, args, ufcsArg);

        outSelected    = viable[0];
        bool ambiguous = false;

        for (size_t i = 1; i < viable.size(); ++i)
        {
            const int cmp = compareCandidates(viable[i]->candidate, outSelected->candidate);
            if (cmp < 0)
            {
                outSelected = viable[i];
                ambiguous   = false;
            }
            else if (cmp == 0)
            {
                ambiguous = true;
            }
        }

        if (ambiguous)
            return raiseAmbiguousBest(sema, nodeCallee.nodeRef, viable, outSelected->candidate);

        return Result::Continue;
    }

    // For each argument, perform the required cast to the destination parameter type.
    // The cast value is then stored back in the argument node.
    Result applyParameterCasts(Sema& sema, const SymbolFunction& selectedFn, const CallArgMapping& mapping, AstNodeRef appliedUfcsArg)
    {
        const TypeInfo& selectedFnType = selectedFn.type(sema.ctx());
        const auto&     params         = selectedFn.parameters();
        const uint32_t  numParams      = static_cast<uint32_t>(params.size());
        const uint32_t  numCommon      = selectedFnType.isAnyVariadic() ? (numParams - 1) : numParams;

        for (uint32_t i = 0; i < numCommon; ++i)
        {
            const AstNodeRef argRef = mapping.paramArgs[i].argRef;
            if (argRef.isInvalid())
                continue;

            SemaNodeView argView(sema, argRef);
            CastFlags    flags = CastFlagsE::Zero;
            if (appliedUfcsArg.isValid() && i == 0)
                flags.add(CastFlagsE::UfcsArgument);
            RESULT_VERIFY(Cast::cast(sema, argView, params[i]->typeRef(), CastKind::Parameter, flags));
        }

        return Result::Continue;
    }

    // For typed variadic functions (e.g., `func(x: ...int)`), each extra argument
    // must be cast to the underlying variadic type.
    Result applyTypedVariadicCasts(Sema& sema, const SymbolFunction& selectedFn, const CallArgMapping& mapping)
    {
        const TypeInfo& selectedFnType = selectedFn.type(sema.ctx());
        if (!selectedFnType.isTypedVariadic())
            return Result::Continue;

        const uint32_t numParams = static_cast<uint32_t>(selectedFn.parameters().size());
        if (numParams == 0)
            return Result::Continue;

        const TypeRef variadicTy = selectedFnType.payloadTypeRef();

        for (const auto& entry : mapping.variadicArgs)
        {
            SemaNodeView argView(sema, entry.argRef);
            RESULT_VERIFY(Cast::cast(sema, argView, variadicTy, CastKind::Implicit));
        }

        return Result::Continue;
    }
}

Result Match::resolveFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
{
    // Collect all function candidates and evaluate their match quality
    SmallVector<Attempt>         attempts;
    SmallVector<SymbolFunction*> functions;
    RESULT_VERIFY(collectAttempts(sema, attempts, functions, symbols, args, ufcsArg));

    // Filter to keep only those that are compatible (viable)
    SmallVector<const Attempt*> viable;
    gatherViableAttempts(attempts, viable);

    // From the viable ones, find the single best candidate.
    // This will raise an error if there are no viable candidates or if the best choice is ambiguous.
    const Attempt* selectedAttempt = nullptr;
    RESULT_VERIFY(selectBestAttempt(sema, nodeCallee, viable, functions, attempts, args, ufcsArg, selectedAttempt));

    // Finalize the selection by applying required casts and conversions to the arguments
    const AstNodeRef      appliedUfcsArg = selectedAttempt->candidate.ufcsUsed ? ufcsArg : AstNodeRef::invalid();
    const SymbolFunction* selectedFn     = selectedAttempt->candidate.fn;
    CallArgMapping        mapping;
    MatchFailure          mappingFail;
    if (!buildCallArgMapping(sema, *selectedFn, args, appliedUfcsArg, mapping, mappingFail))
        return errorBadMatch(sema, nodeCallee, *selectedFn, mappingFail, args, appliedUfcsArg);

    RESULT_VERIFY(finalizeAutoEnumArgs(sema, *selectedFn, mapping));
    RESULT_VERIFY(applyParameterCasts(sema, *selectedFn, mapping, appliedUfcsArg));
    RESULT_VERIFY(applyTypedVariadicCasts(sema, *selectedFn, mapping));

    sema.setSymbol(sema.curNodeRef(), selectedFn);
    sema.setIsValue(sema.node(sema.curNodeRef()));
    return Result::Continue;
}

SWC_END_NAMESPACE();
