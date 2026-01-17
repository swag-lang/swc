#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Symbol/Match.h"
#include "Sema/Symbol/Symbol.Impl.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/Cast.h"

SWC_BEGIN_NAMESPACE();

Result AstFunctionDecl::semaPreDecl(Sema& sema) const
{
    SymbolFunction& sym = SemaHelpers::registerSymbol<SymbolFunction>(sema, *this, tokNameRef);

    sym.setExtraFlags(flags());
    if (nodeBodyRef.isInvalid())
        sym.addExtraFlag(SymbolFunctionFlagsE::Empty);

    return Result::SkipChildren;
}

Result AstFunctionDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);

    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    if (sym.isMethod() && !sema.frame().impl() && !sema.frame().interface())
    {
        const SourceView& srcView   = sema.srcView(srcViewRef());
        const TokenRef    mtdTokRef = srcView.findLeftFrom(tokNameRef, {TokenId::KwdMtd});
        return SemaError::raise(sema, DiagnosticId::sema_err_method_outside_impl, srcViewRef(), mtdTokRef);
    }

    SemaFrame frame = sema.frame();
    frame.setFunction(&sym);
    sema.pushFrame(frame);
    return Result::Continue;
}

namespace
{
    void addMeParameter(Sema& sema, SymbolFunction& sym)
    {
        if (sema.frame().impl() && sema.frame().impl()->isForStruct())
        {
            const SymbolImpl* symImpl   = sema.frame().impl()->asSymMap()->safeCast<SymbolImpl>();
            const TypeRef     ownerType = symImpl->symStruct()->typeRef();
            auto&             ctx       = sema.ctx();
            SymbolVariable*   symMe     = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), sema.idMgr().nameMe(), SymbolFlagsE::Zero);
            TypeInfoFlags     typeFlags = TypeInfoFlagsE::Zero;
            if (sym.hasExtraFlag(SymbolFunctionFlagsE::Const))
                typeFlags.add(TypeInfoFlagsE::Const);
            const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(ownerType, typeFlags));
            symMe->setTypeRef(typeRef);

            sym.addParameter(symMe);
            sym.addSymbol(ctx, symMe, true);
            symMe->setDeclared(ctx);
            symMe->setTyped(ctx);
        }
    }
}

Result AstFunctionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeParamsRef)
    {
        SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
        sema.pushScope(SemaScopeFlagsE::Parameters);
        sema.curScope().setSymMap(&sym);
        if (sym.isMethod())
            addMeParameter(sema, sym);
    }
    else if (childRef == nodeBodyRef)
    {
        return Result::SkipChildren; // TODO
        SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
        sema.pushScope(SemaScopeFlagsE::Local);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstFunctionDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeParamsRef && sema.enteringState())
        sema.popScope();

    if (childRef == nodeReturnTypeRef || (childRef == nodeParamsRef && nodeReturnTypeRef.isInvalid()))
    {
        SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();

        TypeRef returnType = sema.typeMgr().typeVoid();
        if (nodeReturnTypeRef.isValid())
            returnType = sema.typeRefOf(nodeReturnTypeRef);
        sym.setReturnType(returnType);

        const TypeInfo ti      = TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero);
        const TypeRef  typeRef = sema.typeMgr().addType(ti);
        sym.setTypeRef(typeRef);
        sym.setTyped(sema.ctx());

        RESULT_VERIFY(SemaCheck::checkSignature(sema, sym.parameters(), false));
        if (!sym.isEmpty())
            RESULT_VERIFY(Match::ghosting(sema, sym));
    }
    else if (childRef == nodeBodyRef)
    {
        sema.popScope();
    }

    return Result::Continue;
}

Result AstFunctionDecl::semaPostNode(Sema& sema)
{
    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    sym.setCompleted(sema.ctx());
    sema.popFrame();
    return Result::Continue;
}

Result AstFunctionParamMe::semaPreNode(Sema& sema) const
{
    if (!sema.frame().impl())
        return SemaError::raise(sema, DiagnosticId::sema_err_tok_outside_impl, sema.curNodeRef());

    const SymbolImpl* symImpl   = sema.frame().impl()->symMap()->safeCast<SymbolImpl>();
    const TypeRef     ownerType = symImpl->ownerKind() == SymbolImplOwnerKind::Struct ? symImpl->symStruct()->typeRef() : symImpl->symEnum()->typeRef();

    auto& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokRef());

    TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
    if (hasFlag(AstFunctionParamMeFlagsE::Const))
        typeFlags.add(TypeInfoFlagsE::Const);
    const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(ownerType, typeFlags));
    sym.setTypeRef(typeRef);

    return Result::Continue;
}

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

    struct Candidate
    {
        SymbolFunction*       fn = nullptr;
        SmallVector<ConvRank> perArg; // one entry per provided arg
        uint32_t              usedDefaults = 0;
        bool                  viable       = false;
    };

    // You likely already have pieces of this inside Cast, but you need a "probe" version:
    // - must NOT mutate AST
    // - must NOT emit diagnostics
    // - just answers: can convert? and rank?
    ConvRank probeImplicitConversion(Sema& sema, TypeRef from, TypeRef to)
    {
        if (from == to)
            return ConvRank::Exact;

        // TODO: hook into your real rules.
        // If you already have something like Cast::canCast(...), use it here.
        // Pseudocode examples:
        // if (isIntegral(from) && isIntegral(to) && isWidening(from,to)) return ConvRank::Promo;
        // if (isNumeric(from) && isNumeric(to)) return ConvRank::Standard;
        // if (hasUserDefinedConversion(from,to)) return ConvRank::User;
        CastContext castCtx(CastKind::Implicit);
        if (Cast::castAllowed(sema, castCtx, from, to) == Result::Continue)
            return ConvRank::Standard;

        return ConvRank::Bad;
    }

    bool buildCandidate(Sema& sema, SymbolFunction& fn, const SmallVector<AstNodeRef>& args, Candidate& out)
    {
        const auto&    params    = fn.parameters();
        const uint32_t numArgs   = static_cast<uint32_t>(args.size());
        const uint32_t numParams = static_cast<uint32_t>(params.size());

        // Too many args: not viable (unless you support varargs/ellipsis)
        if (numArgs > numParams)
            return false;

        out.fn = &fn;
        out.perArg.clear();
        out.usedDefaults = 0;

        // Rank each provided argument
        for (uint32_t i = 0; i < numArgs; ++i)
        {
            const TypeRef argTy   = sema.typeRefOf(args[i]);
            const TypeRef paramTy = params[i]->typeRef();

            const ConvRank r = probeImplicitConversion(sema, argTy, paramTy);
            if (r == ConvRank::Bad)
                return false;

            out.perArg.push_back(r);
        }

        // Remaining params must be defaulted/initialized
        for (uint32_t i = numArgs; i < numParams; ++i)
        {
            if (!params[i]->hasExtraFlag(SymbolVariableFlagsE::Initialized))
                return false;
            out.usedDefaults++;
        }

        out.viable = true;
        return true;
    }

    // Compare candidates: "best" is the one with the better (smaller) rank for the first differing arg.
    // Tie-breakers can include fewer defaults, non-template, more specialized, etc.
    int compareCandidates(const Candidate& a, const Candidate& b)
    {
        const uint32_t n = static_cast<uint32_t>(a.perArg.size()); // should equal b.perArg.size() for same call
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
}

Result AstCallExpr::semaPostNode(Sema& sema) const
{
    SemaNodeView nodeCallee(sema, nodeExprRef);

    SmallVector<AstNodeRef> args;
    collectArguments(args, sema.ast());

    SmallVector<Symbol*> symbols;
    nodeCallee.getSymbols(symbols);

    SmallVector<Candidate> viable;
    SmallVector<Symbol*>   ambiguousSymbols;

    for (Symbol* s : symbols)
    {
        if (!s->isFunction())
            continue;

        auto& fn = s->cast<SymbolFunction>();

        Candidate c;
        if (buildCandidate(sema, fn, args, c))
            viable.push_back(std::move(c));
    }

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
            // Gather all tied bests for diag
            for (auto& c : viable)
            {
                if (compareCandidates(c, *best) == 0)
                    ambiguousSymbols.push_back(c.fn);
            }
            return SemaError::raiseAmbiguousSymbol(sema, nodeExprRef, ambiguousSymbols);
        }

        selectedFn = best->fn;
        sema.setSymbol(nodeExprRef, selectedFn);
    }

    // If no overload matches, fall back to the "callee is a function type" case as before
    if (!selectedFn)
    {
        if (!nodeCallee.type || !nodeCallee.type->isFunction())
        {
            auto        diag    = SemaError::report(sema, DiagnosticId::sema_err_not_callable, nodeExprRef);
            const auto& srcView = sema.srcView(nodeCallee.node->srcViewRef());
            diag.addArgument(Diagnostic::ARG_SYM, srcView.token(nodeCallee.node->tokRef()).string(srcView));
            diag.addArgument(Diagnostic::ARG_TYPE, nodeCallee.type ? nodeCallee.type->toName(sema.ctx()) : "invalid type");
            diag.report(sema.ctx());
            return Result::Error;
        }

        selectedFn = &nodeCallee.type->symFunction();
    }

    // Now apply implicit conversions + handle defaults
    const auto&    params    = selectedFn->parameters();
    const uint32_t numArgs   = static_cast<uint32_t>(args.size());
    const uint32_t numParams = static_cast<uint32_t>(params.size());

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
