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

    ConvRank probeImplicitConversion(Sema& sema, TypeRef from, TypeRef to, CastFailure& castFailure)
    {
        if (from == to)
            return ConvRank::Exact;

        CastContext castCtx(CastKind::Implicit);
        if (Cast::castAllowed(sema, castCtx, from, to) == Result::Continue)
            return ConvRank::Standard;

        castFailure = castCtx.failure;
        return ConvRank::Bad;
    }

    // Try to build a candidate; if it fails, fill out why + where.
    bool tryBuildCandidate(Sema& sema, SymbolFunction& fn, std::span<AstNodeRef> args, Candidate& outCandidate, MatchFailure& outFail)
    {
        const auto&    params    = fn.parameters();
        const uint32_t numArgs   = static_cast<uint32_t>(args.size());
        const uint32_t numParams = static_cast<uint32_t>(params.size());

        outCandidate.fn = &fn;
        outCandidate.perArg.clear();
        outCandidate.usedDefaults = 0;
        outCandidate.viable       = false;

        auto& ctx = sema.ctx();

        // Variadic?
        bool isVariadic      = false;
        bool isTypedVariadic = false;
        if (numParams > 0)
        {
            const auto& lastParamTy = params.back()->type(ctx);
            isVariadic              = lastParamTy.isVariadic();
            isTypedVariadic         = lastParamTy.isTypedVariadic();
        }

        // Too many args
        if (numArgs > numParams && !isVariadic && !isTypedVariadic)
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
        const uint32_t numCommon = isVariadic || isTypedVariadic ? numParams - 1 : numParams;
        for (uint32_t i = 0; i < std::min(numArgs, numCommon); ++i)
        {
            const TypeRef argTy   = sema.typeRefOf(args[i]);
            const TypeRef paramTy = params[i]->typeRef();

            const ConvRank r = probeImplicitConversion(sema, argTy, paramTy, outFail.castFailure);
            if (r == ConvRank::Bad)
            {
                outFail.kind        = MatchFailKind::InvalidArgumentType;
                outFail.argIndex    = i;
                outFail.paramIndex  = i;
                outFail.hasLocation = true;
                return false;
            }

            outCandidate.perArg.push_back(r);
        }

        // Handle variadic tail
        if (isVariadic || isTypedVariadic)
        {
            const uint32_t startVariadic = numParams - 1;
            if (numArgs >= numParams)
            {
                TypeRef variadicTy = TypeRef::invalid();
                if (isTypedVariadic)
                    variadicTy = params.back()->type(ctx).typeRef();

                for (uint32_t i = startVariadic; i < numArgs; ++i)
                {
                    if (isVariadic)
                    {
                        outCandidate.perArg.push_back(ConvRank::Ellipsis);
                    }
                    else
                    {
                        const TypeRef  argTy = sema.typeRefOf(args[i]);
                        const ConvRank r     = probeImplicitConversion(sema, argTy, variadicTy, outFail.castFailure);
                        if (r == ConvRank::Bad)
                        {
                            outFail.kind        = MatchFailKind::InvalidArgumentType;
                            outFail.argIndex    = i;
                            outFail.paramIndex  = startVariadic;
                            outFail.hasLocation = true;
                            return false;
                        }
                        outCandidate.perArg.push_back(r);
                    }
                }
            }
        }

        // Remaining params must be defaulted/initialized
        const uint32_t numParamsToCheck = (isVariadic || isTypedVariadic) ? numParams - 1 : numParams;
        for (uint32_t i = numArgs; i < numParamsToCheck; ++i)
        {
            if (!params[i]->hasExtraFlag(SymbolVariableFlagsE::Initialized))
            {
                uint32_t minExpectedCount = 0;
                for (uint32_t j = 0; j < numParams; j++)
                {
                    if ((isVariadic || isTypedVariadic) && j == numParams - 1)
                        break;
                    if (params[j]->hasExtraFlag(SymbolVariableFlagsE::Initialized))
                        break;
                    minExpectedCount++;
                }

                outFail.kind          = MatchFailKind::TooFewArguments;
                outFail.expectedCount = minExpectedCount;
                outFail.providedCount = numArgs;
                outFail.argIndex      = numArgs; // first missing
                outFail.paramIndex    = i;       // missing parameter index
                outFail.hasLocation   = false;
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

    void collectAttempts(Sema& sema, SmallVector<Attempt>& outAttempts, SmallVector<SymbolFunction*>& outFunctionSymbols, std::span<Symbol*> symbols, std::span<AstNodeRef> args)
    {
        outAttempts.clear();
        outFunctionSymbols.clear();

        for (Symbol* s : symbols)
        {
            if (!s)
                continue;

            if (!s->isFunction())
                continue;

            auto& fn = s->cast<SymbolFunction>();
            outFunctionSymbols.push_back(&fn);

            Attempt a;
            a.fn = &fn;

            MatchFailure fail;
            Candidate    candidate;

            if (tryBuildCandidate(sema, fn, args, candidate, fail))
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
        auto        diag    = SemaError::report(sema, DiagnosticId::sema_err_not_callable, nodeCallee.nodeRef);
        const auto& srcView = sema.srcView(nodeCallee.node->srcViewRef());
        diag.addArgument(Diagnostic::ARG_SYM, srcView.token(nodeCallee.node->tokRef()).string(srcView));
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
                    if (fail.castFailure.srcTypeRef.isValid())
                        diag.addArgument(Diagnostic::ARG_TYPE, fail.castFailure.srcTypeRef);
                    if (fail.castFailure.dstTypeRef.isValid())
                        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, fail.castFailure.dstTypeRef);
                    if (fail.castFailure.optTypeRef.isValid())
                        diag.addArgument(Diagnostic::ARG_OPT_TYPE, fail.castFailure.optTypeRef);
                    diag.addArgument(Diagnostic::ARG_VALUE, fail.castFailure.valueStr);
                    diag.addNote(fail.castFailure.noteId);
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
                        if (a.fail.castFailure.srcTypeRef.isValid())
                            note.addArgument(Diagnostic::ARG_TYPE, a.fail.castFailure.srcTypeRef);
                        if (a.fail.castFailure.dstTypeRef.isValid())
                            note.addArgument(Diagnostic::ARG_REQUESTED_TYPE, a.fail.castFailure.dstTypeRef);
                        if (a.fail.castFailure.optTypeRef.isValid())
                            note.addArgument(Diagnostic::ARG_OPT_TYPE, a.fail.castFailure.optTypeRef);
                        note.addArgument(Diagnostic::ARG_VALUE, a.fail.castFailure.valueStr);
                        if (a.fail.castFailure.noteId != DiagnosticId::None)
                            diag.addNote(a.fail.castFailure.noteId);
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

Result Match::resolveFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<AstNodeRef> args)
{
    SmallVector<Attempt>         attempts;
    SmallVector<SymbolFunction*> functions;
    collectAttempts(sema, attempts, functions, symbols, args);

    // Gather viable candidates
    SmallVector<Candidate> viable;
    viable.reserve(attempts.size());
    for (const Attempt& a : attempts)
    {
        if (a.viable)
            viable.push_back(a.candidate);
    }

    // If we have viable overload candidates: pick the best (or ambiguous)
    SymbolFunction* selectedFn = nullptr;
    if (!viable.empty())
    {
        const Candidate* best = viable.data();
        bool             tie  = false;

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
    const auto& params      = selectedFn->parameters();
    const auto  numArgs     = static_cast<uint32_t>(args.size());
    const auto  numParams   = static_cast<uint32_t>(params.size());
    const auto& selectedFnT = selectedFn->type(sema.ctx());

    const uint32_t numCommon = selectedFnT.isAnyVariadic() ? numParams - 1 : numParams;
    for (uint32_t i = 0; i < std::min(numArgs, numCommon); ++i)
    {
        SemaNodeView argView(sema, args[i]);
        RESULT_VERIFY(Cast::cast(sema, argView, params[i]->typeRef(), CastKind::Implicit));
        args[i] = argView.nodeRef;
    }

    if (selectedFnT.isTypedVariadic())
    {
        const uint32_t startVariadic = numParams - 1;
        const TypeRef  variadicTy    = selectedFnT.typeRef();
        for (uint32_t i = startVariadic; i < numArgs; ++i)
        {
            SemaNodeView argView(sema, args[i]);
            RESULT_VERIFY(Cast::cast(sema, argView, variadicTy, CastKind::Implicit));
            args[i] = argView.nodeRef;
        }
    }

    sema.setType(sema.curNodeRef(), selectedFn->returnType());
    SemaInfo::setIsValue(sema.node(sema.curNodeRef()));
    return Result::Continue;
}

SWC_END_NAMESPACE();
