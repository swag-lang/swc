#include "pch.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t K_ENUM_VALUE_LIST_LIMIT = 8;

    void appendQuotedEnumValue(Utf8& out, bool& first, std::string_view name)
    {
        if (!first)
            out += ", ";
        first = false;
        out += '\'';
        out += name;
        out += '\'';
    }

    Utf8 formatEnumValueList(const TaskContext& ctx, const SymbolEnum& symEnum)
    {
        std::vector<const Symbol*> symbols;
        symEnum.getAllSymbols(symbols);

        Utf8   result;
        bool   first = true;
        size_t count = 0;
        for (const Symbol* symbol : symbols)
        {
            const auto* enumValue = symbol ? symbol->safeCast<SymbolEnumValue>() : nullptr;
            if (!enumValue)
                continue;

            if (count == K_ENUM_VALUE_LIST_LIMIT)
            {
                result += ", ...";
                break;
            }

            appendQuotedEnumValue(result, first, enumValue->name(ctx));
            ++count;
        }

        return result;
    }

    CodeGenNodePayload& ensureCodeGenNodePayload(Sema& sema, AstNodeRef nodeRef)
    {
        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(nodeRef);
        if (payload)
            return *payload;

        payload = sema.compiler().allocate<CodeGenNodePayload>();
        sema.setCodeGenPayload(nodeRef, payload);
        return *payload;
    }

    void refreshNamedArgumentPayload(Sema& sema, AstNodeRef rawArgRef, AstNodeRef valueNodeRef)
    {
        if (rawArgRef.isInvalid() || valueNodeRef.isInvalid())
            return;
        if (!sema.node(rawArgRef).is(AstNodeId::NamedArgument))
            return;

        sema.inheritPayload(sema.node(rawArgRef), valueNodeRef);
    }

    TypeRef implicitConstReferenceBindingValueTypeRef(Sema& sema, TypeRef paramTypeRef, TypeRef sourceTypeRef)
    {
        if (!paramTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& paramType = sema.typeMgr().get(paramTypeRef);
        if (!paramType.isReference() || !paramType.isConst())
            return TypeRef::invalid();

        const TypeRef pointeeTypeRef = paramType.payloadTypeRef();
        if (!pointeeTypeRef.isValid())
            return TypeRef::invalid();

        if (!sourceTypeRef.isValid())
            return pointeeTypeRef;

        const TypeRef   unwrappedSourceTypeRef = sema.typeMgr().get(sourceTypeRef).unwrap(sema.ctx(), sourceTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeRef   resolvedSourceTypeRef  = unwrappedSourceTypeRef.isValid() ? unwrappedSourceTypeRef : sourceTypeRef;
        const TypeInfo& sourceType             = sema.typeMgr().get(resolvedSourceTypeRef);
        if (sourceType.isPointerOrReference())
            return TypeRef::invalid();

        return pointeeTypeRef;
    }

    SymbolFunction* callableTypeFunction(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
            if (typeInfo.isFunction())
                return &typeInfo.payloadSymFunction();

            const TypeRef unwrapped = typeInfo.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias | TypeExpandE::Enum);
            if (unwrapped.isValid())
            {
                typeRef = unwrapped;
                continue;
            }

            if (typeInfo.isReference())
            {
                typeRef = typeInfo.payloadTypeRef();
                continue;
            }

            break;
        }

        return nullptr;
    }

    bool hasConcreteFunctionCandidate(std::span<Symbol*> symbols)
    {
        for (Symbol* const sym : symbols)
        {
            if (!sym || !sym->isFunction())
                continue;
            const auto& fn = sym->cast<SymbolFunction>();
            if (!fn.isEmpty())
                return true;
        }

        return false;
    }

    void removeEmptyFunctionDeclarations(std::span<Symbol*> inSymbols, SmallVector<Symbol*>& outSymbols)
    {
        outSymbols.clear();
        outSymbols.reserve(inSymbols.size());

        if (!hasConcreteFunctionCandidate(inSymbols))
        {
            for (Symbol* const sym : inSymbols)
            {
                if (sym)
                    outSymbols.push_back(sym);
            }
            return;
        }

        for (Symbol* const sym : inSymbols)
        {
            if (!sym)
                continue;
            if (sym->isFunction())
            {
                const auto& fn = sym->cast<SymbolFunction>();
                if (!fn.isForeign() && fn.isEmpty())
                    continue;
            }

            outSymbols.push_back(sym);
        }
    }

    bool isCallableForMode(const Symbol& sym, Match::ResolveCallMode mode)
    {
        if (mode == Match::ResolveCallMode::AttributeOnly)
            return sym.isFunction() && sym.isAttribute();

        if (sym.isFunction())
            return !sym.isAttribute();
        if (sym.isVariable())
            return true;
        if (sym.isAlias())
        {
            const auto* aliased = sym.cast<SymbolAlias>().aliasedSymbol();
            return aliased && aliased->isFunction();
        }

        return false;
    }

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
        bool          active        = false;
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

    struct GenericRootCallParam
    {
        bool hasDefault = false;
        bool isVariadic = false;
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
        auto n = static_cast<uint32_t>(args.size());
        if (ufcsArg.isValid())
            ++n;
        return n;
    }

    uint32_t callArgIndexFromUserIndex(uint32_t userArgIndex, AstNodeRef ufcsArg)
    {
        return ufcsArg.isValid() ? (userArgIndex + 1) : userArgIndex;
    }

    bool allowsImplicitAddressBinding(const SymbolFunction& fn, uint32_t paramIndex, AstNodeRef ufcsArg)
    {
        if (ufcsArg.isValid() && paramIndex == 0)
            return true;

        // Binary special operators conceptually consume two operands. Keep the right operand
        // addressable as well so invalid-but-diagnosed signatures like `other: &T` still
        // behave consistently with operator syntax while remaining reported to the user.
        return fn.specOpKind() == SpecOpKind::OpBinary && paramIndex == 1;
    }

    VariadicInfo getVariadicInfo(Sema& sema, const SymbolFunction& fn)
    {
        VariadicInfo vi;
        const auto&  params = fn.parameters();
        if (params.empty())
            return vi;

        const TypeInfo& lastParamTy = params.back()->type(sema.ctx());
        vi.isVariadic               = lastParamTy.isVariadic();
        vi.isTypedVariadic          = lastParamTy.isTypedVariadic();
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
        f.active        = true;
    }

    void failTooFew(MatchFailure& f, uint32_t expectedMin, uint32_t provided, uint32_t missingParamIndex)
    {
        f.kind          = MatchFailKind::TooFewArguments;
        f.expectedCount = expectedMin;
        f.providedCount = provided;
        f.argIndex      = provided; // first missing
        f.paramIndex    = missingParamIndex;
        f.hasLocation   = false;
        f.active        = true;
    }

    void failBadType(MatchFailure& f, uint32_t argIndex, uint32_t paramIndex, const CastFailure& cf, bool hasLocation = true)
    {
        f.kind        = MatchFailKind::InvalidArgumentType;
        f.argIndex    = argIndex;
        f.paramIndex  = paramIndex;
        f.castFailure = cf;
        f.hasLocation = hasLocation;
        f.active      = true;
    }

    Utf8 formatNamedParameters(const Sema&                                sema,
                               std::span<SymbolVariable* const>           params,
                               uint32_t                                   paramStart,
                               uint32_t                                   numParams)
    {
        Utf8 result;
        bool first = true;
        for (uint32_t i = paramStart; i < numParams; ++i)
        {
            const SymbolVariable* param = params[i];
            if (!param || !param->idRef().isValid())
                continue;

            if (!first)
                result += ", ";
            first = false;
            result += '\'';
            result += param->name(sema.ctx());
            result += '\'';
        }

        return result;
    }

    bool buildCallArgMapping(Sema& sema, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, CallArgMapping& outMapping, MatchFailure& outFail)
    {
        outMapping = {};

        const auto&    params     = fn.parameters();
        const auto     numParams  = static_cast<uint32_t>(params.size());
        const uint32_t paramStart = ufcsArg.isValid() ? 1u : 0u;

        outMapping.paramArgs.resize(numParams);
        for (CallArgEntry& entry : outMapping.paramArgs)
            entry.callArgIndex = 0;

        if (ufcsArg.isValid() && numParams > 0)
        {
            outMapping.paramArgs[0].argRef       = ufcsArg;
            outMapping.paramArgs[0].callArgIndex = 0;
        }

        bool     seenNamed = false;
        uint32_t nextPos   = paramStart;

        const auto setFailure = [&](uint32_t      userArgIndex,
                                    DiagnosticId  diagId,
                                    IdentifierRef idRef       = IdentifierRef::invalid(),
                                    uint32_t      paramIndex  = UINT32_MAX,
                                    DiagnosticId  noteId      = DiagnosticId::None,
                                    AstNodeRef    noteNodeRef = AstNodeRef::invalid(),
                                    Utf8          noteValues  = {}) {
            CastFailure cf{};
            cf.diagId = diagId;
            if (idRef.isValid())
                cf.valueStr = Utf8{sema.idMgr().get(idRef).name};
            cf.noteId  = noteId;
            cf.nodeRef = noteNodeRef;
            if (!noteValues.empty())
                cf.addArgument(Diagnostic::ARG_VALUES, std::move(noteValues));
            cf.addArgument(Diagnostic::ARG_SYM, fn.name(sema.ctx()));
            const uint32_t callArgIndex = callArgIndexFromUserIndex(userArgIndex, ufcsArg);
            failBadType(outFail, callArgIndex, paramIndex == UINT32_MAX ? callArgIndex : paramIndex, cf);
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
                    const Utf8 namedParams = formatNamedParameters(sema, params, paramStart, numParams);
                    setFailure(userIndex,
                               DiagnosticId::sema_err_named_argument_unknown,
                               idRef,
                               UINT32_MAX,
                               namedParams.empty() ? DiagnosticId::sema_note_call_has_no_named_arguments : DiagnosticId::sema_note_available_named_arguments,
                               AstNodeRef::invalid(),
                               namedParams);
                    return false;
                }

                if (outMapping.paramArgs[found].argRef.isValid())
                {
                    setFailure(userIndex, DiagnosticId::sema_err_named_argument_duplicate, idRef, static_cast<uint32_t>(found), DiagnosticId::sema_note_previous_named_argument, outMapping.paramArgs[found].argRef);
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

    void addCastFailureNote(Sema& sema, Diagnostic& diag, const CastFailure& cf)
    {
        if (cf.noteId == DiagnosticId::None)
            return;

        TaskContext& ctx = sema.ctx();
        diag.addNote(cf.noteId);
        cf.applyArguments(diag.last());

        if (cf.nodeRef.isValid())
        {
            diag.last().addSpan(sema.node(cf.nodeRef).codeRangeWithChildren(ctx, sema.ast()));
            return;
        }

        if (cf.codeRef.isValid())
        {
            const SourceView& srcView = ctx.compiler().srcView(cf.codeRef.srcViewRef);
            const Token&      tok     = srcView.token(cf.codeRef.tokRef);
            diag.last().addSpan(tok.codeRange(ctx, srcView));
        }
    }

    const SymbolVariable* failedParameter(const SymbolFunction& fn, const MatchFailure& fail)
    {
        if (fail.paramIndex >= fn.parameters().size())
            return nullptr;

        return fn.parameters()[fail.paramIndex];
    }

    const SymbolVariable* declaredFailedParameter(const SymbolFunction& fn, const MatchFailure& fail)
    {
        const SymbolVariable* param = failedParameter(fn, fail);
        if (!param || !param->decl())
            return nullptr;

        return param;
    }

    Utf8 makeCannotCastArgumentText(const SymbolFunction& fn, const MatchFailure& fail, const TaskContext& ctx)
    {
        SWC_ASSERT(fail.castFailure.srcTypeRef.isValid());
        SWC_ASSERT(fail.castFailure.dstTypeRef.isValid());

        const Utf8 srcTypeName = ctx.typeMgr().get(fail.castFailure.srcTypeRef).toName(ctx);
        const Utf8 dstTypeName = ctx.typeMgr().get(fail.castFailure.dstTypeRef).toName(ctx);
        if (const SymbolVariable* param = failedParameter(fn, fail))
            return std::format("has type '{}', but parameter '{}' expects '{}'", srcTypeName, param->name(ctx), dstTypeName);

        return std::format("has type '{}', expected '{}'", srcTypeName, dstTypeName);
    }

    Utf8 makeCandidateFailureText(const SymbolFunction& fn, const MatchFailure& fail, const TaskContext& ctx)
    {
        if (fail.kind == MatchFailKind::InvalidArgumentType)
        {
            if (fail.castFailure.diagId != DiagnosticId::None)
            {
                if (const SymbolVariable* param = fail.castFailure.dstTypeRef.isValid() ? failedParameter(fn, fail) : nullptr)
                    return std::format("parameter '{}' cannot accept argument {}: {}", param->name(ctx), fail.argIndex + 1, Diagnostic::diagIdMessage(fail.castFailure.diagId));
                return Utf8{Diagnostic::diagIdMessage(fail.castFailure.diagId)};
            }

            if (const SymbolVariable* param = failedParameter(fn, fail))
                return std::format("argument {} does not match parameter '{}'", fail.argIndex + 1, param->name(ctx));
            return Utf8{Diagnostic::diagIdMessage(DiagnosticId::sema_note_invalid_argument_type)};
        }

        return Utf8{Diagnostic::diagIdMessage(DiagnosticId::sema_note_not_viable)};
    }

    DiagnosticId overloadCandidateDiagnosticId(const MatchFailure& fail)
    {
        switch (fail.kind)
        {
            case MatchFailKind::TooManyArguments:
                return DiagnosticId::sema_note_overload_candidate_too_many_arguments;

            case MatchFailKind::TooFewArguments:
                return DiagnosticId::sema_note_overload_candidate_too_few_arguments;

            case MatchFailKind::InvalidArgumentType:
                if (fail.castFailure.diagId == DiagnosticId::sema_err_cannot_cast && fail.castFailure.srcTypeRef.isValid() && fail.castFailure.dstTypeRef.isValid())
                    return DiagnosticId::sema_note_overload_candidate_argument_type;
                return DiagnosticId::sema_note_overload_candidate_failed;

            default:
                return DiagnosticId::sema_note_overload_candidate_failed;
        }
    }

    void setCallArgumentFailureArgs(DiagnosticElement& diagElement, const SymbolFunction& fn, const MatchFailure& fail, const TaskContext& ctx)
    {
        if (fail.kind != MatchFailKind::InvalidArgumentType)
            return;
        if (fail.castFailure.diagId == DiagnosticId::None)
            return;

        diagElement.addArgument(Diagnostic::ARG_INDEX, fail.argIndex + 1);
        diagElement.addArgument(Diagnostic::ARG_SYM, fn.name(ctx));

        if (fail.castFailure.diagId != DiagnosticId::sema_err_cannot_cast)
            return;
        if (fail.castFailure.srcTypeRef.isInvalid() || fail.castFailure.dstTypeRef.isInvalid())
            return;

        if (const SymbolVariable* param = declaredFailedParameter(fn, fail))
        {
            diagElement.addArgument(Diagnostic::ARG_TOK, Utf8{param->name(ctx)});
            return;
        }

        diagElement.addArgument(Diagnostic::ARG_WHAT, makeCannotCastArgumentText(fn, fail, ctx));
    }

    DiagnosticArguments makeCallCastErrorArguments(const SymbolFunction& fn, uint32_t callArgIndex, const TaskContext& ctx)
    {
        DiagnosticArguments arguments;
        arguments.push_back(DiagnosticArgument{Diagnostic::ARG_INDEX, callArgIndex + 1});
        arguments.push_back(DiagnosticArgument{Diagnostic::ARG_SYM, Utf8{fn.name(ctx)}});
        return arguments;
    }

    void attachCallCastFailureArgs(CastFailure& failure, const SymbolFunction& fn, uint32_t callArgIndex, const TaskContext& ctx)
    {
        failure.mergeArguments(makeCallCastErrorArguments(fn, callArgIndex, ctx));
    }

    Result errorNotCallable(Sema& sema, const SemaNodeView& nodeCallee)
    {
        const Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_not_callable, nodeCallee.nodeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    void fillMatchDiagnostic(Sema& sema, DiagnosticElement& diagElement, Diagnostic& diag, const SymbolFunction& fn, const MatchFailure& fail, std::span<AstNodeRef> args, AstNodeRef ufcsArg, bool isNote)
    {
        const TaskContext& ctx     = sema.ctx();
        const uint32_t     numArgs = countCallArgs(args, ufcsArg);

        switch (fail.kind)
        {
            case MatchFailKind::TooManyArguments:
                if (!isNote)
                    diagElement.addArgument(Diagnostic::ARG_SYM, fn.name(ctx));
                diagElement.addArgument(Diagnostic::ARG_COUNT, fail.expectedCount);
                diagElement.addArgument(Diagnostic::ARG_VALUE, fail.providedCount);
                break;

            case MatchFailKind::TooFewArguments:
                if (!isNote)
                    diagElement.addArgument(Diagnostic::ARG_SYM, fn.name(ctx));
                diagElement.addArgument(Diagnostic::ARG_COUNT, fail.expectedCount);
                diagElement.addArgument(Diagnostic::ARG_VALUE, fail.providedCount);
                if (const SymbolVariable* param = declaredFailedParameter(fn, fail))
                    diagElement.addArgument(Diagnostic::ARG_TOK, Utf8{param->name(ctx)});
                break;

            case MatchFailKind::InvalidArgumentType:
                if (fail.castFailure.diagId != DiagnosticId::None)
                {
                    if (isNote)
                    {
                        if (diagElement.id() == DiagnosticId::sema_note_overload_candidate_argument_type)
                        {
                            diagElement.addArgument(Diagnostic::ARG_INDEX, fail.argIndex + 1);
                            if (const SymbolVariable* param = declaredFailedParameter(fn, fail))
                                diagElement.addArgument(Diagnostic::ARG_TOK, Utf8{param->name(ctx)});
                        }
                        else
                        {
                            diagElement.addArgument(Diagnostic::ARG_WHAT, makeCandidateFailureText(fn, fail, ctx));
                        }
                    }
                    (void) addCastFailureArgs(diagElement, fail.castFailure);
                    addCastFailureNote(sema, diag, fail.castFailure);
                    if (!isNote)
                        setCallArgumentFailureArgs(diagElement, fn, fail, ctx);
                }
                else
                {
                    if (isNote)
                        diagElement.addArgument(Diagnostic::ARG_WHAT, makeCandidateFailureText(fn, fail, ctx));
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

        Diagnostic diag = SemaError::report(sema, id, nodeCallee.nodeRef());
        fillMatchDiagnostic(sema, diag.last(), diag, fn, fail, args, ufcsArg, false);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result errorNoOverloadMatch(Sema& sema, const SemaNodeView& nodeCallee, const SmallVector<Attempt>& attempts, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        TaskContext& ctx = sema.ctx();

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

        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_no_overload_match, nodeCallee.nodeRef());
        if (!attempts.empty())
            diag.last().addArgument(Diagnostic::ARG_SYM, attempts.front().fn->name(ctx));

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
            const Attempt& a = *(sa.a);

            diag.addNote(overloadCandidateDiagnosticId(a.fail));
            diag.last().addArgument(Diagnostic::ARG_SYM, a.fn->isTyped() ? a.fn->type(ctx).toName(ctx) : Utf8{a.fn->name(ctx)});
            fillMatchDiagnostic(sema, diag.last(), diag, *a.fn, a.fail, args, ufcsArg, true);
        }

        diag.report(sema.ctx());
        return Result::Error;
    }

    // Probes if an implicit conversion from 'from' to 'to' is possible and returns its rank.
    Result probeImplicitConversion(Sema& sema, ConvRank& outRank, AstNodeRef argRef, TypeRef from, TypeRef to, CastFailure& outCastFailure, bool isUfcsArgument)
    {
        outRank = ConvRank::Bad;
        if (from == to)
        {
            outRank = ConvRank::Exact;
            return Result::Continue;
        }

        const SemaNodeView argNodeView(sema, argRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Constant);
        auto               castKind  = CastKind::Parameter;
        CastFlags          castFlags = CastFlagsE::Zero;
        SWC_ASSERT(argNodeView.node() != nullptr);
        if (argNodeView.node()->is(AstNodeId::AutoCastExpr))
        {
            const auto& autoCast = argNodeView.node()->cast<AstAutoCastExpr>();
            castKind             = CastKind::Explicit;
            if (autoCast.modifierFlags.has(AstModifierFlagsE::Bit))
                castFlags.add(CastFlagsE::BitCast);
            if (autoCast.modifierFlags.has(AstModifierFlagsE::UnConst))
                castFlags.add(CastFlagsE::UnConst);
        }
        if (argNodeView.cstRef().isValid() && sema.isFoldedTypedConst(argRef))
            castFlags.add(CastFlagsE::FoldedTypedConst);

        CastRequest castRequest(castKind);
        castRequest.flags        = castFlags;
        castRequest.errorNodeRef = argRef;
        castRequest.setConstantFoldingSrc(argNodeView.cstRef());
        if (isUfcsArgument)
            castRequest.flags.add(CastFlagsE::UfcsArgument);

        const TypeRef bindValueTypeRef = implicitConstReferenceBindingValueTypeRef(sema, to, from);
        const TypeRef castToTypeRef    = bindValueTypeRef.isValid() ? bindValueTypeRef : to;
        const Result  castResult       = Cast::castAllowed(sema, castRequest, from, castToTypeRef);
        if (castResult == Result::Pause)
            return Result::Pause;
        if (castResult == Result::Continue)
        {
            outRank = ConvRank::Standard;
            return Result::Continue;
        }

        outCastFailure = castRequest.failure;
        if (bindValueTypeRef.isValid())
            outCastFailure.dstTypeRef = to;
        return Result::Continue;
    }

    Result probeAutoEnumArg(Sema& sema, AstNodeRef argRef, TypeRef paramTy, AutoEnumArgProbe& out, CastFailure& cf)
    {
        out = {};

        // Only handle `.EnumValue` (auto-member) using the overload's parameter enum scope.
        const AstNodeRef argSubRef   = sema.viewZero(argRef).nodeRef();
        const AstNodeRef finalArgRef = argSubRef.isValid() ? argSubRef : argRef;
        const AstNode&   argNode     = sema.node(finalArgRef);
        if (!argNode.is(AstNodeId::AutoMemberAccessExpr))
            return Result::Continue;
        const auto& autoMem = argNode.cast<AstAutoMemberAccessExpr>();

        const TypeInfo& paramTypeInfo = sema.typeMgr().get(paramTy);
        if (!paramTypeInfo.isEnum())
            return Result::Continue;

        const SymbolEnum& enumSym = paramTypeInfo.payloadSymEnum();
        SWC_RESULT(sema.waitSemaCompleted(&enumSym, argNode.codeRef()));

        const SemaNodeView  nodeRightView(sema, autoMem.nodeIdentRef, SemaNodeViewPartE::Node);
        const TokenRef      tokNameRef = nodeRightView.node()->tokRef();
        const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), nodeRightView.node()->codeRef());

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = SourceCodeRef{argNode.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint    = &enumSym;
        lookUpCxt.noWaitOnEmpty = true;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        if (!lookUpCxt.empty())
        {
            out.matched = true;
            out.typeRef = paramTy;
        }
        else
        {
            cf.diagId                  = DiagnosticId::sema_err_auto_scope_missing_enum_value;
            cf.srcTypeRef              = TypeRef::invalid();
            cf.dstTypeRef              = paramTy;
            cf.valueStr                = Utf8{sema.idMgr().get(idRef).name};
            const Utf8 availableValues = formatEnumValueList(sema.ctx(), enumSym);
            if (!availableValues.empty())
            {
                cf.noteId = DiagnosticId::sema_note_available_enum_values;
                cf.addArgument(Diagnostic::ARG_VALUES, availableValues);
            }
        }

        return Result::Continue;
    }

    Result resolveAutoEnumArgFinal(Sema& sema, AstNodeRef argRef, TypeRef paramTy)
    {
        const AstNodeRef argSubRef   = sema.viewZero(argRef).nodeRef();
        const AstNodeRef finalArgRef = argSubRef.isValid() ? argSubRef : argRef;
        const AstNode&   argNode     = sema.node(finalArgRef);
        if (!argNode.is(AstNodeId::AutoMemberAccessExpr))
            return Result::Continue;
        const auto& autoMem = argNode.cast<AstAutoMemberAccessExpr>();

        const TypeInfo& paramTypeInfo = sema.typeMgr().get(paramTy);
        if (!paramTypeInfo.isEnum())
            return Result::Continue;

        const SymbolEnum& enumSym = paramTypeInfo.payloadSymEnum();
        SWC_RESULT(sema.waitSemaCompleted(&enumSym, argNode.codeRef()));

        const SemaNodeView  nodeRightView(sema, autoMem.nodeIdentRef, SemaNodeViewPartE::Node);
        const TokenRef      tokNameRef = nodeRightView.node()->tokRef();
        const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), nodeRightView.node()->codeRef());

        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{argNode.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &enumSym;

        // Keep normal wait semantics here (noWaitOnEmpty = false) to behave like `Enum.Value`.
        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        if (lookUpCxt.empty())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_auto_scope_missing_enum_value, argRef);
            diag.addArgument(Diagnostic::ARG_VALUE, sema.idMgr().get(idRef).name);
            diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, paramTy);
            const Utf8 availableValues = formatEnumValueList(sema.ctx(), enumSym);
            if (!availableValues.empty())
            {
                diag.addNote(DiagnosticId::sema_note_available_enum_values);
                diag.last().addArgument(Diagnostic::ARG_VALUES, availableValues);
            }
            diag.report(sema.ctx());
            return Result::Error;
        }

        // Substitute `.Value` -> `Enum.Value` for downstream codegen / semantic checks.
        auto [memberRef, memberPtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(argNode.tokRef());
        auto [leftRef, leftPtr]     = sema.ast().makeNode<AstNodeId::Identifier>(argNode.tokRef());
        sema.setSymbol(leftRef, &enumSym);
        sema.setIsValue(*leftPtr);

        memberPtr->nodeLeftRef  = leftRef;
        memberPtr->nodeRightRef = autoMem.nodeIdentRef;

        sema.setSymbolList(memberRef, lookUpCxt.symbols());
        sema.setSymbolList(autoMem.nodeIdentRef, lookUpCxt.symbols());
        sema.setSubstitute(argRef, memberRef);
        sema.setIsValue(*memberPtr);

        return Result::Continue;
    }

    uint32_t minRequiredArgs(const SymbolFunction& fn, bool ignoreVariadicTail)
    {
        const auto&    params = fn.parameters();
        const auto     n      = static_cast<uint32_t>(params.size());
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

    void appendGenericRootCallParams(Sema& sema, AstNodeRef paramRef, SmallVector<GenericRootCallParam>& outParams)
    {
        if (paramRef.isInvalid())
            return;

        const AstNode* paramNode = &sema.node(paramRef);
        while (paramNode->is(AstNodeId::AttributeList))
        {
            paramRef  = paramNode->cast<AstAttributeList>().nodeBodyRef;
            paramNode = &sema.node(paramRef);
        }

        if (paramNode->is(AstNodeId::VarDeclList))
        {
            SmallVector<AstNodeRef> vars;
            sema.ast().appendNodes(vars, paramNode->cast<AstVarDeclList>().spanChildrenRef);
            for (const AstNodeRef varRef : vars)
                appendGenericRootCallParams(sema, varRef, outParams);
            return;
        }

        if (const auto* varDecl = paramNode->safeCast<AstSingleVarDecl>())
        {
            const AstNodeRef typeRef = varDecl->typeOrInitRef();
            outParams.push_back({
                .hasDefault = varDecl->nodeInitRef.isValid(),
                .isVariadic = typeRef.isValid() && (sema.node(typeRef).is(AstNodeId::VariadicType) || sema.node(typeRef).is(AstNodeId::TypedVariadicType)),
            });
            return;
        }

        if (const auto* multiVar = paramNode->safeCast<AstMultiVarDecl>())
        {
            SmallVector<TokenRef> tokNames;
            sema.ast().appendTokens(tokNames, multiVar->spanNamesRef);
            const AstNodeRef typeRef    = multiVar->typeOrInitRef();
            const bool       hasDefault = multiVar->nodeInitRef.isValid();
            const bool       isVariadic = typeRef.isValid() && (sema.node(typeRef).is(AstNodeId::VariadicType) || sema.node(typeRef).is(AstNodeId::TypedVariadicType));
            for ([[maybe_unused]] const TokenRef tokNameRef : tokNames)
                outParams.push_back({.hasDefault = hasDefault, .isVariadic = isVariadic});
            return;
        }

        if (paramNode->is(AstNodeId::FunctionParamMe))
            outParams.push_back({});
    }

    uint32_t minRequiredGenericRootArgs(std::span<const GenericRootCallParam> params)
    {
        const uint32_t n   = static_cast<uint32_t>(params.size());
        const uint32_t end = !params.empty() && params.back().isVariadic ? (n - 1) : n;

        uint32_t required = 0;
        for (uint32_t i = 0; i < end; ++i)
        {
            if (params[i].hasDefault)
                break;
            ++required;
        }

        return required;
    }

    Result tryBuildCandidate(Sema& sema, SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, Candidate& outCandidate, MatchFailure& outFail);

    Result precheckGenericCallShape(Sema& sema, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, MatchFailure& outFail)
    {
        outFail = {};

        if (fn.parameters().empty())
        {
            const auto* decl = fn.decl() ? fn.decl()->safeCast<AstFunctionDecl>() : nullptr;
            if (!decl || decl->nodeParamsRef.isInvalid())
                return Result::Continue;

            SmallVector<AstNodeRef> paramNodes;
            const AstNode&          paramsNode = sema.node(decl->nodeParamsRef);
            if (paramsNode.is(AstNodeId::FunctionParamList))
                sema.ast().appendNodes(paramNodes, paramsNode.cast<AstFunctionParamList>().spanChildrenRef);
            else
                paramsNode.collectChildrenFromAst(paramNodes, sema.ast());

            SmallVector<GenericRootCallParam> params;
            for (const AstNodeRef paramRef : paramNodes)
                appendGenericRootCallParams(sema, paramRef, params);

            const uint32_t numParams = static_cast<uint32_t>(params.size());
            const uint32_t numArgs   = countCallArgs(args, ufcsArg);
            const bool     variadic  = !params.empty() && params.back().isVariadic;

            if (!variadic && numArgs > numParams)
            {
                failTooMany(outFail, numParams, numArgs);
                return Result::Continue;
            }

            const uint32_t minExpected = minRequiredGenericRootArgs(params);
            if (numArgs < minExpected)
            {
                failTooFew(outFail, minExpected, numArgs, numArgs);
                return Result::Continue;
            }

            return Result::Continue;
        }

        CallArgMapping mapping;
        if (!buildCallArgMapping(sema, fn, args, ufcsArg, mapping, outFail))
            return Result::Continue;

        const auto&        params    = fn.parameters();
        const auto         numParams = static_cast<uint32_t>(params.size());
        const uint32_t     numArgs   = countCallArgs(args, ufcsArg);
        const VariadicInfo vi        = getVariadicInfo(sema, fn);

        if (!vi.any() && !mapping.variadicArgs.empty())
        {
            failTooMany(outFail, numParams, numArgs);
            return Result::Continue;
        }

        const uint32_t numCommon = (vi.any() && numParams > 0) ? (numParams - 1) : numParams;
        for (uint32_t i = 0; i < numCommon; ++i)
        {
            if (mapping.paramArgs[i].argRef.isValid())
                continue;
            if (params[i]->hasExtraFlag(SymbolVariableFlagsE::Initialized))
                continue;

            const uint32_t minExpected = minRequiredArgs(fn, vi.any());
            failTooFew(outFail, minExpected, numArgs, i);
            return Result::Continue;
        }

        return Result::Continue;
    }

    Result tryInstantiateGenericCandidate(Sema& sema, SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, Candidate& outCandidate, MatchFailure& outFail)
    {
        outCandidate = {};
        outFail      = {};

        SWC_RESULT(precheckGenericCallShape(sema, fn, args, ufcsArg, outFail));
        if (outFail.active)
            return Result::Continue;

        SymbolFunction* concreteFn          = nullptr;
        CastFailure     genericFailure      = {};
        uint32_t        genericFailureIndex = UINT32_MAX;
        SWC_RESULT(SemaGeneric::instantiateFunctionFromCall(sema, fn, args, ufcsArg, concreteFn, &genericFailure, &genericFailureIndex));
        if (!concreteFn)
        {
            if (genericFailure.diagId != DiagnosticId::None)
                failBadType(outFail, genericFailureIndex == UINT32_MAX ? 0 : genericFailureIndex, 0, genericFailure, genericFailureIndex != UINT32_MAX);
            return Result::Continue;
        }

        return tryBuildCandidate(sema, *concreteFn, args, ufcsArg, outCandidate, outFail);
    }

    // Try to build a candidate; if it fails, fill out why + where.
    // Evaluate a single function symbol against the provided arguments to see if it's a valid match.
    // It determines conversion ranks, UFCS usage, and handles variadic arguments.
    Result tryBuildCandidate(Sema& sema, SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, Candidate& outCandidate, MatchFailure& outFail)
    {
        const auto     params    = fn.parameters();
        const auto     numParams = static_cast<uint32_t>(params.size());
        const uint32_t numArgs   = countCallArgs(args, ufcsArg);

        outCandidate.fn = &fn;
        outCandidate.perArg.clear();
        outCandidate.usedDefaults = 0;
        outCandidate.viable       = false;
        outCandidate.ufcsUsed     = ufcsArg.isValid();

        TaskContext&       ctx = sema.ctx();
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
            const TypeInfo&  param   = sema.typeMgr().get(paramTy);

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

            if (param.isCodeBlock())
            {
                outCandidate.perArg.push_back(ConvRank::Exact);
                continue;
            }

            CastFailure        cf{};
            const SemaNodeView argNodeView(sema, argRef, SemaNodeViewPartE::Type);
            TypeRef            argTy = argNodeView.typeRef();

            if (argTy.isInvalid())
            {
                AutoEnumArgProbe probe;
                SWC_RESULT(probeAutoEnumArg(sema, argRef, paramTy, probe, cf));
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
                attachCallCastFailureArgs(cf, fn, mapping.paramArgs[i].callArgIndex, ctx);
                failBadType(outFail, mapping.paramArgs[i].callArgIndex, i, cf);
                return Result::Continue;
            }

            const bool isUfcsArgument = allowsImplicitAddressBinding(fn, i, ufcsArg);
            auto       r              = ConvRank::Bad;
            SWC_RESULT(probeImplicitConversion(sema, r, argRef, argTy, paramTy, cf, isUfcsArgument));
            if (r == ConvRank::Bad)
            {
                if (cf.diagId == DiagnosticId::None)
                {
                    cf.diagId     = DiagnosticId::sema_err_cannot_cast;
                    cf.srcTypeRef = argTy;
                    cf.dstTypeRef = paramTy;
                }
                attachCallCastFailureArgs(cf, fn, mapping.paramArgs[i].callArgIndex, ctx);
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
                for ([[maybe_unused]] const CallArgEntry& entry : mapping.variadicArgs)
                    outCandidate.perArg.push_back(ConvRank::Ellipsis);
            }
            else
            {
                const uint32_t startVariadic = numParams - 1;
                const TypeRef  variadicTy    = params.back()->type(ctx).payloadTypeRef();

                for (const CallArgEntry& entry : mapping.variadicArgs)
                {
                    const AstNodeRef argRef = entry.argRef;
                    const TypeRef    argTy  = sema.viewType(argRef).typeRef();
                    CastFailure      cf{};
                    auto             r = ConvRank::Bad;
                    SWC_RESULT(probeImplicitConversion(sema, r, argRef, argTy, variadicTy, cf, false));
                    if (r == ConvRank::Bad)
                    {
                        if (cf.diagId == DiagnosticId::None)
                        {
                            cf.diagId     = DiagnosticId::sema_err_cannot_cast;
                            cf.srcTypeRef = argTy;
                            cf.dstTypeRef = variadicTy;
                        }
                        // paramIndex points at the variadic parameter
                        attachCallCastFailureArgs(cf, fn, entry.callArgIndex, ctx);
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
        const auto     na = static_cast<uint32_t>(a.perArg.size());
        const auto     nb = static_cast<uint32_t>(b.perArg.size());
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
            else if (s->isAlias())
            {
                const auto* aliased = s->cast<SymbolAlias>().aliasedSymbol();
                if (aliased && aliased->isFunction())
                    fn = &const_cast<Symbol*>(aliased)->cast<SymbolFunction>();
            }
            else if (s->isVariable())
            {
                fn = callableTypeFunction(sema.ctx(), s->typeRef());
            }

            if (!fn)
                continue;

            outFunctionSymbols.push_back(fn);

            Attempt a;
            a.fn = fn;

            if (fn->isGenericRoot())
            {
                MatchFailure fail;
                Candidate    candidate;
                SWC_RESULT(tryInstantiateGenericCandidate(sema, *fn, args, AstNodeRef::invalid(), candidate, fail));
                if (candidate.viable)
                {
                    a.viable    = true;
                    a.candidate = std::move(candidate);
                }

                if (!a.viable && ufcsArg.isValid())
                {
                    candidate = {};
                    fail      = {};
                    SWC_RESULT(tryInstantiateGenericCandidate(sema, *fn, args, ufcsArg, candidate, fail));
                    if (candidate.viable)
                    {
                        a.viable    = true;
                        a.candidate = std::move(candidate);
                    }
                }

                if (!a.viable)
                    a.fail = fail;

                outAttempts.push_back(std::move(a));
                continue;
            }

            MatchFailure fail;
            Candidate    candidate;

            // First: non-UFCS call shape.
            SWC_RESULT(tryBuildCandidate(sema, *fn, args, AstNodeRef::invalid(), candidate, fail));
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
                SWC_RESULT(tryBuildCandidate(sema, *fn, args, ufcsArg, candidate, fail));
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
        const auto      numParams      = static_cast<uint32_t>(params.size());
        const uint32_t  commonParams   = numCommonParamsForFinalize(selectedFnType, numParams);

        for (uint32_t i = 0; i < commonParams; ++i)
        {
            const AstNodeRef argRef  = mapping.paramArgs[i].argRef;
            const TypeRef    paramTy = params[i]->typeRef();
            if (argRef.isValid() && !sema.typeMgr().get(paramTy).isCodeBlock())
                SWC_RESULT(resolveAutoEnumArgFinal(sema, argRef, paramTy));
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
            return raiseAmbiguousBest(sema, nodeCallee.nodeRef(), viable, outSelected->candidate);

        return Result::Continue;
    }

    // For each argument, perform the required cast to the destination parameter type.
    // The cast value is then stored back in the argument node.
    Result applyParameterCasts(Sema& sema, const SymbolFunction& selectedFn, const CallArgMapping& mapping, AstNodeRef appliedUfcsArg)
    {
        const auto& params    = selectedFn.parameters();
        const auto  numParams = static_cast<uint32_t>(params.size());
        uint32_t    numCommon = numParams;
        if (numParams > 0)
        {
            const SymbolVariable* lastParam = params.back();
            SWC_ASSERT(lastParam != nullptr);
            if (lastParam->type(sema.ctx()).isAnyVariadic())
                numCommon = numParams - 1;
        }

        for (uint32_t i = 0; i < numCommon; ++i)
        {
            const AstNodeRef argRef = mapping.paramArgs[i].argRef;
            if (argRef.isInvalid())
                continue;

            if (params[i]->type(sema.ctx()).isCodeBlock())
                continue;

            const AstNodeRef argValueRef = Match::resolveCallArgumentValueRef(sema, argRef);
            SemaNodeView     argView(sema, argValueRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            const TypeRef    paramTypeRef = params[i]->typeRef();
            TypeRef          castTypeRef  = paramTypeRef;
            if (const TypeRef bindValueTypeRef = implicitConstReferenceBindingValueTypeRef(sema, paramTypeRef, argView.typeRef()); bindValueTypeRef.isValid())
                castTypeRef = bindValueTypeRef;

            CastFlags flags = CastFlagsE::Zero;
            if (castTypeRef == paramTypeRef && allowsImplicitAddressBinding(selectedFn, i, appliedUfcsArg))
                flags.add(CastFlagsE::UfcsArgument);
            const DiagnosticArguments errorArguments = makeCallCastErrorArguments(selectedFn, mapping.paramArgs[i].callArgIndex, sema.ctx());
            SWC_RESULT(Cast::cast(sema, argView, castTypeRef, CastKind::Parameter, flags, &errorArguments));
            refreshNamedArgumentPayload(sema, argRef, argView.nodeRef());
        }

        return Result::Continue;
    }

    // For typed variadic functions (e.g., `func(x: ...int)`), each extra argument
    // must be cast to the underlying variadic type.
    Result applyTypedVariadicCasts(Sema& sema, const SymbolFunction& selectedFn, const CallArgMapping& mapping)
    {
        const auto numParams = static_cast<uint32_t>(selectedFn.parameters().size());
        if (numParams == 0)
            return Result::Continue;

        const SymbolVariable* variadicParam = selectedFn.parameters().back();
        SWC_ASSERT(variadicParam != nullptr);
        const TypeInfo& variadicType = variadicParam->type(sema.ctx());
        if (!variadicType.isTypedVariadic())
            return Result::Continue;

        const TypeRef       variadicTy       = variadicType.payloadTypeRef();
        const CallArgEntry& fixedVariadicArg = mapping.paramArgs[numParams - 1];
        if (fixedVariadicArg.argRef.isValid())
        {
            SemaNodeView              argView(sema, fixedVariadicArg.argRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            const DiagnosticArguments errorArguments = makeCallCastErrorArguments(selectedFn, fixedVariadicArg.callArgIndex, sema.ctx());
            SWC_RESULT(Cast::cast(sema, argView, variadicTy, CastKind::Implicit, CastFlagsE::Zero, &errorArguments));
        }

        for (const CallArgEntry& entry : mapping.variadicArgs)
        {
            SemaNodeView              argView(sema, entry.argRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            const DiagnosticArguments errorArguments = makeCallCastErrorArguments(selectedFn, entry.callArgIndex, sema.ctx());
            SWC_RESULT(Cast::cast(sema, argView, variadicTy, CastKind::Implicit, CastFlagsE::Zero, &errorArguments));
        }

        return Result::Continue;
    }

    Result concretizeUntypedVariadicArg(Sema& sema, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return Result::Continue;

        SemaNodeView argView(sema, argRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        if (!argView.type())
            return Result::Continue;

        if (argView.cst())
        {
            ConstantRef newCstRef = ConstantRef::invalid();
            SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, argView.nodeRef(), argView.cstRef(), TypeInfo::Sign::Unknown));
            sema.setConstant(argView.nodeRef(), newCstRef);
            argView = SemaNodeView(sema, argRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        }

        if (!argView.type()->isAggregateArray())
            return Result::Continue;

        const auto& elemTypes = argView.type()->payloadAggregate().types;
        if (elemTypes.empty())
            return Result::Continue;

        const TypeRef firstElemTypeRef = elemTypes.front();
        for (const TypeRef elemTypeRef : elemTypes)
        {
            if (elemTypeRef != firstElemTypeRef)
                return Result::Continue;
        }

        SmallVector4<uint64_t> dims;
        dims.push_back(elemTypes.size());
        const TypeRef concreteArrayTypeRef = sema.typeMgr().addType(TypeInfo::makeArray(dims, firstElemTypeRef));

        SemaNodeView castView(sema, argRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        SWC_RESULT(Cast::cast(sema, castView, concreteArrayTypeRef, CastKind::Implicit));
        return Result::Continue;
    }

    Result concretizeUntypedVariadicArgs(Sema& sema, const SymbolFunction& selectedFn, const CallArgMapping& mapping)
    {
        const auto numParams = static_cast<uint32_t>(selectedFn.parameters().size());
        if (numParams == 0)
            return Result::Continue;

        const SymbolVariable* variadicParam = selectedFn.parameters().back();
        SWC_ASSERT(variadicParam != nullptr);
        const TypeInfo& variadicType = variadicParam->type(sema.ctx());
        if (!variadicType.isVariadic())
            return Result::Continue;

        const CallArgEntry& fixedVariadicArg = mapping.paramArgs[numParams - 1];
        SWC_RESULT(concretizeUntypedVariadicArg(sema, fixedVariadicArg.argRef));

        for (const CallArgEntry& entry : mapping.variadicArgs)
            SWC_RESULT(concretizeUntypedVariadicArg(sema, entry.argRef));

        return Result::Continue;
    }

    AstNodeRef findInterfaceReceiverArg(Sema& sema, const SemaNodeView& nodeCallee)
    {
        if (!nodeCallee.node())
            return AstNodeRef::invalid();

        const AstNodeRef resolvedCalleeRef = SemaHelpers::unwrapCallCalleeRef(sema, nodeCallee.nodeRef());
        if (resolvedCalleeRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& resolvedCalleeNode = sema.node(resolvedCalleeRef);
        if (!resolvedCalleeNode.is(AstNodeId::MemberAccessExpr))
            return AstNodeRef::invalid();
        const auto& memberAccess = resolvedCalleeNode.cast<AstMemberAccessExpr>();

        const SemaNodeView receiverView = sema.viewNodeTypeSymbol(memberAccess.nodeLeftRef);
        if (receiverView.sym() && receiverView.sym()->isImpl())
            return AstNodeRef::invalid();
        if (receiverView.type() && receiverView.type()->isInterface() && sema.isValue(*receiverView.node()))
            return receiverView.nodeRef();

        return AstNodeRef::invalid();
    }

    bool mappedReceiverAsFirstArg(Sema& sema, AstNodeRef receiverArgRef, const CallArgMapping& mapping)
    {
        if (receiverArgRef.isInvalid())
            return false;
        if (mapping.paramArgs.empty())
            return false;

        const AstNodeRef firstArgRef = mapping.paramArgs[0].argRef;
        if (firstArgRef.isInvalid())
            return false;

        return Match::resolveCallArgumentValueRef(sema, firstArgRef) == Match::resolveCallArgumentValueRef(sema, receiverArgRef);
    }

    bool appendImplicitInterfaceReceiverArg(Sema& sema, SmallVector<ResolvedCallArgument>& outResolvedArgs, const SemaNodeView& nodeCallee, const SymbolFunction& selectedFn, const CallArgMapping& mapping)
    {
        if (!selectedFn.hasInterfaceMethodSlot())
            return false;

        // Interface member calls may need an implicit receiver argument carrying the concrete object.
        const AstNodeRef interfaceReceiverArg = findInterfaceReceiverArg(sema, nodeCallee);
        if (interfaceReceiverArg.isInvalid())
            return false;

        // When overload mapping already placed that same receiver as the first argument, do not duplicate it.
        if (mappedReceiverAsFirstArg(sema, interfaceReceiverArg, mapping))
            return false;

        outResolvedArgs.push_back({.argRef = interfaceReceiverArg, .passKind = CallArgumentPassKind::InterfaceObject});
        return true;
    }

    Result assignUntypedVariadicTypeInfo(Sema& sema, ResolvedCallArgument& outResolvedArg)
    {
        if (outResolvedArg.argRef.isInvalid())
            return Result::Continue;

        const SemaNodeView argView = sema.viewType(outResolvedArg.argRef);
        SWC_ASSERT(argView.typeRef().isValid());

        ConstantRef typeInfoCstRef = ConstantRef::invalid();
        SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, argView.typeRef(), outResolvedArg.argRef));
        outResolvedArg.typeInfoCstRef = typeInfoCstRef;
        return Result::Continue;
    }

    AstNodeRef resolveResolvedArgSourceRef(Sema& sema, AstNodeRef argRef)
    {
        AstNodeRef sourceRef = argRef;
        for (;;)
        {
            const AstNode& sourceNode = sema.node(sourceRef);
            if (sourceNode.is(AstNodeId::AutoCastExpr))
            {
                sourceRef = sourceNode.cast<AstAutoCastExpr>().nodeExprRef;
                continue;
            }

            if (sourceNode.is(AstNodeId::CastExpr))
            {
                sourceRef = sourceNode.cast<AstCastExpr>().nodeExprRef;
                continue;
            }

            if (sourceNode.is(AstNodeId::AsCastExpr))
            {
                sourceRef = sourceNode.cast<AstAsCastExpr>().nodeExprRef;
                continue;
            }

            return sourceRef;
        }
    }

    bool bindsReferenceToValue(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return false;

        const TypeInfo& paramType = sema.typeMgr().get(paramTypeRef);
        if (!paramType.isReference())
            return false;

        const AstNodeRef sourceRef     = resolveResolvedArgSourceRef(sema, argRef);
        const TypeRef    sourceTypeRef = sema.viewStored(sourceRef, SemaNodeViewPartE::Type).typeRef();
        if (sourceTypeRef.isInvalid())
            return true;

        const TypeRef   unwrappedSourceTypeRef = sema.typeMgr().get(sourceTypeRef).unwrap(sema.ctx(), sourceTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeRef   resolvedSourceTypeRef  = unwrappedSourceTypeRef.isValid() ? unwrappedSourceTypeRef : sourceTypeRef;
        const TypeInfo& sourceType             = sema.typeMgr().get(resolvedSourceTypeRef);
        return !sourceType.isPointerOrReference();
    }

    TypeRef referenceBindingStorageTypeRef(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef)
    {
        if (argRef.isInvalid() || paramTypeRef.isInvalid())
            return TypeRef::invalid();

        const TypeInfo& paramType = sema.typeMgr().get(paramTypeRef);
        if (!paramType.isReference())
            return TypeRef::invalid();

        const AstNodeRef sourceRef     = resolveResolvedArgSourceRef(sema, argRef);
        const TypeRef    sourceTypeRef = sema.viewStored(sourceRef, SemaNodeViewPartE::Type).typeRef();
        if (!sourceTypeRef.isValid())
            return paramType.payloadTypeRef();

        const TypeRef unwrappedSourceTypeRef = sema.typeMgr().get(sourceTypeRef).unwrap(sema.ctx(), sourceTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (unwrappedSourceTypeRef.isValid())
            return unwrappedSourceTypeRef;

        return sourceTypeRef;
    }

    Result completeReferenceBindingRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        if (SymbolFunction* ownerFunction = sema.currentFunction(); ownerFunction && typeRef.isValid())
        {
            const TypeInfo& symType = sema.typeMgr().get(typeRef);
            SWC_RESULT(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
            ownerFunction->addLocalVariable(sema.ctx(), &symVar);
        }

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    Result attachReferenceBindingRuntimeStorageIfNeeded(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef)
    {
        if (argRef.isInvalid() || sema.isGlobalScope())
            return Result::Continue;

        const TypeRef storageTypeRef = referenceBindingStorageTypeRef(sema, paramTypeRef, argRef);
        if (storageTypeRef.isInvalid())
            return Result::Continue;

        const auto* payload = sema.codeGenPayload<CodeGenNodePayload>(argRef);
        if (payload && payload->runtimeStorageSym != nullptr)
            return Result::Continue;

        if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
        {
            ensureCodeGenNodePayload(sema, argRef).runtimeStorageSym = boundStorage;
            return Result::Continue;
        }

        TaskContext&        ctx         = sema.ctx();
        const IdentifierRef idRef       = SemaHelpers::getUniqueIdentifier(sema, "__call_arg_ref_storage");
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();
        auto*               symVariable = Symbol::make<SymbolVariable>(ctx, &sema.node(argRef), sema.node(argRef).tokRef(), idRef, flags);
        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(symVariable);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            SWC_ASSERT(symMap != nullptr);
            symMap->addSymbol(ctx, symVariable, true);
        }

        symVariable->registerAttributes(sema);
        symVariable->setDeclared(sema.ctx());
        SWC_RESULT(Match::ghosting(sema, *symVariable));
        SWC_RESULT(completeReferenceBindingRuntimeStorageSymbol(sema, *symVariable, storageTypeRef));
        ensureCodeGenNodePayload(sema, argRef).runtimeStorageSym = symVariable;
        return Result::Continue;
    }

    Result buildResolvedCallArgs(Sema& sema, SmallVector<ResolvedCallArgument>& outResolvedArgs, const SemaNodeView& nodeCallee, const SymbolFunction& selectedFn, const CallArgMapping& mapping, AstNodeRef appliedUfcsArg)
    {
        outResolvedArgs.clear();
        appendImplicitInterfaceReceiverArg(sema, outResolvedArgs, nodeCallee, selectedFn, mapping);

        const auto numParams          = static_cast<uint32_t>(selectedFn.parameters().size());
        bool       hasAnyVariadic     = false;
        bool       hasUntypedVariadic = false;
        uint32_t   variadicParamIdx   = 0;
        if (numParams)
        {
            const SymbolVariable* variadicParam = selectedFn.parameters().back();
            SWC_ASSERT(variadicParam != nullptr);
            const TypeInfo& variadicType = variadicParam->type(sema.ctx());
            hasAnyVariadic               = variadicType.isAnyVariadic();
            hasUntypedVariadic           = variadicType.isVariadic();
            variadicParamIdx             = numParams - 1;
        }

        for (uint32_t i = 0; i < mapping.paramArgs.size(); ++i)
        {
            const CallArgEntry& entry          = mapping.paramArgs[i];
            const bool          isVariadicSlot = hasAnyVariadic && numParams && i == numParams - 1;
            if (entry.argRef.isInvalid())
            {
                if (isVariadicSlot)
                    continue;

                ResolvedCallArgument resolvedArg;
                resolvedArg.argRef   = AstNodeRef::invalid();
                resolvedArg.passKind = CallArgumentPassKind::Direct;
                if (i < numParams)
                {
                    const SymbolVariable* param = selectedFn.parameters()[i];
                    SWC_ASSERT(param != nullptr);
                    if (param->hasExtraFlag(SymbolVariableFlagsE::Initialized))
                    {
                        if (param->defaultValueRef().isValid())
                        {
                            resolvedArg.defaultKind   = CallArgumentDefaultKind::Constant;
                            resolvedArg.defaultCstRef = param->defaultValueRef();
                        }
                        else if (SemaHelpers::isDirectCallerLocationDefault(sema, *param))
                        {
                            resolvedArg.defaultKind = CallArgumentDefaultKind::Constant;
                            SWC_RESULT(ConstantHelpers::makeSourceCodeLocation(sema, resolvedArg.defaultCstRef, sema.node(sema.curNodeRef()), SemaHelpers::currentLocationFunction(sema)));
                        }
                    }
                }
                outResolvedArgs.push_back(resolvedArg);
                continue;
            }

            const AstNodeRef finalArgRef = Match::resolveCallArgumentValueRef(sema, entry.argRef);

            auto passKind = CallArgumentPassKind::Direct;
            if (i == 0 && appliedUfcsArg.isValid() && selectedFn.hasInterfaceMethodSlot())
            {
                const SemaNodeView argView = sema.viewType(finalArgRef);
                if (argView.type() && argView.type()->isInterface())
                    passKind = CallArgumentPassKind::InterfaceObject;
            }

            ResolvedCallArgument resolvedArg{
                .argRef                = finalArgRef,
                .passKind              = passKind,
                .bindsReferenceToValue = i < numParams && bindsReferenceToValue(sema, selectedFn.parameters()[i]->typeRef(), finalArgRef),
            };

            if (resolvedArg.bindsReferenceToValue)
                SWC_RESULT(attachReferenceBindingRuntimeStorageIfNeeded(sema, selectedFn.parameters()[i]->typeRef(), finalArgRef));

            if (hasUntypedVariadic && i == variadicParamIdx)
                SWC_RESULT(assignUntypedVariadicTypeInfo(sema, resolvedArg));

            outResolvedArgs.push_back(resolvedArg);
        }

        for (const CallArgEntry& entry : mapping.variadicArgs)
        {
            if (entry.argRef.isInvalid())
                continue;
            const AstNodeRef     finalArgRef = Match::resolveCallArgumentValueRef(sema, entry.argRef);
            ResolvedCallArgument resolvedArg{
                .argRef   = finalArgRef,
                .passKind = CallArgumentPassKind::Direct,
            };

            if (hasUntypedVariadic)
                SWC_RESULT(assignUntypedVariadicTypeInfo(sema, resolvedArg));

            outResolvedArgs.push_back(resolvedArg);
        }

        return Result::Continue;
    }
}

AstNodeRef Match::resolveCallArgumentRef(Sema& sema, AstNodeRef argRef)
{
    AstNodeRef finalRef = sema.viewZero(argRef).nodeRef();
    if (finalRef.isInvalid())
        finalRef = argRef;
    return finalRef;
}

AstNodeRef Match::resolveCallArgumentValueRef(Sema& sema, AstNodeRef argRef)
{
    const AstNodeRef finalRef = resolveCallArgumentRef(sema, argRef);

    const AstNode& finalNode = sema.node(finalRef);
    if (finalNode.is(AstNodeId::NamedArgument))
        return resolveCallArgumentRef(sema, finalNode.cast<AstNamedArgument>().nodeArgRef);

    return finalRef;
}

void Match::resolveCallArgumentValues(Sema& sema, SmallVector<AstNodeRef>& outArgs, std::span<const AstNodeRef> args)
{
    outArgs.clear();
    outArgs.reserve(args.size());
    for (const AstNodeRef argRef : args)
        outArgs.push_back(resolveCallArgumentValueRef(sema, argRef));
}

Result Match::resolveFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SmallVector<ResolvedCallArgument>* outResolvedArgs, ResolveCallMode mode)
{
    SmallVector<Symbol*> filteredSymbols;
    filteredSymbols.reserve(symbols.size());
    for (Symbol* sym : symbols)
    {
        if (!sym)
            continue;
        if (isCallableForMode(*sym, mode))
            filteredSymbols.push_back(sym);
    }

    SmallVector<Symbol*> concreteSymbols;
    SmallVector<Symbol*> runtimeSymbols;
    SWC_RESULT(SemaRuntime::filterRuntimeAccessibleSymbols(sema, nodeCallee.nodeRef(), filteredSymbols.span(), runtimeSymbols));
    removeEmptyFunctionDeclarations(runtimeSymbols, concreteSymbols);

    if (mode == ResolveCallMode::AttributeOnly && !symbols.empty() && filteredSymbols.empty())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_attribute, nodeCallee.nodeRef());

    // Collect all function candidates and evaluate their match quality
    SmallVector<Attempt>         attempts;
    SmallVector<SymbolFunction*> functions;
    SWC_RESULT(collectAttempts(sema, attempts, functions, concreteSymbols.span(), args, ufcsArg));

    // Filter to keep only those that are compatible (viable)
    SmallVector<const Attempt*> viable;
    gatherViableAttempts(attempts, viable);

    // From the viable ones, find the single best candidate.
    // This will raise an error if there are no viable candidates or if the best choice is ambiguous.
    const Attempt* selectedAttempt = nullptr;
    SWC_RESULT(selectBestAttempt(sema, nodeCallee, viable, functions, attempts, args, ufcsArg, selectedAttempt));

    // Finalize the selection by applying required casts and conversions to the arguments
    const AstNodeRef      appliedUfcsArg = selectedAttempt->candidate.ufcsUsed ? ufcsArg : AstNodeRef::invalid();
    const SymbolFunction* selectedFn     = selectedAttempt->candidate.fn;
    CallArgMapping        mapping;
    MatchFailure          mappingFail;
    if (!buildCallArgMapping(sema, *selectedFn, args, appliedUfcsArg, mapping, mappingFail))
        return errorBadMatch(sema, nodeCallee, *selectedFn, mappingFail, args, appliedUfcsArg);

    SWC_RESULT(finalizeAutoEnumArgs(sema, *selectedFn, mapping));
    SWC_RESULT(applyParameterCasts(sema, *selectedFn, mapping, appliedUfcsArg));
    SWC_RESULT(applyTypedVariadicCasts(sema, *selectedFn, mapping));
    SWC_RESULT(concretizeUntypedVariadicArgs(sema, *selectedFn, mapping));
    if (outResolvedArgs)
        SWC_RESULT(buildResolvedCallArgs(sema, *outResolvedArgs, nodeCallee, *selectedFn, mapping, appliedUfcsArg));

    sema.setSymbol(sema.curNodeRef(), selectedFn);
    sema.setIsValue(sema.curNode());
    sema.unsetIsLValue(sema.curNodeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
