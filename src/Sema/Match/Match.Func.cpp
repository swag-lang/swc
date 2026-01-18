#include "pch.h"
#include "Sema/Match/Match.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Core/Sema.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbol.Function.h"
#include "Sema/Symbol/Symbol.Variable.h"
#include "Sema/Type/TypeInfo.h"

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

    DiagnosticId addCastFailureArgs(DiagnosticElement& e, const CastFailure& cf)
    {
        if (cf.srcTypeRef.isValid())
            e.addArgument(Diagnostic::ARG_TYPE, cf.srcTypeRef);
        if (cf.dstTypeRef.isValid())
            e.addArgument(Diagnostic::ARG_REQUESTED_TYPE, cf.dstTypeRef);
        if (cf.optTypeRef.isValid())
            e.addArgument(Diagnostic::ARG_OPT_TYPE, cf.optTypeRef);
        e.addArgument(Diagnostic::ARG_VALUE, cf.valueStr);
        return cf.noteId;
    }

    ConvRank probeImplicitConversion(Sema& sema, TypeRef from, TypeRef to, CastFailure& outCastFailure)
    {
        if (from == to)
            return ConvRank::Exact;

        CastContext castCtx(CastKind::Implicit);
        if (Cast::castAllowed(sema, castCtx, from, to) == Result::Continue)
            return ConvRank::Standard;

        outCastFailure = castCtx.failure;
        return ConvRank::Bad;
    }

    // Try to build a candidate; if it fails, fill out why + where.
    bool tryBuildCandidate(Sema& sema, SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, Candidate& outCandidate, MatchFailure& outFail)
    {
        const auto&    params    = fn.parameters();
        const uint32_t numParams = static_cast<uint32_t>(params.size());

        uint32_t numArgs = static_cast<uint32_t>(args.size());
        if (ufcsArg.isValid())
            numArgs++;

        outCandidate.fn = &fn;
        outCandidate.perArg.clear();
        outCandidate.usedDefaults = 0;
        outCandidate.viable       = false;

        auto&              ctx = sema.ctx();
        const VariadicInfo vi  = getVariadicInfo(sema, fn);

        // Too many args (non-variadic only)
        if (numArgs > numParams && !vi.any())
        {
            failTooMany(outFail, numParams, numArgs);
            return false;
        }

        // Rank each provided argument (excluding the variadic parameter itself when variadic)
        const uint32_t numCommon = vi.any() && numParams > 0 ? (numParams - 1) : numParams;
        const uint32_t upto      = std::min(numArgs, numCommon);

        for (uint32_t i = 0; i < upto; ++i)
        {
            AstNodeRef argRef;
            if (ufcsArg.isValid())
            {
                if (i == 0)
                    argRef = ufcsArg;
                else
                    argRef = args[i - 1];
            }
            else
            {
                argRef = args[i];
            }

            const TypeRef argTy   = sema.typeRefOf(argRef);
            const TypeRef paramTy = params[i]->typeRef();

            CastFailure    cf{};
            const ConvRank r = probeImplicitConversion(sema, argTy, paramTy, cf);
            if (r == ConvRank::Bad)
            {
                failBadType(outFail, i, i, cf);
                return false;
            }
            outCandidate.perArg.push_back(r);
        }

        // Handle variadic tail
        if (vi.any() && numParams > 0)
        {
            const uint32_t startVariadic = numParams - 1;
            if (numArgs >= numParams)
            {
                TypeRef variadicTy = TypeRef::invalid();
                if (vi.isTypedVariadic)
                    variadicTy = params.back()->type(ctx).typeRef();

                for (uint32_t i = startVariadic; i < numArgs; ++i)
                {
                    if (vi.isVariadic)
                    {
                        outCandidate.perArg.push_back(ConvRank::Ellipsis);
                    }
                    else
                    {
                        AstNodeRef argRef;
                        if (ufcsArg.isValid())
                            argRef = (i == 0) ? ufcsArg : args[i - 1];
                        else
                            argRef = args[i];

                        const TypeRef  argTy = sema.typeRefOf(argRef);
                        CastFailure    cf{};
                        const ConvRank r = probeImplicitConversion(sema, argTy, variadicTy, cf);
                        if (r == ConvRank::Bad)
                        {
                            // paramIndex points at the variadic parameter
                            failBadType(outFail, i, startVariadic, cf);
                            return false;
                        }
                        outCandidate.perArg.push_back(r);
                    }
                }
            }
        }

        // Remaining params must be defaulted/initialized (excluding the variadic parameter itself)
        const uint32_t numParamsToCheck = vi.any() && numParams > 0 ? (numParams - 1) : numParams;
        for (uint32_t i = numArgs; i < numParamsToCheck; ++i)
        {
            if (!params[i]->hasExtraFlag(SymbolVariableFlagsE::Initialized))
            {
                const uint32_t minExpected = minRequiredArgs(fn, vi.any());
                failTooFew(outFail, minExpected, numArgs, i);
                return false;
            }
            outCandidate.usedDefaults++;
        }

        outCandidate.viable = true;
        return true;
    }

    // Compare candidates: "best" is the one with the better (smaller) rank for the first differing arg.
    // Tie-breakers can include fewer defaults, non-template, more specialized, etc.
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

    void collectAttempts(Sema& sema, SmallVector<Attempt>& outAttempts, SmallVector<SymbolFunction*>& outFunctionSymbols, std::span<Symbol*> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        outAttempts.clear();
        outFunctionSymbols.clear();

        for (Symbol* s : symbols)
        {
            if (!s || !s->isFunction())
                continue;

            auto& fn = s->cast<SymbolFunction>();
            outFunctionSymbols.push_back(&fn);

            Attempt a;
            a.fn = &fn;

            MatchFailure fail;
            Candidate    candidate;

            if (tryBuildCandidate(sema, fn, args, ufcsArg, candidate, fail))
            {
                a.viable    = true;
                a.candidate = std::move(candidate);
            }
            else
            {
                a.viable = false;
                a.fail   = fail;
            }

            outAttempts.push_back(std::move(a));
        }
    }

    Result emitNotCallable(Sema& sema, const SemaNodeView& nodeCallee)
    {
        const auto diag = SemaError::report(sema, DiagnosticId::sema_err_not_callable, nodeCallee.nodeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result emitBadMatch(Sema& sema, const SemaNodeView& nodeCallee, const SymbolFunction& fn, const MatchFailure& fail, std::span<AstNodeRef> args)
    {
        const auto& ctx = sema.ctx();

        Diagnostic diag;
        switch (fail.kind)
        {
            case MatchFailKind::TooManyArguments:
                diag = SemaError::report(sema, DiagnosticId::sema_err_too_many_arguments, nodeCallee.nodeRef);
                diag.addArgument(Diagnostic::ARG_COUNT, fail.expectedCount);
                diag.addArgument(Diagnostic::ARG_VALUE, fail.providedCount);
                break;

            case MatchFailKind::TooFewArguments:
                diag = SemaError::report(sema, DiagnosticId::sema_err_too_few_arguments, nodeCallee.nodeRef);
                diag.addArgument(Diagnostic::ARG_COUNT, fail.expectedCount);
                diag.addArgument(Diagnostic::ARG_VALUE, fail.providedCount);
                break;

            case MatchFailKind::InvalidArgumentType:
                if (fail.castFailure.diagId != DiagnosticId::None)
                {
                    diag = SemaError::report(sema, fail.castFailure.diagId, nodeCallee.nodeRef);
                    if (const DiagnosticId nid = addCastFailureArgs(diag.last(), fail.castFailure); nid != DiagnosticId::None)
                        diag.addNote(nid);
                }
                else
                {
                    diag = SemaError::report(sema, DiagnosticId::sema_err_bad_function_match, nodeCallee.nodeRef);
                    diag.addArgument(Diagnostic::ARG_SYM, fn.name(ctx));
                }
                break;

            default:
                diag = SemaError::report(sema, DiagnosticId::sema_err_bad_function_match, nodeCallee.nodeRef);
                diag.addArgument(Diagnostic::ARG_SYM, fn.name(ctx));
                break;
        }

        if (fail.hasLocation && fail.argIndex < args.size())
            diag.last().addSpan(sema.node(args[fail.argIndex]).location(ctx));

        diag.report(sema.ctx());
        return Result::Error;
    }

    Result emitNoOverloadMatch(Sema& sema, const SemaNodeView& nodeCallee, const SmallVector<Attempt>& attempts, std::span<AstNodeRef> args)
    {
        auto& ctx  = sema.ctx();
        auto  diag = SemaError::report(sema, DiagnosticId::sema_err_no_overload_match, nodeCallee.nodeRef);

        // One note per overload attempt describing why it failed (and where when possible).
        for (const Attempt& a : attempts)
        {
            if (!a.fn || a.viable)
                continue;

            diag.addNote(DiagnosticId::sema_note_overload_candidate_failed);
            auto& note = diag.last();
            note.addArgument(Diagnostic::ARG_SYM, a.fn->type(ctx).toName(ctx));

            switch (a.fail.kind)
            {
                case MatchFailKind::TooManyArguments:
                    note.addArgument(Diagnostic::ARG_WHAT, Diagnostic::diagIdMessage(DiagnosticId::sema_note_too_many_arguments));
                    note.addArgument(Diagnostic::ARG_COUNT, a.fail.expectedCount);
                    note.addArgument(Diagnostic::ARG_VALUE, a.fail.providedCount);
                    break;

                case MatchFailKind::TooFewArguments:
                    note.addArgument(Diagnostic::ARG_WHAT, Diagnostic::diagIdMessage(DiagnosticId::sema_note_too_few_arguments));
                    note.addArgument(Diagnostic::ARG_COUNT, a.fail.expectedCount);
                    note.addArgument(Diagnostic::ARG_VALUE, a.fail.providedCount);
                    break;

                case MatchFailKind::InvalidArgumentType:
                    if (a.fail.castFailure.diagId != DiagnosticId::None)
                    {
                        note.addArgument(Diagnostic::ARG_WHAT, Diagnostic::diagIdMessage(a.fail.castFailure.diagId));
                        if (const DiagnosticId nid = addCastFailureArgs(note, a.fail.castFailure); nid != DiagnosticId::None)
                            diag.addNote(nid);
                    }
                    else
                    {
                        note.addArgument(Diagnostic::ARG_WHAT, Diagnostic::diagIdMessage(DiagnosticId::sema_note_invalid_argument_type));
                    }
                    break;

                default:
                    note.addArgument(Diagnostic::ARG_WHAT, Diagnostic::diagIdMessage(DiagnosticId::sema_note_not_viable));
                    break;
            }

            if (a.fail.hasLocation && a.fail.argIndex < args.size())
                diag.last().addSpan(sema.node(args[a.fail.argIndex]).location(ctx));
        }

        diag.report(sema.ctx());
        return Result::Error;
    }
}

Result Match::resolveFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
{
    SmallVector<Attempt>         attempts;
    SmallVector<SymbolFunction*> functions;
    collectAttempts(sema, attempts, functions, symbols, args, ufcsArg);

    // Gather viable candidates
    SmallVector<const Attempt*> viable;
    viable.reserve(attempts.size());
    for (const Attempt& a : attempts)
    {
        if (a.viable)
            viable.push_back(&a);
    }

    // If we have viable overload candidates: pick the best (or ambiguous)
    SymbolFunction* selectedFn = nullptr;
    if (!viable.empty())
    {
        const Attempt* best = viable[0];
        bool           tie  = false;

        for (uint32_t i = 1; i < static_cast<uint32_t>(viable.size()); ++i)
        {
            const int cmp = compareCandidates(viable[i]->candidate, best->candidate);
            if (cmp < 0)
            {
                best = viable[i];
                tie  = false;
            }
            else if (cmp == 0)
            {
                tie = true;
            }
        }

        if (tie)
        {
            SmallVector<Symbol*> ambiguousSymbols;
            for (const Attempt* a : viable)
            {
                if (compareCandidates(a->candidate, best->candidate) == 0)
                    ambiguousSymbols.push_back(a->candidate.fn);
            }

            return SemaError::raiseAmbiguousSymbol(sema, nodeCallee.nodeRef, ambiguousSymbols);
        }

        selectedFn = best->candidate.fn;
    }

    // No viable overload selected -> decide which error to raise
    if (!selectedFn)
    {
        // No function symbols at all in "symbols" -> "not callable"
        if (functions.empty())
            return emitNotCallable(sema, nodeCallee);

        // Exactly one function symbol -> "bad match" with reason
        if (functions.size() == 1)
            return emitBadMatch(sema, nodeCallee, *attempts.front().fn, attempts.front().fail, args);

        // Multiple function symbols -> "no overload match" with per-overload failure notes
        return emitNoOverloadMatch(sema, nodeCallee, attempts, args);
    }

    // Apply implicit conversions + handle defaults (already validated by tryBuildCandidate)
    const auto& params    = selectedFn->parameters();
    const auto  numParams = static_cast<uint32_t>(params.size());

    uint32_t numArgs = static_cast<uint32_t>(args.size());
    if (ufcsArg.isValid())
        numArgs++;

    const auto& selectedFnT = selectedFn->type(sema.ctx());

    const uint32_t numCommon = selectedFnT.isAnyVariadic() ? numParams - 1 : numParams;
    for (uint32_t i = 0; i < std::min(numArgs, numCommon); ++i)
    {
        AstNodeRef argRef;
        if (ufcsArg.isValid())
            argRef = (i == 0) ? ufcsArg : args[i - 1];
        else
            argRef = args[i];

        SemaNodeView argView(sema, argRef);
        RESULT_VERIFY(Cast::cast(sema, argView, params[i]->typeRef(), CastKind::Implicit));

        if (ufcsArg.isValid() && i == 0)
        {
            // Note: ufcsArg is currently just a potential first argument.
            // If it matches, it might need to be explicitly handled by the caller or somehow integrated.
            // For now, we follow the logic that it's treated as the first argument.
        }
        else
        {
            args[ufcsArg.isValid() ? i - 1 : i] = argView.nodeRef;
        }
    }

    if (selectedFnT.isTypedVariadic())
    {
        const uint32_t startVariadic = numParams - 1;
        const TypeRef  variadicTy    = selectedFnT.typeRef();
        for (uint32_t i = startVariadic; i < numArgs; ++i)
        {
            AstNodeRef argRef;
            if (ufcsArg.isValid())
                argRef = (i == 0) ? ufcsArg : args[i - 1];
            else
                argRef = args[i];

            SemaNodeView argView(sema, argRef);
            RESULT_VERIFY(Cast::cast(sema, argView, variadicTy, CastKind::Implicit));

            if (ufcsArg.isValid() && i == 0)
            {
                // Should not happen for typed variadic usually (variadic is at the end),
                // unless it's a very strange function with only one variadic param.
            }
            else
            {
                args[ufcsArg.isValid() ? i - 1 : i] = argView.nodeRef;
            }
        }
    }

    sema.setType(sema.curNodeRef(), selectedFn->returnType());
    SemaInfo::setIsValue(sema.node(sema.curNodeRef()));
    return Result::Continue;
}

SWC_END_NAMESPACE();
