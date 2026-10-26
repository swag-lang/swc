#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CompilerInstance.h"
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

        const TypeInfo& resolvedStorageType = sema.typeMgr().unwrapAliasEnumTypeOrSelf(sema.ctx(), paramType.payloadTypeRef());
        if (SemaHelpers::isByValueAggregateType(resolvedStorageType) || (resolvedStorageType.isFunction() && resolvedStorageType.isLambdaClosure()))
            return resolvedStorageType.typeRef();

        return TypeRef::invalid();
    }
}

const Symbol* SemaHelpers::findPredefinedRuntimeSymbol(const Sema& sema, IdentifierManager::PredefinedName name)
{
    const IdentifierRef swagIdRef   = sema.idMgr().predefined(IdentifierManager::PredefinedName::Swag);
    const IdentifierRef targetIdRef = sema.idMgr().predefined(name);

    // Runtime files root their top-level symbols under the shared import-root namespace (see
    // topLevelCreationSymMap); without one they fall back to the module namespace.
    const SymbolMap* roots[] = {sema.compiler().importRootNamespace(), &sema.moduleNamespace()};

    for (const SymbolMap* root : roots)
    {
        if (!root)
            continue;

        // Homonyms already follow declaration order, so a named lookup preserves the
        // selection without collecting and sorting unrelated symbols in either scope.
        for (const Symbol* rootSym = root->findFirstSymbol(swagIdRef); rootSym; rootSym = rootSym->nextHomonym())
        {
            if (rootSym->isIgnored() || !rootSym->isNamespace())
                continue;

            if (const Symbol* candidate = rootSym->asSymMap()->findFirstSymbol(targetIdRef))
                return candidate;
        }
    }

    return nullptr;
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

    const TypeInfo& storageType = sema.typeMgr().unwrapAliasEnumTypeOrSelf(sema.ctx(), exprTypeRef);
    if (!storageType.isArray())
        return TypeRef::invalid();

    const uint64_t storageSize = storageType.sizeOf(sema.ctx());
    if (storageSize != 1 && storageSize != 2 && storageSize != 4 && storageSize != 8)
        return TypeRef::invalid();

    return storageType.typeRef();
}

TypeRef SemaHelpers::borrowedAggregateArgumentRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn, TypeRef paramTypeRef)
{
    if (sema.isGlobalScope() || !paramTypeRef.isValid())
        return TypeRef::invalid();

    const TypeInfo& storageType = sema.typeMgr().unwrapAliasEnumTypeOrSelf(sema.ctx(), paramTypeRef);
    const bool      isAggregate = isByValueAggregateType(storageType) || (storageType.isFunction() && storageType.isLambdaClosure());
    if (!isAggregate)
        return TypeRef::invalid();

    const CallConv&                        callConv       = CallConv::get(calledFn.callConvKind());
    const ABITypeNormalize::NormalizedType normalizedType = ABITypeNormalize::normalize(sema.ctx(), callConv, storageType, ABITypeNormalize::Usage::Argument);

    // Borrowed indirect aggregates need a home whose address the call passes. Aggregates the
    // ABI passes by value in a register still need one for the rvalue case: the literal
    // materializes into it and the call site loads the register image out of it.
    if (normalizedType.isIndirect && normalizedType.needsIndirectCopy)
        return TypeRef::invalid();

    return storageType.typeRef();
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
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(sema.ctx(), callConv, returnType, ABITypeNormalize::Usage::Return);
    if (!normalizedRet.isIndirect)
        return TypeRef::invalid();

    const TypeRef storageTypeRef = returnType.unwrap(sema.ctx(), returnTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    if (storageTypeRef.isValid())
        return storageTypeRef;

    return returnTypeRef;
}

Result SemaHelpers::attachRuntimeStorageIfNeeded(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, TypeRef storageTypeRef, std::string_view privateName, bool allowBoundStorageTypeMismatch)
{
    if (storageTypeRef.isInvalid())
        return Result::Continue;

    auto& storageSym = getOrCreateRuntimeStorageSymbol(sema, payloadNodeRef, storageNode, storageTypeRef, privateName, allowBoundStorageTypeMismatch);
    SWC_RESULT(ensureRuntimeStorageDeclaredAndCompleted(sema, storageSym, storageTypeRef));

    return Result::Continue;
}

Result SemaHelpers::attachRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, TypeRef storageTypeRef, std::string_view privateName, bool allowBoundStorageTypeMismatch)
{
    return attachRuntimeStorageIfNeeded(sema, sema.curNodeRef(), node, storageTypeRef, privateName, allowBoundStorageTypeMismatch);
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
    SWC_RESULT(requireRuntimeCatchErrDependency(sema, codeRef));

    // Hidden error owners have ordinary drops. Failure unwinding parks the
    // active error during cleanup, even when catch has no explicit defer.
    return requireRuntimePopErrDependency(sema, codeRef);
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

Result SemaHelpers::attachRuntimeSliceCmpFunctionToNode(Sema& sema, AstNodeRef nodeRef, const SourceCodeRef& codeRef)
{
    return attachRuntimeFunctionToNode(sema, nodeRef, IdentifierManager::RuntimeFunctionKind::SliceCmp, codeRef);
}

Result SemaHelpers::setupRuntimeSafetyPanic(Sema& sema, AstNodeRef nodeRef, Runtime::SafetyWhat safetyKind, const SourceCodeRef& codeRef)
{
    if (!sema.frame().currentAttributes().hasRuntimeSafety(sema.runtimeSafetyGuards(), safetyKind))
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

bool SemaHelpers::ownsExpressionValue(Sema& sema, AstNodeRef nodeRef)
{
    nodeRef = sema.resolvedNodeRef(nodeRef);
    while (nodeRef.isValid())
    {
        const auto* lowering = sema.loweringPayload<CodeGenLoweringPayload>(nodeRef);
        if (lowering && lowering->ownsValue)
            return true;

        const AstNode& node = sema.node(nodeRef);
        AstNodeRef     childRef;
        if (node.is(AstNodeId::CastExpr))
            childRef = node.cast<AstCastExpr>().nodeExprRef;
        else if (node.is(AstNodeId::ParenExpr))
            childRef = node.cast<AstParenExpr>().nodeExprRef;
        else if (node.is(AstNodeId::InitializerExpr))
            childRef = node.cast<AstInitializerExpr>().nodeExprRef;
        else if (node.is(AstNodeId::NamedArgument))
            childRef = node.cast<AstNamedArgument>().nodeArgRef;
        else
            return false;

        nodeRef = node.is(AstNodeId::CastExpr) ? childRef : sema.resolvedNodeRef(childRef);
    }

    return false;
}

bool SemaHelpers::expressionBorrowsStorage(Sema& sema, AstNodeRef nodeRef)
{
    nodeRef                   = sema.resolvedNodeRef(nodeRef);
    const auto* inlinePayload = sema.inlinePayload(nodeRef);
    if (inlinePayload && inlinePayload->inlineRootRef == nodeRef && inlinePayload->returnTypeRef.isValid())
        return sema.typeMgr().get(inlinePayload->returnTypeRef).isReference();

    if (ownsExpressionValue(sema, nodeRef))
        return false;

    const AstNode& node = sema.node(nodeRef);
    if (node.is(AstNodeId::CallExpr))
        return sema.viewType(nodeRef).type()->isReference();
    if (node.is(AstNodeId::ParenExpr))
        return expressionBorrowsStorage(sema, node.cast<AstParenExpr>().nodeExprRef);
    if (node.is(AstNodeId::InitializerExpr))
        return expressionBorrowsStorage(sema, node.cast<AstInitializerExpr>().nodeExprRef);
    if (node.is(AstNodeId::NamedArgument))
        return expressionBorrowsStorage(sema, node.cast<AstNamedArgument>().nodeArgRef);

    return sema.isLValueStored(nodeRef) || node.is(AstNodeId::ConditionalExpr) || node.is(AstNodeId::NullCoalescingExpr);
}

Result SemaHelpers::materializeMovedValue(Sema& sema, SemaNodeView& view)
{
    if (!view.type() || !view.type()->isMoveReference())
        return Result::Continue;

    AstNodeRef sourceRef = view.nodeRef();
    while (sema.node(sourceRef).is(AstNodeId::ParenExpr))
        sourceRef = sema.node(sourceRef).cast<AstParenExpr>().nodeExprRef;
    if (sema.node(sourceRef).isNot(AstNodeId::UnaryExpr) || sema.token(sema.node(sourceRef).codeRef()).id != TokenId::ModifierMove)
        return SemaCheck::noMoveRefType(sema, view.typeRef(), sema.node(sourceRef).codeRef());

    const TypeRef valueTypeRef = view.type()->payloadTypeRef();
    if (view.type()->isConst())
        return SemaError::raiseCannotCast(sema, view.nodeRef(), view.typeRef(), valueTypeRef);

    SWC_RESULT(SemaCheck::checkMoveSourceCanReset(sema, view.nodeRef(), valueTypeRef, AstModifierFlagsE::Move));

    const AstNodeRef castRef  = Cast::createCast(sema, valueTypeRef, view.nodeRef());
    auto&            lowering = ensureCodeGenLoweringPayload(sema, castRef);
    lowering.moveValue        = true;
    lowering.ownsValue        = true;

    auto& storage              = registerUniqueRuntimeStorageSymbol(sema, sema.node(castRef), "__moved_value");
    lowering.runtimeStorageSym = &storage;
    SWC_RESULT(ensureRuntimeStorageDeclaredAndCompleted(sema, storage, valueTypeRef));

    view.recompute(sema);

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

    return attachRuntimeStorageIfNeeded(sema, node, literalView.typeRef(), "__literal_runtime_storage", true);
}

SymbolVariable& SemaHelpers::getOrCreateRuntimeStorageSymbol(Sema& sema, AstNodeRef payloadNodeRef, const AstNode& storageNode, TypeRef storageTypeRef, std::string_view privateName, bool allowBoundStorageTypeMismatch)
{
    auto& payload = ensureCodeGenLoweringPayload(sema, payloadNodeRef);
    if (payload.runtimeStorageSym != nullptr)
        return *payload.runtimeStorageSym;

    SymbolVariable* boundStorage = currentRuntimeStorage(sema);
    // A retyped literal can share its destination; a conversion result needs storage of its own.
    if (boundStorage &&
        (allowBoundStorageTypeMismatch ||
         (boundStorage->typeRef().isValid() &&
          sema.typeMgr().unwrapAlias(sema.ctx(), boundStorage->typeRef()) == sema.typeMgr().unwrapAlias(sema.ctx(), storageTypeRef))))
    {
        payload.runtimeStorageSym = boundStorage;
        return *boundStorage;
    }

    if (payload.registeredRuntimeStorageSym && payload.registeredRuntimeStorageSym->typeRef() == storageTypeRef)
    {
        payload.runtimeStorageSym = payload.registeredRuntimeStorageSym;
        return *payload.runtimeStorageSym;
    }

    auto& sym                           = registerUniqueRuntimeStorageSymbol(sema, storageNode, privateName);
    payload.runtimeStorageSym           = &sym;
    payload.registeredRuntimeStorageSym = &sym;

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
    // Caller-bound storage is finalized by the surrounding context. Declaring
    // it again would register it twice.
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

// Late fields and globals begin as null storage and receive their values later.
bool SemaHelpers::isLateInitAccess(Sema& sema, AstNodeRef nodeRef)
{
    if (nodeRef.isInvalid())
        return false;

    const AstNode* node = sema.viewNode(nodeRef).node();
    if (!node)
        return false;

    AstNodeRef slotRef = nodeRef;
    if (node->is(AstNodeId::MemberAccessExpr))
        slotRef = node->cast<AstMemberAccessExpr>().nodeRightRef;
    else if (node->isNot(AstNodeId::Identifier))
        return false;

    const Symbol* sym = sema.viewSymbol(slotRef).sym();
    return sym && sym->isVariable() && sym->cast<SymbolVariable>().hasExtraFlag(SymbolVariableFlagsE::LateInit);
}

namespace
{
    CodeGenLoweringPayload* lateReadGuardPayload(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return nullptr;

        const SemaNodeView view = sema.viewNode(nodeRef);
        if (!view.node() || (view.node()->isNot(AstNodeId::MemberAccessExpr) && view.node()->isNot(AstNodeId::Identifier)))
            return nullptr;

        return sema.loweringPayload<CodeGenLoweringPayload>(view.nodeRef());
    }
}

// True while the read at 'nodeRef' still carries the runtime guard of a late field or global.
bool SemaHelpers::hasLateReadGuard(Sema& sema, AstNodeRef nodeRef)
{
    const CodeGenLoweringPayload* payload = lateReadGuardPayload(sema, nodeRef);
    return payload && payload->hasRuntimeSafety(Runtime::SafetyWhat::Null);
}

// Non-reading consumers (assignment targets, address-of, null comparisons)
// cancel the read guard on late fields and globals.
void SemaHelpers::clearLateFieldReadGuard(Sema& sema, AstNodeRef nodeRef)
{
    if (auto* payload = lateReadGuardPayload(sema, nodeRef))
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

    const AstNodeRef resolvedTargetRef  = sema.resolvedNodeRef(nodeRef);
    const AstNodeRef resolvedCurrentRef = sema.resolvedNodeRef(sema.curNodeRef());
    if (resolvedTargetRef != resolvedCurrentRef)
        return nullptr;

    return sym;
}

void SemaHelpers::addCurrentFunctionCallDependency(Sema& sema, const SymbolFunction* calleeSym)
{
    SWC_ASSERT(calleeSym);

    SymbolFunction* owner = sema.currentFunction();
    if (!owner || sema.knowsCallDependency(*owner, *calleeSym))
        return;

    owner->addCallDependency(calleeSym);

    // Only an edge the function now holds is remembered: its dependency set never shrinks.
    if (calleeSym != owner && !calleeSym->isForeignOrEmptyOrAttribute() && !calleeSym->attributes().hasMacroOrMixin())
        sema.noteCallDependency(*owner, *calleeSym);
}

namespace
{
    bool isDeclaredByInlineSource(Sema& sema, SemaInlinePayload& payload, const SymbolVariable& symVar)
    {
        const SymbolFunction* source = payload.sourceFunction;
        if (!source || !source->decl() || source->srcViewRef() != symVar.srcViewRef())
            return false;
        if (sema.ast().srcView().ref() != source->srcViewRef())
            return false;
        if (!payload.sourceEndRef.isValid())
            payload.sourceEndRef = source->decl()->tokRefEnd(sema.ast());

        const uint32_t tok = symVar.tokRef().get();
        return tok >= source->decl()->tokRef().get() && tok <= payload.sourceEndRef.get();
    }
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

        // The original callee declaration owns unused-local checks. Caller
        // aliases and caller-supplied code still belong to the call site.
        symVar.setInlineExpansion();
        for (const SemaInlinePayload* payload = inlinePayload; payload; payload = payload->parentInlinePayload)
        {
            const auto it = std::ranges::find(payload->aliasIdentifiers, symVar.idRef());
            if (it == payload->aliasIdentifiers.end())
                continue;

            const auto slot = static_cast<size_t>(it - payload->aliasIdentifiers.begin());
            if (payload->aliasNameRefs[slot].isValid())
            {
                symVar.setCallerNameRef(payload->aliasNameRefs[slot]);
                return Result::Continue;
            }

            break;
        }

        for (SemaInlinePayload* payload = inlinePayload; payload; payload = payload->parentInlinePayload)
        {
            if (isDeclaredByInlineSource(sema, *payload, symVar))
            {
                symVar.markReferenced();
                break;
            }
        }
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

    // A newly declared local was just appended by registerSymbol.
    if (!scope->symbols().empty() && scope->symbols().back() == sym)
        return;

    if (scope->mayHaveSymbolNamed(sym->idRef()))
    {
        for (const Symbol* existing : scope->symbols())
        {
            if (existing == sym)
                return;
        }
    }

    scope->addSymbol(sym);
    sema.compiler().notifyAlive();
}

void SemaHelpers::ensureCurrentLocalScopeSymbols(Sema& sema, std::span<Symbol* const> symbols)
{
    if (!sema.curScope().isLocal() || symbols.empty())
        return;

    // Multiple declarations append their symbols together, in this same order.
    if (const SemaScope* scope = currentLocalSymbolScope(sema))
    {
        const auto scopeSymbols = scope->symbols().span();
        if (scopeSymbols.size() >= symbols.size() && std::ranges::equal(scopeSymbols.last(symbols.size()), symbols))
            return;
    }

    for (Symbol* sym : symbols)
        ensureCurrentLocalScopeSymbol(sema, sym);
}

bool SemaHelpers::needsPersistentCompilerRunReturn(const TaskContext& ctx, TypeRef typeRef)
{
    if (!typeRef.isValid())
        return false;

    const TypeInfo& typeInfo = ctx.typeMgr().unwrapAliasEnumTypeOrSelf(ctx, typeRef);

    if (typeInfo.isAnyString() || typeInfo.isSlice() || typeInfo.isAny() || typeInfo.isInterface())
        return true;

    if (typeInfo.isAggregate())
        return true;

    // Simd constants borrow a byte payload, so the raw return bytes must be
    // re-anchored in persistent constant storage.
    if (typeInfo.isSimd())
        return true;

    if (typeInfo.isArray())
        return needsPersistentCompilerRunReturn(ctx, typeInfo.payloadArrayElemTypeRef());

    if (typeInfo.isStruct())
    {
        for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
        {
            if (field && needsPersistentCompilerRunReturn(ctx, field->typeRef()))
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
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(ctx, callConv, ctx.typeMgr().get(returnTypeRef), ABITypeNormalize::Usage::Return);
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

// Lifecycle copies run opPostCopy to give the caller independent ownership.
// Eliding them can share allocations with source fields and double-free at drop.
// Keep the copy whenever the type has lifecycle hooks.
bool SemaHelpers::typeHasLifecycle(TaskContext& ctx, TypeRef typeRef)
{
    if (!typeRef.isValid())
        return false;

    // Generated lifecycle wrappers may still be completing, making effective
    // operator lookups depend on scheduling. TypeGen flags use directly
    // registered operators and field walks for a stable answer.
    const TypeGen::LifecycleFlags flags = TypeGen::lifecycleFlagsOfTypeRef(ctx, typeRef);
    return flags.hasDrop || flags.hasPostCopy || flags.hasPostMove;
}

// The inline expansion whose result storage a retval local names, or null when it names
// the function's own return slot. A '#[Swag.CalleeReturn]' body returns through its caller.
const SemaInlinePayload* SemaHelpers::retValStorageOwner(const Sema& sema, const SymbolVariable& symVar)
{
    if (!symVar.decl())
        return nullptr;

    const AstNodeRef declRef = sema.ast().tryFindNodeRef(symVar.decl());
    if (declRef.isInvalid())
        return nullptr;

    const SemaInlinePayload* expansion = sema.inlinePayload(declRef);
    return expansion && !expansion->returnsToCallerSite() ? expansion : nullptr;
}

// A named retval local exposes the storage of its return context (the caller's slot, or
// an inline expansion's result) to expressions. Building a value directly there could
// overwrite data it still needs to read, so that destination is disabled once exposed.
// Compiler runtime storages share the RetVal flag but have no readable name.
bool SemaHelpers::returnStorageExposed(const Sema& sema, const SymbolFunction& function, const SemaInlinePayload* returnContext, const SymbolVariable* ignoreSym)
{
    for (const SymbolVariable* local : function.localVariables())
    {
        if (!local || local == ignoreSym)
            continue;
        if (!local->hasExtraFlag(SymbolVariableFlagsE::RetVal) || local->hasExtraFlag(SymbolVariableFlagsE::RuntimeStorage))
            continue;
        if (retValStorageOwner(sema, *local) == returnContext)
            return true;
    }

    return false;
}

SWC_END_NAMESPACE();
