#pragma once
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
struct CodeGenNodePayload;

namespace SemaHelpers
{
    struct CountOfResultInfo
    {
        TypeRef         typeRef  = TypeRef::invalid();
        ConstantRef     cstRef   = ConstantRef::invalid();
        SymbolFunction* calledFn = nullptr;
    };

    CodeGenNodePayload&   ensureCodeGenNodePayload(Sema& sema, AstNodeRef nodeRef);
    Result                declareGhostAndCompleteStorage(Sema& sema, SymbolVariable& symVar, TypeRef typeRef);
    Result                ensureRuntimeStorageDeclaredAndCompleted(Sema& sema, SymbolVariable& storageSym, TypeRef storageTypeRef);
    Result                completeRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef);
    SymbolVariable&       registerUniqueRuntimeStorageSymbol(Sema& sema, const AstNode& node, std::string_view privateName);
    SymbolVariable&       getOrCreateRuntimeStorageSymbol(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, std::string_view privateName);
    Result                attachRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, TypeRef storageTypeRef, std::string_view privateName);
    Result                attachRuntimeStorageIfNeeded(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, TypeRef storageTypeRef, std::string_view privateName);
    Result                attachLiteralRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SemaNodeView& literalView);
    Result                setupRuntimeSafetyPanic(Sema& sema, AstNodeRef nodeRef, Runtime::SafetyWhat safetyKind, const SourceCodeRef& codeRef);
    bool                  binaryOpNeedsOverflowSafety(TokenId canonicalOp, AstModifierFlags modifierFlags);
    bool                  canUseContextualBinding(Sema& sema, AstNodeRef nodeRef);
    TypeRef               unwrapLambdaBindingType(TaskContext& ctx, TypeRef typeRef);
    TypeRef               unwrapAliasRefType(TaskContext& ctx, TypeRef typeRef);
    const SymbolFunction* resolveLambdaBindingFunction(Sema& sema);
    SymbolFunction*       callableTypeFunction(TaskContext& ctx, TypeRef typeRef);
    Result                attachRuntimeFunctionToNode(Sema& sema, AstNodeRef nodeRef, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef);
    Result                requireRuntimeFunctionDependency(Sema& sema, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef);
    Result                requireRuntimeFunctionDependency(SymbolFunction*& outRuntimeFn, Sema& sema, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef);
    TypeRef               indirectReturnRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn);
    Result                attachIndirectReturnRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SymbolFunction& calledFn, std::string_view privateName);
    TypeRef               borrowedAggregateArgumentRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn, TypeRef paramTypeRef);
    Result                attachBorrowedAggregateArgumentRuntimeStorageIfNeeded(Sema& sema, const SymbolFunction& calledFn, TypeRef paramTypeRef, AstNodeRef argRef);
    SymbolVariable*       currentRuntimeStorage(Sema& sema);
    void                  addCurrentFunctionCallDependency(Sema& sema, SymbolFunction* calleeSym);
    Result                addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar, TypeRef typeRef);
    Result                addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar);
    bool                  needsPersistentCompilerRunReturn(const Sema& sema, TypeRef typeRef);
    bool                  functionUsesIndirectReturnStorage(TaskContext& ctx, const SymbolFunction& function);
    bool                  currentFunctionUsesIndirectReturnStorage(Sema& sema);
    bool                  usesCallerReturnStorage(TaskContext& ctx, const SymbolFunction& function, const SymbolVariable& symVar);
    const SymbolFunction* currentLocationFunction(const Sema& sema);
    AstNodeRef            defaultArgumentExprRef(const SymbolVariable& param);
    bool                  isDirectCallerLocationDefault(const Sema& sema, const SymbolVariable& param);
    AstNodeRef            unwrapCallCalleeRef(Sema& sema, AstNodeRef nodeRef);
    void                  pushConstExprRequirement(Sema& sema, AstNodeRef childRef);
    IdentifierRef         getUniqueIdentifier(Sema& sema, const std::string_view& name);
    IdentifierRef         resolveIdentifier(Sema& sema, const SourceCodeRef& codeRef);
    uint32_t              aliasSlotIndex(TokenId tokenId);
    IdentifierRef         resolveAliasIdentifier(Sema& sema, TokenId tokenId);
    uint32_t              uniqSlotIndex(TokenId tokenId);
    AstNodeRef            uniqSyntaxScopeNodeRef(Sema& sema);
    SemaInlinePayload*    mixinInlinePayloadForUniq(Sema& sema);
    IdentifierRef         ensureCurrentScopeUniqIdentifier(Sema& sema, TokenId tokenId);
    IdentifierRef         resolveUniqIdentifier(Sema& sema, TokenId tokenId);
    Result                checkBinaryOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView);
    Result                castBinaryRightToLeft(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& leftView, SemaNodeView& rightView, CastKind castKind);
    Result                resolveCountOfResult(Sema& sema, CountOfResultInfo& outResult, AstNodeRef exprRef);
    Result                intrinsicCountOf(Sema& sema, AstNodeRef targetRef, AstNodeRef exprRef);
    Result                finalizeAggregateStruct(Sema& sema, const SmallVector<AstNodeRef>& children, bool autoNameFromIdentifiers = false);
    Result                resolveStructLikeChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef, TypeRef& outTypeRef);
    Result                resolveArrayLikeChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef, TypeRef& outTypeRef);
    void                  handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym);
    void                  ensureCurrentLocalScopeSymbol(Sema& sema, Symbol* sym);
    void                  ensureCurrentLocalScopeSymbols(Sema& sema, std::span<Symbol*> symbols);
    bool                  resolveAggregateMemberIndex(Sema& sema, const TypeInfo& aggregateType, IdentifierRef idRef, size_t& outIndex);
    Result                resolveMemberAccess(Sema& sema, AstNodeRef memberRef, AstMemberAccessExpr& node, bool allowOverloadSet);

    template<typename T>
    T& registerSymbol(Sema& sema, const AstNode& node, TokenRef tokNameRef)
    {
        TaskContext&        ctx   = sema.ctx();
        const SourceCodeRef nameRef{node.srcViewRef(), tokNameRef};
        const Token&        tok   = sema.srcView(nameRef.srcViewRef).token(nameRef.tokRef);
        const IdentifierRef idRef = Token::isCompilerUniq(tok.id) ? ensureCurrentScopeUniqIdentifier(sema, tok.id) : resolveIdentifier(sema, nameRef);

        const SymbolFlags flags = sema.frame().flagsForCurrentAccess();

        T*         sym       = Symbol::make<T>(ctx, &node, tokNameRef, idRef, flags);
        SymbolMap* symbolMap = SemaFrame::currentSymMap(sema);

        if (sema.curScope().isLocal())
            sema.curScope().addSymbol(sym);
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

        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(sym);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
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
