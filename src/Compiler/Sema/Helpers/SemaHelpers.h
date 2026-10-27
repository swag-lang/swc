#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class SymbolStruct;
struct AstNode;
struct CodeGenLoweringPayload;

namespace SemaHelpers
{
    // Structs, arrays, and aggregates carry a composite value in by-value storage.
    bool isByValueAggregateType(const TypeInfo& typeInfo);

    Result prepareFallibleCast(Sema& sema);
    bool   isAssumedCast(Sema& sema);

    bool isVariadicTypeRefOrAlias(Sema& sema, TypeRef typeRef);
    bool isVariadicTypeNode(Sema& sema, AstNodeRef typeNodeRef);

    Result materializeMovedValue(Sema& sema, SemaNodeView& view);
    bool   ownsExpressionValue(Sema& sema, AstNodeRef nodeRef);
    bool   expressionBorrowsStorage(Sema& sema, AstNodeRef nodeRef);

    struct CountOfResultInfo
    {
        TypeRef         typeRef  = TypeRef::invalid();
        ConstantRef     cstRef   = ConstantRef::invalid();
        SymbolFunction* calledFn = nullptr;
    };

    // Keep separate facts for each boolean outcome so either branch can narrow.
    struct NarrowGuards
    {
        SmallVector2<SemaNarrowFact> whenTrue;
        SmallVector2<SemaNarrowFact> whenFalse;
    };

    // A literal child targets a declared struct field or an anonymous aggregate slot.
    struct AggregateChildSlot
    {
        const SymbolVariable* field   = nullptr;
        size_t                index   = 0;
        TypeRef               typeRef = TypeRef::invalid();
    };

    bool resolveAggregateChildSlot(Sema& sema, AggregateChildSlot& outSlot, const TypeInfo& targetType, std::span<const AstNodeRef> children, AstNodeRef childRef);

    // Preserve the numeric argument's own type, including aliases.
    bool isAliasPreservingNumericIntrinsic(TokenId tokenId);

    // Check constant divisors for zero in /, %, /=, and %=.
    Result checkDivideByZeroConstant(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView);

    // Distinguish field-by-field Swag.init arguments from copying one whole value.
    bool intrinsicInitTreatsArgsAsStructTuple(Sema& sema, TypeRef fillTypeRef, const SmallVector<AstNodeRef>& args);

    bool    extractNarrowPath(Sema& sema, AstNodeRef nodeRef, SmallVector4<const Symbol*>& outPath);
    void    collectNarrowGuards(Sema& sema, AstNodeRef condRef, NarrowGuards& out);
    TypeRef nullNarrowedTypeRef(Sema& sema, AstNodeRef nodeRef, TypeRef typeRef);
    TypeRef nullCoalescingResultType(Sema& sema, TypeRef leftTypeRef, TypeRef rightTypeRef);

    // Judge declared control-flow contracts even when runtime guards are off:
    // panic, NoReturn calls, unreachable, and exhaustive complete switches stop flow.
    // Block accepts local exits such as break; Function requires leaving the
    // function or looping forever, for missing-return checks.
    enum class LocalFlowStop : uint8_t
    {
        Block,
        Function,
    };

    bool stopsLocalFlow(Sema& sema, AstNodeRef nodeRef, LocalFlowStop stop = LocalFlowStop::Block);

    void addNarrowFacts(SemaFrame& frame, std::span<const SemaNarrowFact> facts);
    void killNarrowFactsForLoopBody(Sema& sema, AstNodeRef bodyRef, SemaFrame& frame);
    void killNarrowPathAfterStatement(Sema& sema, AstNodeRef exprRef, bool nonNull);

    CodeGenLoweringPayload& ensureCodeGenLoweringPayload(Sema& sema, AstNodeRef nodeRef);

    Result declareGhostAndCompleteStorage(Sema& sema, SymbolVariable& symVar, TypeRef typeRef);
    Result ensureRuntimeStorageDeclaredAndCompleted(Sema& sema, SymbolVariable& storageSym, TypeRef storageTypeRef);
    Result completeRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef);

    SymbolVariable& registerUniqueRuntimeStorageSymbol(Sema& sema, const AstNode& node, std::string_view privateName);
    SymbolVariable& getOrCreateRuntimeStorageSymbol(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, TypeRef storageTypeRef, std::string_view privateName, bool allowBoundStorageTypeMismatch = false);
    Result          attachRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, TypeRef storageTypeRef, std::string_view privateName, bool allowBoundStorageTypeMismatch = false);
    Result          attachRuntimeStorageIfNeeded(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, TypeRef storageTypeRef, std::string_view privateName, bool allowBoundStorageTypeMismatch = false);
    Result          attachLiteralRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SemaNodeView& literalView);

    Result setupRuntimeSafetyPanic(Sema& sema, AstNodeRef nodeRef, Runtime::SafetyWhat safetyKind, const SourceCodeRef& codeRef);
    bool   isLateInitAccess(Sema& sema, AstNodeRef nodeRef);
    bool   hasLateReadGuard(Sema& sema, AstNodeRef nodeRef);
    void   clearLateFieldReadGuard(Sema& sema, AstNodeRef nodeRef);
    bool   binaryOpNeedsOverflowSafety(TokenId canonicalOp, AstModifierFlags modifierFlags);
    Result checkConstantShiftAmount(Sema& sema, AstNodeRef nodeRef, const TypeInfo& valueType, const SemaNodeView& amountView, AstNodeRef amountNodeRef);

    bool canUseContextualBinding(Sema& sema, AstNodeRef nodeRef);
    void scopeBindingsForStatement(Sema& sema);

    // Instance fields require a base, and another function's parameters have
    // no storage here (for example macro receivers). Neither resolves as a
    // standalone identifier in the current codegen context.
    bool bindingSymbolResolvesStandalone(Sema& sema, const SymbolVariable& symVar);

    bool       isTransparentExprNode(const AstNode& node);
    AstNodeRef resolveTransparentExprSourceRef(Sema& sema, AstNodeRef nodeRef);
    AstNodeRef resolveTransparentConditionExprSourceRef(Sema& sema, AstNodeRef nodeRef);
    void       preferContextualAutoMemberBindingType(Sema& sema, AstNodeRef exprRef);

    // Strip alias, enum, and reference wrappers to compare the storage a binding exposes.
    TypeRef unwrapBindingType(TaskContext& ctx, TypeRef typeRef);
    TypeRef ensureStructTypeRef(Sema& sema, SymbolStruct& symStruct);
    TypeRef unwrapAliasRefType(TaskContext& ctx, TypeRef typeRef);

    const SymbolFunction* resolveLambdaBindingFunction(Sema& sema);
    SymbolFunction*       callableTypeFunction(TaskContext& ctx, TypeRef typeRef);

    // '#[Swag.Signal]': the struct reached by 'owner' in 'owner.field', which is the object the
    // signal stored in 'field' invokes its callbacks with. Invalid for any other expression.
    TypeRef signalOwnerTypeRef(Sema& sema, AstNodeRef signalRef);
    // The callback type a signal hands an owner of type 'ownerTypeRef': its first parameter reads
    // the owner with its own type when the owner starts with the declared one.
    Result signalCallbackTypeForOwner(Sema& sema, TypeRef callbackTypeRef, TypeRef ownerTypeRef, AstNodeRef waitNodeRef, TypeRef& outTypeRef);

    // Find runtime symbols under the shared import root or local module namespace.
    const Symbol* findPredefinedRuntimeSymbol(const Sema& sema, IdentifierManager::PredefinedName name);
    Result        attachRuntimeFunctionToNode(Sema& sema, AstNodeRef nodeRef, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef);
    Result        attachRuntimeAsFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef);
    Result        attachRuntimeIsFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef);
    Result        attachRuntimeStringCmpFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef);
    Result        attachRuntimeSliceCmpFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef);

    Result requireRuntimeSafetyPanicDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result requireRuntimeSafetyPanicDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef);
    Result requireRuntimeAsDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result requireRuntimeAsDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef);
    Result requireRuntimeIsDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result requireRuntimeIsDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef);

    Result requireRuntimeErrorContextDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result requireRuntimePushErrDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result requireRuntimePopErrDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result requireRuntimeCatchErrDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result requireRuntimeCatchScopeDependencies(Sema& sema, const SourceCodeRef& codeRef);
    Result requireRuntimePopScopeDependencies(Sema& sema, const SourceCodeRef& codeRef);

    Result requireRuntimeStringCmpDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result requireRuntimeStringCmpDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef);

    Result requireRuntimeFunctionDependency(Sema& sema, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef);
    Result requireRuntimeFunctionDependency(SymbolFunction*& outRuntimeFn, Sema& sema, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef);

    TypeRef indirectReturnRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn);
    Result  attachIndirectReturnRuntimeStorageIfNeeded(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, const SymbolFunction& calledFn, std::string_view privateName);
    Result  attachIndirectReturnRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SymbolFunction& calledFn, std::string_view privateName);

    TypeRef borrowedAggregateArgumentRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn, TypeRef paramTypeRef);
    TypeRef smallByValueArrayRuntimeStorageTypeRef(Sema& sema, AstNodeRef exprRef, TypeRef exprTypeRef, ConstantRef exprCstRef);
    Result  attachBorrowedAggregateArgumentRuntimeStorageIfNeeded(Sema& sema, const SymbolFunction& calledFn, TypeRef paramTypeRef, AstNodeRef argRef);

    SymbolVariable* currentRuntimeStorage(Sema& sema);
    void            addCurrentFunctionCallDependency(Sema& sema, const SymbolFunction* calleeSym);
    Result          addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar, TypeRef typeRef);
    Result          addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar);

    bool                     needsPersistentCompilerRunReturn(const TaskContext& ctx, TypeRef typeRef);
    bool                     functionUsesIndirectReturnStorage(TaskContext& ctx, const SymbolFunction& function);
    Result                   currentFunctionUsesIndirectReturnStorage(bool& outUsesIndirectReturnStorage, Sema& sema);
    bool                     usesCallerReturnStorage(TaskContext& ctx, const SymbolFunction& function, const SymbolVariable& symVar);
    const SemaInlinePayload* retValStorageOwner(const Sema& sema, const SymbolVariable& symVar);

    bool typeHasLifecycle(TaskContext& ctx, TypeRef typeRef);

    const SemaInlinePayload* effectiveInlinePayload(const Sema& sema);

    // Visit inline chains from the innermost frame, skipping adjacent duplicate
    // payloads, until the visitor returns true.
    template<typename F>
    bool visitFrameInlinePayloads(const Sema& sema, F&& visit)
    {
        const SemaInlinePayload* previousPayload = nullptr;

        for (size_t i = sema.frames().size(); i > 0; --i)
        {
            const SemaInlinePayload* inlinePayload = sema.frames()[i - 1].currentInlinePayload();
            if (inlinePayload == previousPayload)
                continue;

            previousPayload = inlinePayload;

            for (; inlinePayload; inlinePayload = inlinePayload->parentInlinePayload)
            {
                if (visit(*inlinePayload))
                    return true;
            }
        }

        return false;
    }

    // Ordinary inline bodies already passed use-site nullability checks. Clones
    // lack the original flow facts, so rechecking their live types can reject
    // valid guarded accesses, especially with automatic release-mode inlining.
    // Macros and mixins were never checked standalone and need checks here.
    bool nullabilityValidatedBeforeInlining(const Sema& sema);

    const SymbolFunction* currentLocationFunction(const Sema& sema);

    AstNodeRef defaultArgumentExprRef(const SymbolVariable& param);
    bool       isCallerLocationDefaultInitializer(Sema& sema, AstNodeRef initRef);
    bool       isDirectCallerLocationDefault(const Sema& sema, const SymbolVariable& param);

    AstNodeRef unwrapCallCalleeRef(Sema& sema, AstNodeRef nodeRef);

    void pushConstExprRequirement(Sema& sema, AstNodeRef childRef);

    // Concatenate constant parts using their printed forms for compiler directives.
    Result appendConstantText(Sema& sema, std::span<const AstNodeRef> parts, Utf8& outText);

    IdentifierRef getUniqueIdentifier(Sema& sema, const std::string_view& name);
    // A generated name that every build of the same sources spells the same way. Use it for
    // functions and types, whose names reach runtime type identity and debug records.
    IdentifierRef getStableIdentifier(Sema& sema, const AstNode& node, const std::string_view& name);
    IdentifierRef resolveIdentifier(Sema& sema, const SourceCodeRef& codeRef);
    IdentifierRef resolveCodeParamIdentifier(const Sema& sema, uint32_t slot);

    uint32_t           uniqSlotIndex(TokenId tokenId);
    AstNodeRef         uniqSyntaxScopeNodeRef(Sema& sema);
    SemaInlinePayload* mixinInlinePayloadForUniq(Sema& sema);
    IdentifierRef      ensureCurrentScopeUniqIdentifier(Sema& sema, TokenId tokenId);
    IdentifierRef      resolveUniqIdentifier(Sema& sema, TokenId tokenId);

    Result checkBinaryOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView);
    Result castBinaryRightToLeft(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& leftView, SemaNodeView& rightView, CastKind castKind);

    Result resolveCountOfResult(Sema& sema, CountOfResultInfo& outResult, AstNodeRef exprRef);
    Result intrinsicCountOf(Sema& sema, AstNodeRef targetRef, AstNodeRef exprRef);

    bool    isTypeLikeTypeRef(const TaskContext& ctx, TypeRef typeRef);
    TypeRef structuralTypeRefFromTypeNode(Sema& sema, AstNodeRef typeNodeRef);
    TypeRef resolveRepresentedTypeRef(Sema& sema, const SemaNodeView& view);
    void    normalizeTypeOperandToConstant(Sema& sema, SemaNodeView& view);
    TypeRef normalizeTypeLikeValueTypeRef(Sema& sema, TypeRef typeRef, ConstantRef cstRef, AstNodeRef ownerNodeRef);
    TypeRef preciseAnyBoxedValueTypeRef(Sema& sema, TypeRef valueTypeRef, ConstantRef valueCstRef, AstNodeRef ownerNodeRef);
    Result  normalizeTypeInfoConstantRef(Sema& sema, ConstantRef& ioCstRef, AstNodeRef ownerNodeRef);

    Result deduceDefaultValueType(Sema& sema, AstNodeRef defaultValueRef, TypeRef& outTypeRef);
    Result finalizeDefaultValue(Sema& sema, AstNodeRef defaultValueRef, SymbolVariable& symVar);

    Result     tryMaterializeAggregateLiteralConstant(Sema& sema, AstNodeRef exprRef, TypeRef typeRef);
    Result     finalizeAggregateStruct(Sema& sema, const SmallVector<AstNodeRef>& children, bool autoNameFromIdentifiers = false);
    AstNodeRef bracePositionalElement(const Sema& sema, AstNodeRef nodeRef);
    AstNodeRef fieldShorthandIdentifier(const Ast& ast, AstNodeRef nodeRef);
    struct RecordOrTupleField
    {
        IdentifierRef nameRef = IdentifierRef::invalid();
        TypeRef       typeRef = TypeRef::invalid();
        uint64_t      offset  = 0;
    };

    bool collectRecordOrTupleFields(TaskContext& ctx, SmallVector<RecordOrTupleField>& out, TypeRef typeRef);
    bool sameRecordOrTupleShape(TaskContext& ctx, TypeRef leftTypeRef, TypeRef rightTypeRef);

    struct DestructuringField
    {
        AstNodeRef  bindingRef  = AstNodeRef::invalid();
        TypeRef     typeRef     = TypeRef::invalid();
        ConstantRef constantRef = ConstantRef::invalid();
        uint64_t    offset      = 0;
        bool        ignored     = false;
    };

    Result  resolveDestructuringPattern(Sema& sema, SmallVector<DestructuringField>& out, AstNodeRef patternRef, TypeRef sourceTypeRef, ConstantRef sourceConstantRef);
    Result  resolveDestructuringFieldIndices(Sema& sema, SmallVector<size_t>& outIndices, TypeRef sourceTypeRef, SourceViewRef patternSrcViewRef, std::span<const TokenRef> fieldNameRefs);
    TypeRef deduceConcretizedAggregateArrayType(Sema& sema, TypeRef typeRef, ConstantRef cstRef);
    TypeRef deduceConcretizedAggregateLiteralType(Sema& sema, TypeRef typeRef, ConstantRef cstRef);
    Result  resolveStructLikeChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef, TypeRef& outTypeRef);
    Result  resolveArrayLikeChildBindingType(Sema& sema, size_t childIndex, TypeRef targetTypeRef, TypeRef& outTypeRef);

    void handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym);
    void ensureCurrentLocalScopeSymbol(Sema& sema, Symbol* sym);
    void ensureCurrentLocalScopeSymbols(Sema& sema, std::span<Symbol* const> symbols);

    Result resolveMemberAccess(Sema& sema, AstNodeRef memberRef, AstMemberAccessExpr& node, bool allowOverloadSet);

    inline SemaScope* currentLocalSymbolScope(Sema& sema)
    {
        SemaScope* lookupScope = sema.lookupScope();
        if (lookupScope && lookupScope->isLocal())
            return lookupScope;

        return sema.curScope().isLocal() ? sema.curScopePtr() : nullptr;
    }

    // Strip aliases while preserving enum identity.
    inline const TypeInfo& aliasType(Sema& sema, const SemaNodeView& view)
    {
        const TypeInfo& typeInfo = *view.type();
        if (!typeInfo.isAlias())
            return typeInfo;

        const TypeRef typeRef = typeInfo.unwrap(sema.ctx(), view.typeRef(), TypeExpandE::Alias);
        SWC_ASSERT(typeRef.isValid());
        return sema.typeMgr().get(typeRef);
    }

    inline const SymbolEnum* enumSymbolFromType(Sema& sema, const TypeInfo& type)
    {
        const TypeInfo* enumType = &type;
        while (enumType->isAlias())
        {
            const TypeRef enumTypeRef = enumType->payloadSymAlias().underlyingTypeRef();
            if (enumTypeRef.isInvalid())
                return nullptr;

            enumType = &sema.typeMgr().get(enumTypeRef);
        }

        if (enumType->isEnum())
            return &enumType->payloadSymEnum();

        return nullptr;
    }

    inline const SymbolEnum* enumSymbolFromTypeRef(Sema& sema, TypeRef typeRef)
    {
        return typeRef.isValid() ? enumSymbolFromType(sema, sema.typeMgr().get(typeRef)) : nullptr;
    }

    // Strip aliases and enum wrappers down to their payload type.
    inline TypeRef aliasEnumTypeRef(Sema& sema, TypeRef typeRef)
    {
        const TypeRef unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        SWC_ASSERT(unwrappedTypeRef.isValid());

        return unwrappedTypeRef;
    }

    inline const TypeInfo& aliasEnumType(Sema& sema, const SemaNodeView& view)
    {
        const TypeInfo& typeInfo = *view.type();
        return typeInfo.unwrapAliasEnumTypeOrSelf(sema.ctx());
    }

    // Indexing uses an enum constant's underlying payload.
    inline ConstantRef indexOperandConstantRef(const SemaNodeView& view)
    {
        if (view.cstRef().isInvalid())
            return ConstantRef::invalid();
        if (!view.cst() || !view.cst()->isEnumValue())
            return view.cstRef();

        return view.cst()->getEnumValue();
    }

    // Operators consume the value behind a reference. Keep this common path
    // inline because assignment, binary, logical, and unary operators all use it.
    inline Result readReferenceValue(Sema& sema, SemaNodeView& view)
    {
        if (!view.typeRef().isValid())
            return Result::Continue;

        const TypeInfo& normalizedType = aliasEnumType(sema, view);
        if (!normalizedType.isReference())
            return Result::Continue;

        const TypeRef valueTypeRef = normalizedType.payloadTypeRef();
        SWC_RESULT(Cast::cast(sema, view, valueTypeRef, CastKind::Implicit));

        return Result::Continue;
    }

    void addCurrentScopeSymbol(Sema& sema, Symbol* sym);

    template<typename T>
    T& registerSymbol(Sema& sema, const AstNode& node, TokenRef tokNameRef, IdentifierRef forcedIdentRef = IdentifierRef::invalid())
    {
        TaskContext&        ctx = sema.ctx();
        const SourceCodeRef nameRef{node.srcViewRef(), tokNameRef};
        const Token&        tok   = sema.srcView(nameRef.srcViewRef).token(nameRef.tokRef);
        IdentifierRef       idRef = forcedIdentRef;
        if (!idRef.isValid())
        {
            if (Token::isCompilerUniq(tok.id))
                idRef = ensureCurrentScopeUniqIdentifier(sema, tok.id);
            else if (tok.id == TokenId::KwdUnnamed)
                idRef = sema.idMgr().addIdentifierOwned(std::format("__unnamed_param_{}", tokNameRef.get())); // A '_' parameter: no source name reaches it.
            else
                idRef = resolveIdentifier(sema, nameRef);
        }

        const SymbolFlags flags = sema.frame().flagsForCurrentAccess();

        T*         sym       = Symbol::make<T>(ctx, &node, tokNameRef, idRef, flags);
        SymbolMap* symbolMap = SemaFrame::currentSymMap(sema);
        if constexpr (std::is_same_v<T, SymbolVariable>)
        {
            if (tok.id == TokenId::KwdUnnamed)
                sym->setUnnamed();
        }

        SemaScope* localScope = currentLocalSymbolScope(sema);

        if (localScope)
        {
            localScope->addSymbol(sym);
            ctx.notifyAlive();
        }
        else
            symbolMap->addSymbol(ctx, sym, true);

        handleSymbolRegistration(sema, symbolMap, sym);
        sym->registerCompilerIf(sema);
        sema.setSymbol(sema.curNodeRef(), sym);

        return *(sym);
    }

    // Lexical declarations must ignore caller lookup overrides. Restore the
    // frame after the declaration and preserve its return value.
    template<typename F>
    decltype(auto) withoutLookupOverride(Sema& sema, F&& declare)
    {
        const auto savedFrame = sema.frame();
        auto&      frame      = sema.frame();
        frame.setLookupScope(nullptr);
        frame.setLookupScopeOverrideNodes(nullptr);

        decltype(auto) result = declare();
        sema.frame()          = savedFrame;

        return result;
    }

    template<typename T>
    T& registerUniqueSymbol(Sema& sema, const AstNode& node, const std::string_view& name)
    {
        TaskContext& ctx         = sema.ctx();
        const Utf8   privateName = Utf8("__") + Utf8(name);

        // A local's generated name reaches nothing but CodeView, so it keeps the cheaper counter.
        IdentifierRef idRef;
        if constexpr (std::is_same_v<T, SymbolVariable>)
            idRef = getUniqueIdentifier(sema, privateName);
        else
            idRef = getStableIdentifier(sema, node, privateName);
        const SymbolFlags flags = sema.frame().flagsForCurrentAccess();

        T* sym = Symbol::make<T>(ctx, &node, node.tokRef(), idRef, flags);

        SemaScope* localScope = currentLocalSymbolScope(sema);
        if (localScope && !localScope->symMap())
        {
            addCurrentScopeSymbol(sema, sym);
        }
        else
        {
            SymbolMap* symMap = localScope && localScope->symMap() ? localScope->symMap() : SemaFrame::currentSymMap(sema);
            symMap->addSymbol(ctx, sym, true);
        }

        sema.setSymbol(sema.curNodeRef(), sym);

        return *(sym);
    }

    template<typename T>
    void declareSymbol(Sema& sema, const T& node)
    {
        const AstNodeRef curNodeRef = sema.curNodeRef();
        if (!sema.viewSymbol(curNodeRef).hasSymbol())
            node.semaPreDecl(sema);

        SemaNodeView view = sema.viewSymbol(curNodeRef);
        SWC_ASSERT(view.hasSymbol());

        Symbol& sym = *view.sym();
        ensureCurrentLocalScopeSymbol(sema, &sym);
        sym.registerAttributes(sema);
        sym.setDeclared(sema.ctx());
    }
}

SWC_END_NAMESPACE();
