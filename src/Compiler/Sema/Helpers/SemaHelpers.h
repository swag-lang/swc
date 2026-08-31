#pragma once
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
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
    struct CountOfResultInfo
    {
        TypeRef         typeRef  = TypeRef::invalid();
        ConstantRef     cstRef   = ConstantRef::invalid();
        SymbolFunction* calledFn = nullptr;
    };

    // Flow facts implied by a boolean condition: the paths proven when the condition is
    // true, and those proven when it is false (e.g. `if x != null and y` → whenTrue =
    // {x, y}; `if !x` → whenFalse = {x}).
    struct NarrowGuards
    {
        SmallVector2<SemaNarrowFact> whenTrue;
        SmallVector2<SemaNarrowFact> whenFalse;
    };

    // One member of a struct-like aggregate literal, as reached by a given child expression:
    // a declared field when the target is a struct, otherwise the positional member of an
    // anonymous aggregate struct.
    struct AggregateChildSlot
    {
        const SymbolVariable* field   = nullptr;
        size_t                index   = 0;
        TypeRef               typeRef = TypeRef::invalid();
    };

    bool resolveAggregateChildSlot(Sema& sema, AggregateChildSlot& outSlot, const TypeInfo& targetType, std::span<const AstNodeRef> children, AstNodeRef childRef);
    // Intrinsics that hand back their numeric argument's own type, alias included, instead of
    // the underlying builtin one.
    bool isAliasPreservingNumericIntrinsic(TokenId tokenId);
    // Dividing by a literal zero is an error whether it is written '/' or '/='. Call it only
    // once the right operand is known to be constant.
    Result checkDivideByZeroConstant(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView);
    // Whether 'Swag.init(what, args...)' spells out a struct's fields one by one, rather than
    // handing it a single value of its own type to copy.
    bool    intrinsicInitTreatsArgsAsStructTuple(Sema& sema, TypeRef fillTypeRef, const SmallVector<AstNodeRef>& args);
    bool    extractNarrowPath(Sema& sema, AstNodeRef nodeRef, SmallVector4<const Symbol*>& outPath);
    void    collectNarrowGuards(Sema& sema, AstNodeRef condRef, NarrowGuards& out);
    TypeRef nullNarrowedTypeRef(Sema& sema, AstNodeRef nodeRef, TypeRef typeRef);
    // Which statements count as leaving the enclosing block. 'Guaranteed' keeps only the
    // ones that always do; 'Declared' adds the two that merely promise to and can still fall
    // through. 'Swag.panic' returns to its caller whenever a panic hook is installed — which is
    // exactly what the '#test' runner does, so one failing test does not end the run — and
    // under '#run', where the compiler decides whether execution continues
    // ('Swag.panic' in bin/runtime/error.swg). 'unreachable' lowers to nothing once
    // '#[Swag.Safety(.Unreachable, false)]' turns its guard off.
    enum class LocalFlowStop : uint8_t
    {
        Guaranteed,
        Declared,
    };

    bool stopsLocalFlow(Sema& sema, AstNodeRef nodeRef, LocalFlowStop stop = LocalFlowStop::Declared);
    void addNarrowFacts(SemaFrame& frame, std::span<const SemaNarrowFact> facts);
    void killNarrowFactsForLoopBody(Sema& sema, AstNodeRef bodyRef, SemaFrame& frame);
    void killNarrowPathAfterStatement(Sema& sema, AstNodeRef exprRef, bool nonNull);

    CodeGenLoweringPayload& ensureCodeGenLoweringPayload(Sema& sema, AstNodeRef nodeRef);
    Result                  declareGhostAndCompleteStorage(Sema& sema, SymbolVariable& symVar, TypeRef typeRef);
    Result                  ensureRuntimeStorageDeclaredAndCompleted(Sema& sema, SymbolVariable& storageSym, TypeRef storageTypeRef);
    Result                  completeRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef);
    SymbolVariable&         registerUniqueRuntimeStorageSymbol(Sema& sema, const AstNode& node, std::string_view privateName);
    SymbolVariable&         getOrCreateRuntimeStorageSymbol(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, std::string_view privateName);
    Result                  attachRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, TypeRef storageTypeRef, std::string_view privateName);
    Result                  attachRuntimeStorageIfNeeded(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, TypeRef storageTypeRef, std::string_view privateName);
    Result                  attachLiteralRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SemaNodeView& literalView);
    Result                  setupRuntimeSafetyPanic(Sema& sema, AstNodeRef nodeRef, Runtime::SafetyWhat safetyKind, const SourceCodeRef& codeRef);
    bool                    isLateInitAccess(Sema& sema, AstNodeRef nodeRef);
    void                    clearLateFieldReadGuard(Sema& sema, AstNodeRef nodeRef);
    bool                    binaryOpNeedsOverflowSafety(TokenId canonicalOp, AstModifierFlags modifierFlags);
    bool                    canUseContextualBinding(Sema& sema, AstNodeRef nodeRef);
    void                    scopeBindingsForStatement(Sema& sema);
    // Whether a bare identifier carrying this symbol resolves at codegen inside the
    // function currently being analyzed. An instance field only exists relative to a
    // base expression, and a parameter of another function (a macro receiver bound at
    // the call site) has no storage in the caller; neither can be named standalone.
    bool       bindingSymbolResolvesStandalone(Sema& sema, const SymbolVariable& symVar);
    bool       isTransparentExprNode(const AstNode& node);
    AstNodeRef resolveTransparentExprSourceRef(Sema& sema, AstNodeRef nodeRef);
    AstNodeRef resolveTransparentConditionExprSourceRef(Sema& sema, AstNodeRef nodeRef);
    void       preferContextualAutoMemberBindingType(Sema& sema, AstNodeRef exprRef);
    // The storage a binding ultimately exposes: aliases, enum wrappers and references
    // stripped, so later checks compare the carried payload and not the syntax that
    // happened to produce it.
    TypeRef               unwrapBindingType(TaskContext& ctx, TypeRef typeRef);
    TypeRef               ensureStructTypeRef(Sema& sema, SymbolStruct& symStruct);
    TypeRef               unwrapAliasRefType(TaskContext& ctx, TypeRef typeRef);
    const SymbolFunction* resolveLambdaBindingFunction(Sema& sema);
    SymbolFunction*       callableTypeFunction(TaskContext& ctx, TypeRef typeRef);
    // The runtime `Swag.<name>` symbol of the current compilation, wherever runtime files rooted
    // it (the shared import-root namespace, or the module namespace without one).
    const Symbol*            findPredefinedRuntimeSymbol(const Sema& sema, IdentifierManager::PredefinedName name);
    Result                   attachRuntimeFunctionToNode(Sema& sema, AstNodeRef nodeRef, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef);
    Result                   attachRuntimeAsFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef);
    Result                   attachRuntimeIsFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef);
    Result                   attachRuntimeStringCmpFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef);
    Result                   attachRuntimeSliceCmpFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef);
    Result                   requireRuntimeSafetyPanicDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimeSafetyPanicDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimeAsDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimeAsDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimeIsDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimeIsDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimeErrorContextDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimePushErrDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimePopErrDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimeCatchErrDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimeCatchScopeDependencies(Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimePopScopeDependencies(Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimeStringCmpDependency(Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimeStringCmpDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef);
    Result                   requireRuntimeFunctionDependency(Sema& sema, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef);
    Result                   requireRuntimeFunctionDependency(SymbolFunction*& outRuntimeFn, Sema& sema, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef);
    TypeRef                  indirectReturnRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn);
    Result                   attachIndirectReturnRuntimeStorageIfNeeded(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, const SymbolFunction& calledFn, std::string_view privateName);
    Result                   attachIndirectReturnRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SymbolFunction& calledFn, std::string_view privateName);
    TypeRef                  borrowedAggregateArgumentRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn, TypeRef paramTypeRef);
    TypeRef                  smallByValueArrayRuntimeStorageTypeRef(Sema& sema, AstNodeRef exprRef, TypeRef exprTypeRef, ConstantRef exprCstRef);
    Result                   attachBorrowedAggregateArgumentRuntimeStorageIfNeeded(Sema& sema, const SymbolFunction& calledFn, TypeRef paramTypeRef, AstNodeRef argRef);
    SymbolVariable*          currentRuntimeStorage(Sema& sema);
    void                     addCurrentFunctionCallDependency(Sema& sema, const SymbolFunction* calleeSym);
    Result                   addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar, TypeRef typeRef);
    Result                   addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar);
    bool                     needsPersistentCompilerRunReturn(const Sema& sema, TypeRef typeRef);
    bool                     functionUsesIndirectReturnStorage(TaskContext& ctx, const SymbolFunction& function);
    Result                   currentFunctionUsesIndirectReturnStorage(bool& outUsesIndirectReturnStorage, Sema& sema);
    bool                     usesCallerReturnStorage(TaskContext& ctx, const SymbolFunction& function, const SymbolVariable& symVar);
    bool                     functionExposesReturnSlot(const SymbolFunction& function, const SymbolVariable* ignoreSym = nullptr);
    bool                     typeHasLifecycle(TaskContext& ctx, TypeRef typeRef);
    const SemaInlinePayload* effectiveInlinePayload(const Sema& sema);
    const SymbolFunction*    currentLocationFunction(const Sema& sema);
    AstNodeRef               defaultArgumentExprRef(const SymbolVariable& param);
    bool                     isCallerLocationDefaultInitializer(Sema& sema, AstNodeRef initRef);
    bool                     isDirectCallerLocationDefault(const Sema& sema, const SymbolVariable& param);
    AstNodeRef               unwrapCallCalleeRef(Sema& sema, AstNodeRef nodeRef);
    void                     pushConstExprRequirement(Sema& sema, AstNodeRef childRef);
    IdentifierRef            getUniqueIdentifier(Sema& sema, const std::string_view& name);
    IdentifierRef            resolveIdentifier(Sema& sema, const SourceCodeRef& codeRef);
    IdentifierRef            resolveCodeParamIdentifier(const Sema& sema, uint32_t slot);
    uint32_t                 uniqSlotIndex(TokenId tokenId);
    AstNodeRef               uniqSyntaxScopeNodeRef(Sema& sema);
    SemaInlinePayload*       mixinInlinePayloadForUniq(Sema& sema);
    IdentifierRef            ensureCurrentScopeUniqIdentifier(Sema& sema, TokenId tokenId);
    IdentifierRef            resolveUniqIdentifier(Sema& sema, TokenId tokenId);
    Result                   checkBinaryOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView);
    Result                   castBinaryRightToLeft(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& leftView, SemaNodeView& rightView, CastKind castKind);
    Result                   resolveCountOfResult(Sema& sema, CountOfResultInfo& outResult, AstNodeRef exprRef);
    Result                   intrinsicCountOf(Sema& sema, AstNodeRef targetRef, AstNodeRef exprRef);
    bool                     isTypeLikeTypeRef(const TaskContext& ctx, TypeRef typeRef);
    TypeRef                  structuralTypeRefFromTypeNode(Sema& sema, AstNodeRef typeNodeRef);
    TypeRef                  resolveRepresentedTypeRef(Sema& sema, const SemaNodeView& view);
    void                     normalizeTypeOperandToConstant(Sema& sema, SemaNodeView& view);
    TypeRef                  normalizeTypeLikeValueTypeRef(Sema& sema, TypeRef typeRef, ConstantRef cstRef, AstNodeRef ownerNodeRef);
    TypeRef                  preciseAnyBoxedValueTypeRef(Sema& sema, TypeRef valueTypeRef, ConstantRef valueCstRef, AstNodeRef ownerNodeRef);
    Result                   normalizeTypeInfoConstantRef(Sema& sema, ConstantRef& ioCstRef, AstNodeRef ownerNodeRef);
    Result                   deduceDefaultValueType(Sema& sema, AstNodeRef defaultValueRef, TypeRef& outTypeRef);
    Result                   finalizeDefaultValue(Sema& sema, AstNodeRef defaultValueRef, SymbolVariable& symVar);
    Result                   tryMaterializeAggregateLiteralConstant(Sema& sema, AstNodeRef exprRef, TypeRef typeRef);
    Result                   finalizeAggregateStruct(Sema& sema, const SmallVector<AstNodeRef>& children, bool autoNameFromIdentifiers = false);
    Result                   resolveDestructuringFieldIndices(Sema& sema, SmallVector<size_t>& outIndices, TypeRef sourceTypeRef, SourceViewRef patternSrcViewRef, std::span<const TokenRef> fieldNameRefs);
    TypeRef                  deduceConcretizedAggregateArrayType(Sema& sema, TypeRef typeRef, ConstantRef cstRef);
    TypeRef                  deduceConcretizedAggregateLiteralType(Sema& sema, TypeRef typeRef, ConstantRef cstRef);
    Result                   resolveStructLikeChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef, TypeRef& outTypeRef);
    Result                   resolveArrayLikeChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef, TypeRef& outTypeRef);
    void                     handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym);
    void                     ensureCurrentLocalScopeSymbol(Sema& sema, Symbol* sym);
    void                     ensureCurrentLocalScopeSymbols(Sema& sema, std::span<Symbol* const> symbols);
    Result                   resolveMemberAccess(Sema& sema, AstNodeRef memberRef, AstMemberAccessExpr& node, bool allowOverloadSet);

    inline SemaScope* currentLocalSymbolScope(Sema& sema)
    {
        SemaScope* lookupScope = sema.lookupScope();
        if (lookupScope && lookupScope->isLocal())
            return lookupScope;
        return sema.curScope().isLocal() ? sema.curScopePtr() : nullptr;
    }

    inline bool shouldReadReferenceValue(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeRef normalizedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        if (!normalizedTypeRef.isValid())
            return false;

        const TypeInfo& normalizedType = sema.typeMgr().get(normalizedTypeRef);
        return normalizedType.isReference();
    }

    // An operand of reference type takes part in an expression through the value it designates,
    // so the reference is read before the operator sees it. Kept inline because every operator
    // form (assign, binary, logical, unary) calls it on its own operands.
    inline Result readReferenceValue(Sema& sema, SemaNodeView& view)
    {
        if (!shouldReadReferenceValue(sema, view.typeRef()))
            return Result::Continue;

        const TypeRef normalizedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), view.typeRef());
        const TypeRef valueTypeRef      = sema.typeMgr().get(normalizedTypeRef).payloadTypeRef();
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
        const IdentifierRef idRef = forcedIdentRef.isValid() ? forcedIdentRef : (Token::isCompilerUniq(tok.id) ? ensureCurrentScopeUniqIdentifier(sema, tok.id) : resolveIdentifier(sema, nameRef));

        const SymbolFlags flags = sema.frame().flagsForCurrentAccess();

        T*         sym        = Symbol::make<T>(ctx, &node, tokNameRef, idRef, flags);
        SymbolMap* symbolMap  = SemaFrame::currentSymMap(sema);
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

    template<typename T>
    T& registerUniqueSymbol(Sema& sema, const AstNode& node, const std::string_view& name)
    {
        TaskContext&        ctx         = sema.ctx();
        const Utf8          privateName = Utf8("__") + Utf8(name);
        const IdentifierRef idRef       = getUniqueIdentifier(sema, privateName);
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();

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
