#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbol.impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

Result SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SymbolFunction& calledFn, std::string_view privateName)
{
    return attachRuntimeStorageIfNeeded(sema, node, indirectReturnRuntimeStorageTypeRef(sema, calledFn), privateName);
}

TypeRef SemaHelpers::indirectReturnRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn)
{
    if (sema.isGlobalScope())
        return TypeRef::invalid();

    const TypeRef returnTypeRef = calledFn.returnTypeRef();
    if (!returnTypeRef.isValid())
        return TypeRef::invalid();

    const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
    if (returnType.isVoid())
        return TypeRef::invalid();

    const CallConv&                        callConv      = CallConv::get(calledFn.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(sema.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
    if (!normalizedRet.isIndirect)
        return TypeRef::invalid();

    const TypeRef storageTypeRef = returnType.unwrap(sema.ctx(), returnTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    if (storageTypeRef.isValid())
        return storageTypeRef;

    return returnTypeRef;
}

Result SemaHelpers::attachRuntimeStorageIfNeeded(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, TypeRef storageTypeRef, std::string_view privateName)
{
    if (storageTypeRef.isInvalid())
        return Result::Continue;

    auto& storageSym = getOrCreateRuntimeStorageSymbol(sema, payloadNodeRef, storageNode, privateName);
    SWC_RESULT(ensureRuntimeStorageDeclaredAndCompleted(sema, storageSym, storageTypeRef));
    return Result::Continue;
}

Result SemaHelpers::attachRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, TypeRef storageTypeRef, std::string_view privateName)
{
    return attachRuntimeStorageIfNeeded(sema, sema.curNodeRef(), node, storageTypeRef, privateName);
}

Result SemaHelpers::requireRuntimeFunctionDependency(SymbolFunction*& outRuntimeFn, Sema& sema, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef)
{
    outRuntimeFn = nullptr;
    SWC_RESULT(sema.waitRuntimeFunction(kind, outRuntimeFn, codeRef));
    SWC_ASSERT(outRuntimeFn != nullptr);
    addCurrentFunctionCallDependency(sema, outRuntimeFn);
    return Result::Continue;
}

Result SemaHelpers::requireRuntimeFunctionDependency(Sema& sema, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef)
{
    SymbolFunction* runtimeFn = nullptr;
    return requireRuntimeFunctionDependency(runtimeFn, sema, kind, codeRef);
}

Result SemaHelpers::attachRuntimeFunctionToNode(Sema& sema, AstNodeRef nodeRef, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef)
{
    SymbolFunction* runtimeFn = nullptr;
    SWC_RESULT(sema.waitRuntimeFunction(kind, runtimeFn, codeRef));
    SWC_ASSERT(runtimeFn != nullptr);

    addCurrentFunctionCallDependency(sema, runtimeFn);
    ensureCodeGenNodePayload(sema, nodeRef).runtimeFunctionSymbol = runtimeFn;
    return Result::Continue;
}

TypeRef SemaHelpers::unwrapLambdaBindingType(TaskContext& ctx, TypeRef typeRef)
{
    while (typeRef.isValid())
    {
        const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
        const TypeRef   unwrapped = typeInfo.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias | TypeExpandE::Enum);
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

    return typeRef;
}

TypeRef SemaHelpers::unwrapAliasRefType(TaskContext& ctx, TypeRef typeRef)
{
    while (typeRef.isValid())
    {
        const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
        const TypeRef   unwrapped = typeInfo.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias);
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

    return typeRef;
}

SymbolFunction* SemaHelpers::callableTypeFunction(TaskContext& ctx, TypeRef typeRef)
{
    typeRef = unwrapLambdaBindingType(ctx, typeRef);
    if (!typeRef.isValid())
        return nullptr;

    const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
    if (!typeInfo.isFunction())
        return nullptr;

    return &typeInfo.payloadSymFunction();
}

const SymbolFunction* SemaHelpers::resolveLambdaBindingFunction(Sema& sema)
{
    const std::span<const TypeRef> bindingTypes = sema.frame().bindingTypes();
    for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
    {
        const TypeRef bindingTypeRef = unwrapLambdaBindingType(sema.ctx(), bindingTypes[bindingIndex - 1]);
        if (!bindingTypeRef.isValid())
            continue;

        const TypeInfo& bindingType = sema.typeMgr().get(bindingTypeRef);
        if (bindingType.isFunction())
            return &bindingType.payloadSymFunction();
    }

    return nullptr;
}

bool SemaHelpers::binaryOpNeedsOverflowSafety(TokenId canonicalOp, AstModifierFlags modifierFlags)
{
    switch (canonicalOp)
    {
        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymAsterisk:
        case TokenId::SymSlash:
        case TokenId::SymPercent:
            return !modifierFlags.has(AstModifierFlagsE::Wrap);

        case TokenId::SymLowerLower:
        case TokenId::SymGreaterGreater:
            return true;

        default:
            return false;
    }
}

bool SemaHelpers::canUseContextualBinding(Sema& sema, AstNodeRef nodeRef)
{
    if (nodeRef.isInvalid())
        return false;

    const AstNode& node = sema.node(nodeRef);
    switch (node.id())
    {
        case AstNodeId::AutoMemberAccessExpr:
        case AstNodeId::IntegerLiteral:
        case AstNodeId::BinaryLiteral:
        case AstNodeId::HexaLiteral:
        case AstNodeId::FloatLiteral:
        case AstNodeId::NullLiteral:
        case AstNodeId::ArrayLiteral:
        case AstNodeId::StructLiteral:
            return true;

        case AstNodeId::BinaryExpr:
        {
            const auto& binary = node.cast<AstBinaryExpr>();
            return canUseContextualBinding(sema, binary.nodeLeftRef) || canUseContextualBinding(sema, binary.nodeRightRef);
        }

        case AstNodeId::ParenExpr:
            return canUseContextualBinding(sema, node.cast<AstParenExpr>().nodeExprRef);

        case AstNodeId::UnaryExpr:
            return canUseContextualBinding(sema, node.cast<AstUnaryExpr>().nodeExprRef);

        default:
            return false;
    }
}

Result SemaHelpers::setupRuntimeSafetyPanic(Sema& sema, AstNodeRef nodeRef, Runtime::SafetyWhat safetyKind, const SourceCodeRef& codeRef)
{
    if (!sema.frame().currentAttributes().hasRuntimeSafety(sema.buildCfg().safetyGuards, safetyKind))
        return Result::Continue;

    auto& payload = ensureCodeGenNodePayload(sema, nodeRef);
    payload.addRuntimeSafety(safetyKind);

    if (!sema.isCurrentFunction())
        return Result::Continue;

    SymbolFunction* panicFn = nullptr;
    SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::SafetyPanic, panicFn, codeRef));
    SWC_ASSERT(panicFn != nullptr);

    addCurrentFunctionCallDependency(sema, panicFn);
    payload.runtimeFunctionSymbol = panicFn;
    return Result::Continue;
}

Result SemaHelpers::attachLiteralRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SemaNodeView& literalView)
{
    if (sema.isGlobalScope())
        return Result::Continue;
    if (!literalView.type())
        return Result::Continue;
    if (literalView.hasConstant())
        return Result::Continue;
    if (!literalView.type()->isAggregateStruct() && !literalView.type()->isAggregateArray())
        return Result::Continue;

    return attachRuntimeStorageIfNeeded(sema, node, literalView.typeRef(), "__literal_runtime_storage");
}

SymbolVariable& SemaHelpers::getOrCreateRuntimeStorageSymbol(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, std::string_view privateName)
{
    auto& payload = ensureCodeGenNodePayload(sema, payloadNodeRef);
    if (payload.runtimeStorageSym != nullptr)
        return *payload.runtimeStorageSym;

    if (SymbolVariable* const boundStorage = currentRuntimeStorage(sema))
    {
        payload.runtimeStorageSym = boundStorage;
        return *boundStorage;
    }

    auto& sym                 = registerUniqueRuntimeStorageSymbol(sema, storageNode, privateName);
    payload.runtimeStorageSym = &sym;
    return sym;
}

SymbolVariable& SemaHelpers::registerUniqueRuntimeStorageSymbol(Sema& sema, const AstNode& node, std::string_view privateName)
{
    TaskContext&        ctx         = sema.ctx();
    const IdentifierRef idRef       = getUniqueIdentifier(sema, privateName);
    const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();
    auto* const         symVariable = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);

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

    return *symVariable;
}

Result SemaHelpers::ensureRuntimeStorageDeclaredAndCompleted(Sema& sema, SymbolVariable& storageSym, TypeRef storageTypeRef)
{
    // Skip when this storage is the implicit binding the caller passed in: it's already
    // owned and finalized by the surrounding context, so re-declaring would double-register.
    if (&storageSym == currentRuntimeStorage(sema))
        return Result::Continue;

    if (!storageSym.isDeclared())
    {
        storageSym.registerAttributes(sema);
        storageSym.setDeclared(sema.ctx());
    }

    if (!storageSym.isSemaCompleted())
    {
        SWC_RESULT(Match::ghosting(sema, storageSym));
        SWC_RESULT(completeRuntimeStorageSymbol(sema, storageSym, storageTypeRef));
    }

    return Result::Continue;
}

Result SemaHelpers::declareGhostAndCompleteStorage(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
{
    symVar.registerAttributes(sema);
    symVar.setDeclared(sema.ctx());
    SWC_RESULT(Match::ghosting(sema, symVar));
    SWC_RESULT(completeRuntimeStorageSymbol(sema, symVar, typeRef));
    return Result::Continue;
}

Result SemaHelpers::completeRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
{
    symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
    symVar.setTypeRef(typeRef);

    SWC_RESULT(addCurrentFunctionLocalVariable(sema, symVar, typeRef));

    symVar.setTyped(sema.ctx());
    symVar.setSemaCompleted(sema.ctx());
    return Result::Continue;
}

CodeGenNodePayload& SemaHelpers::ensureCodeGenNodePayload(Sema& sema, AstNodeRef nodeRef)
{
    auto* payload = sema.codeGenPayload<CodeGenNodePayload>(nodeRef);
    if (payload)
        return *payload;

    payload  = sema.compiler().allocate<CodeGenNodePayload>();
    *payload = {};
    sema.setCodeGenPayload(nodeRef, payload);
    return *payload;
}

SymbolVariable* SemaHelpers::currentRuntimeStorage(Sema& sema)
{
    SymbolVariable* const sym     = sema.frame().currentRuntimeStorageSym();
    const AstNodeRef      nodeRef = sema.frame().currentRuntimeStorageNodeRef();
    if (!sym || !nodeRef.isValid())
        return nullptr;

    const AstNodeRef resolvedTargetRef  = sema.viewZero(nodeRef).nodeRef();
    const AstNodeRef resolvedCurrentRef = sema.viewZero(sema.curNodeRef()).nodeRef();
    if (resolvedTargetRef != resolvedCurrentRef)
        return nullptr;

    return sym;
}

void SemaHelpers::addCurrentFunctionCallDependency(Sema& sema, SymbolFunction* calleeSym)
{
    SWC_ASSERT(calleeSym);
    if (!sema.isCurrentFunction())
        return;

    sema.currentFunction()->addCallDependency(calleeSym);
}

Result SemaHelpers::addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
{
    if (!sema.isCurrentFunction() || !typeRef.isValid())
        return Result::Continue;

    const TypeInfo& symType = sema.typeMgr().get(typeRef);
    SWC_RESULT(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
    sema.currentFunction()->addLocalVariable(sema.ctx(), &symVar);
    return Result::Continue;
}

Result SemaHelpers::addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar)
{
    return addCurrentFunctionLocalVariable(sema, symVar, symVar.typeRef());
}

void SemaHelpers::ensureCurrentLocalScopeSymbol(Sema& sema, Symbol* sym)
{
    if (!sym || !sema.curScope().isLocal())
        return;

    for (const Symbol* existing : sema.curScope().symbols())
    {
        if (existing == sym)
            return;
    }

    sema.curScope().addSymbol(sym);
}

void SemaHelpers::ensureCurrentLocalScopeSymbols(Sema& sema, std::span<Symbol*> symbols)
{
    if (!sema.curScope().isLocal())
        return;

    for (Symbol* sym : symbols)
        ensureCurrentLocalScopeSymbol(sema, sym);
}

bool SemaHelpers::needsPersistentCompilerRunReturn(const Sema& sema, TypeRef typeRef)
{
    if (!typeRef.isValid())
        return false;

    const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
    if (typeInfo.isAlias())
        return needsPersistentCompilerRunReturn(sema, typeInfo.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias));

    if (typeInfo.isEnum())
        return needsPersistentCompilerRunReturn(sema, typeInfo.unwrap(sema.ctx(), typeRef, TypeExpandE::Enum));

    if (typeInfo.isString() || typeInfo.isSlice() || typeInfo.isAny() || typeInfo.isInterface() || typeInfo.isCString())
        return true;

    if (typeInfo.isArray())
        return needsPersistentCompilerRunReturn(sema, typeInfo.payloadArrayElemTypeRef());

    if (typeInfo.isStruct())
    {
        for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
        {
            if (field && needsPersistentCompilerRunReturn(sema, field->typeRef()))
                return true;
        }
    }

    return false;
}

bool SemaHelpers::functionUsesIndirectReturnStorage(TaskContext& ctx, const SymbolFunction& function)
{
    const TypeRef returnTypeRef = function.returnTypeRef();
    if (!returnTypeRef.isValid())
        return false;

    const CallConv&                        callConv      = CallConv::get(function.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(ctx, callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
    return normalizedRet.isIndirect;
}

bool SemaHelpers::currentFunctionUsesIndirectReturnStorage(Sema& sema)
{
    const SymbolFunction* currentFn = sema.currentFunction();
    return currentFn && functionUsesIndirectReturnStorage(sema.ctx(), *currentFn);
}

bool SemaHelpers::usesCallerReturnStorage(TaskContext& ctx, const SymbolFunction& function, const SymbolVariable& symVar)
{
    return symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) &&
           functionUsesIndirectReturnStorage(ctx, function);
}

AstNodeRef SemaHelpers::unwrapCallCalleeRef(Sema& sema, AstNodeRef nodeRef)
{
    while (nodeRef.isValid())
    {
        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isValid() && resolvedRef != nodeRef)
        {
            nodeRef = resolvedRef;
            continue;
        }

        const AstNode& node = sema.node(nodeRef);
        if (node.is(AstNodeId::ParenExpr))
        {
            nodeRef = node.cast<AstParenExpr>().nodeExprRef;
            continue;
        }

        if (node.is(AstNodeId::QuotedExpr))
        {
            nodeRef = node.cast<AstQuotedExpr>().nodeExprRef;
            continue;
        }

        if (node.is(AstNodeId::QuotedListExpr))
        {
            nodeRef = node.cast<AstQuotedListExpr>().nodeExprRef;
            continue;
        }

        break;
    }

    return nodeRef;
}

const SymbolFunction* SemaHelpers::currentLocationFunction(const Sema& sema)
{
    const auto* inlinePayload = sema.frame().currentInlinePayload();
    if (inlinePayload && inlinePayload->sourceFunction)
        return SemaRuntime::transparentLocationFunction(inlinePayload->sourceFunction);

    return SemaRuntime::transparentLocationFunction(sema.currentFunction());
}

AstNodeRef SemaHelpers::defaultArgumentExprRef(const SymbolVariable& param)
{
    const AstNode* declNode = param.decl();
    if (!declNode)
        return AstNodeRef::invalid();

    if (const auto* singleVar = declNode->safeCast<AstSingleVarDecl>())
        return singleVar->nodeInitRef;

    if (const auto* multiVar = declNode->safeCast<AstMultiVarDecl>())
        return multiVar->nodeInitRef;

    return AstNodeRef::invalid();
}

bool SemaHelpers::isDirectCallerLocationDefault(const Sema& /*sema*/, const SymbolVariable& param)
{
    return param.hasExtraFlag(SymbolVariableFlagsE::CallerLocationDefault);
}

void SemaHelpers::pushConstExprRequirement(Sema& sema, AstNodeRef childRef)
{
    SWC_ASSERT(childRef.isValid());
    auto frame = sema.frame();
    frame.addContextFlag(SemaFrameContextFlagsE::RequireConstExpr);
    sema.pushFramePopOnPostChild(frame, childRef);
}

IdentifierRef SemaHelpers::getUniqueIdentifier(Sema& sema, const std::string_view& name)
{
    const uint32_t id = sema.compiler().atomicId().fetch_add(1);
    return sema.idMgr().addIdentifierOwned(std::format("{}_{}", name, id));
}

IdentifierRef SemaHelpers::resolveIdentifier(Sema& sema, const SourceCodeRef& codeRef)
{
    const Token& tok = sema.srcView(codeRef.srcViewRef).token(codeRef.tokRef);
    if (Token::isCompilerUniq(tok.id))
        return resolveUniqIdentifier(sema, tok.id);

    if (Token::isCompilerAlias(tok.id))
    {
        const IdentifierRef idRef = resolveAliasIdentifier(sema, tok.id);
        if (idRef.isValid())
            return idRef;
    }

    return sema.idMgr().addIdentifier(sema.ctx(), codeRef);
}

uint32_t SemaHelpers::aliasSlotIndex(const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerAlias(tokenId));
    return static_cast<uint32_t>(tokenId) - static_cast<uint32_t>(TokenId::CompilerAlias0);
}

IdentifierRef SemaHelpers::resolveAliasIdentifier(Sema& sema, const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerAlias(tokenId));

    const auto* inlinePayload = sema.frame().currentInlinePayload();
    if (!inlinePayload)
        return IdentifierRef::invalid();

    const uint32_t slot = aliasSlotIndex(tokenId);
    if (slot >= inlinePayload->aliasIdentifiers.size())
        return IdentifierRef::invalid();

    return inlinePayload->aliasIdentifiers[slot];
}

uint32_t SemaHelpers::uniqSlotIndex(const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerUniq(tokenId));
    return static_cast<uint32_t>(tokenId) - static_cast<uint32_t>(TokenId::CompilerUniq0);
}

AstNodeRef SemaHelpers::uniqSyntaxScopeNodeRef(Sema& sema)
{
    if (sema.curNode().is(AstNodeId::FunctionBody) || sema.curNode().is(AstNodeId::EmbeddedBlock))
        return sema.curNodeRef();

    for (size_t parentIndex = 0;; parentIndex++)
    {
        const AstNodeRef parentRef = sema.visit().parentNodeRef(parentIndex);
        if (parentRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeId parentId = sema.node(parentRef).id();
        if (parentId == AstNodeId::FunctionBody || parentId == AstNodeId::EmbeddedBlock)
            return parentRef;
    }
}

SemaInlinePayload* SemaHelpers::mixinInlinePayloadForUniq(Sema& sema)
{
    auto* inlinePayload = sema.frame().currentInlinePayload();
    if (!inlinePayload || !inlinePayload->sourceFunction)
        return nullptr;
    if (!inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        return nullptr;
    if (uniqSyntaxScopeNodeRef(sema) != inlinePayload->inlineRootRef)
        return nullptr;
    return inlinePayload;
}

IdentifierRef SemaHelpers::ensureCurrentScopeUniqIdentifier(Sema& sema, const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerUniq(tokenId));
    const uint32_t slot = uniqSlotIndex(tokenId);
    if (auto* inlinePayload = mixinInlinePayloadForUniq(sema))
    {
        const IdentifierRef done = inlinePayload->uniqIdentifiers[slot];
        if (done.isValid())
            return done;

        const IdentifierRef idRef            = getUniqueIdentifier(sema, std::format("__uniq{}", slot));
        inlinePayload->uniqIdentifiers[slot] = idRef;
        return idRef;
    }

    auto&               scope = sema.curScope();
    const IdentifierRef done  = scope.uniqIdentifier(slot);
    if (done.isValid())
        return done;

    const IdentifierRef idRef = getUniqueIdentifier(sema, std::format("__uniq{}", slot));
    scope.setUniqIdentifier(slot, idRef);
    return idRef;
}

IdentifierRef SemaHelpers::resolveUniqIdentifier(Sema& sema, const TokenId tokenId)
{
    SWC_ASSERT(Token::isCompilerUniq(tokenId));

    const uint32_t slot = uniqSlotIndex(tokenId);
    for (const SemaScope* scope = sema.lookupScope(); scope; scope = scope->lookupParent())
    {
        const IdentifierRef idRef = scope->uniqIdentifier(slot);
        if (idRef.isValid())
            return idRef;
    }

    if (const auto* inlinePayload = mixinInlinePayloadForUniq(sema))
    {
        const IdentifierRef idRef = inlinePayload->uniqIdentifiers[slot];
        if (idRef.isValid())
            return idRef;
    }

    return ensureCurrentScopeUniqIdentifier(sema, tokenId);
}

Result SemaHelpers::checkBinaryOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView)
{
    switch (op)
    {
        case TokenId::SymPlus:
            if (leftView.type()->isAnyPointer() && leftView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, leftRef, leftView.typeRef());
            if (rightView.type()->isAnyPointer() && rightView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, rightRef, rightView.typeRef());

            if (leftView.type()->isAnyPointer() && rightView.type()->isScalarNumeric())
                return Result::Continue;
            if (leftView.type()->isAnyPointer() && rightView.type()->isAnyPointer())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
            if (leftView.type()->isScalarNumeric() && rightView.type()->isAnyPointer())
                return Result::Continue;
            break;

        case TokenId::SymMinus:
            if (leftView.type()->isAnyPointer() && leftView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, leftRef, leftView.typeRef());
            if (rightView.type()->isAnyPointer() && rightView.type()->payloadTypeRef() == sema.typeMgr().typeVoid())
                return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, rightRef, rightView.typeRef());

            if (leftView.type()->isAnyPointer() && rightView.type()->isScalarNumeric())
                return Result::Continue;
            if (leftView.type()->isAnyPointer() && rightView.type()->isAnyPointer())
                return Result::Continue;
            break;

        default:
            break;
    }

    switch (op)
    {
        case TokenId::SymSlash:
        case TokenId::SymPercent:
        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymAsterisk:
            if (!leftView.type()->isScalarNumeric())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef(), rightView.typeRef());
            if (!rightView.type()->isScalarNumeric())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
            break;

        case TokenId::SymAmpersand:
        case TokenId::SymPipe:
        case TokenId::SymCircumflex:
        case TokenId::SymGreaterGreater:
        case TokenId::SymLowerLower:
            if (op == TokenId::SymAmpersand || op == TokenId::SymPipe || op == TokenId::SymCircumflex)
            {
                const bool leftEnumFlags  = leftView.type()->isEnumFlags();
                const bool rightEnumFlags = rightView.type()->isEnumFlags();
                if (leftEnumFlags && rightEnumFlags && leftView.typeRef() == rightView.typeRef())
                    break;
            }

            if (!leftView.type()->isIntLike())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef(), rightView.typeRef());
            if (!rightView.type()->isIntLike())
                return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, leftView.typeRef(), rightView.typeRef());
            break;

        default:
            break;
    }

    return Result::Continue;
}

Result SemaHelpers::castBinaryRightToLeft(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& leftView, SemaNodeView& rightView, CastKind castKind)
{
    SWC_UNUSED(nodeRef);
    switch (op)
    {
        case TokenId::SymPlus:
        case TokenId::SymMinus:
            if (leftView.type()->isAnyPointer() && rightView.type()->isScalarNumeric())
            {
                SWC_RESULT(Cast::cast(sema, rightView, sema.typeMgr().typeS64(), CastKind::Implicit));
                return Result::Continue;
            }
            if (leftView.type()->isScalarNumeric() && rightView.type()->isAnyPointer())
            {
                return Result::Continue;
            }
            if (leftView.type()->isAnyPointer() && rightView.type()->isAnyPointer())
            {
                return Result::Continue;
            }
            break;

        default:
            break;
    }

    if (op == TokenId::SymGreaterGreater || op == TokenId::SymLowerLower)
        return Result::Continue;

    SWC_RESULT(Cast::cast(sema, rightView, leftView.typeRef(), castKind));
    return Result::Continue;
}

Result SemaHelpers::resolveCountOfResult(Sema& sema, CountOfResultInfo& outResult, AstNodeRef exprRef)
{
    outResult               = {};
    auto               ctx  = sema.ctx();
    const SemaNodeView view = sema.viewTypeConstant(exprRef);

    if (!view.type())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, view.nodeRef());

    if (view.cst())
    {
        if (view.cst()->isString())
        {
            outResult.cstRef  = sema.cstMgr().addInt(ctx, view.cst()->getString().length());
            outResult.typeRef = sema.cstMgr().get(outResult.cstRef).typeRef();
            return Result::Continue;
        }

        if (view.cst()->isSlice())
        {
            const uint64_t count = view.cst()->getSliceCount();
            outResult.cstRef     = sema.cstMgr().addInt(ctx, count);
            outResult.typeRef    = sema.cstMgr().get(outResult.cstRef).typeRef();
            return Result::Continue;
        }

        if (view.cst()->isInt())
        {
            if (view.cst()->getInt().isNegative())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_count_negative, view.nodeRef());
                diag.addArgument(Diagnostic::ARG_VALUE, view.cst()->toString(ctx));
                diag.report(ctx);
                return Result::Error;
            }

            SWC_RESULT(Cast::concretizeConstant(sema, outResult.cstRef, view.nodeRef(), view.cstRef(), TypeInfo::Sign::Unsigned));
            outResult.typeRef = sema.cstMgr().get(outResult.cstRef).typeRef();
            return Result::Continue;
        }
    }

    const TypeRef   countTypeRef = unwrapAliasRefType(ctx, view.typeRef());
    const TypeInfo& countType    = sema.typeMgr().get(countTypeRef);

    if (countType.isEnum())
    {
        SWC_RESULT(sema.waitSemaCompleted(&countType, view.nodeRef()));
        outResult.cstRef  = sema.cstMgr().addInt(ctx, countType.payloadSymEnum().count());
        outResult.typeRef = sema.cstMgr().get(outResult.cstRef).typeRef();
        return Result::Continue;
    }

    if (countType.isCString())
    {
        outResult.typeRef = sema.typeMgr().typeU64();
        return Result::Continue;
    }

    if (countType.isString())
    {
        outResult.typeRef = sema.typeMgr().typeU64();
        return Result::Continue;
    }

    if (countType.isArray())
    {
        const uint64_t  sizeOf     = countType.sizeOf(ctx);
        const TypeRef   typeRef    = countType.payloadArrayElemTypeRef();
        const TypeInfo& ty         = sema.typeMgr().get(typeRef);
        const uint64_t  sizeOfElem = ty.sizeOf(ctx);
        SWC_ASSERT(sizeOfElem > 0);
        outResult.cstRef  = sema.cstMgr().addInt(ctx, sizeOf / sizeOfElem);
        outResult.typeRef = sema.cstMgr().get(outResult.cstRef).typeRef();
        return Result::Continue;
    }

    if (countType.isAggregateArray())
    {
        outResult.cstRef  = sema.cstMgr().addInt(ctx, countType.payloadAggregate().types.size());
        outResult.typeRef = sema.cstMgr().get(outResult.cstRef).typeRef();
        return Result::Continue;
    }

    if (countType.isSlice() || countType.isAnyVariadic())
    {
        outResult.typeRef = sema.typeMgr().typeU64();
        return Result::Continue;
    }

    if (countType.isInt())
    {
        outResult.typeRef = countTypeRef;
        return Result::Continue;
    }

    bool            handledSpecOp = false;
    SymbolFunction* calledFn      = nullptr;
    SWC_RESULT(SemaSpecOp::tryResolveCountOf(sema, exprRef, calledFn, handledSpecOp));
    if (handledSpecOp)
    {
        const SemaNodeView resultView = sema.viewNodeTypeConstant(sema.curNodeRef());
        outResult.typeRef             = resultView.typeRef();
        outResult.cstRef              = resultView.cstRef();
        outResult.calledFn            = calledFn;
        if (!outResult.typeRef.isValid() && calledFn)
            outResult.typeRef = calledFn->returnTypeRef();
        return Result::Continue;
    }

    auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, view.nodeRef());
    diag.addArgument(Diagnostic::ARG_TYPE, view.typeRef());
    diag.report(ctx);
    return Result::Error;
}

Result SemaHelpers::intrinsicCountOf(Sema& sema, AstNodeRef targetRef, AstNodeRef exprRef)
{
    CountOfResultInfo result;
    SWC_RESULT(resolveCountOfResult(sema, result, exprRef));
    if (result.calledFn != nullptr)
    {
        auto* payload = sema.semaPayload<CountOfSpecOpPayload>(targetRef);
        if (!payload)
        {
            payload = sema.compiler().allocate<CountOfSpecOpPayload>();
            sema.setSemaPayload(targetRef, payload);
        }

        payload->calledFn = result.calledFn;
    }

    if (result.cstRef.isValid())
    {
        sema.setConstant(targetRef, result.cstRef);
        return Result::Continue;
    }

    sema.setType(targetRef, result.typeRef);
    sema.setIsValue(targetRef);
    return Result::Continue;
}

namespace
{
    TypeRef normalizeBindingType(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
            const TypeRef   unwrapped = typeInfo.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias | TypeExpandE::Enum);
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

        return typeRef;
    }

    IdentifierRef namedArgumentIdentifier(Sema& sema, AstNodeRef childRef)
    {
        const AstNode& childNode = sema.node(childRef);
        if (childNode.isNot(AstNodeId::NamedArgument))
            return IdentifierRef::invalid();

        return sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef());
    }

    template<typename T>
    bool resolveAggregateChildIndex(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, size_t memberCount, const T& resolveNamedIndex, size_t& outIndex)
    {
        outIndex = 0;
        if (!memberCount)
            return false;

        std::vector<uint8_t> assigned(memberCount, 0);
        size_t               nextPos = 0;

        for (const AstNodeRef currentChildRef : children)
        {
            const IdentifierRef namedIdRef = namedArgumentIdentifier(sema, currentChildRef);
            if (namedIdRef.isValid())
            {
                size_t namedIndex = 0;
                if (!resolveNamedIndex(namedIdRef, namedIndex) || namedIndex >= memberCount)
                {
                    if (currentChildRef == childRef)
                        return false;
                    continue;
                }

                if (currentChildRef == childRef)
                {
                    outIndex = namedIndex;
                    return true;
                }

                assigned[namedIndex] = 1;
                continue;
            }

            while (nextPos < memberCount && assigned[nextPos])
                ++nextPos;

            if (currentChildRef == childRef)
            {
                if (nextPos >= memberCount)
                    return false;

                outIndex = nextPos;
                return true;
            }

            if (nextPos < memberCount)
            {
                assigned[nextPos] = 1;
                ++nextPos;
            }
        }

        return false;
    }
}

Result SemaHelpers::finalizeAggregateStruct(Sema& sema, const SmallVector<AstNodeRef>& children, bool autoNameFromIdentifiers)
{
    SmallVector<TypeRef>       memberTypes;
    SmallVector<IdentifierRef> memberNames;
    memberTypes.reserve(children.size());
    memberNames.reserve(children.size());

    bool                     allConstant = true;
    SmallVector<ConstantRef> values;
    values.reserve(children.size());

    for (const AstNodeRef& child : children)
    {
        const AstNode& childNode = sema.node(child);
        if (childNode.is(AstNodeId::NamedArgument))
            memberNames.push_back(sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef()));
        else if (autoNameFromIdentifiers && childNode.is(AstNodeId::Identifier))
            memberNames.push_back(sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef()));
        else
            memberNames.push_back(IdentifierRef::invalid());

        SemaNodeView view = sema.viewTypeConstant(child);
        SWC_ASSERT(view.typeRef().isValid());
        memberTypes.push_back(view.typeRef());
        allConstant = allConstant && view.cstRef().isValid();
        values.push_back(view.cstRef());
    }

    if (allConstant)
    {
        const auto val = ConstantValue::makeAggregateStruct(sema.ctx(), memberNames, values);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), val));
    }
    else
    {
        const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeAggregateStruct(memberNames, memberTypes));
        sema.setType(sema.curNodeRef(), typeRef);
    }

    sema.setIsValue(sema.curNodeRef());
    return Result::Continue;
}

Result SemaHelpers::resolveStructLikeChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef, TypeRef& outTypeRef)
{
    outTypeRef              = TypeRef::invalid();
    const TypeRef targetRef = normalizeBindingType(sema.ctx(), targetTypeRef);
    if (!targetRef.isValid())
        return Result::Continue;

    const TypeInfo& targetType = sema.typeMgr().get(targetRef);
    size_t          fieldIndex = 0;

    if (targetType.isStruct())
    {
        SWC_RESULT(sema.waitSemaCompleted(&targetType, childRef));
        const auto& fields = targetType.payloadSymStruct().fields();
        const bool  found  = resolveAggregateChildIndex(
            sema,
            children,
            childRef,
            fields.size(),
            [&](IdentifierRef idRef, size_t& outIndex) {
                for (size_t i = 0; i < fields.size(); ++i)
                {
                    if (fields[i] && fields[i]->idRef() == idRef)
                    {
                        outIndex = i;
                        return true;
                    }
                }

                return false;
            },
            fieldIndex);
        if (!found || fieldIndex >= fields.size() || !fields[fieldIndex])
            return Result::Continue;

        outTypeRef = fields[fieldIndex]->typeRef();
        return Result::Continue;
    }

    if (!targetType.isAggregateStruct())
        return Result::Continue;

    const auto& aggregate = targetType.payloadAggregate();
    const bool  found     = resolveAggregateChildIndex(
        sema,
        children,
        childRef,
        aggregate.types.size(),
        [&](IdentifierRef idRef, size_t& outIndex) {
            return resolveAggregateMemberIndex(sema, targetType, idRef, outIndex);
        },
        fieldIndex);
    if (!found || fieldIndex >= aggregate.types.size())
        return Result::Continue;

    outTypeRef = aggregate.types[fieldIndex];
    return Result::Continue;
}

Result SemaHelpers::resolveArrayLikeChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef, TypeRef& outTypeRef)
{
    outTypeRef              = TypeRef::invalid();
    const TypeRef targetRef = normalizeBindingType(sema.ctx(), targetTypeRef);
    if (!targetRef.isValid())
        return Result::Continue;

    size_t childIndex = 0;
    bool   found      = false;
    for (const AstNodeRef currentChildRef : children)
    {
        if (currentChildRef == childRef)
        {
            found = true;
            break;
        }

        ++childIndex;
    }

    if (!found)
        return Result::Continue;

    const TypeInfo& targetType = sema.typeMgr().get(targetRef);
    if (targetType.isArray())
    {
        outTypeRef = targetType.payloadArrayElemTypeRef();
        return Result::Continue;
    }

    if (targetType.isSlice() || targetType.isTypedVariadic())
    {
        outTypeRef = targetType.payloadTypeRef();
        return Result::Continue;
    }

    if (!targetType.isAggregateArray())
        return Result::Continue;

    const auto& elementTypes = targetType.payloadAggregate().types;
    if (childIndex >= elementTypes.size())
        return Result::Continue;

    outTypeRef = elementTypes[childIndex];
    return Result::Continue;
}

void SemaHelpers::handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym)
{
    SWC_ASSERT(symbolMap != nullptr);
    SWC_ASSERT(sym != nullptr);

    if (sym->isVariable())
    {
        auto& symVar = sym->cast<SymbolVariable>();
        if (symbolMap->isStruct())
            symbolMap->cast<SymbolStruct>().addField(&symVar);

        if (sema.curScope().isParameters())
        {
            symVar.addExtraFlag(SymbolVariableFlagsE::Parameter);
            if (symbolMap->isFunction())
                symbolMap->cast<SymbolFunction>().addParameter(&symVar);
        }
    }

    if (sym->isFunction())
    {
        auto& symFunc = sym->cast<SymbolFunction>();
        if (symbolMap->isInterface())
            symbolMap->cast<SymbolInterface>().addFunction(&symFunc);
        if (symbolMap->isImpl())
            symbolMap->cast<SymbolImpl>().addFunction(sema.ctx(), &symFunc);
    }
}

namespace
{
    bool hasImmediatePostfixCall(const Sema& sema, const AstMemberAccessExpr& node)
    {
        if (node.nodeRightRef.isInvalid())
            return false;

        const TokenRef tokRightRef = sema.node(node.nodeRightRef).tokRef();
        if (!tokRightRef.isValid())
            return false;

        const SourceView& srcView   = sema.srcView(node.srcViewRef());
        const uint32_t    nextIndex = tokRightRef.get() + 1;
        if (nextIndex >= srcView.numTokens())
            return false;

        return srcView.token(TokenRef{nextIndex}).id == TokenId::SymLeftParen;
    }

    const SymbolStruct* genericStructRootFromQuotedBase(Sema& sema, AstNodeRef exprRef)
    {
        SmallVector<Symbol*> symbols;
        sema.viewNodeTypeSymbol(exprRef).getSymbols(symbols);
        for (Symbol* sym : symbols)
        {
            if (!sym || !sym->isStruct())
                continue;

            auto& symStruct = sym->cast<SymbolStruct>();
            if (symStruct.isGenericRoot() && !symStruct.isGenericInstance())
                return &symStruct;
        }

        return nullptr;
    }

    bool canSplitQuotedSuffixArgument(Sema& sema, const SymbolStruct& genericRoot, const SemaNodeView& leftView)
    {
        const auto* decl = genericRoot.decl() ? genericRoot.decl()->safeCast<AstStructDecl>() : nullptr;
        if (!decl || !decl->spanGenericParamsRef.isValid())
            return false;

        SmallVector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, *decl, decl->spanGenericParamsRef, params);
        if (params.empty())
            return false;

        switch (params.front().kind)
        {
            case SemaGeneric::GenericParamKind::Type:
                return leftView.typeRef().isValid();
            case SemaGeneric::GenericParamKind::Value:
                return leftView.cstRef().isValid();
        }

        return false;
    }

    Result substituteQuotedGenericMemberCall(Sema& sema, AstNodeRef parentRef, AstNodeRef currentRef, TokenRef tokNameRef, std::span<const Symbol*> symbols, bool& outHandled)
    {
        if (symbols.empty())
            return Result::Continue;

        auto [calleeRef, calleePtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokNameRef);
        SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, calleeRef, true, symbols));
        sema.setSubstitute(parentRef, calleeRef);
        sema.setSubstitute(currentRef, calleeRef);
        sema.setIsValue(*calleePtr);
        outHandled = true;
        return Result::Continue;
    }

    Result tryLiftQuotedGenericStructMemberAccess(Sema& sema, AstNodeRef currentRef, const AstMemberAccessExpr& node, bool& outHandled)
    {
        outHandled                 = false;
        const AstNodeRef parentRef = sema.visit().parentNodeRef();
        if (parentRef.isInvalid())
            return Result::Continue;

        AstNode&    parentNode = sema.node(parentRef);
        const auto* quotedExpr = parentNode.safeCast<AstQuotedExpr>();
        if (!quotedExpr || quotedExpr->nodeSuffixRef != currentRef)
            return Result::Continue;
        if (!hasImmediatePostfixCall(sema, node))
            return Result::Continue;

        const SymbolStruct* genericRoot = genericStructRootFromQuotedBase(sema, quotedExpr->nodeExprRef);
        if (!genericRoot)
            return Result::Continue;

        const SemaNodeView leftView = sema.viewNodeTypeConstant(node.nodeLeftRef);
        if (!canSplitQuotedSuffixArgument(sema, *genericRoot, leftView))
            return Result::Continue;

        const auto* identRight = sema.node(node.nodeRightRef).safeCast<AstIdentifier>();
        if (!identRight)
            return Result::Continue;

        const IdentifierRef idRef      = SemaHelpers::resolveIdentifier(sema, identRight->codeRef());
        const TokenRef      tokNameRef = identRight->tokRef();
        const SourceCodeRef memberCode{node.srcViewRef(), tokNameRef};

        const AstNodeRef           genericArgRef = node.nodeLeftRef;
        SmallVector<const Symbol*> specializedFunctions;
        for (const SymbolImpl* symImpl : genericRoot->impls())
        {
            if (!symImpl)
                continue;

            std::vector<const Symbol*> symbols;
            symImpl->getAllSymbols(symbols);
            for (const Symbol* sym : symbols)
            {
                if (!sym || !sym->isFunction() || sym->idRef() != idRef)
                    continue;

                SymbolFunction* instance = nullptr;
                auto&           fn       = const_cast<SymbolFunction&>(sym->cast<SymbolFunction>());
                SWC_RESULT(SemaGeneric::instantiateFunctionExplicit(sema, fn, std::span{&genericArgRef, 1}, instance));
                if (instance)
                    specializedFunctions.push_back(instance);
            }
        }

        // `Type'Arg.member()` is parsed as `Type'(Arg.member)()`. When `member`
        // resolves to a generic static function of the generic root, reinterpret
        // that syntax as an explicit specialization of the function itself.
        if (!specializedFunctions.empty())
            return substituteQuotedGenericMemberCall(sema, parentRef, currentRef, tokNameRef, specializedFunctions.span(), outHandled);

        // For a concrete generic struct specialization, reinterpret the suffix
        // as member lookup on the specialized struct instead of on the suffix argument.
        SymbolStruct* specializedStruct = nullptr;
        auto&         genericRootRef    = const_cast<SymbolStruct&>(*genericRoot);
        SWC_RESULT(SemaGeneric::instantiateStructExplicit(sema, genericRootRef, std::span{&genericArgRef, 1}, specializedStruct));
        if (!specializedStruct)
            return Result::Continue;

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = memberCode;
        lookUpCxt.noWaitOnEmpty = true;
        lookUpCxt.symMapHint    = specializedStruct;
        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        if (lookUpCxt.empty())
            return Result::Continue;

        SmallVector<const Symbol*> specializedMembers;
        specializedMembers.reserve(lookUpCxt.count());
        for (const Symbol* sym : lookUpCxt.symbols())
            specializedMembers.push_back(sym);

        return substituteQuotedGenericMemberCall(sema, parentRef, currentRef, tokNameRef, specializedMembers.span(), outHandled);
    }

    bool needsStructMemberRuntimeStorage(Sema& sema, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView)
    {
        if (sema.isGlobalScope())
            return false;
        if (!nodeLeftView.type())
            return false;
        if (nodeLeftView.type()->isReference())
            return false;
        if (!sema.isLValue(node.nodeLeftRef))
            return true;

        const SemaNodeView leftSymbolView = sema.viewSymbol(node.nodeLeftRef);
        if (!leftSymbolView.sym() || !leftSymbolView.sym()->isVariable())
            return false;

        const auto& leftSymVar = leftSymbolView.sym()->cast<SymbolVariable>();
        return leftSymVar.hasExtraFlag(SymbolVariableFlagsE::Parameter);
    }

    Result bindMatchedMemberSymbols(Sema& sema, AstNodeRef targetNodeRef, AstNodeRef rightNodeRef, bool allowOverloadSet, std::span<const Symbol*> matchedSymbols)
    {
        SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, targetNodeRef, allowOverloadSet, matchedSymbols));
        SWC_RESULT(SemaSymbolLookup::bindSymbolList(sema, rightNodeRef, allowOverloadSet, matchedSymbols));
        return Result::Continue;
    }

    Result reportUnknownMemberSymbol(Sema& sema, const AstMemberAccessExpr& node, IdentifierRef idRef, TokenRef tokNameRef)
    {
        const SourceCodeRef codeRef{node.srcViewRef(), tokNameRef};
        auto                diag = SemaError::report(sema, DiagnosticId::sema_err_unknown_symbol, codeRef);
        diag.addArgument(Diagnostic::ARG_SYM, idRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    bool isCompilerDefinedMemberAccess(Sema& sema, const AstMemberAccessExpr& node)
    {
        const auto* ident = sema.node(node.nodeRightRef).safeCast<AstIdentifier>();
        return ident && ident->hasFlag(AstIdentifierFlagsE::InCompilerDefined);
    }

    Result bindMissingCompilerDefinedMember(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, bool& outHandled)
    {
        outHandled = false;
        if (!isCompilerDefinedMemberAccess(sema, node))
            return Result::Continue;

        std::span<const Symbol*> empty;
        sema.setSymbolList(targetNodeRef, empty);
        sema.setSymbolList(node.nodeRightRef, empty);
        outHandled = true;
        return Result::Continue;
    }

    Result tryBindUfcsFreeFunctions(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, IdentifierRef idRef, TokenRef tokNameRef, bool allowOverloadSet, bool& outHandled)
    {
        outHandled = false;
        if (!allowOverloadSet)
            return Result::Continue;

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = SourceCodeRef{node.srcViewRef(), tokNameRef};
        lookUpCxt.noWaitOnEmpty = true;
        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));

        SmallVector<const Symbol*> callableSymbols;
        if (!SemaSymbolLookup::filterCallCalleeCandidates(lookUpCxt.symbols().span(), callableSymbols))
            return Result::Continue;

        SWC_RESULT(bindMatchedMemberSymbols(sema, targetNodeRef, node.nodeRightRef, true, callableSymbols.span()));
        outHandled = true;
        return Result::SkipChildren;
    }

    Result lookupScopedMember(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SymbolMap& symMap, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        MatchContext lookUpCxt;
        lookUpCxt.codeRef    = SourceCodeRef{node.srcViewRef(), tokNameRef};
        lookUpCxt.symMapHint = &symMap;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        SWC_RESULT(bindMatchedMemberSymbols(sema, targetNodeRef, node.nodeRightRef, allowOverloadSet, lookUpCxt.symbols().span()));
        return Result::SkipChildren;
    }

    Result memberNamespace(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolNamespace& namespaceSym = nodeLeftView.sym()->cast<SymbolNamespace>();
        return lookupScopedMember(sema, targetNodeRef, node, namespaceSym, idRef, tokNameRef, allowOverloadSet);
    }

    Result memberEnum(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolEnum&   enumSym = nodeLeftView.type()->payloadSymEnum();
        const SourceCodeRef codeRef{node.srcViewRef(), tokNameRef};
        SWC_RESULT(sema.waitSemaCompleted(&enumSym, codeRef));
        return lookupScopedMember(sema, targetNodeRef, node, enumSym, idRef, tokNameRef, allowOverloadSet);
    }

    Result memberInterface(Sema& sema, AstNodeRef targetNodeRef, const AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet)
    {
        const SymbolInterface& symInterface = nodeLeftView.type()->payloadSymInterface();
        const SourceCodeRef    codeRef{node.srcViewRef(), tokNameRef};
        SWC_RESULT(sema.waitSemaCompleted(&symInterface, codeRef));

        const SymbolMap& lookupMap = nodeLeftView.sym() && nodeLeftView.sym()->isImpl() ? *nodeLeftView.sym()->asSymMap() : static_cast<const SymbolMap&>(symInterface);
        return lookupScopedMember(sema, targetNodeRef, node, lookupMap, idRef, tokNameRef, allowOverloadSet);
    }

    Result memberStruct(Sema& sema, AstNodeRef targetNodeRef, AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, const IdentifierRef& idRef, TokenRef tokNameRef, bool allowOverloadSet, const TypeInfo& typeInfo)
    {
        const SymbolStruct& symStruct = typeInfo.payloadSymStruct();
        const SourceCodeRef codeRef{node.srcViewRef(), tokNameRef};
        SWC_RESULT(sema.waitSemaCompleted(&symStruct, codeRef));

        MatchContext lookUpCxt;
        lookUpCxt.codeRef       = codeRef;
        lookUpCxt.symMapHint    = &symStruct;
        lookUpCxt.noWaitOnEmpty = true;

        SWC_RESULT(Match::match(sema, lookUpCxt, idRef));
        if (lookUpCxt.empty())
        {
            bool handled = false;
            SWC_RESULT(bindMissingCompilerDefinedMember(sema, targetNodeRef, node, handled));
            if (handled)
                return Result::SkipChildren;
            SWC_RESULT(tryBindUfcsFreeFunctions(sema, targetNodeRef, node, idRef, tokNameRef, allowOverloadSet, handled));
            if (handled)
                return Result::SkipChildren;
            return reportUnknownMemberSymbol(sema, node, idRef, tokNameRef);
        }

        // Bind member-access node (curNodeRef) and RHS identifier.
        SWC_RESULT(bindMatchedMemberSymbols(sema, targetNodeRef, node.nodeRightRef, allowOverloadSet, lookUpCxt.symbols().span()));

        // Constant struct member access
        const SemaNodeView       nodeRightView = sema.viewSymbolList(node.nodeRightRef);
        const std::span<Symbol*> symbols       = nodeRightView.symList();
        const size_t             finalSymCount = symbols.size();
        if (nodeLeftView.cst() && finalSymCount == 1 && symbols[0]->isVariable())
        {
            const SymbolVariable& symVar = symbols[0]->cast<SymbolVariable>();
            SWC_RESULT(ConstantExtract::structMember(sema, *nodeLeftView.cst(), symVar, targetNodeRef, node.nodeRightRef));
            return Result::SkipChildren;
        }

        if (nodeLeftView.type()->isAnyPointer() || nodeLeftView.type()->isReference() || sema.isLValue(node.nodeLeftRef))
            sema.setIsLValue(node);

        if (finalSymCount == 1 && symbols[0]->isVariable() && needsStructMemberRuntimeStorage(sema, node, nodeLeftView))
        {
            auto& payload = SemaHelpers::ensureCodeGenNodePayload(sema, targetNodeRef);
            if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
            {
                payload.runtimeStorageSym = boundStorage;
            }
            else
            {
                auto& storageSym = SemaHelpers::registerUniqueRuntimeStorageSymbol(sema, node, "__member_runtime_storage");
                storageSym.registerAttributes(sema);
                storageSym.setDeclared(sema.ctx());
                SWC_RESULT(Match::ghosting(sema, storageSym));
                SmallVector<uint64_t> storageDims;
                storageDims.push_back(8);
                const TypeRef storageTypeRef = sema.typeMgr().addType(TypeInfo::makeArray(storageDims.span(), sema.typeMgr().typeU8()));
                SWC_RESULT(SemaHelpers::completeRuntimeStorageSymbol(sema, storageSym, storageTypeRef));
                payload.runtimeStorageSym = &storageSym;
            }
        }

        return Result::SkipChildren;
    }

    Result memberAggregateStruct(Sema& sema, AstNodeRef targetNodeRef, AstMemberAccessExpr& node, const SemaNodeView& nodeLeftView, IdentifierRef idRef, TokenRef tokNameRef, bool allowOverloadSet, const TypeInfo& typeInfo)
    {
        const auto& aggregate = typeInfo.payloadAggregate();
        const auto& types     = aggregate.types;
        SWC_ASSERT(aggregate.names.size() == types.size());

        size_t memberIndex = 0;
        if (!SemaHelpers::resolveAggregateMemberIndex(sema, typeInfo, idRef, memberIndex))
        {
            bool handled = false;
            SWC_RESULT(tryBindUfcsFreeFunctions(sema, targetNodeRef, node, idRef, tokNameRef, allowOverloadSet, handled));
            if (handled)
                return Result::SkipChildren;
            return reportUnknownMemberSymbol(sema, node, idRef, tokNameRef);
        }

        const TypeRef memberTypeRef = types[memberIndex];
        sema.setType(targetNodeRef, memberTypeRef);
        sema.setType(node.nodeRightRef, memberTypeRef);
        sema.setIsValue(node);
        sema.setIsValue(node.nodeRightRef);
        if (sema.isLValue(node.nodeLeftRef))
            sema.setIsLValue(node);

        if (nodeLeftView.cst() && nodeLeftView.cst()->isAggregateStruct())
        {
            const auto& values = nodeLeftView.cst()->getAggregateStruct();
            SWC_ASSERT(memberIndex < values.size());
            sema.setConstant(targetNodeRef, values[memberIndex]);
        }
        return Result::SkipChildren;
    }
}

bool SemaHelpers::resolveAggregateMemberIndex(Sema& sema, const TypeInfo& aggregateType, IdentifierRef idRef, size_t& outIndex)
{
    if (!aggregateType.isAggregateStruct())
        return false;

    const auto&            names  = aggregateType.payloadAggregate().names;
    const std::string_view idName = sema.idMgr().get(idRef).name;
    for (size_t i = 0; i < names.size(); ++i)
    {
        if (names[i].isValid() && names[i] == idRef)
        {
            outIndex = i;
            return true;
        }

        if (!names[i].isValid() && idName == ("item" + std::to_string(i)))
        {
            outIndex = i;
            return true;
        }
    }

    return false;
}

Result SemaHelpers::resolveMemberAccess(Sema& sema, AstNodeRef memberRef, AstMemberAccessExpr& node, bool allowOverloadSet)
{
    bool handled = false;
    SWC_RESULT(tryLiftQuotedGenericStructMemberAccess(sema, memberRef, node, handled));
    if (handled)
        return Result::SkipChildren;

    SemaNodeView        nodeLeftView  = sema.viewNodeTypeConstantSymbol(node.nodeLeftRef);
    const SemaNodeView  nodeRightView = sema.viewNode(node.nodeRightRef);
    const TokenRef      tokNameRef    = nodeRightView.node()->tokRef();
    const IdentifierRef idRef         = sema.idMgr().addIdentifier(sema.ctx(), nodeRightView.node()->codeRef());
    SWC_ASSERT(nodeRightView.node()->is(AstNodeId::Identifier));

    // Namespace
    if (nodeLeftView.sym() && nodeLeftView.sym()->isNamespace())
        return memberNamespace(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Auto-deduce generic arguments for bare generic root structs in expression context
    if (nodeLeftView.sym() && nodeLeftView.sym()->isStruct() && !nodeLeftView.type())
    {
        auto& st = nodeLeftView.sym()->cast<SymbolStruct>();
        if (st.isGenericRoot())
        {
            SymbolStruct* instance = nullptr;
            SWC_RESULT(SemaGeneric::instantiateStructFromContext(sema, st, instance));
            if (instance)
            {
                sema.setSymbol(node.nodeLeftRef, instance);
                nodeLeftView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
            }
        }
    }

    SWC_ASSERT(nodeLeftView.type());

    // Enum
    if (nodeLeftView.type()->isEnum())
        return memberEnum(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Interface
    if (nodeLeftView.type()->isInterface())
        return memberInterface(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet);

    // Aggregate struct
    if (nodeLeftView.type()->isAggregateStruct())
        return memberAggregateStruct(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet, *nodeLeftView.type());

    // Dereference pointer
    const TypeInfo* typeInfo = nodeLeftView.type();
    if (typeInfo->isTypeValue())
    {
        const TypeRef typeInfoRef = sema.typeMgr().typeTypeInfo();
        SWC_RESULT(Cast::cast(sema, nodeLeftView, typeInfoRef, CastKind::Explicit));

        // Resolve the derived TypeInfo struct that matches the underlying type,
        // so that type-specific fields (e.g. TypeInfoArray.count) are accessible.
        const TypeInfo& underlying = sema.typeMgr().get(typeInfo->payloadTypeRef());
        TypeRef         structRef  = sema.typeMgr().structTypeInfo();
        if (underlying.isArray() || underlying.isAggregateArray())
            structRef = sema.typeMgr().structTypeInfoArray();
        else if (underlying.isStruct() || underlying.isAggregateStruct())
            structRef = sema.typeMgr().structTypeInfoStruct();
        else if (underlying.isEnum())
            structRef = sema.typeMgr().structTypeInfoEnum();
        else if (underlying.isFunction())
            structRef = sema.typeMgr().structTypeInfoFunc();
        else if (underlying.isSlice())
            structRef = sema.typeMgr().structTypeInfoSlice();
        else if (underlying.isAnyPointer())
            structRef = sema.typeMgr().structTypeInfoPointer();
        else if (underlying.isAlias())
            structRef = sema.typeMgr().structTypeInfoAlias();
        else if (underlying.isAnyVariadic())
            structRef = sema.typeMgr().structTypeInfoVariadic();
        else if (underlying.isCodeBlock())
            structRef = sema.typeMgr().structTypeInfoCodeBlock();
        typeInfo = &sema.typeMgr().get(structRef);
    }
    else if (typeInfo->isTypeInfo())
    {
        TypeRef typeInfoRef = sema.typeMgr().structTypeInfo();
        if (!typeInfoRef.isValid())
            SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::TypeInfo, typeInfoRef, {node.srcViewRef(), tokNameRef}));
        SWC_ASSERT(typeInfoRef.isValid());
        typeInfo = &sema.typeMgr().get(typeInfoRef);
    }
    else if (typeInfo->isAnyPointer() || typeInfo->isReference())
    {
        typeInfo = &sema.typeMgr().get(typeInfo->payloadTypeRef());
    }

    // Aggregate struct through pointer/reference
    if (typeInfo->isAggregateStruct())
        return memberAggregateStruct(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet, *typeInfo);

    // Struct
    if (typeInfo->isStruct())
        return memberStruct(sema, memberRef, node, nodeLeftView, idRef, tokNameRef, allowOverloadSet, *typeInfo);

    // Pointer/Reference
    if (nodeLeftView.type()->isAnyPointer() || nodeLeftView.type()->isReference())
    {
        sema.setType(memberRef, nodeLeftView.type()->payloadTypeRef());
        sema.setIsValue(node);
        return Result::SkipChildren;
    }

    bool ufcsHandled = false;
    SWC_RESULT(bindMissingCompilerDefinedMember(sema, memberRef, node, ufcsHandled));
    if (ufcsHandled)
        return Result::SkipChildren;

    SWC_RESULT(tryBindUfcsFreeFunctions(sema, memberRef, node, idRef, tokNameRef, allowOverloadSet, ufcsHandled));
    if (ufcsHandled)
        return Result::SkipChildren;
    return reportUnknownMemberSymbol(sema, node, idRef, tokNameRef);
}

SWC_END_NAMESPACE();
