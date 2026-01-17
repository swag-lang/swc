#include "pch.h"
#include "Sema/Symbol/Match.h"
#include "Sema/Core/Sema.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Type/Cast.h"
#include "Sema/Type/TypeInfo.h"
#include "Symbol.Function.h"
#include "Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class ConvRank : uint8_t
    {
        Exact    = 0, // same type (or identical canonical type)
        Promo    = 1, // e.g. smaller int -> bigger int, bool->int, etc.
        Standard = 2, // safe numeric, pointer decay, etc.
        User     = 3, // user-defined conversion (if you have it)
        Ellipsis = 4, // varargs fallback (if you support it)
        Bad      = 255
    };

    enum class MatchFailKind : uint8_t
    {
        TooManyArguments,
        TooFewArguments,
        InvalidArgumentType, // cannot convert arg -> param
        NotAFunction
    };

    struct MatchFailure
    {
        MatchFailKind kind          = MatchFailKind::InvalidArgumentType;
        uint32_t      argIndex      = 0; // where it failed (argument index)
        uint32_t      paramIndex    = 0; // where it failed (parameter index)
        uint32_t      expectedCount = 0; // for too many/few
        uint32_t      providedCount = 0; // for too many/few
        bool          hasLocation   = false;
    };

    struct Candidate
    {
        SymbolFunction*       fn = nullptr;
        SmallVector<ConvRank> perArg;
        uint32_t              usedDefaults = 0;
        bool                  viable       = false;
    };

    struct Attempt
    {
        SymbolFunction* fn     = nullptr;
        Candidate       cand   = {};
        bool            viable = false;
        MatchFailure    fail   = {};
    };

    // Probe: must NOT mutate AST, must NOT emit diagnostics.
    ConvRank probeImplicitConversion(Sema& sema, TypeRef from, TypeRef to)
    {
        if (from == to)
            return ConvRank::Exact;

        CastContext castCtx(CastKind::Implicit);
        if (Cast::castAllowed(sema, castCtx, from, to) == Result::Continue)
            return ConvRank::Standard;

        return ConvRank::Bad;
    }

    // Try to build a candidate; if it fails, fill out why + where.
    bool tryBuildCandidate(Sema&                 sema,
                           SymbolFunction&       fn,
                           std::span<AstNodeRef> args,
                           Candidate&            outCand,
                           MatchFailure&         outFail)
    {
        const auto&    params    = fn.parameters();
        const uint32_t numArgs   = static_cast<uint32_t>(args.size());
        const uint32_t numParams = static_cast<uint32_t>(params.size());

        outCand.fn = &fn;
        outCand.perArg.clear();
        outCand.usedDefaults = 0;
        outCand.viable       = false;

        // Too many args (no varargs support here)
        if (numArgs > numParams)
        {
            outFail.kind          = MatchFailKind::TooManyArguments;
            outFail.expectedCount = numParams;
            outFail.providedCount = numArgs;
            outFail.argIndex      = numParams; // first "extra" argument
            outFail.paramIndex    = numParams;
            outFail.hasLocation   = true;
            return false;
        }

        // Rank each provided argument
        for (uint32_t i = 0; i < numArgs; ++i)
        {
            const TypeRef argTy   = sema.typeRefOf(args[i]);
            const TypeRef paramTy = params[i]->typeRef();

            const ConvRank r = probeImplicitConversion(sema, argTy, paramTy);
            if (r == ConvRank::Bad)
            {
                outFail.kind        = MatchFailKind::InvalidArgumentType;
                outFail.argIndex    = i;
                outFail.paramIndex  = i;
                outFail.hasLocation = true;
                return false;
            }

            outCand.perArg.push_back(r);
        }

        // Remaining params must be defaulted/initialized
        for (uint32_t i = numArgs; i < numParams; ++i)
        {
            if (!params[i]->hasExtraFlag(SymbolVariableFlagsE::Initialized))
            {
                outFail.kind          = MatchFailKind::TooFewArguments;
                outFail.expectedCount = numParams;
                outFail.providedCount = numArgs;
                outFail.argIndex      = numArgs; // first missing
                outFail.paramIndex    = i;       // missing parameter index
                outFail.hasLocation   = false;
                return false;
            }
            outCand.usedDefaults++;
        }

        outCand.viable = true;
        return true;
    }

    // Compare candidates: "best" is the one with better (smaller) rank for the first differing arg.
    // Tie-breakers can include fewer defaults, non-template, more specialized, etc.
    int compareCandidates(const Candidate& a, const Candidate& b)
    {
        const uint32_t n = static_cast<uint32_t>(a.perArg.size());
        for (uint32_t i = 0; i < n; ++i)
        {
            if (a.perArg[i] != b.perArg[i])
                return (a.perArg[i] < b.perArg[i]) ? -1 : 1;
        }

        // Tie-breaker: prefer fewer defaults used
        if (a.usedDefaults != b.usedDefaults)
            return (a.usedDefaults < b.usedDefaults) ? -1 : 1;
        return 0;
    }

    void collectAttempts(Sema&                         sema,
                         std::span<Symbol*>            symbols,
                         std::span<AstNodeRef>         args,
                         SmallVector<Attempt>&         outAttempts,
                         SmallVector<SymbolFunction*>& outFunctionSyms)
    {
        outAttempts.clear();
        outFunctionSyms.clear();

        for (Symbol* s : symbols)
        {
            if (!s)
                continue;

            if (!s->isFunction())
                continue;

            auto& fn = s->cast<SymbolFunction>();
            outFunctionSyms.push_back(&fn);

            Attempt a;
            a.fn = &fn;

            MatchFailure fail;
            Candidate    cand;

            if (tryBuildCandidate(sema, fn, args, cand, fail))
            {
                a.viable = true;
                a.cand   = std::move(cand);
            }
            else
            {
                a.viable = false;
                a.fail   = fail;
            }

            outAttempts.push_back(std::move(a));
        }
    }

    void emitNotCallable(Sema& sema, const SemaNodeView& nodeCallee)
    {
        auto        diag    = SemaError::report(sema, DiagnosticId::sema_err_not_callable, nodeCallee.nodeRef);
        const auto& srcView = sema.srcView(nodeCallee.node->srcViewRef());
        diag.addArgument(Diagnostic::ARG_SYM, srcView.token(nodeCallee.node->tokRef()).string(srcView));
        diag.report(sema.ctx());
    }

    void emitBadMatch(Sema& sema, const SemaNodeView& nodeCallee, SymbolFunction& fn, const MatchFailure& fail, std::span<AstNodeRef> args)
    {
        const auto ctx = sema.ctx();

        // Main error
        Diagnostic diag;
        switch (fail.kind)
        {
            case MatchFailKind::TooManyArguments:
                diag = SemaError::report(sema, DiagnosticId::sema_err_too_many_arguments, nodeCallee.nodeRef);
                diag.addArgument(Diagnostic::ARG_COUNT, std::to_string(fail.expectedCount));
                diag.addArgument(Diagnostic::ARG_VALUE, std::to_string(fail.providedCount));
                break;

            case MatchFailKind::TooFewArguments:
                diag = SemaError::report(sema, DiagnosticId::sema_err_too_few_arguments, nodeCallee.nodeRef);
                diag.addArgument(Diagnostic::ARG_COUNT, std::to_string(fail.expectedCount));
                diag.addArgument(Diagnostic::ARG_VALUE, std::to_string(fail.providedCount));
                break;

            case MatchFailKind::InvalidArgumentType:
                diag = SemaError::report(sema, DiagnosticId::sema_err_bad_function_match, nodeCallee.nodeRef);
                diag.addArgument(Diagnostic::ARG_SYM, fn.name(ctx));
                break;

            default:
                diag = SemaError::report(sema, DiagnosticId::sema_err_bad_function_match, nodeCallee.nodeRef);
                diag.addArgument(Diagnostic::ARG_SYM, fn.name(ctx));
                break;
        }

        diag.report(sema.ctx());

        // Optional pinpoint note to the argument node if we have it.
        if (fail.kind == MatchFailKind::TooManyArguments && fail.hasLocation && fail.argIndex < args.size())
        {
            auto note = SemaError::report(sema, DiagnosticId::sema_note_candidate_failed_here, args[fail.argIndex]);
            note.addArgument(Diagnostic::ARG_SYM, fn.name(ctx));
            note.report(sema.ctx());
        }
        else if (fail.kind == MatchFailKind::InvalidArgumentType && fail.hasLocation && fail.argIndex < args.size())
        {
            auto note = SemaError::report(sema, DiagnosticId::sema_note_candidate_failed_here, args[fail.argIndex]);
            note.addArgument(Diagnostic::ARG_SYM, fn.name(ctx));
            // note.addArgument(Diagnostic::ARG_INDEX, std::to_string(fail.argIndex));
            note.report(sema.ctx());
        }
    }

    void emitNoOverloadMatch(Sema& sema, const SemaNodeView& nodeCallee, const SmallVector<Attempt>& attempts, std::span<AstNodeRef> args)
    {
        const auto& ctx = sema.ctx();

        const auto diag = SemaError::report(sema, DiagnosticId::sema_err_no_overload_match, nodeCallee.nodeRef);
        diag.report(sema.ctx());

        // One note per overload attempt describing why it failed (and where when possible).
        for (const Attempt& a : attempts)
        {
            if (!a.fn || a.viable)
                continue;

            auto note = SemaError::report(sema, DiagnosticId::sema_note_overload_candidate_failed, nodeCallee.nodeRef);
            note.addArgument(Diagnostic::ARG_SYM, a.fn->name(ctx));

            switch (a.fail.kind)
            {
                case MatchFailKind::TooManyArguments:
                    note.addArgument(Diagnostic::ARG_WHAT, "too many arguments");
                    note.addArgument(Diagnostic::ARG_COUNT, std::to_string(a.fail.expectedCount));
                    note.addArgument(Diagnostic::ARG_VALUE, std::to_string(a.fail.providedCount));
                    break;

                case MatchFailKind::TooFewArguments:
                    note.addArgument(Diagnostic::ARG_WHAT, "too few arguments");
                    note.addArgument(Diagnostic::ARG_COUNT, std::to_string(a.fail.expectedCount));
                    note.addArgument(Diagnostic::ARG_VALUE, std::to_string(a.fail.providedCount));
                    break;

                case MatchFailKind::InvalidArgumentType:
                    note.addArgument(Diagnostic::ARG_WHAT, "invalid argument type");
                    // note.addArgument(Diagnostic::ARG_INDEX, std::to_string(a.fail.argIndex));
                    break;

                default:
                    note.addArgument(Diagnostic::ARG_WHAT, "not viable");
                    break;
            }

            note.report(sema.ctx());

            // Extra pinpoint note, if we can point to a specific arg node.
            if (a.fail.hasLocation && a.fail.argIndex < args.size())
            {
                auto here = SemaError::report(sema, DiagnosticId::sema_note_candidate_failed_here, args[a.fail.argIndex]);
                here.addArgument(Diagnostic::ARG_SYM, a.fn->name(ctx));
                here.report(sema.ctx());
            }
        }
    }
}

Result Match::resolveFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<AstNodeRef> args)
{
    SmallVector<Attempt>         attempts;
    SmallVector<SymbolFunction*> functionSyms;
    collectAttempts(sema, symbols, args, attempts, functionSyms);

    // Gather viable candidates
    SmallVector<Candidate> viable;
    viable.reserve(attempts.size());
    for (const Attempt& a : attempts)
    {
        if (a.viable)
            viable.push_back(a.cand);
    }

    // If we have viable overload candidates: pick the best (or ambiguous)
    SymbolFunction* selectedFn = nullptr;
    if (!viable.empty())
    {
        Candidate* best = viable.data();
        bool       tie  = false;

        for (uint32_t i = 1; i < static_cast<uint32_t>(viable.size()); ++i)
        {
            const int cmp = compareCandidates(viable[i], *best);
            if (cmp < 0)
            {
                best = &viable[i];
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
            for (auto& c : viable)
            {
                if (compareCandidates(c, *best) == 0)
                    ambiguousSymbols.push_back(c.fn);
            }
            
            return SemaError::raiseAmbiguousSymbol(sema, nodeCallee.nodeRef, ambiguousSymbols);
        }

        selectedFn = best->fn;
    }

    // No viable overload selected -> decide which error to raise (or fallback to "callee is function type")
    if (!selectedFn)
    {
        // No function symbols at all in "symbols" -> either fallback to callee function type, or "not callable"
        if (functionSyms.empty())
        {
            if (!nodeCallee.type || !nodeCallee.type->isFunction())
            {
                emitNotCallable(sema, nodeCallee);
                return Result::Error;
            }

            // Old behavior: direct call via function-typed callee.
            selectedFn = &nodeCallee.type->symFunction();
        }
        else if (functionSyms.size() == 1)
        {
            // Exactly one function symbol -> "bad match" with reason
            const Attempt* theAttempt = nullptr;
            for (const Attempt& a : attempts)
            {
                if (a.fn == functionSyms[0])
                {
                    theAttempt = &a;
                    break;
                }
            }

            if (theAttempt && !theAttempt->viable)
            {
                emitBadMatch(sema, nodeCallee, *theAttempt->fn, theAttempt->fail, args);
                return Result::Error;
            }

            // Defensive fallback: should not happen, but keep old behavior
            emitNotCallable(sema, nodeCallee);
            return Result::Error;
        }
        else
        {
            // Multiple function symbols -> "no overload match" with per-overload failure notes
            emitNoOverloadMatch(sema, nodeCallee, attempts, args);
            return Result::Error;
        }
    }

    // Apply implicit conversions + handle defaults (should be consistent with the probe but keep real checks)
    const auto&    params    = selectedFn->parameters();
    const uint32_t numArgs   = static_cast<uint32_t>(args.size());
    const uint32_t numParams = static_cast<uint32_t>(params.size());

    // Still guard (selectedFn may come from callee function type)
    if (numArgs > numParams)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_too_many_arguments, args[numParams]);
        diag.addArgument(Diagnostic::ARG_COUNT, std::to_string(numParams));
        diag.addArgument(Diagnostic::ARG_VALUE, std::to_string(numArgs));
        diag.report(sema.ctx());
        return Result::Error;
    }

    for (uint32_t i = 0; i < numParams; ++i)
    {
        if (i < numArgs)
        {
            SemaNodeView argView(sema, args[i]);
            RESULT_VERIFY(Cast::cast(sema, argView, params[i]->typeRef(), CastKind::Implicit));
        }
        else
        {
            if (!params[i]->hasExtraFlag(SymbolVariableFlagsE::Initialized))
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_too_few_arguments, sema.curNodeRef());
                diag.addArgument(Diagnostic::ARG_COUNT, std::to_string(numParams));
                diag.addArgument(Diagnostic::ARG_VALUE, std::to_string(numArgs));
                diag.report(sema.ctx());
                return Result::Error;
            }
        }
    }

    sema.setType(sema.curNodeRef(), selectedFn->returnType());
    SemaInfo::setIsValue(sema.node(sema.curNodeRef()));
    return Result::Continue;
}

SWC_END_NAMESPACE();
