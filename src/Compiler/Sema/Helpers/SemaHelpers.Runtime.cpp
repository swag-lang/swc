#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef referenceBoundAggregateArgumentRuntimeStorageTypeRef(Sema& sema, TypeRef paramTypeRef, AstNodeRef argRef)
    {
        if (sema.isGlobalScope() || argRef.isInvalid() || !paramTypeRef.isValid())
            return TypeRef::invalid();
        if (sema.isLValue(argRef) && !sema.viewConstant(argRef).hasConstant())
            return TypeRef::invalid();

        const TypeInfo& paramType = sema.typeMgr().get(paramTypeRef);
        if (!paramType.isReference())
            return TypeRef::invalid();

        TypeRef         storageTypeRef          = paramType.payloadTypeRef();
        const TypeInfo& storageType             = sema.typeMgr().get(storageTypeRef);
        const TypeRef   unwrappedStorageTypeRef = storageType.unwrap(sema.ctx(), storageTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (unwrappedStorageTypeRef.isValid())
            storageTypeRef = unwrappedStorageTypeRef;

        const TypeInfo& resolvedStorageType = sema.typeMgr().get(storageTypeRef);
        if (resolvedStorageType.isStruct() || resolvedStorageType.isArray() || resolvedStorageType.isAggregate() || (resolvedStorageType.isFunction() && resolvedStorageType.isLambdaClosure()))
            return storageTypeRef;

        return TypeRef::invalid();
    }
}

Result SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, const SymbolFunction& calledFn, std::string_view privateName)
{
    if (const TypeRef returnTypeRef = calledFn.returnTypeRef(); returnTypeRef.isValid())
    {
        const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
        SWC_RESULT(sema.waitSemaCompleted(&returnType, payloadNodeRef));
    }

    return attachRuntimeStorageIfNeeded(sema, payloadNodeRef, storageNode, indirectReturnRuntimeStorageTypeRef(sema, calledFn), privateName);
}

Result SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SymbolFunction& calledFn, std::string_view privateName)
{
    return attachIndirectReturnRuntimeStorageIfNeeded(sema, sema.curNodeRef(), node, calledFn, privateName);
}

TypeRef SemaHelpers::smallByValueArrayRuntimeStorageTypeRef(Sema& sema, AstNodeRef exprRef, TypeRef exprTypeRef, ConstantRef exprCstRef)
{
    if (!exprTypeRef.isValid())
        return TypeRef::invalid();
    if (exprCstRef.isValid())
        return TypeRef::invalid();
    if (sema.isLValue(exprRef))
        return TypeRef::invalid();

    const TypeRef   storageTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), exprTypeRef);
    const TypeInfo& storageType    = sema.typeMgr().get(storageTypeRef);
    if (!storageType.isArray())
        return TypeRef::invalid();

    const uint64_t storageSize = storageType.sizeOf(sema.ctx());
    if (storageSize != 1 && storageSize != 2 && storageSize != 4 && storageSize != 8)
        return TypeRef::invalid();

    return storageTypeRef;
}

TypeRef SemaHelpers::borrowedAggregateArgumentRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn, TypeRef paramTypeRef)
{
    if (sema.isGlobalScope() || !paramTypeRef.isValid())
        return TypeRef::invalid();

    const TypeInfo& paramType      = sema.typeMgr().get(paramTypeRef);
    TypeRef         storageTypeRef = paramType.unwrap(sema.ctx(), paramTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    if (storageTypeRef.isInvalid())
        storageTypeRef = paramTypeRef;

    const TypeInfo& storageType = sema.typeMgr().get(storageTypeRef);
    const bool      isAggregate = storageType.isStruct() || storageType.isArray() || storageType.isAggregate() || (storageType.isFunction() && storageType.isLambdaClosure());
    if (!isAggregate)
        return TypeRef::invalid();

    const CallConv&                        callConv       = CallConv::get(calledFn.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedType = ABITypeNormalize::normalize(sema.ctx(), callConv, paramTypeRef, ABITypeNormalize::Usage::Argument);
    if (normalizedType.isIndirect && !normalizedType.needsIndirectCopy)
        return storageTypeRef;

    return TypeRef::invalid();
}

Result SemaHelpers::attachBorrowedAggregateArgumentRuntimeStorageIfNeeded(Sema& sema, const SymbolFunction& calledFn, TypeRef paramTypeRef, AstNodeRef argRef)
{
    if (argRef.isInvalid())
        return Result::Continue;

    if (paramTypeRef.isValid())
    {
        const TypeInfo& paramType = sema.typeMgr().get(paramTypeRef);
        SWC_RESULT(sema.waitSemaCompleted(&paramType, argRef));
    }

    const TypeRef storageTypeRef = borrowedAggregateArgumentRuntimeStorageTypeRef(sema, calledFn, paramTypeRef);
    if (storageTypeRef.isValid())
        return attachRuntimeStorageIfNeeded(sema, argRef, sema.node(argRef), storageTypeRef, "__call_arg_ref_storage");

    const TypeRef referenceStorageTypeRef = referenceBoundAggregateArgumentRuntimeStorageTypeRef(sema, paramTypeRef, argRef);
    return attachRuntimeStorageIfNeeded(sema, argRef, sema.node(argRef), referenceStorageTypeRef, "__call_arg_ref_storage");
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

Result SemaHelpers::requireRuntimeSafetyPanicDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef)
{
    return requireRuntimeFunctionDependency(outRuntimeFn, sema, IdentifierManager::RuntimeFunctionKind::SafetyPanic, codeRef);
}

Result SemaHelpers::requireRuntimeSafetyPanicDependency(Sema& sema, const SourceCodeRef& codeRef)
{
    SymbolFunction* runtimeFn = nullptr;
    return requireRuntimeSafetyPanicDependency(runtimeFn, sema, codeRef);
}

Result SemaHelpers::requireRuntimeAsDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef)
{
    return requireRuntimeFunctionDependency(outRuntimeFn, sema, IdentifierManager::RuntimeFunctionKind::As, codeRef);
}

Result SemaHelpers::requireRuntimeAsDependency(Sema& sema, const SourceCodeRef& codeRef)
{
    SymbolFunction* runtimeFn = nullptr;
    return requireRuntimeAsDependency(runtimeFn, sema, codeRef);
}

Result SemaHelpers::requireRuntimeIsDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef)
{
    return requireRuntimeFunctionDependency(outRuntimeFn, sema, IdentifierManager::RuntimeFunctionKind::Is, codeRef);
}

Result SemaHelpers::requireRuntimeIsDependency(Sema& sema, const SourceCodeRef& codeRef)
{
    SymbolFunction* runtimeFn = nullptr;
    return requireRuntimeIsDependency(runtimeFn, sema, codeRef);
}

Result SemaHelpers::requireRuntimeErrorContextDependency(Sema& sema, const SourceCodeRef& codeRef)
{
    return requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::IsErrContext, codeRef);
}

Result SemaHelpers::requireRuntimePushErrDependency(Sema& sema, const SourceCodeRef& codeRef)
{
    return requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::PushErr, codeRef);
}

Result SemaHelpers::requireRuntimePopErrDependency(Sema& sema, const SourceCodeRef& codeRef)
{
    return requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::PopErr, codeRef);
}

Result SemaHelpers::requireRuntimeCatchErrDependency(Sema& sema, const SourceCodeRef& codeRef)
{
    return requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::CatchErr, codeRef);
}

Result SemaHelpers::requireRuntimeCatchScopeDependencies(Sema& sema, const SourceCodeRef& codeRef)
{
    SWC_RESULT(requireRuntimePushErrDependency(sema, codeRef));
    return requireRuntimeCatchErrDependency(sema, codeRef);
}

Result SemaHelpers::requireRuntimePopScopeDependencies(Sema& sema, const SourceCodeRef& codeRef)
{
    SWC_RESULT(requireRuntimePushErrDependency(sema, codeRef));
    return requireRuntimePopErrDependency(sema, codeRef);
}

Result SemaHelpers::requireRuntimeStringCmpDependency(SymbolFunction*& outRuntimeFn, Sema& sema, const SourceCodeRef& codeRef)
{
    return requireRuntimeFunctionDependency(outRuntimeFn, sema, IdentifierManager::RuntimeFunctionKind::StringCmp, codeRef);
}

Result SemaHelpers::requireRuntimeStringCmpDependency(Sema& sema, const SourceCodeRef& codeRef)
{
    SymbolFunction* runtimeFn = nullptr;
    return requireRuntimeStringCmpDependency(runtimeFn, sema, codeRef);
}

Result SemaHelpers::attachRuntimeFunctionToNode(Sema& sema, AstNodeRef nodeRef, IdentifierManager::RuntimeFunctionKind kind, const SourceCodeRef& codeRef)
{
    SymbolFunction* runtimeFn = nullptr;
    SWC_RESULT(requireRuntimeFunctionDependency(runtimeFn, sema, kind, codeRef));
    ensureCodeGenLoweringPayload(sema, nodeRef).runtimeFunctionSymbol = runtimeFn;
    return Result::Continue;
}

Result SemaHelpers::attachRuntimeAsFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef)
{
    return attachRuntimeFunctionToNode(sema, nodeRef, IdentifierManager::RuntimeFunctionKind::As, codeRef);
}

Result SemaHelpers::attachRuntimeIsFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef)
{
    return attachRuntimeFunctionToNode(sema, nodeRef, IdentifierManager::RuntimeFunctionKind::Is, codeRef);
}

Result SemaHelpers::attachRuntimeStringCmpFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef)
{
    return attachRuntimeFunctionToNode(sema, nodeRef, IdentifierManager::RuntimeFunctionKind::StringCmp, codeRef);
}

Result SemaHelpers::setupRuntimeSafetyPanic(Sema& sema, AstNodeRef nodeRef, Runtime::SafetyWhat safetyKind, const SourceCodeRef& codeRef)
{
    if (!sema.frame().currentAttributes().hasRuntimeSafety(sema.buildCfg().safetyGuards, safetyKind))
        return Result::Continue;

    if (!sema.isCurrentFunction())
        return Result::Continue;

    SymbolFunction* panicFn = nullptr;
    SWC_RESULT(requireRuntimeSafetyPanicDependency(panicFn, sema, codeRef));

    auto& payload = ensureCodeGenLoweringPayload(sema, nodeRef);
    payload.addRuntimeSafety(safetyKind);
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
    auto& payload = ensureCodeGenLoweringPayload(sema, payloadNodeRef);
    if (payload.runtimeStorageSym != nullptr)
        return *payload.runtimeStorageSym;

    if (SymbolVariable* boundStorage = currentRuntimeStorage(sema))
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
    symVariable->addExtraFlag(SymbolVariableFlagsE::RuntimeStorage);

    if (currentLocalSymbolScope(sema))
    {
        addCurrentScopeSymbol(sema, symVariable);
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

    ensureCurrentLocalScopeSymbol(sema, &storageSym);

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
    ensureCurrentLocalScopeSymbol(sema, &symVar);
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

// A '#late' field access requests a null-safety read guard when it resolves
// (memberStruct). Consumers that never read the field value — pure assignment
// target, address-of, '@isset' — call this to cancel the guard.
void SemaHelpers::clearLateFieldReadGuard(Sema& sema, AstNodeRef nodeRef)
{
    if (nodeRef.isInvalid())
        return;
    const SemaNodeView view = sema.viewNode(nodeRef);
    // A '#late' read guard sits on a field member access or on a bare identifier (a
    // '#late' global). Both are cleared by a non-reading consumer (assignment target,
    // address-of, '@isset').
    if (!view.node() || (view.node()->isNot(AstNodeId::MemberAccessExpr) && view.node()->isNot(AstNodeId::Identifier)))
        return;
    if (auto* payload = sema.loweringPayload<CodeGenLoweringPayload>(view.nodeRef()))
        payload->removeRuntimeSafety(Runtime::SafetyWhat::Null);
}

CodeGenLoweringPayload& SemaHelpers::ensureCodeGenLoweringPayload(Sema& sema, AstNodeRef nodeRef)
{
    auto* payload = sema.loweringPayload<CodeGenLoweringPayload>(nodeRef);
    if (payload)
        return *payload;

    payload  = sema.compiler().allocate<CodeGenLoweringPayload>();
    *payload = {};
    sema.setLoweringPayload(nodeRef, payload);
    return *payload;
}

SymbolVariable* SemaHelpers::currentRuntimeStorage(Sema& sema)
{
    SymbolVariable*  sym     = sema.frame().currentRuntimeStorageSym();
    const AstNodeRef nodeRef = sema.frame().currentRuntimeStorageNodeRef();
    if (!sym || !nodeRef.isValid())
        return nullptr;

    const AstNodeRef resolvedTargetRef  = sema.viewZero(nodeRef).nodeRef();
    const AstNodeRef resolvedCurrentRef = sema.viewZero(sema.curNodeRef()).nodeRef();
    if (resolvedTargetRef != resolvedCurrentRef)
        return nullptr;

    return sym;
}

void SemaHelpers::addCurrentFunctionCallDependency(Sema& sema, const SymbolFunction* calleeSym)
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
    sema.setVariableScopeDepth(symVar, sema.currentScopeDepth());

    if (auto* inlinePayload = const_cast<SemaInlinePayload*>(effectiveInlinePayload(sema)))
    {
        if (std::ranges::find(inlinePayload->localVariables, &symVar) == inlinePayload->localVariables.end())
            inlinePayload->localVariables.push_back(&symVar);
    }

    return Result::Continue;
}

Result SemaHelpers::addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar)
{
    return addCurrentFunctionLocalVariable(sema, symVar, symVar.typeRef());
}

void SemaHelpers::ensureCurrentLocalScopeSymbol(Sema& sema, Symbol* sym)
{
    SemaScope* scope = currentLocalSymbolScope(sema);
    if (!sym || !scope)
        return;

    for (const Symbol* existing : scope->symbols())
    {
        if (existing == sym)
            return;
    }

    scope->addSymbol(sym);
    sema.compiler().notifyAlive();
}

void SemaHelpers::ensureCurrentLocalScopeSymbols(Sema& sema, std::span<Symbol* const> symbols)
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

    if (typeInfo.isAggregateStruct() || typeInfo.isAggregateArray())
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

Result SemaHelpers::currentFunctionUsesIndirectReturnStorage(bool& outUsesIndirectReturnStorage, Sema& sema)
{
    outUsesIndirectReturnStorage = false;

    const SymbolFunction* currentFn = sema.currentFunction();
    if (!currentFn)
        return Result::Continue;

    if (const TypeRef returnTypeRef = currentFn->returnTypeRef(); returnTypeRef.isValid())
    {
        const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
        SWC_RESULT(sema.waitSemaCompleted(&returnType, sema.curNodeRef()));
    }

    outUsesIndirectReturnStorage = functionUsesIndirectReturnStorage(sema.ctx(), *currentFn);
    return Result::Continue;
}

bool SemaHelpers::usesCallerReturnStorage(TaskContext& ctx, const SymbolFunction& function, const SymbolVariable& symVar)
{
    return symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) &&
           functionUsesIndirectReturnStorage(ctx, function);
}

SWC_END_NAMESPACE();
