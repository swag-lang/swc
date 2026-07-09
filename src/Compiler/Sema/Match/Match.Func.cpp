#include "pch.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void collectExplicitGenericArgNodes(const AstNode& calleeNode, const Ast& ast, SmallVector<AstNodeRef>& outArgs)
    {
        outArgs.clear();

        if (const auto* quotedExpr = calleeNode.safeCast<AstQuotedExpr>())
        {
            if (quotedExpr->nodeSuffixRef.isValid())
                outArgs.push_back(quotedExpr->nodeSuffixRef);
            return;
        }

        if (const auto* quotedList = calleeNode.safeCast<AstQuotedListExpr>())
        {
            ast.appendNodes(outArgs, quotedList->spanChildrenRef);
        }
    }

    Sema* tryCreateSemaForFunctionDecl(Sema& sema, const SymbolFunction& fn, std::unique_ptr<Sema>& ownedSema)
    {
        return sema.tryCreateDeclSema(ownedSema, fn.srcViewRef(), fn.decl(), fn.declNodeRef());
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
        if (!paramType.isReference())
            return TypeRef::invalid();

        const bool isMoveRefParam = paramType.isMoveReference();
        if (!isMoveRefParam && !paramType.isConst())
            return TypeRef::invalid();

        const TypeRef pointeeTypeRef = paramType.payloadTypeRef();
        if (!pointeeTypeRef.isValid())
            return TypeRef::invalid();

        if (!sourceTypeRef.isValid())
            return pointeeTypeRef;

        const TypeRef   unwrappedSourceTypeRef = sema.typeMgr().get(sourceTypeRef).unwrap(sema.ctx(), sourceTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeRef   resolvedSourceTypeRef  = unwrappedSourceTypeRef.isValid() ? unwrappedSourceTypeRef : sourceTypeRef;
        const TypeInfo& sourceType             = sema.typeMgr().get(resolvedSourceTypeRef);

        // A '#move' parameter accepts an UNSIZED literal: the argument is cast to the
        // pointee value and materialized into the call-site temporary like a plain
        // variable. Typed sources keep going through the copy-to-move cast path.
        if (isMoveRefParam)
            return sourceType.isScalarUnsized() ? pointeeTypeRef : TypeRef::invalid();

        if (sourceType.isPointerOrReference())
            return TypeRef::invalid();
        if (sourceType.isStruct())
            return TypeRef::invalid();

        return pointeeTypeRef;
    }

    const SymbolFunction* attributeFunctionFromView(Sema& sema, const SemaNodeView& view)
    {
        SmallVector<Symbol*> symbols;
        view.getSymbols(symbols);
        if (symbols.size() == 1)
        {
            const Symbol* sym = symbols[0];
            if (sym && sym->isFunction())
            {
                const auto& function = sym->cast<SymbolFunction>();
                if (function.isAttribute())
                    return &function;
            }
        }

        if (!view.typeRef().isValid())
            return nullptr;

        const TypeInfo& type = sema.typeMgr().get(view.typeRef());
        if (!type.isFunction())
            return nullptr;

        const auto& function = type.payloadSymFunction();
        return function.isAttribute() ? &function : nullptr;
    }

    Result makeAttributeTypeInfoCallArgument(Sema& sema, AstNodeRef argValueRef, SemaNodeView& argView)
    {
        SemaNodeView          attributeView(sema, argValueRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        const SymbolFunction* attribute = attributeFunctionFromView(sema, attributeView);
        if (!attribute)
            return Result::Continue;

        const TypeRef attributeTypeRef = attributeView.typeRef().isValid() ? attributeView.typeRef() : attribute->typeRef();
        if (!attributeTypeRef.isValid())
            return Result::Continue;

        ConstantRef cstRef;
        SWC_RESULT(sema.makeRuntimeTypeInfo(cstRef, attributeTypeRef, attributeView.nodeRef()));
        sema.setConstant(attributeView.nodeRef(), cstRef);
        argView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        return Result::Continue;
    }

    bool isAttributeTypeInfoCallArgument(Sema& sema, AstNodeRef argRef, TypeRef paramTypeRef)
    {
        if (!argRef.isValid() || !paramTypeRef.isValid())
            return false;

        const TypeInfo& paramType = sema.typeMgr().get(paramTypeRef);
        if (!paramType.isAnyTypeInfo(sema.ctx()))
            return false;

        const AstNodeRef argValueRef = Match::resolveCallArgumentValueRef(sema, argRef);
        if (argValueRef.isInvalid())
            return false;

        const SemaNodeView attributeView(sema, argValueRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        return attributeFunctionFromView(sema, attributeView) != nullptr;
    }

    Result normalizeTypeInfoCallArgument(Sema& sema, AstNodeRef argValueRef, TypeRef paramTypeRef, SemaNodeView& argView)
    {
        if (!argValueRef.isValid() || !paramTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& paramType = sema.typeMgr().get(paramTypeRef);
        if (!paramType.isAnyTypeInfo(sema.ctx()))
            return Result::Continue;
        if (sema.isValue(argValueRef))
        {
            // The argument was already lowered to a typeinfo value (e.g. by a previous overload
            // probe, or passed directly). There is nothing left to normalize: skip the attribute
            // function probe, which would otherwise re-resolve symbols (getSymbols) on every
            // candidate during collection.
            if (argView.typeRef().isValid() && sema.typeMgr().get(argView.typeRef()).isAnyTypeInfo(sema.ctx()))
                return Result::Continue;
            return makeAttributeTypeInfoCallArgument(sema, argValueRef, argView);
        }

        return SemaCheck::isValueOrTypeInfo(sema, argView);
    }

    using SemaHelpers::callableTypeFunction;
    using SemaSymbolLookup::removeEmptyFunctionDeclarations;

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

    bool isAliasPreservingNumericIntrinsic(TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::IntrinsicAbs:
            case TokenId::IntrinsicMin:
            case TokenId::IntrinsicMax:
            case TokenId::IntrinsicRol:
            case TokenId::IntrinsicRor:
            case TokenId::IntrinsicByteSwap:
            case TokenId::IntrinsicBitCountNz:
            case TokenId::IntrinsicBitCountTz:
            case TokenId::IntrinsicBitCountLz:
            case TokenId::IntrinsicAtomicAdd:
            case TokenId::IntrinsicAtomicAnd:
            case TokenId::IntrinsicAtomicOr:
            case TokenId::IntrinsicAtomicXor:
            case TokenId::IntrinsicAtomicXchg:
            case TokenId::IntrinsicAtomicCmpXchg:
                return true;

            default:
                return false;
        }
    }

    bool isIntrinsicAliasStorageMatch(Sema& sema, Match::ResolveCallMode mode, const SymbolFunction& fn, TypeRef argTypeRef, TypeRef paramTypeRef)
    {
        if (mode != Match::ResolveCallMode::Intrinsic || !argTypeRef.isValid() || !paramTypeRef.isValid())
            return false;
        if (!isAliasPreservingNumericIntrinsic(sema.token(fn.codeRef()).id))
            return false;

        const TypeInfo& argType = sema.typeMgr().get(argTypeRef);
        if (!argType.isAlias())
            return false;

        const TypeRef storageTypeRef = argType.unwrap(sema.ctx(), argTypeRef, TypeExpandE::Alias);
        return storageTypeRef.isValid() && storageTypeRef == paramTypeRef;
    }

    enum class ConvRank
    {
        Exact,       // same type (or identical canonical type)
        Standard,    // safe numeric, pointer decay, etc.
        CopyToMove,  // plain value bound to a '#move' parameter via a temporary copy
        MoveToValue, // explicit '#move' argument consumed into a by-value parameter
        Ellipsis,    // varargs fallback (if you support it)
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
        // Conversion ranks are kept per supplied argument, including an injected UFCS
        // receiver when one is used. Later comparison functions can then decide whether
        // to include or ignore that receiver for tie-breaking.
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

    struct SortedAttempt
    {
        const Attempt* a     = nullptr;
        uint32_t       rank  = 0;
        uint32_t       order = 0;
    };

    struct SortedAttemptByRankDesc
    {
        bool operator()(const SortedAttempt& a, const SortedAttempt& b) const
        {
            if (a.rank != b.rank)
                return a.rank > b.rank;
            return a.order < b.order;
        }
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

    const SymbolEnum* enumSymbolFromTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return nullptr;

        const TypeRef   enumTypeRef = sema.typeMgr().get(typeRef).unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
        const TypeInfo& enumType    = sema.typeMgr().get(enumTypeRef);
        if (enumType.isEnum())
            return &enumType.payloadSymEnum();

        return nullptr;
    }

    AstNodeRef autoEnumArgRef(Sema& sema, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return AstNodeRef::invalid();

        AstNodeRef valueRef = argRef;
        if (sema.node(valueRef).is(AstNodeId::NamedArgument))
            valueRef = sema.node(valueRef).cast<AstNamedArgument>().nodeArgRef;

        if (valueRef.isInvalid())
            return AstNodeRef::invalid();
        if (sema.node(valueRef).is(AstNodeId::AutoMemberAccessExpr))
            return valueRef;

        const AstNodeRef substitutedRef = sema.viewZero(valueRef).nodeRef();
        if (substitutedRef.isValid() && sema.node(substitutedRef).is(AstNodeId::AutoMemberAccessExpr))
            return substitutedRef;

        return AstNodeRef::invalid();
    }

    struct CallArgEntry
    {
        AstNodeRef argRef       = AstNodeRef::invalid();
        AstNodeRef valueRef     = AstNodeRef::invalid();
        uint32_t   callArgIndex = 0;
    };

    struct CallArgMapping
    {
        SmallVector<CallArgEntry> paramArgs;
        SmallVector<CallArgEntry> variadicArgs;
        bool                      hasNamed = false;
    };

    AstNodeRef resolvedCallArgValueRef(Sema& sema, const CallArgEntry& entry)
    {
        if (entry.valueRef.isValid())
            return entry.valueRef;
        if (entry.argRef.isInvalid())
            return AstNodeRef::invalid();
        return Match::resolveCallArgumentValueRef(sema, entry.argRef);
    }

    struct GenericRootCallParam
    {
        bool hasDefault = false;
        bool isVariadic = false;
        bool isReceiver = false;
    };

    struct CandidateAttempts
    {
        SmallVector<Attempt>         attempts;
        SmallVector<SymbolFunction*> functions;
        SmallVector<const Attempt*>  viable;
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

    bool isImplicitTrailingCodeBlockArg(Sema& sema, AstNodeRef argRef)
    {
        const AstNode& argNode = sema.node(argRef);
        if (!argNode.is(AstNodeId::CompilerCodeBlock))
            return false;

        const AstNodeRef bodyRef = argNode.cast<AstCompilerCodeBlock>().nodeBodyRef;
        if (bodyRef.isInvalid())
            return false;
        if (!sema.node(bodyRef).is(AstNodeId::EmbeddedBlock))
            return false;

        return sema.node(bodyRef).cast<AstEmbeddedBlock>().hasFlag(AstEmbeddedBlockFlagsE::ImplicitCodeBlockArg);
    }

    bool allowsImplicitAddressBinding(const SymbolFunction& fn, uint32_t paramIndex, AstNodeRef ufcsArg)
    {
        if (ufcsArg.isValid() && paramIndex == 0)
            return true;

        // Binary operator overloads conceptually consume two operands. Keep the right operand
        // addressable as well so invalid-but-diagnosed signatures like `other: &T` still
        // behave consistently with operator syntax while remaining reported to the user.
        const SpecOpKind kind = fn.specOpKind();
        return (kind == SpecOpKind::OpBinary || kind == SpecOpKind::OpBinaryRight) && paramIndex == 1;
    }

    TypeRef unwrapAliasEnumOrSelf(Sema& sema, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return TypeRef::invalid();

        const TypeRef unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        return unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
    }

    // True when the argument expression is an explicit '#move expr' (or the move variant of
    // '#fwd expr'), i.e. a freshly formed move reference, as opposed to reading a variable
    // whose type happens to be a move reference (a documented copy).
    bool isExplicitMoveArgumentNode(Sema& sema, AstNodeRef argRef)
    {
        AstNodeRef valueRef = argRef;
        if (sema.node(valueRef).is(AstNodeId::NamedArgument))
            valueRef = sema.node(valueRef).cast<AstNamedArgument>().nodeArgRef;

        const auto* unary = sema.node(valueRef).safeCast<AstUnaryExpr>();
        if (!unary)
            return false;

        const TokenId tokId = sema.token(unary->codeRef()).id;
        return tokId == TokenId::ModifierMove || tokId == TokenId::ModifierFwd;
    }

    VariadicInfo getVariadicInfo(Sema& sema, const SymbolFunction& fn)
    {
        VariadicInfo vi;
        const auto&  params = fn.parameters();
        if (params.empty())
            return vi;

        const TypeRef   lastParamTypeRef = unwrapAliasEnumOrSelf(sema, params.back()->typeRef());
        const TypeInfo& lastParamTy      = sema.typeMgr().get(lastParamTypeRef);
        vi.isVariadic                    = lastParamTy.isVariadic();
        vi.isTypedVariadic               = lastParamTy.isTypedVariadic();
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

    void recordCallArgFailure(Sema& sema, const SymbolFunction& fn, MatchFailure& outFail, AstNodeRef ufcsArg, uint32_t userArgIndex, DiagnosticId diagId, IdentifierRef idRef = IdentifierRef::invalid(), uint32_t paramIndex = UINT32_MAX, DiagnosticId noteId = DiagnosticId::None, AstNodeRef noteNodeRef = AstNodeRef::invalid(), Utf8 noteValues = {})
    {
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
    }

    Utf8 formatNamedParameters(const Sema& sema, std::span<SymbolVariable* const> params, uint32_t paramStart, uint32_t numParams)
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

        // Build a parameter-indexed view first. That lets type probing stay uniform for
        // positional, named, defaulted, UFCS, and variadic arguments.
        for (uint32_t userIndex = 0; userIndex < args.size(); ++userIndex)
        {
            const AstNodeRef argRef  = args[userIndex];
            const AstNode&   argNode = sema.node(argRef);

            if (argNode.is(AstNodeId::NamedArgument))
            {
                seenNamed           = true;
                outMapping.hasNamed = true;

                const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), argNode.codeRef());

                size_t found = 0;
                if (!fn.tryGetParameterIndexByName(found, idRef, paramStart))
                {
                    const Utf8 namedParams = formatNamedParameters(sema, params, paramStart, numParams);
                    recordCallArgFailure(sema, fn, outFail, ufcsArg, userIndex, DiagnosticId::sema_err_named_argument_unknown, idRef, UINT32_MAX, namedParams.empty() ? DiagnosticId::sema_note_call_has_no_named_arguments : DiagnosticId::sema_note_available_named_arguments, AstNodeRef::invalid(), namedParams);
                    return false;
                }

                if (outMapping.paramArgs[found].argRef.isValid())
                {
                    recordCallArgFailure(sema, fn, outFail, ufcsArg, userIndex, DiagnosticId::sema_err_named_argument_duplicate, idRef, static_cast<uint32_t>(found), DiagnosticId::sema_note_previous_named_argument, outMapping.paramArgs[found].argRef);
                    return false;
                }

                outMapping.paramArgs[found].argRef       = argRef;
                outMapping.paramArgs[found].callArgIndex = callArgIndexFromUserIndex(userIndex, ufcsArg);
                continue;
            }

            if (isImplicitTrailingCodeBlockArg(sema, argRef) &&
                numParams > 0 &&
                params.back()->type(sema.ctx()).isCodeBlock() &&
                !outMapping.paramArgs.back().argRef.isValid())
            {
                outMapping.paramArgs.back().argRef       = argRef;
                outMapping.paramArgs.back().callArgIndex = callArgIndexFromUserIndex(userIndex, ufcsArg);
                continue;
            }

            if (seenNamed)
            {
                recordCallArgFailure(sema, fn, outFail, ufcsArg, userIndex, DiagnosticId::sema_err_unnamed_parameter);
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

    bool isFunctionWhereFailure(DiagnosticId diagId)
    {
        return diagId == DiagnosticId::sema_err_function_where_not_bool ||
               diagId == DiagnosticId::sema_err_function_where_not_const ||
               diagId == DiagnosticId::sema_err_function_where_failed;
    }

    bool isGenericInstantiationFailure(DiagnosticId diagId)
    {
        return diagId == DiagnosticId::sema_err_generic_type_deduction_conflict ||
               diagId == DiagnosticId::sema_err_generic_value_deduction_conflict ||
               diagId == DiagnosticId::sema_err_generic_parameter_not_deduced ||
               isFunctionWhereFailure(diagId);
    }

    const Utf8* castFailureUtf8Argument(const CastFailure& failure, std::string_view name)
    {
        for (const auto& arg : failure.arguments)
        {
            if (arg.name != name)
                continue;

            if (const auto* value = std::get_if<Utf8>(&arg.val))
                return value;
        }

        return nullptr;
    }

    Utf8 formatFunctionWhereFailureBindings(const CastFailure& failure)
    {
        const Utf8* values = castFailureUtf8Argument(failure, Diagnostic::ARG_VALUES);
        if (!values || values->empty())
            return {};

        Utf8 result = " for generic arguments '";
        result += *values;
        result += "'";
        return result;
    }

    void addFunctionWhereFailureNotes(Sema& sema, Diagnostic& diag, const CastFailure& failure)
    {
        if (!isFunctionWhereFailure(failure.diagId))
            return;

        if (const Utf8* values = castFailureUtf8Argument(failure, Diagnostic::ARG_VALUES))
        {
            if (!values->empty())
            {
                diag.addNote(DiagnosticId::sema_note_generic_instantiated_with);
                diag.last().addArgument(Diagnostic::ARG_VALUES, *values);
            }
        }

        if (failure.noteNodeRef.isValid())
        {
            diag.addNote(DiagnosticId::sema_note_generic_where_declared_here);
            SemaError::addSpan(sema, diag.last(), failure.noteNodeRef);
        }
        else if (failure.noteCodeRef.isValid())
        {
            diag.addNote(DiagnosticId::sema_note_generic_where_declared_here);
            const SourceView& srcView = sema.ctx().compiler().srcView(failure.noteCodeRef.srcViewRef);
            diag.last().addSpan(srcView.tokenCodeRange(sema.ctx(), failure.noteCodeRef.tokRef));
        }
    }

    Utf8 makeCandidateFailureText(const SymbolFunction& fn, const MatchFailure& fail, const TaskContext& ctx)
    {
        if (fail.kind == MatchFailKind::InvalidArgumentType)
        {
            if (fail.castFailure.diagId != DiagnosticId::None)
            {
                if (isFunctionWhereFailure(fail.castFailure.diagId))
                {
                    const Utf8 bindingText = formatFunctionWhereFailureBindings(fail.castFailure);
                    switch (fail.castFailure.diagId)
                    {
                        case DiagnosticId::sema_err_function_where_not_bool:
                        {
                            const Utf8 typeName = fail.castFailure.srcTypeRef.isValid() ? ctx.typeMgr().get(fail.castFailure.srcTypeRef).toName(ctx) : Utf8{"<invalid>"};
                            return std::format("its 'where' constraint has type '{}' instead of 'bool'{}", typeName, bindingText);
                        }

                        case DiagnosticId::sema_err_function_where_not_const:
                            return std::format("its 'where' constraint is not a compile-time constant{}", bindingText);

                        case DiagnosticId::sema_err_function_where_failed:
                            return std::format("its 'where' constraint evaluated to false{}", bindingText);

                        default:
                            break;
                    }
                }

                if (fail.castFailure.diagId == DiagnosticId::sema_err_fwd_not_copyable)
                {
                    const Utf8 typeName = fail.castFailure.srcTypeRef.isValid() ? ctx.typeMgr().get(fail.castFailure.srcTypeRef).toName(ctx) : Utf8{"<invalid>"};
                    if (const SymbolVariable* param = failedParameter(fn, fail))
                        return std::format("its '#fwd' parameter '{}' cannot take a copy of non-copyable type '{}'; pass the value with '#move'", param->name(ctx), typeName);
                    return std::format("its '#fwd' parameter cannot take a copy of non-copyable type '{}'; pass the value with '#move'", typeName);
                }

                if (fail.castFailure.diagId == DiagnosticId::sema_err_move_arg_not_copyable)
                {
                    const Utf8 typeName = fail.castFailure.srcTypeRef.isValid() ? ctx.typeMgr().get(fail.castFailure.srcTypeRef).toName(ctx) : Utf8{"<invalid>"};
                    if (const SymbolVariable* param = failedParameter(fn, fail))
                        return std::format("its '#move' parameter '{}' cannot take a copy of non-copyable type '{}'; pass the value with '#move'", param->name(ctx), typeName);
                    return std::format("its '#move' parameter cannot take a copy of non-copyable type '{}'; pass the value with '#move'", typeName);
                }

                if (fail.castFailure.diagId == DiagnosticId::sema_err_move_arg_param_not_move)
                {
                    if (const SymbolVariable* param = failedParameter(fn, fail))
                        return std::format("its reference parameter '{}' cannot take a '#move' argument", param->name(ctx));
                    return Utf8{"its reference parameter cannot take a '#move' argument"};
                }

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
                        }
                        else
                        {
                            diagElement.addArgument(Diagnostic::ARG_WHAT, makeCandidateFailureText(fn, fail, ctx));
                        }
                    }
                    (void) addCastFailureArgs(diagElement, fail.castFailure);
                    if (isNote && diagElement.id() == DiagnosticId::sema_note_overload_candidate_argument_type)
                    {
                        if (const SymbolVariable* param = declaredFailedParameter(fn, fail))
                            diagElement.addArgument(Diagnostic::ARG_TOK, Utf8{param->name(ctx)});
                    }
                    addCastFailureNote(sema, diag, fail.castFailure);
                    addFunctionWhereFailureNotes(sema, diag, fail.castFailure);
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

    template<typename ADD_NOTE_FN>
    void addOverloadFailureNotes(Sema& sema, Diagnostic& diag, const SmallVector<SortedAttempt>& sorted, std::span<AstNodeRef> args, AstNodeRef ufcsArg, const ADD_NOTE_FN& shouldSkip)
    {
        TaskContext& ctx = sema.ctx();

        int count = 0;
        for (const auto& sa : sorted)
        {
            const Attempt& a = *(sa.a);
            if (shouldSkip(a))
                continue;

            if (count >= 5)
            {
                int remaining = 0;
                for (const auto& sb : sorted)
                {
                    if (!shouldSkip(*sb.a))
                        remaining++;
                }

                diag.addNote(DiagnosticId::sema_note_too_many_overloads);
                diag.last().addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(remaining - count));
                break;
            }

            count++;
            diag.addNote(overloadCandidateDiagnosticId(a.fail));
            diag.last().addArgument(Diagnostic::ARG_SYM, a.fn->isTyped() ? a.fn->type(ctx).toName(ctx) : Utf8{a.fn->name(ctx)});
            fillMatchDiagnostic(sema, diag.last(), diag, *a.fn, a.fail, args, ufcsArg, true);
        }
    }

    Result errorGenericInstantiationFailure(Sema& sema, const SemaNodeView& nodeCallee, const Attempt& primary, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        const TaskContext& ctx = sema.ctx();

        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_generic_function_instantiation_failed, nodeCallee.nodeRef());
        diag.last().addArgument(Diagnostic::ARG_SYM, primary.fn->name(ctx));
        fillMatchDiagnostic(sema, diag.last(), diag, *primary.fn, primary.fail, args, ufcsArg, false);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result errorNoOverloadMatch(Sema& sema, const SemaNodeView& nodeCallee, const SmallVector<Attempt>& attempts, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        const TaskContext& ctx = sema.ctx();

        SmallVector<SortedAttempt> sorted;
        uint32_t                   order = 0;
        for (const Attempt& a : attempts)
        {
            if (!a.fn || a.viable)
            {
                order++;
                continue;
            }

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

            sorted.push_back({.a = &a, .rank = rank, .order = order});
            order++;
        }

        std::ranges::sort(sorted, SortedAttemptByRankDesc{});

        if (!sorted.empty())
        {
            const uint32_t bestRank = sorted.front().rank;
            for (const auto& sa : sorted)
            {
                if (sa.rank != bestRank)
                    break;

                const Attempt& a = *sa.a;
                if (a.fail.kind == MatchFailKind::InvalidArgumentType && isGenericInstantiationFailure(a.fail.castFailure.diagId))
                    return errorGenericInstantiationFailure(sema, nodeCallee, a, args, ufcsArg);
            }
        }

        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_no_overload_match, nodeCallee.nodeRef());
        if (!attempts.empty())
            diag.last().addArgument(Diagnostic::ARG_SYM, attempts.front().fn->name(ctx));

        addOverloadFailureNotes(sema, diag, sorted, args, ufcsArg, [](const Attempt&) { return false; });

        diag.report(sema.ctx());
        return Result::Error;
    }

    // Probes if an implicit conversion from 'from' to 'to' is possible and returns its rank.
    Result probeImplicitConversion(Sema& sema, ConvRank& outRank, AstNodeRef argRef, TypeRef from, TypeRef to, CastFailure& outCastFailure, bool isUfcsArgument, bool allowUserDefinedLiteralSuffix)
    {
        outRank = ConvRank::Bad;
        UserDefinedLiteralSuffixInfo suffixInfo;
        const bool                   hasUserDefinedLiteralSuffix = Cast::resolveUserDefinedLiteralSuffix(sema, argRef, suffixInfo);
        if (from == to && (!hasUserDefinedLiteralSuffix || allowUserDefinedLiteralSuffix))
        {
            outRank = ConvRank::Exact;
            return Result::Continue;
        }

        const AstNodeRef argValueRef = Match::resolveCallArgumentValueRef(sema, argRef);
        SemaNodeView     argNodeView(sema, argValueRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        auto             castKind  = CastKind::Parameter;
        CastFlags        castFlags = CastFlagsE::Zero;
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
        const bool readOnlyParamPath         = SemaCheck::isReadOnlyParameterPath(sema, argNodeView.nodeRef());
        const bool targetBindsMutableStorage = to.isValid() && (sema.typeMgr().get(to).isReference() || sema.typeMgr().get(to).isAnyPointer() || sema.typeMgr().get(to).isMoveReference());
        if ((argNodeView.sym() && argNodeView.sym()->isConstant()) ||
            SemaCheck::isConstAssignmentTarget(sema, argNodeView.nodeRef(), argNodeView) ||
            (readOnlyParamPath && (isUfcsArgument || targetBindsMutableStorage)) ||
            (argNodeView.cstRef().isValid() && !argNodeView.hasSymbol()))
            castFlags.add(CastFlagsE::ConstSource);

        const TypeRef bindValueTypeRef = implicitConstReferenceBindingValueTypeRef(sema, to, from);
        const TypeRef castToTypeRef    = bindValueTypeRef.isValid() ? bindValueTypeRef : to;
        SWC_RESULT(normalizeTypeInfoCallArgument(sema, argValueRef, castToTypeRef, argNodeView));
        from = argNodeView.typeRef().isValid() ? argNodeView.typeRef() : from;

        CastRequest castRequest(castKind);
        castRequest.flags        = castFlags;
        castRequest.errorNodeRef = argValueRef;
        if (castKind == CastKind::Parameter)
            castRequest.flags.add(CastFlagsE::AllowCopyToMoveRef);
        // Overload probing only needs the allow/deny + rank decision; the selected overload
        // re-runs the real cast (with folding) in applyParameterCasts. Skip throwaway
        // fold-result materialization (whole-value lowering, aggregate/array fold interning).
        castRequest.probing = true;
        castRequest.setConstantFoldingSrc(argNodeView.cstRef());
        if (isUfcsArgument)
            castRequest.flags.add(CastFlagsE::UfcsArgument);
        if (allowUserDefinedLiteralSuffix)
            castRequest.flags.add(CastFlagsE::LiteralSuffixConsume);
        const Result castResult = Cast::castAllowed(sema, castRequest, from, castToTypeRef);
        if (castResult == Result::Pause)
            return Result::Pause;
        if (castResult == Result::Continue)
        {
            // An untyped literal binding a '#move' parameter through its pointee value is a
            // copy-to-move as well: a dedicated copy overload ('#fwd') must stay preferred.
            const bool bindsValueToMoveRef = bindValueTypeRef.isValid() && sema.typeMgr().get(to).isMoveReference();

            outRank = (castRequest.usedCopyToMoveRef || bindsValueToMoveRef) ? ConvRank::CopyToMove : ConvRank::Standard;
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
        const AstNodeRef finalArgRef = autoEnumArgRef(sema, argRef);
        if (finalArgRef.isInvalid())
            return Result::Continue;
        const AstNode& argNode = sema.node(finalArgRef);
        const auto&    autoMem = argNode.cast<AstAutoMemberAccessExpr>();

        const SymbolEnum* enumSym = enumSymbolFromTypeRef(sema, paramTy);
        if (!enumSym)
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(enumSym, argNode.codeRef()));

        const SemaNodeView  nodeRightView(sema, autoMem.nodeIdentRef, SemaNodeViewPartE::Node);
        const TokenRef      tokNameRef = nodeRightView.node()->tokRef();
        const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), nodeRightView.node()->codeRef());

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = SourceCodeRef{argNode.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint    = enumSym;
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
            const Utf8 availableValues = SemaError::formatEnumValueList(sema.ctx(), *enumSym);
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
        const AstNodeRef finalArgRef = autoEnumArgRef(sema, argRef);
        if (finalArgRef.isInvalid())
            return Result::Continue;
        const AstNode& argNode = sema.node(finalArgRef);
        const auto&    autoMem = argNode.cast<AstAutoMemberAccessExpr>();

        const SymbolEnum* enumSym = enumSymbolFromTypeRef(sema, paramTy);
        if (!enumSym)
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(enumSym, argNode.codeRef()));

        const SemaNodeView  nodeRightView(sema, autoMem.nodeIdentRef, SemaNodeViewPartE::Node);
        const TokenRef      tokNameRef = nodeRightView.node()->tokRef();
        const IdentifierRef idRef      = sema.idMgr().addIdentifier(sema.ctx(), nodeRightView.node()->codeRef());

        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{argNode.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = enumSym;

        // Keep normal wait semantics here (noWaitOnEmpty = false) to behave like `Enum.Value`.
        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        if (lookUpCxt.empty())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_auto_scope_missing_enum_value, argRef);
            diag.addArgument(Diagnostic::ARG_VALUE, sema.idMgr().get(idRef).name);
            diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, paramTy);
            const Utf8 availableValues = SemaError::formatEnumValueList(sema.ctx(), *enumSym);
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
        sema.setSymbol(leftRef, enumSym);
        sema.setIsValue(*leftPtr);

        memberPtr->nodeLeftRef  = leftRef;
        memberPtr->nodeRightRef = autoMem.nodeIdentRef;

        sema.setSymbolList(memberRef, lookUpCxt.symbols());
        sema.setSymbolList(autoMem.nodeIdentRef, lookUpCxt.symbols());
        AstNodeRef substituteRef = memberRef;
        if (paramTy != enumSym->typeRef())
            substituteRef = Cast::createCastNode(sema, paramTy, memberRef);
        sema.setSubstitute(argRef, substituteRef);
        sema.setIsValue(*memberPtr);

        return Result::Continue;
    }

    bool applyContextualAutoEnumAliasCast(Sema& sema, AstNodeRef argRef, SemaNodeView& argView, TypeRef paramTypeRef)
    {
        if (autoEnumArgRef(sema, argRef).isInvalid())
            return false;

        const SymbolEnum* enumSym = enumSymbolFromTypeRef(sema, paramTypeRef);
        if (!enumSym || paramTypeRef == enumSym->typeRef())
            return false;
        if (argView.typeRef() != enumSym->typeRef())
            return false;

        argView.nodeRef() = Cast::createCast(sema, paramTypeRef, argView.nodeRef());
        argView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        return true;
    }

    bool isMatchingTypedVariadicForwardingArg(Sema& sema, AstNodeRef argRef, TypeRef variadicTypeRef)
    {
        if (argRef.isInvalid() || !variadicTypeRef.isValid())
            return false;

        const AstNodeRef argValueRef = Match::resolveCallArgumentValueRef(sema, argRef);
        const TypeRef    argTypeRef  = sema.viewType(argValueRef).typeRef();
        if (!argTypeRef.isValid())
            return false;

        const TypeInfo& argType = sema.typeMgr().get(argTypeRef);
        return argType.isTypedVariadic() && argType.payloadTypeRef() == variadicTypeRef;
    }

    Result probeTypedVariadicArgument(Sema& sema, const SymbolFunction& fn, const CallArgEntry& entry, TypeRef variadicTy, uint32_t variadicParamIndex, bool allowForwarding, Candidate& outCandidate, MatchFailure& outFail)
    {
        if (entry.argRef.isInvalid())
            return Result::Continue;

        const AstNodeRef argValueRef = Match::resolveCallArgumentValueRef(sema, entry.argRef);
        const TypeRef    argTy       = sema.viewType(argValueRef).typeRef();
        CastFailure      cf{};

        if (argTy.isInvalid())
        {
            cf.diagId     = DiagnosticId::sema_err_cannot_cast;
            cf.srcTypeRef = argTy;
            cf.dstTypeRef = variadicTy;
            attachCallCastFailureArgs(cf, fn, entry.callArgIndex, sema.ctx());
            failBadType(outFail, entry.callArgIndex, variadicParamIndex, cf);
            return Result::Continue;
        }

        const TypeInfo& argType = sema.typeMgr().get(argTy);
        if (argType.isTypedVariadic())
        {
            if (allowForwarding && argType.payloadTypeRef() == variadicTy)
            {
                outCandidate.perArg.push_back(ConvRank::Exact);
                return Result::Continue;
            }

            cf.diagId     = DiagnosticId::sema_err_cannot_cast;
            cf.srcTypeRef = argTy;
            cf.dstTypeRef = variadicTy;
            attachCallCastFailureArgs(cf, fn, entry.callArgIndex, sema.ctx());
            failBadType(outFail, entry.callArgIndex, variadicParamIndex, cf);
            return Result::Continue;
        }

        auto r = ConvRank::Bad;
        SWC_RESULT(probeImplicitConversion(sema, r, entry.argRef, argTy, variadicTy, cf, false, false));
        if (r == ConvRank::Bad)
        {
            if (cf.diagId == DiagnosticId::None)
            {
                cf.diagId     = DiagnosticId::sema_err_cannot_cast;
                cf.srcTypeRef = argTy;
                cf.dstTypeRef = variadicTy;
            }

            attachCallCastFailureArgs(cf, fn, entry.callArgIndex, sema.ctx());
            failBadType(outFail, entry.callArgIndex, variadicParamIndex, cf);
            return Result::Continue;
        }

        outCandidate.perArg.push_back(r);
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

    TypeRef builtinTypeRef(Sema& sema, const AstBuiltinType& builtinType)
    {
        const Token&       tok     = sema.token(builtinType.codeRef());
        const TypeManager& typeMgr = sema.typeMgr();

        switch (tok.id)
        {
            case TokenId::TypeS8:
                return typeMgr.typeInt(8, TypeInfo::Sign::Signed);
            case TokenId::TypeS16:
                return typeMgr.typeInt(16, TypeInfo::Sign::Signed);
            case TokenId::TypeS32:
                return typeMgr.typeInt(32, TypeInfo::Sign::Signed);
            case TokenId::TypeS64:
                return typeMgr.typeInt(64, TypeInfo::Sign::Signed);
            case TokenId::TypeU8:
                return typeMgr.typeInt(8, TypeInfo::Sign::Unsigned);
            case TokenId::TypeU16:
                return typeMgr.typeInt(16, TypeInfo::Sign::Unsigned);
            case TokenId::TypeU32:
                return typeMgr.typeInt(32, TypeInfo::Sign::Unsigned);
            case TokenId::TypeU64:
                return typeMgr.typeInt(64, TypeInfo::Sign::Unsigned);
            case TokenId::TypeF32:
                return typeMgr.typeF32();
            case TokenId::TypeF64:
                return typeMgr.typeF64();
            case TokenId::TypeBool:
                return typeMgr.typeBool();
            case TokenId::TypeString:
                return typeMgr.typeString();
            case TokenId::TypeVoid:
                return typeMgr.typeVoid();
            case TokenId::TypeAny:
                return typeMgr.typeAny();
            case TokenId::TypeCString:
                return typeMgr.typeCString();
            case TokenId::TypeRune:
                return typeMgr.typeRune();
            case TokenId::TypeTypeInfo:
                return typeMgr.typeTypeInfo();
            default:
                return TypeRef::invalid();
        }
    }

    TypeRef typeRefFromTypeNode(Sema& sema, AstNodeRef typeNodeRef)
    {
        if (typeNodeRef.isInvalid())
            return TypeRef::invalid();

        const TypeRef typeRef = sema.viewType(typeNodeRef).typeRef();
        if (typeRef.isValid())
            return typeRef;

        const AstNode& typeNode = sema.node(typeNodeRef);
        if (const auto* builtinType = typeNode.safeCast<AstBuiltinType>())
            return builtinTypeRef(sema, *builtinType);

        if (const auto* codeType = typeNode.safeCast<AstCodeType>())
        {
            const TypeRef payloadTypeRef = typeRefFromTypeNode(sema, codeType->nodeTypeRef);
            return payloadTypeRef.isValid() ? sema.typeMgr().addType(TypeInfo::makeCodeBlock(payloadTypeRef)) : TypeRef::invalid();
        }

        if (typeNode.is(AstNodeId::VariadicType))
            return sema.typeMgr().typeVariadic();

        if (const auto* typedVariadicType = typeNode.safeCast<AstTypedVariadicType>())
        {
            const TypeRef elementTypeRef = typeRefFromTypeNode(sema, typedVariadicType->nodeTypeRef);
            return elementTypeRef.isValid() ? sema.typeMgr().addType(TypeInfo::makeTypedVariadic(elementTypeRef)) : TypeRef::invalid();
        }

        if (const auto* refType = typeNode.safeCast<AstReferenceType>())
        {
            const TypeRef pointeeTypeRef = typeRefFromTypeNode(sema, refType->nodePointeeTypeRef);
            return pointeeTypeRef.isValid() ? sema.typeMgr().addType(TypeInfo::makeReference(pointeeTypeRef)) : TypeRef::invalid();
        }

        if (const auto* moveRefType = typeNode.safeCast<AstMoveRefType>())
        {
            const TypeRef pointeeTypeRef = typeRefFromTypeNode(sema, moveRefType->nodePointeeTypeRef);
            return pointeeTypeRef.isValid() ? sema.typeMgr().addType(TypeInfo::makeMoveReference(pointeeTypeRef)) : TypeRef::invalid();
        }

        if (const auto* valuePtrType = typeNode.safeCast<AstValuePointerType>())
        {
            const TypeRef pointeeTypeRef = typeRefFromTypeNode(sema, valuePtrType->nodePointeeTypeRef);
            return pointeeTypeRef.isValid() ? sema.typeMgr().addType(TypeInfo::makeValuePointer(pointeeTypeRef)) : TypeRef::invalid();
        }

        if (const auto* blockPtrType = typeNode.safeCast<AstBlockPointerType>())
        {
            const TypeRef pointeeTypeRef = typeRefFromTypeNode(sema, blockPtrType->nodePointeeTypeRef);
            return pointeeTypeRef.isValid() ? sema.typeMgr().addType(TypeInfo::makeBlockPointer(pointeeTypeRef)) : TypeRef::invalid();
        }

        if (const auto* sliceType = typeNode.safeCast<AstSliceType>())
        {
            const TypeRef elementTypeRef = typeRefFromTypeNode(sema, sliceType->nodePointeeTypeRef);
            return elementTypeRef.isValid() ? sema.typeMgr().addType(TypeInfo::makeSlice(elementTypeRef)) : TypeRef::invalid();
        }

        if (const auto* namedType = typeNode.safeCast<AstNamedType>())
        {
            const SemaNodeView identView = sema.viewNodeTypeSymbol(namedType->nodeIdentRef);
            if (identView.typeRef().isValid())
                return identView.typeRef();
            if (identView.sym() && identView.sym()->isType())
                return identView.sym()->typeRef();

            if (const auto* ident = sema.node(namedType->nodeIdentRef).safeCast<AstIdentifier>())
            {
                MatchContext lookUpCxt;
                lookUpCxt.codeRef         = ident->codeRef();
                lookUpCxt.noWaitOnEmpty   = true;
                const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
                if (Match::match(sema, lookUpCxt, idRef) == Result::Continue)
                {
                    for (const Symbol* sym : lookUpCxt.symbols())
                    {
                        if (sym && sym->isType() && sym->typeRef().isValid())
                            return sym->typeRef();
                    }
                }
            }
        }

        return TypeRef::invalid();
    }

    TypeRef safeNamedTypeRef(Sema& sema, const AstNamedType& namedType)
    {
        const SemaNodeView identView = sema.viewStored(namedType.nodeIdentRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
        if (identView.typeRef().isValid())
            return identView.typeRef();
        if (identView.sym() && identView.sym()->isType())
            return identView.sym()->typeRef();

        const auto* ident = sema.node(namedType.nodeIdentRef).safeCast<AstIdentifier>();
        if (!ident)
            return TypeRef::invalid();

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = ident->codeRef();
        lookUpCxt.noWaitOnEmpty = true;

        const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, ident->codeRef());
        if (Match::match(sema, lookUpCxt, idRef) != Result::Continue)
            return TypeRef::invalid();

        for (const Symbol* sym : lookUpCxt.symbols())
        {
            if (sym && sym->isType() && sym->typeRef().isValid())
                return sym->typeRef();
        }

        return TypeRef::invalid();
    }

    bool isVariadicTypeRefOrAlias(Sema& sema, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return false;

        const TypeRef unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        const TypeRef effectiveTypeRef = unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
        return sema.typeMgr().get(effectiveTypeRef).isAnyVariadic();
    }

    bool isVariadicTypeNode(Sema& sema, AstNodeRef typeNodeRef, bool resolveAliases)
    {
        if (typeNodeRef.isInvalid())
            return false;

        const AstNode& typeNode = sema.node(typeNodeRef);
        if (typeNode.is(AstNodeId::VariadicType) || typeNode.is(AstNodeId::TypedVariadicType))
            return true;
        if (!resolveAliases)
        {
            if (const auto* namedType = typeNode.safeCast<AstNamedType>())
                return isVariadicTypeRefOrAlias(sema, safeNamedTypeRef(sema, *namedType));
            return false;
        }

        const TypeRef typeRef = typeRefFromTypeNode(sema, typeNodeRef);
        return isVariadicTypeRefOrAlias(sema, typeRef);
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
            outParams.push_back({.hasDefault = varDecl->nodeInitRef.isValid(), .isVariadic = isVariadicTypeNode(sema, typeRef, false)});
            return;
        }

        if (const auto* multiVar = paramNode->safeCast<AstMultiVarDecl>())
        {
            SmallVector<TokenRef> tokNames;
            sema.ast().appendTokens(tokNames, multiVar->spanNamesRef);
            const AstNodeRef typeRef    = multiVar->typeOrInitRef();
            const bool       hasDefault = multiVar->nodeInitRef.isValid();
            const bool       isVariadic = isVariadicTypeNode(sema, typeRef, false);
            for ([[maybe_unused]] const TokenRef tokNameRef : tokNames)
                outParams.push_back({.hasDefault = hasDefault, .isVariadic = isVariadic});
            return;
        }

        if (paramNode->is(AstNodeId::FunctionParamMe))
            outParams.push_back({.isReceiver = true});
    }

    bool genericRootParamsExposeReceiver(std::span<const GenericRootCallParam> params)
    {
        return !params.empty() && params.front().isReceiver;
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

    Result tryBuildCandidate(Sema& sema, SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, Match::ResolveCallMode mode, Candidate& outCandidate, MatchFailure& outFail);

    Result precheckGenericCallShape(Sema& sema, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, MatchFailure& outFail)
    {
        outFail = {};

        if (fn.parameters().empty())
        {
            std::unique_ptr<Sema> declSemaHolder;
            Sema*                 declSema = tryCreateSemaForFunctionDecl(sema, fn, declSemaHolder);
            if (!declSema)
                declSema = &sema;
            const auto* decl = fn.decl() ? fn.decl()->safeCast<AstFunctionDecl>() : nullptr;
            if (!decl || decl->nodeParamsRef.isInvalid())
                return Result::Continue;

            SmallVector<AstNodeRef> paramNodes;
            const AstNode&          paramsNode = declSema->node(decl->nodeParamsRef);
            if (paramsNode.is(AstNodeId::FunctionParamList))
                declSema->ast().appendNodes(paramNodes, paramsNode.cast<AstFunctionParamList>().spanChildrenRef);
            else
                paramsNode.collectChildrenFromAst(paramNodes, declSema->ast());

            SmallVector<GenericRootCallParam> params;
            for (const AstNodeRef paramRef : paramNodes)
                appendGenericRootCallParams(*declSema, paramRef, params);

            const uint32_t numParams      = static_cast<uint32_t>(params.size());
            const bool     prependUfcsArg = ufcsArg.isValid() && (!fn.isMethod() || genericRootParamsExposeReceiver(params.span()));
            const uint32_t numArgs        = static_cast<uint32_t>(args.size()) + (prependUfcsArg ? 1u : 0u);
            const bool     variadic       = !params.empty() && params.back().isVariadic;

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

    Result tryInstantiateGenericCandidate(Sema& sema, SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, std::span<const AstNodeRef> explicitGenericArgNodes, Match::ResolveCallMode mode, bool suppressInstantiationErrors, Candidate& outCandidate, MatchFailure& outFail)
    {
        outCandidate = {};
        outFail      = {};

        // Shape precheck is deliberately cheap and runs before generic instantiation:
        // it avoids producing speculative instances for arities that cannot possibly
        // match this call.
        SWC_RESULT(precheckGenericCallShape(sema, fn, args, ufcsArg, outFail));
        if (outFail.active)
            return Result::Continue;

        SymbolFunction* concreteFn          = nullptr;
        CastFailure     genericFailure      = {};
        uint32_t        genericFailureIndex = UINT32_MAX;
        auto            instantiateResult   = Result::Continue;
        if (suppressInstantiationErrors)
        {
            const bool savedSilent = sema.ctx().silentDiagnostic();
            sema.ctx().setSilentDiagnostic(true);
            instantiateResult = SemaGeneric::instantiateFunctionFromCall(sema, fn, args, ufcsArg, explicitGenericArgNodes, concreteFn, &genericFailure, &genericFailureIndex);
            sema.ctx().setSilentDiagnostic(savedSilent);
        }
        else
        {
            instantiateResult = SemaGeneric::instantiateFunctionFromCall(sema, fn, args, ufcsArg, explicitGenericArgNodes, concreteFn, &genericFailure, &genericFailureIndex);
        }
        if (instantiateResult == Result::Pause)
            return Result::Pause;
        if (instantiateResult != Result::Continue)
            return suppressInstantiationErrors ? Result::Continue : instantiateResult;
        if (!concreteFn)
        {
            if (genericFailure.diagId != DiagnosticId::None)
                failBadType(outFail, genericFailureIndex == UINT32_MAX ? 0 : genericFailureIndex, 0, genericFailure, genericFailureIndex != UINT32_MAX);
            return Result::Continue;
        }

        return tryBuildCandidate(sema, *concreteFn, args, ufcsArg, mode, outCandidate, outFail);
    }

    bool canDeferWhereConstraintFailure(const SymbolFunction& fn, const CastFailure& failure)
    {
        return failure.diagId == DiagnosticId::sema_err_function_where_not_const && fn.hasUnmaterializedGenericBody();
    }

    // Probe one concrete function against one call shape. This pass records viability
    // and ranks only; the selected overload will later perform the real casts and
    // substitutions so failed candidates do not mutate the AST.
    Result tryBuildCandidate(Sema& sema, SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, Match::ResolveCallMode mode, Candidate& outCandidate, MatchFailure& outFail)
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

        bool        whereSatisfied = true;
        CastFailure whereFailure;
        SWC_RESULT(SemaGeneric::evaluateFunctionWhereConstraints(sema, whereSatisfied, fn, &whereFailure));
        if (!whereSatisfied)
        {
            if (!canDeferWhereConstraintFailure(fn, whereFailure))
            {
                failBadType(outFail, 0, 0, whereFailure, false);
                return Result::Continue;
            }
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

            // The copy variant of a '#fwd' parameter only accepts copyable types: for a
            // non-copyable type the candidate is discarded (like an implicit 'where'
            // constraint), leaving only the move variant.
            if (params[i]->hasExtraFlag(SymbolVariableFlagsE::FwdCopy))
            {
                const TypeRef   fwdTypeRef = unwrapAliasEnumOrSelf(sema, paramTy);
                const TypeInfo& fwdType    = sema.typeMgr().get(fwdTypeRef);
                if (fwdType.isStruct())
                {
                    SWC_RESULT(sema.waitSemaCompleted(&fwdType, argRef));
                    if (!TypeGen::lifecycleFlagsOfTypeRef(ctx, fwdTypeRef).canCopy)
                    {
                        CastFailure cf{};
                        cf.diagId     = DiagnosticId::sema_err_fwd_not_copyable;
                        cf.srcTypeRef = fwdTypeRef;
                        failBadType(outFail, mapping.paramArgs[i].callArgIndex, i, cf);
                        return Result::Continue;
                    }
                }
            }

            // An explicit '#move' argument binds a '#move' parameter, or a by-value
            // parameter (the source is then consumed into a call-site temporary). A
            // reference/pointer parameter would silently ignore the transfer: rejected.
            const bool argIsExplicitMove = isExplicitMoveArgumentNode(sema, argRef);
            if (argIsExplicitMove)
            {
                const TypeInfo& paramCheck = sema.typeMgr().get(unwrapAliasEnumOrSelf(sema, paramTy));
                if (!paramCheck.isMoveReference() && paramCheck.isPointerOrReference())
                {
                    CastFailure cf{};
                    cf.diagId     = DiagnosticId::sema_err_move_arg_param_not_move;
                    cf.dstTypeRef = paramTy;
                    failBadType(outFail, mapping.paramArgs[i].callArgIndex, i, cf);
                    return Result::Continue;
                }
            }

            CastFailure        cf{};
            const SemaNodeView argNodeView(sema, argRef, SemaNodeViewPartE::Type);
            TypeRef            argTy = argNodeView.typeRef();

            AutoEnumArgProbe probe;
            SWC_RESULT(probeAutoEnumArg(sema, argRef, paramTy, probe, cf));
            if (probe.matched)
                argTy = probe.typeRef;

            if (isAttributeTypeInfoCallArgument(sema, argRef, paramTy))
                argTy = paramTy;

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

            const bool isUfcsArgument                = allowsImplicitAddressBinding(fn, i, ufcsArg);
            const bool allowUserDefinedLiteralSuffix = fn.idRef() == sema.idMgr().predefined(IdentifierManager::PredefinedName::OpSetLiteral);
            auto       r                             = ConvRank::Bad;
            if (isIntrinsicAliasStorageMatch(sema, mode, fn, argTy, paramTy))
                r = ConvRank::Standard;
            else
                SWC_RESULT(probeImplicitConversion(sema, r, argRef, argTy, paramTy, cf, isUfcsArgument, allowUserDefinedLiteralSuffix));
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

            // An explicit '#move' argument consumed by a by-value parameter ranks below
            // copy-to-move: an overload with a real '#move' parameter stays preferred.
            if (argIsExplicitMove && !sema.typeMgr().get(unwrapAliasEnumOrSelf(sema, paramTy)).isMoveReference())
                r = ConvRank::MoveToValue;

            outCandidate.perArg.push_back(r);
        }

        // Variadic tails are ranked after fixed parameters. Untyped variadics are always
        // the weakest fallback; typed variadics still probe each supplied tail argument.
        if (vi.any() && numParams > 0)
        {
            const uint32_t     startVariadic    = numParams - 1;
            const CallArgEntry fixedVariadicArg = mapping.paramArgs[startVariadic];
            if (vi.isVariadic)
            {
                if (fixedVariadicArg.argRef.isValid())
                    outCandidate.perArg.push_back(ConvRank::Ellipsis);
                for ([[maybe_unused]] const CallArgEntry& entry : mapping.variadicArgs)
                    outCandidate.perArg.push_back(ConvRank::Ellipsis);
            }
            else
            {
                const TypeRef variadicParamTypeRef = unwrapAliasEnumOrSelf(sema, params.back()->typeRef());
                const TypeRef variadicTy           = sema.typeMgr().get(variadicParamTypeRef).payloadTypeRef();
                if (fixedVariadicArg.argRef.isValid())
                    SWC_RESULT(probeTypedVariadicArgument(sema, fn, fixedVariadicArg, variadicTy, startVariadic, mapping.variadicArgs.empty(), outCandidate, outFail));
                if (outFail.active)
                    return Result::Continue;
                for (const CallArgEntry& entry : mapping.variadicArgs)
                {
                    SWC_RESULT(probeTypedVariadicArgument(sema, fn, entry, variadicTy, startVariadic, false, outCandidate, outFail));
                    if (outFail.active)
                        return Result::Continue;
                }
            }
        }

        outCandidate.viable = true;
        return Result::Continue;
    }

    bool candidateUsesGenericInstance(const Candidate& candidate)
    {
        return candidate.fn && candidate.fn->isGenericInstance();
    }

    // Compare full call shapes. `ConvRank` is ordered from best to worst, so lower enum
    // values win; later tie-breakers prefer fewer defaults and non-generic overloads.
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

        const bool aGenericInstance = candidateUsesGenericInstance(a);
        const bool bGenericInstance = candidateUsesGenericInstance(b);
        if (aGenericInstance != bGenericInstance)
            return aGenericInstance ? 1 : -1;

        return 0;
    }

    int compareCandidatesIgnoringReceiver(const Candidate& a, const Candidate& b)
    {
        const uint32_t aStart        = a.ufcsUsed ? 1 : 0;
        const uint32_t bStart        = b.ufcsUsed ? 1 : 0;
        const auto     na            = static_cast<uint32_t>(a.perArg.size());
        const auto     nb            = static_cast<uint32_t>(b.perArg.size());
        const uint32_t aExplicitArgs = na > aStart ? na - aStart : 0;
        const uint32_t bExplicitArgs = nb > bStart ? nb - bStart : 0;
        const uint32_t n             = std::min(aExplicitArgs, bExplicitArgs);

        for (uint32_t i = 0; i < n; ++i)
        {
            const ConvRank aRank = a.perArg[aStart + i];
            const ConvRank bRank = b.perArg[bStart + i];
            if (aRank != bRank)
                return (aRank < bRank) ? -1 : 1;
        }

        if (aExplicitArgs != bExplicitArgs)
            return (aExplicitArgs < bExplicitArgs) ? -1 : 1;

        if (a.usedDefaults != b.usedDefaults)
            return (a.usedDefaults < b.usedDefaults) ? -1 : 1;

        const bool aGenericInstance = candidateUsesGenericInstance(a);
        const bool bGenericInstance = candidateUsesGenericInstance(b);
        if (aGenericInstance != bGenericInstance)
            return aGenericInstance ? 1 : -1;

        return 0;
    }

    enum class ReceiverConstness
    {
        Unknown,
        Mutable,
        Const,
    };

    ReceiverConstness candidateReceiverConstness(Sema& sema, const Candidate& candidate)
    {
        if (!candidate.fn || candidate.fn->parameters().empty())
            return ReceiverConstness::Unknown;

        const SymbolVariable* receiver = candidate.fn->parameters().front();
        if (!receiver || !receiver->typeRef().isValid())
            return ReceiverConstness::Unknown;

        return sema.typeMgr().get(receiver->typeRef()).isConst() ? ReceiverConstness::Const : ReceiverConstness::Mutable;
    }

    bool receiverArgIsConst(Sema& sema, AstNodeRef ufcsArg)
    {
        if (ufcsArg.isInvalid())
            return false;

        const AstNodeRef receiverRef = Match::resolveCallArgumentValueRef(sema, ufcsArg);
        if (receiverRef.isInvalid())
            return false;

        const SemaNodeView receiverView(sema, receiverRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
        if (SemaCheck::isReadOnlyParameterPath(sema, receiverRef))
            return true;
        if (receiverView.sym() && receiverView.sym()->isConstant())
            return true;

        return !sema.isLValue(receiverRef);
    }

    int compareReceiverConstness(Sema& sema, const Candidate& a, const Candidate& b, AstNodeRef ufcsArg)
    {
        if (ufcsArg.isInvalid())
            return 0;

        const ReceiverConstness aConstness = candidateReceiverConstness(sema, a);
        const ReceiverConstness bConstness = candidateReceiverConstness(sema, b);
        if (aConstness == bConstness || aConstness == ReceiverConstness::Unknown || bConstness == ReceiverConstness::Unknown)
            return 0;

        // UFCS/member calls should favor the overload whose receiver mutability matches the
        // call-site receiver. This keeps mutable methods preferred from mutable contexts while
        // still selecting const overloads for const receivers and temporaries.
        const bool preferConstReceiver = receiverArgIsConst(sema, ufcsArg);
        if (preferConstReceiver)
            return aConstness == ReceiverConstness::Const ? -1 : 1;

        return aConstness == ReceiverConstness::Mutable ? -1 : 1;
    }

    int compareReceiverKind(const Candidate& a, const Candidate& b, AstNodeRef ufcsArg)
    {
        if (ufcsArg.isInvalid() || !a.fn || !b.fn || a.fn->isMethod() == b.fn->isMethod())
            return 0;

        return a.fn->isMethod() ? -1 : 1;
    }

    int compareCallCandidates(Sema& sema, const Candidate& a, const Candidate& b, AstNodeRef ufcsArg)
    {
        if (ufcsArg.isValid())
        {
            const int explicitArgCmp = compareCandidatesIgnoringReceiver(a, b);
            if (explicitArgCmp != 0)
                return explicitArgCmp;

            const int receiverKindCmp = compareReceiverKind(a, b, ufcsArg);
            if (receiverKindCmp != 0)
                return receiverKindCmp;
        }

        const int cmp = compareCandidates(a, b);
        if (cmp != 0)
            return cmp;

        return compareReceiverConstness(sema, a, b, ufcsArg);
    }

    bool canKeepFirstSpecialOpTie(const Candidate& a, const Candidate& b)
    {
        if (!a.fn || !b.fn)
            return false;

        const SpecOpKind kind = a.fn->specOpKind();
        return kind == SpecOpKind::OpAssign && b.fn->specOpKind() == kind;
    }

    // Evaluate every reachable function symbol in source order. Generic roots are probed
    // through speculative instantiation; concrete functions are probed first as regular
    // calls and then, if relevant, as UFCS/member-style calls with an injected receiver.
    Result collectAttempts(Sema& sema, SmallVector<Attempt>& outAttempts, SmallVector<SymbolFunction*>& outFunctionSymbols, std::span<Symbol* const> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg, std::span<const AstNodeRef> explicitGenericArgNodes, Match::ResolveCallMode mode)
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

            if (!explicitGenericArgNodes.empty() && !fn->isGenericRoot() && !fn->isGenericInstance())
                continue;

            bool alreadyAdded = false;
            for (const SymbolFunction* addedFn : outFunctionSymbols)
            {
                if (addedFn == fn)
                {
                    alreadyAdded = true;
                    break;
                }
            }

            if (alreadyAdded)
                continue;

            outFunctionSymbols.push_back(fn);
        }

        // With multiple overloads, a failed generic instantiation is just one failed
        // candidate. Suppress its immediate diagnostics and preserve the structured
        // failure so overload reporting can choose the most useful note.
        const bool suppressGenericInstantiationErrors = outFunctionSymbols.size() > 1;

        for (SymbolFunction* fn : outFunctionSymbols)
        {
            SWC_ASSERT(fn != nullptr);

            Attempt a;
            a.fn = fn;

            if (fn->isGenericRoot())
            {
                MatchFailure fail;
                Candidate    candidate;
                SWC_RESULT(tryInstantiateGenericCandidate(sema, *fn, args, AstNodeRef::invalid(), explicitGenericArgNodes, mode, suppressGenericInstantiationErrors, candidate, fail));
                if (candidate.viable)
                {
                    a.viable    = true;
                    a.candidate = std::move(candidate);
                }

                if (!a.viable && ufcsArg.isValid())
                {
                    candidate = {};
                    fail      = {};
                    SWC_RESULT(tryInstantiateGenericCandidate(sema, *fn, args, ufcsArg, explicitGenericArgNodes, mode, suppressGenericInstantiationErrors, candidate, fail));
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
            SWC_RESULT(tryBuildCandidate(sema, *fn, args, AstNodeRef::invalid(), mode, candidate, fail));
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
                SWC_RESULT(tryBuildCandidate(sema, *fn, args, ufcsArg, mode, candidate, fail));
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
    bool bindsReferenceToValue(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef);
    bool movesValueToParam(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef);

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

    Result collectCandidateAttempts(Sema& sema, CandidateAttempts& out, std::span<Symbol* const> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg, std::span<const AstNodeRef> explicitGenericArgNodes, Match::ResolveCallMode mode)
    {
        SWC_RESULT(collectAttempts(sema, out.attempts, out.functions, symbols, args, ufcsArg, explicitGenericArgNodes, mode));
        gatherViableAttempts(out.attempts, out.viable);
        return Result::Continue;
    }

    const Attempt* bestAttemptNoDiagnostics(Sema& sema, const SmallVector<const Attempt*>& viable, AstNodeRef ufcsArg)
    {
        if (viable.empty())
            return nullptr;

        const Attempt* best = viable[0];
        for (size_t i = 1; i < viable.size(); ++i)
        {
            if (compareCallCandidates(sema, viable[i]->candidate, best->candidate, ufcsArg) < 0)
                best = viable[i];
        }

        return best;
    }

    bool fallbackHasBetterCandidate(Sema& sema, const SmallVector<const Attempt*>& currentViable, const SmallVector<const Attempt*>& fallbackViable, AstNodeRef ufcsArg)
    {
        const Attempt* currentBest  = bestAttemptNoDiagnostics(sema, currentViable, ufcsArg);
        const Attempt* fallbackBest = bestAttemptNoDiagnostics(sema, fallbackViable, ufcsArg);
        if (!currentBest || !fallbackBest)
            return false;
        if (!currentBest->candidate.fn || !fallbackBest->candidate.fn)
            return false;

        // The current best was selected from the highest-priority scope tier only, so a
        // genuinely better-matching overload living in a lower-priority tier (for example an
        // imported `cos(f32)` shadowed by a same-name `cos(f64)` instance closer in scope) can
        // be missing from it. The fallback set gathers every visible same-name overload, so
        // prefer it whenever it yields a strictly better conversion ranking. Never let the
        // fallback promote a *method*: that path stays reserved for the UFCS disambiguation
        // below, where a non-method free function should win over a higher-priority method.
        if (fallbackBest->candidate.fn->isMethod())
            return false;

        return compareCallCandidates(sema, fallbackBest->candidate, currentBest->candidate, ufcsArg) < 0;
    }

    Result maybeReplaceWithBetterCallFallback(Sema& sema, const SemaNodeView& nodeCallee, CandidateAttempts& current, std::span<AstNodeRef> args, AstNodeRef ufcsArg, Match::ResolveCallMode mode)
    {
        if (mode != Match::ResolveCallMode::Normal || current.functions.empty())
            return Result::Continue;

        // The primary lookup tier can stop once it finds same-name symbols, but overload
        // quality is call-site dependent. Re-check the broader fallback set so a strictly
        // better visible overload is not hidden by a worse closer one.
        SmallVector<Symbol*> fallbackSymbols;
        SWC_RESULT(Match::matchCallFallbackSymbols(sema, nodeCallee, fallbackSymbols));
        if (fallbackSymbols.empty())
            return Result::Continue;

        SmallVector<Symbol*> fallbackRuntimeSymbols;
        SmallVector<Symbol*> fallbackConcreteSymbols;
        SWC_RESULT(SemaRuntime::filterRuntimeAccessibleSymbols(sema, nodeCallee.nodeRef(), fallbackSymbols.span(), fallbackRuntimeSymbols));
        removeEmptyFunctionDeclarations(fallbackRuntimeSymbols.span(), fallbackConcreteSymbols);

        CandidateAttempts fallback;
        SWC_RESULT(collectCandidateAttempts(sema, fallback, fallbackConcreteSymbols.span(), args, ufcsArg, {}, mode));
        if (fallback.viable.empty())
            return Result::Continue;

        if (!current.viable.empty() && !fallbackHasBetterCandidate(sema, current.viable, fallback.viable, ufcsArg))
            return Result::Continue;

        current = std::move(fallback);
        gatherViableAttempts(current.attempts, current.viable);
        return Result::Continue;
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

    Result raiseAmbiguousBest(Sema& sema, AstNodeRef calleeRef, const SmallVector<const Attempt*>& viable, const Candidate& best, AstNodeRef ufcsArg)
    {
        SmallVector<const Symbol*> ambiguousSymbols;
        for (const Attempt* a : viable)
        {
            if (compareCallCandidates(sema, a->candidate, best, ufcsArg) == 0)
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

    void fillFunctionCandidateProbe(Match::FunctionCandidateProbe& outProbe, const Attempt& selectedAttempt)
    {
        outProbe.perArgRanks.clear();
        outProbe.perArgRanks.reserve(selectedAttempt.candidate.perArg.size());
        for (const ConvRank rank : selectedAttempt.candidate.perArg)
            outProbe.perArgRanks.push_back(static_cast<uint8_t>(rank));

        outProbe.fn              = selectedAttempt.candidate.fn;
        outProbe.usedDefaults    = selectedAttempt.candidate.usedDefaults;
        outProbe.genericInstance = candidateUsesGenericInstance(selectedAttempt.candidate);
        outProbe.matched         = true;
    }

    // Select exactly one viable candidate. Ambiguity is computed after all tie-breakers,
    // except for special assignment operators where keeping declaration order is part of
    // the language rule.
    Result selectBestAttempt(Sema& sema, const SemaNodeView& nodeCallee, const SmallVector<const Attempt*>& viable, const SmallVector<SymbolFunction*>& functions, const SmallVector<Attempt>& attempts, std::span<AstNodeRef> args, AstNodeRef ufcsArg, const Attempt*& outSelected)
    {
        if (viable.empty())
            return raiseNoSelection(sema, nodeCallee, functions, attempts, args, ufcsArg);

        outSelected    = viable[0];
        bool ambiguous = false;

        for (size_t i = 1; i < viable.size(); ++i)
        {
            const int cmp = compareCallCandidates(sema, viable[i]->candidate, outSelected->candidate, ufcsArg);
            if (cmp < 0)
            {
                outSelected = viable[i];
                ambiguous   = false;
            }
            else if (cmp == 0)
            {
                if (!canKeepFirstSpecialOpTie(outSelected->candidate, viable[i]->candidate))
                    ambiguous = true;
            }
        }

        if (ambiguous)
            return raiseAmbiguousBest(sema, nodeCallee.nodeRef(), viable, outSelected->candidate, ufcsArg);

        return Result::Continue;
    }

    // Finalization pass for the selected overload. Unlike candidate probing, this is
    // allowed to mutate the AST: auto-enum substitutions, cast nodes, and argument
    // payloads become the canonical form consumed by codegen.
    Result applyParameterCasts(Sema& sema, const SymbolFunction& selectedFn, CallArgMapping& mapping, AstNodeRef appliedUfcsArg, Match::ResolveCallMode mode)
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
            CallArgEntry&    entry  = mapping.paramArgs[i];
            const AstNodeRef argRef = entry.argRef;
            if (argRef.isInvalid())
                continue;

            if (params[i]->type(sema.ctx()).isCodeBlock())
                continue;

            const AstNodeRef argValueRef = Match::resolveCallArgumentValueRef(sema, argRef);
            SemaNodeView     argView(sema, argValueRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            const TypeRef    paramTypeRef     = params[i]->typeRef();
            TypeRef          castTypeRef      = paramTypeRef;
            const TypeRef    bindValueTypeRef = implicitConstReferenceBindingValueTypeRef(sema, paramTypeRef, argView.typeRef());
            if (bindValueTypeRef.isValid())
                castTypeRef = bindValueTypeRef;
            SWC_RESULT(normalizeTypeInfoCallArgument(sema, argValueRef, castTypeRef, argView));
            if (isIntrinsicAliasStorageMatch(sema, mode, selectedFn, argView.typeRef(), castTypeRef))
                continue;

            // Backstop for call paths that skip candidate probing (e.g. calls through a
            // function value): an explicit '#move' argument binds a '#move' or a by-value
            // parameter, never a reference/pointer one (the transfer would be ignored).
            if (isExplicitMoveArgumentNode(sema, argRef))
            {
                const TypeInfo& paramCheck = sema.typeMgr().get(unwrapAliasEnumOrSelf(sema, paramTypeRef));
                if (!paramCheck.isMoveReference() && paramCheck.isPointerOrReference())
                    return SemaError::raise(sema, DiagnosticId::sema_err_move_arg_param_not_move, argValueRef);
            }

            // Copy-to-move binding: a plain value bound to a '#move' parameter stays a plain
            // value (no cast node); the call site materializes the temporary copy and passes
            // its address as the move reference. When a value conversion is pending (an
            // untyped literal binding the pointee), the cast below must still run.
            if (castTypeRef == paramTypeRef &&
                sema.typeMgr().get(paramTypeRef).isMoveReference() &&
                argView.type() && !argView.type()->isMoveReference() &&
                bindsReferenceToValue(sema, paramTypeRef, argValueRef))
                continue;

            // Move-to-value binding: an explicit '#move' argument bound to a by-value
            // struct parameter also keeps its raw form (a read-through cast node would
            // detour the payload); the call site moves the source into a temporary and
            // passes its address as the borrowed argument.
            if (movesValueToParam(sema, paramTypeRef, argRef))
                continue;

            CastFlags flags = CastFlagsE::AllowCopyToMoveRef;
            if (castTypeRef == paramTypeRef && allowsImplicitAddressBinding(selectedFn, i, appliedUfcsArg))
                flags.add(CastFlagsE::UfcsArgument);
            if (selectedFn.idRef() == sema.idMgr().predefined(IdentifierManager::PredefinedName::OpSetLiteral))
                flags.add(CastFlagsE::LiteralSuffixConsume);
            const DiagnosticArguments errorArguments = makeCallCastErrorArguments(selectedFn, entry.callArgIndex, sema.ctx());
            if (!applyContextualAutoEnumAliasCast(sema, argRef, argView, castTypeRef))
                SWC_RESULT(Cast::cast(sema, argView, castTypeRef, CastKind::Parameter, flags, &errorArguments));
            entry.valueRef = argView.nodeRef();
            refreshNamedArgumentPayload(sema, argRef, argView.nodeRef());
        }

        return Result::Continue;
    }

    // For typed variadic functions (e.g., `func(x: ...int)`), each extra argument
    // must be cast to the underlying variadic type.
    Result applyTypedVariadicCasts(Sema& sema, const SymbolFunction& selectedFn, CallArgMapping& mapping)
    {
        const auto numParams = static_cast<uint32_t>(selectedFn.parameters().size());
        if (numParams == 0)
            return Result::Continue;

        const SymbolVariable* variadicParam = selectedFn.parameters().back();
        SWC_ASSERT(variadicParam != nullptr);
        const TypeInfo& variadicType = variadicParam->type(sema.ctx());
        if (!variadicType.isTypedVariadic())
            return Result::Continue;

        const TypeRef variadicTy       = variadicType.payloadTypeRef();
        CallArgEntry& fixedVariadicArg = mapping.paramArgs[numParams - 1];
        if (fixedVariadicArg.argRef.isValid())
        {
            if (mapping.variadicArgs.empty() && isMatchingTypedVariadicForwardingArg(sema, fixedVariadicArg.argRef, variadicTy))
                return Result::Continue;

            const AstNodeRef argValueRef = resolvedCallArgValueRef(sema, fixedVariadicArg);
            SemaNodeView     argView(sema, argValueRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            SWC_RESULT(normalizeTypeInfoCallArgument(sema, argValueRef, variadicTy, argView));
            const DiagnosticArguments errorArguments = makeCallCastErrorArguments(selectedFn, fixedVariadicArg.callArgIndex, sema.ctx());
            SWC_RESULT(Cast::cast(sema, argView, variadicTy, CastKind::Implicit, CastFlagsE::Zero, &errorArguments));
            fixedVariadicArg.valueRef = argView.nodeRef();
            refreshNamedArgumentPayload(sema, fixedVariadicArg.argRef, argView.nodeRef());
        }

        for (CallArgEntry& entry : mapping.variadicArgs)
        {
            const AstNodeRef argValueRef = resolvedCallArgValueRef(sema, entry);
            SemaNodeView     argView(sema, argValueRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            SWC_RESULT(normalizeTypeInfoCallArgument(sema, argValueRef, variadicTy, argView));
            const DiagnosticArguments errorArguments = makeCallCastErrorArguments(selectedFn, entry.callArgIndex, sema.ctx());
            SWC_RESULT(Cast::cast(sema, argView, variadicTy, CastKind::Implicit, CastFlagsE::Zero, &errorArguments));
            entry.valueRef = argView.nodeRef();
            refreshNamedArgumentPayload(sema, entry.argRef, argView.nodeRef());
        }

        return Result::Continue;
    }

    Result concretizeUntypedVariadicArg(Sema& sema, CallArgEntry& entry)
    {
        const AstNodeRef argRef = resolvedCallArgValueRef(sema, entry);
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

        const TypeRef concreteArrayTypeRef = SemaHelpers::deduceConcretizedAggregateArrayType(sema, argView.typeRef(), argView.cstRef());
        if (concreteArrayTypeRef == argView.typeRef())
            return Result::Continue;

        SemaNodeView castView(sema, argRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        SWC_RESULT(Cast::cast(sema, castView, concreteArrayTypeRef, CastKind::Implicit));
        entry.valueRef = castView.nodeRef();
        return Result::Continue;
    }

    Result concretizeUntypedVariadicArgs(Sema& sema, const SymbolFunction& selectedFn, CallArgMapping& mapping)
    {
        const auto numParams = static_cast<uint32_t>(selectedFn.parameters().size());
        if (numParams == 0)
            return Result::Continue;

        const SymbolVariable* variadicParam = selectedFn.parameters().back();
        SWC_ASSERT(variadicParam != nullptr);
        const TypeInfo& variadicType = variadicParam->type(sema.ctx());
        if (!variadicType.isVariadic())
            return Result::Continue;

        CallArgEntry& fixedVariadicArg = mapping.paramArgs[numParams - 1];
        SWC_RESULT(concretizeUntypedVariadicArg(sema, fixedVariadicArg));

        for (CallArgEntry& entry : mapping.variadicArgs)
            SWC_RESULT(concretizeUntypedVariadicArg(sema, entry));

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

        const AstNodeRef firstArgRef = resolvedCallArgValueRef(sema, mapping.paramArgs[0]);
        if (firstArgRef.isInvalid())
            return false;

        return firstArgRef == Match::resolveCallArgumentValueRef(sema, receiverArgRef);
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
        SWC_RESULT(sema.makeRuntimeTypeInfo(typeInfoCstRef, argView.typeRef(), outResolvedArg.argRef));
        outResolvedArg.typeInfoCstRef = typeInfoCstRef;
        return Result::Continue;
    }

    bool bindsReferenceToValue(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return false;

        const TypeInfo& paramType = sema.typeMgr().get(paramTypeRef);
        if (!paramType.isReference())
            return false;

        const AstNodeRef sourceRef     = SemaHelpers::resolveTransparentExprSourceRef(sema, argRef);
        const TypeRef    sourceTypeRef = sema.viewStored(sourceRef, SemaNodeViewPartE::Type).typeRef();
        if (sourceTypeRef.isInvalid())
            return true;

        const TypeRef   unwrappedSourceTypeRef = sema.typeMgr().get(sourceTypeRef).unwrap(sema.ctx(), sourceTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeRef   resolvedSourceTypeRef  = unwrappedSourceTypeRef.isValid() ? unwrappedSourceTypeRef : sourceTypeRef;
        const TypeInfo& sourceType             = sema.typeMgr().get(resolvedSourceTypeRef);
        return !sourceType.isPointerOrReference();
    }

    bool passUfcsAddressAsPointer(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef, AstNodeRef appliedUfcsArg)
    {
        if (argRef.isInvalid() || appliedUfcsArg.isInvalid())
            return false;

        if (Match::resolveCallArgumentValueRef(sema, argRef) != Match::resolveCallArgumentValueRef(sema, appliedUfcsArg))
            return false;

        const TypeInfo& paramType = sema.typeMgr().get(paramTypeRef);
        if (!paramType.isAnyPointer())
            return false;

        const AstNodeRef sourceRef     = SemaHelpers::resolveTransparentExprSourceRef(sema, argRef);
        const TypeRef    sourceTypeRef = sema.viewStored(sourceRef, SemaNodeViewPartE::Type).typeRef();
        if (!sourceTypeRef.isValid())
            return false;

        const TypeRef   resolvedSourceTypeRef  = sema.typeMgr().unwrapAliasEnum(sema.ctx(), sourceTypeRef);
        const TypeRef   resolvedPointeeTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), paramType.payloadTypeRef());
        const TypeRef   sourceTypeToCheck      = resolvedSourceTypeRef.isValid() ? resolvedSourceTypeRef : sourceTypeRef;
        const TypeRef   pointeeTypeToCheck     = resolvedPointeeTypeRef.isValid() ? resolvedPointeeTypeRef : paramType.payloadTypeRef();
        const TypeInfo& sourceType             = sema.typeMgr().get(sourceTypeToCheck);
        if (sourceType.isPointerOrReference())
            return false;

        return pointeeTypeToCheck == sourceTypeToCheck;
    }

    TypeRef referenceBindingStorageTypeRef(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef)
    {
        if (argRef.isInvalid() || paramTypeRef.isInvalid())
            return TypeRef::invalid();

        const TypeInfo& paramType = sema.typeMgr().get(paramTypeRef);
        if (!paramType.isReference())
            return TypeRef::invalid();

        const AstNodeRef sourceRef     = SemaHelpers::resolveTransparentExprSourceRef(sema, argRef);
        const TypeRef    sourceTypeRef = sema.viewStored(sourceRef, SemaNodeViewPartE::Type).typeRef();
        if (!sourceTypeRef.isValid())
            return paramType.payloadTypeRef();

        const TypeRef unwrappedSourceTypeRef = sema.typeMgr().get(sourceTypeRef).unwrap(sema.ctx(), sourceTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (unwrappedSourceTypeRef.isValid())
            return unwrappedSourceTypeRef;

        return sourceTypeRef;
    }

    Result attachReferenceBindingRuntimeStorageIfNeeded(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef)
    {
        if (argRef.isInvalid() || sema.isGlobalScope())
            return Result::Continue;

        const TypeRef storageTypeRef = referenceBindingStorageTypeRef(sema, paramTypeRef, argRef);
        return SemaHelpers::attachRuntimeStorageIfNeeded(sema, argRef, sema.node(argRef), storageTypeRef, "__call_arg_ref_storage");
    }

    // An explicit '#move' argument bound to a by-value STRUCT parameter: the source is
    // consumed into a call-site temporary that the callee borrows.
    bool movesValueToParam(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef)
    {
        if (argRef.isInvalid() || !isExplicitMoveArgumentNode(sema, argRef))
            return false;

        const TypeInfo& paramType = sema.typeMgr().get(unwrapAliasEnumOrSelf(sema, paramTypeRef));
        return !paramType.isMoveReference() && paramType.isStruct();
    }

    Result attachMovedValueRuntimeStorageIfNeeded(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef)
    {
        if (argRef.isInvalid() || sema.isGlobalScope())
            return Result::Continue;

        const TypeRef storageTypeRef = unwrapAliasEnumOrSelf(sema, paramTypeRef);
        return SemaHelpers::attachRuntimeStorageIfNeeded(sema, argRef, sema.node(argRef), storageTypeRef, "__call_arg_move_storage");
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

            const AstNodeRef finalArgRef = resolvedCallArgValueRef(sema, entry);

            auto passKind = CallArgumentPassKind::Direct;
            if (i == 0 && appliedUfcsArg.isValid() && selectedFn.hasInterfaceMethodSlot())
            {
                const SemaNodeView argView = sema.viewType(finalArgRef);
                if (argView.type() && argView.type()->isInterface())
                    passKind = CallArgumentPassKind::InterfaceObject;
            }

            ResolvedCallArgument resolvedArg{
                .argRef                   = finalArgRef,
                .passKind                 = passKind,
                .bindsReferenceToValue    = i < numParams && bindsReferenceToValue(sema, selectedFn.parameters()[i]->typeRef(), finalArgRef),
                .movesValueToParam        = i < numParams && movesValueToParam(sema, selectedFn.parameters()[i]->typeRef(), entry.argRef),
                .passUfcsAddressAsPointer = i < numParams && passUfcsAddressAsPointer(sema, selectedFn.parameters()[i]->typeRef(), finalArgRef, appliedUfcsArg),
            };

            if (resolvedArg.bindsReferenceToValue)
                SWC_RESULT(attachReferenceBindingRuntimeStorageIfNeeded(sema, selectedFn.parameters()[i]->typeRef(), finalArgRef));
            if (resolvedArg.movesValueToParam)
                SWC_RESULT(attachMovedValueRuntimeStorageIfNeeded(sema, selectedFn.parameters()[i]->typeRef(), finalArgRef));
            if (i < numParams)
                SWC_RESULT(SemaHelpers::attachBorrowedAggregateArgumentRuntimeStorageIfNeeded(sema, selectedFn, selectedFn.parameters()[i]->typeRef(), finalArgRef));

            if (hasUntypedVariadic && i == variadicParamIdx)
                SWC_RESULT(assignUntypedVariadicTypeInfo(sema, resolvedArg));

            outResolvedArgs.push_back(resolvedArg);
        }

        for (const CallArgEntry& entry : mapping.variadicArgs)
        {
            if (entry.argRef.isInvalid())
                continue;
            const AstNodeRef     finalArgRef = resolvedCallArgValueRef(sema, entry);
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

    void collectMappedCallValueArgs(Sema& sema, SmallVector<AstNodeRef>& outArgs, const CallArgMapping& mapping)
    {
        outArgs.clear();
        outArgs.reserve(mapping.paramArgs.size() + mapping.variadicArgs.size());

        for (const CallArgEntry& entry : mapping.paramArgs)
        {
            if (entry.argRef.isInvalid())
                outArgs.push_back(AstNodeRef::invalid());
            else
                outArgs.push_back(resolvedCallArgValueRef(sema, entry));
        }

        for (const CallArgEntry& entry : mapping.variadicArgs)
        {
            if (entry.argRef.isInvalid())
                outArgs.push_back(AstNodeRef::invalid());
            else
                outArgs.push_back(resolvedCallArgValueRef(sema, entry));
        }
    }
}

AstNodeRef Match::resolveCallArgumentRef(Sema& sema, AstNodeRef argRef)
{
    if (argRef.isInvalid())
        return AstNodeRef::invalid();

    const AstNode& argNode = sema.node(argRef);
    if (argNode.is(AstNodeId::CastExpr) || argNode.is(AstNodeId::AutoCastExpr))
        return argRef;

    AstNodeRef finalRef = sema.viewZero(argRef).nodeRef();
    if (finalRef.isInvalid())
        finalRef = argRef;
    return finalRef;
}

bool Match::isExplicitMoveArgument(Sema& sema, const AstNodeRef argRef)
{
    return isExplicitMoveArgumentNode(sema, argRef);
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

int Match::compareFunctionCandidateProbes(const FunctionCandidateProbe& a, const FunctionCandidateProbe& b)
{
    const auto     na = static_cast<uint32_t>(a.perArgRanks.size());
    const auto     nb = static_cast<uint32_t>(b.perArgRanks.size());
    const uint32_t n  = std::min(na, nb);

    for (uint32_t i = 0; i < n; ++i)
    {
        if (a.perArgRanks[i] != b.perArgRanks[i])
            return (a.perArgRanks[i] < b.perArgRanks[i]) ? -1 : 1;
    }

    if (na != nb)
        return (na < nb) ? -1 : 1;

    if (a.usedDefaults != b.usedDefaults)
        return (a.usedDefaults < b.usedDefaults) ? -1 : 1;

    if (a.genericInstance != b.genericInstance)
        return a.genericInstance ? 1 : -1;

    return 0;
}

Result Match::probeFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol* const> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg, FunctionCandidateProbe& outProbe, bool allowNoMatch, ResolveCallMode mode)
{
    outProbe = {};

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
    removeEmptyFunctionDeclarations(runtimeSymbols.span(), concreteSymbols);

    if (mode == ResolveCallMode::AttributeOnly && !symbols.empty() && filteredSymbols.empty())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_attribute, nodeCallee.nodeRef());

    CandidateAttempts       candidates;
    SmallVector<AstNodeRef> explicitGenericArgNodes;
    collectExplicitGenericArgNodes(*nodeCallee.node(), sema.ast(), explicitGenericArgNodes);
    SWC_RESULT(collectCandidateAttempts(sema, candidates, concreteSymbols.span(), args, ufcsArg, explicitGenericArgNodes.span(), mode));
    SWC_RESULT(maybeReplaceWithBetterCallFallback(sema, nodeCallee, candidates, args, ufcsArg, mode));

    if (candidates.viable.empty())
    {
        if (allowNoMatch)
            return Result::Continue;
        return raiseNoSelection(sema, nodeCallee, candidates.functions, candidates.attempts, args, ufcsArg);
    }

    const Attempt* selectedAttempt = nullptr;
    SWC_RESULT(selectBestAttempt(sema, nodeCallee, candidates.viable, candidates.functions, candidates.attempts, args, ufcsArg, selectedAttempt));
    SWC_ASSERT(selectedAttempt != nullptr);
    fillFunctionCandidateProbe(outProbe, *selectedAttempt);
    return Result::Continue;
}

Result Match::resolveFunctionCandidates(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol* const> symbols, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SmallVector<ResolvedCallArgument>* outResolvedArgs, ResolveCallMode mode)
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
    removeEmptyFunctionDeclarations(runtimeSymbols.span(), concreteSymbols);

    if (mode == ResolveCallMode::AttributeOnly && !symbols.empty() && filteredSymbols.empty())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_attribute, nodeCallee.nodeRef());

    // Collect all function candidates and evaluate their match quality
    CandidateAttempts       candidates;
    SmallVector<AstNodeRef> explicitGenericArgNodes;
    collectExplicitGenericArgNodes(*nodeCallee.node(), sema.ast(), explicitGenericArgNodes);
    SWC_RESULT(collectCandidateAttempts(sema, candidates, concreteSymbols.span(), args, ufcsArg, explicitGenericArgNodes.span(), mode));
    SWC_RESULT(maybeReplaceWithBetterCallFallback(sema, nodeCallee, candidates, args, ufcsArg, mode));

    // From the viable ones, find the single best candidate.
    // This will raise an error if there are no viable candidates or if the best choice is ambiguous.
    const Attempt* selectedAttempt = nullptr;
    SWC_RESULT(selectBestAttempt(sema, nodeCallee, candidates.viable, candidates.functions, candidates.attempts, args, ufcsArg, selectedAttempt));

    // Finalize the selection by applying required casts and conversions to the arguments
    const AstNodeRef      appliedUfcsArg = selectedAttempt->candidate.ufcsUsed ? ufcsArg : AstNodeRef::invalid();
    const SymbolFunction* selectedFn     = selectedAttempt->candidate.fn;
    CallArgMapping        mapping;
    MatchFailure          mappingFail;
    if (!buildCallArgMapping(sema, *selectedFn, args, appliedUfcsArg, mapping, mappingFail))
        return errorBadMatch(sema, nodeCallee, *selectedFn, mappingFail, args, appliedUfcsArg);

    SmallVector<AstNodeRef> mappedValueArgs;
    collectMappedCallValueArgs(sema, mappedValueArgs, mapping);
    SWC_RESULT(ConstantIntrinsic::tryConstantFoldCallBeforeParameterCasts(sema, *selectedFn, mappedValueArgs.span()));
    const ConstantRef preCastFoldedConst = sema.viewConstant(sema.curNodeRef()).cstRef();

    if (!preCastFoldedConst.isValid())
    {
        SWC_RESULT(finalizeAutoEnumArgs(sema, *selectedFn, mapping));
        SWC_RESULT(applyParameterCasts(sema, *selectedFn, mapping, appliedUfcsArg, mode));
        SWC_RESULT(applyTypedVariadicCasts(sema, *selectedFn, mapping));
        SWC_RESULT(concretizeUntypedVariadicArgs(sema, *selectedFn, mapping));
        if (outResolvedArgs)
            SWC_RESULT(buildResolvedCallArgs(sema, *outResolvedArgs, nodeCallee, *selectedFn, mapping, appliedUfcsArg));
    }

    sema.setSymbol(sema.curNodeRef(), selectedFn);
    if (preCastFoldedConst.isValid())
    {
        sema.setConstant(sema.curNodeRef(), preCastFoldedConst);
        sema.setFoldedTypedConst(sema.curNodeRef());
    }
    sema.setIsValue(sema.curNode());
    sema.unsetIsLValue(sema.curNodeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
