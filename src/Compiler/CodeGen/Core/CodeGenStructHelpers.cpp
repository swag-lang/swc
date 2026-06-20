#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenStructHelpers.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool ownerStructReachableThroughUsing(CodeGen& codeGen, const SymbolStruct& leftStruct, const SymbolStruct& ownerStruct)
    {
        SmallVector<SymbolStructUsingPathStep> ignoredSteps;
        return leftStruct.resolveUsingFieldPath(codeGen.ctx(), ownerStruct, ignoredSteps);
    }
}

const SymbolStruct* CodeGenStructHelpers::variableOwnerStruct(const SymbolVariable& symVar)
{
    const SymbolMap* owner = symVar.ownerSymMap();
    if (!owner)
        return nullptr;

    if (owner->isStruct())
        return &owner->cast<SymbolStruct>();

    if (owner->isImpl())
    {
        const auto& ownerImpl = owner->cast<SymbolImpl>();
        if (ownerImpl.isForStruct())
            return ownerImpl.symStruct();
    }

    return nullptr;
}

const SymbolStruct* CodeGenStructHelpers::resolveRuntimeStructType(CodeGen& codeGen, TypeRef typeRef)
{
    if (!typeRef.isValid())
        return nullptr;

    typeRef = codeGen.typeMgr().get(typeRef).unwrapAliasEnum(codeGen.ctx(), typeRef);
    if (typeRef.isInvalid())
        return nullptr;

    const TypeInfo* typeInfo = &codeGen.typeMgr().get(typeRef);
    if (typeInfo->isPointerOrReference())
    {
        typeRef  = codeGen.typeMgr().get(typeInfo->payloadTypeRef()).unwrapAliasEnum(codeGen.ctx(), typeInfo->payloadTypeRef());
        typeInfo = &codeGen.typeMgr().get(typeRef);
    }

    if (!typeInfo->isStruct())
        return nullptr;

    return &typeInfo->payloadSymStruct();
}

const SymbolStruct* CodeGenStructHelpers::resolveReceiverRuntimeStruct(CodeGen& codeGen)
{
    const auto& params = codeGen.function().parameters();
    if (params.empty() || !params.front())
        return codeGen.function().ownerStruct();

    const SymbolVariable* receiver = params.front();
    if (receiver->idRef() != codeGen.sema().idMgr().predefined(IdentifierManager::PredefinedName::Me))
        return codeGen.function().ownerStruct();

    if (const SymbolStruct* receiverStruct = resolveRuntimeStructType(codeGen, receiver->typeRef()))
        return receiverStruct;

    return codeGen.function().ownerStruct();
}

TypeRef CodeGenStructHelpers::resolveRuntimeLeftTypeRef(CodeGen& codeGen, AstNodeRef leftRef, TypeRef leftTypeRef)
{
    if (!leftRef.isValid())
        return leftTypeRef;

    if (!codeGen.node(leftRef).is(AstNodeId::Identifier))
        return leftTypeRef;

    const SemaNodeView leftSymView = codeGen.viewSymbol(leftRef);
    const auto* const  symVar      = leftSymView.sym() ? leftSymView.sym()->safeCast<SymbolVariable>() : nullptr;
    if (!symVar)
        return leftTypeRef;
    if (symVar->idRef() != codeGen.sema().idMgr().predefined(IdentifierManager::PredefinedName::Me))
        return leftTypeRef;

    const SymbolStruct* receiverStruct = resolveReceiverRuntimeStruct(codeGen);
    if (!receiverStruct)
        return leftTypeRef;

    return receiverStruct->typeRef();
}

const SymbolVariable* CodeGenStructHelpers::tryResolveConcreteStructMemberSymbol(CodeGen& codeGen, TypeRef leftTypeRef, const SymbolVariable& memberSym)
{
    const SymbolStruct* leftStruct = resolveRuntimeStructType(codeGen, leftTypeRef);
    if (!leftStruct)
        return nullptr;

    const SymbolStruct* ownerStruct = variableOwnerStruct(memberSym);
    if (!ownerStruct || ownerStruct == leftStruct)
        return nullptr;

    const SymbolVariable* directField = leftStruct->findFieldByName(memberSym.idRef());
    if (!directField)
        return nullptr;

    if (ownerStruct->sameGenericFamily(*leftStruct))
        return directField;
    if (!ownerStructReachableThroughUsing(codeGen, *leftStruct, *ownerStruct))
        return directField;

    return nullptr;
}

const SymbolVariable* CodeGenStructHelpers::tryResolveConcreteReceiverFieldSymbol(CodeGen& codeGen, const SymbolVariable& fieldSym)
{
    const SymbolStruct* receiverStruct = resolveReceiverRuntimeStruct(codeGen);
    if (!receiverStruct)
        return nullptr;

    const SymbolStruct* fieldOwner = variableOwnerStruct(fieldSym);
    if (!fieldOwner || fieldOwner == receiverStruct)
        return nullptr;

    const SymbolVariable* directField = receiverStruct->findFieldByName(fieldSym.idRef());
    if (!directField)
        return nullptr;

    if (fieldOwner->sameGenericFamily(*receiverStruct))
        return directField;
    if (!ownerStructReachableThroughUsing(codeGen, *receiverStruct, *fieldOwner))
        return directField;

    return nullptr;
}

const SymbolVariable* CodeGenStructHelpers::tryResolveSameGenericFamilyFieldSymbol(const SymbolStruct& runtimeStruct, const SymbolVariable& fieldSym)
{
    const SymbolStruct* fieldOwner = variableOwnerStruct(fieldSym);
    if (!fieldOwner || fieldOwner == &runtimeStruct)
        return nullptr;
    if (!fieldOwner->sameGenericFamily(runtimeStruct))
        return nullptr;

    return runtimeStruct.findFieldByName(fieldSym.idRef());
}

SWC_END_NAMESPACE();
