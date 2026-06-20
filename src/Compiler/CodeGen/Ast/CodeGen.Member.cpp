#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenStructHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Symbol* recoverMemberAccessRightSymbol(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return nullptr;

        if (Symbol* symbol = codeGen.sema().viewStored(nodeRef, SemaNodeViewPartE::Symbol).sym())
            return symbol;

        const AstNodeRef resolvedRef = codeGen.resolvedNodeRef(nodeRef);
        if (resolvedRef.isValid() && resolvedRef != nodeRef)
            return codeGen.sema().viewStored(resolvedRef, SemaNodeViewPartE::Symbol).sym();

        return nullptr;
    }

    struct StructUsingPathStep
    {
        const SymbolVariable* field     = nullptr;
        bool                  isPointer = false;
    };

    bool resolveUsingMemberPathRec(CodeGen& codeGen, const SymbolStruct& currentStruct, const SymbolStruct& targetStruct, SmallVector<StructUsingPathStep>& outSteps, std::unordered_set<const SymbolStruct*>& visited)
    {
        if (&currentStruct == &targetStruct)
            return true;
        if (!visited.insert(&currentStruct).second)
            return false;

        for (const SymbolVariable* field : currentStruct.fields())
        {
            SWC_ASSERT(field != nullptr);
            if (!field->isUsingField())
                continue;

            bool                usingFieldIsPointer = false;
            const SymbolStruct* usingTargetStruct   = field->usingTargetStruct(codeGen.ctx(), usingFieldIsPointer);
            if (!usingTargetStruct)
                continue;

            // Follow nested `using` fields until we reach the struct that actually owns the member.
            outSteps.push_back({.field = field, .isPointer = usingFieldIsPointer});
            if (resolveUsingMemberPathRec(codeGen, *usingTargetStruct, targetStruct, outSteps, visited))
                return true;
            outSteps.pop_back();
        }

        return false;
    }

    bool resolveStructMemberPath(CodeGen& codeGen, TypeRef leftTypeRef, const SymbolVariable& memberSym, SmallVector<StructUsingPathStep>& outSteps)
    {
        outSteps.clear();

        const SymbolMap* ownerSymMap = memberSym.ownerSymMap();
        const auto*      ownerStruct = ownerSymMap ? ownerSymMap->safeCast<SymbolStruct>() : nullptr;
        if (!ownerStruct)
            return false;

        TypeRef baseTypeRef = codeGen.typeMgr().get(leftTypeRef).unwrapAliasEnum(codeGen.ctx(), leftTypeRef);
        if (baseTypeRef.isInvalid())
            return false;

        const TypeInfo* baseTypeInfo = &codeGen.typeMgr().get(baseTypeRef);
        if (baseTypeInfo->isPointerOrReference())
        {
            baseTypeRef  = codeGen.typeMgr().get(baseTypeInfo->payloadTypeRef()).unwrapAliasEnum(codeGen.ctx(), baseTypeInfo->payloadTypeRef());
            baseTypeInfo = &codeGen.typeMgr().get(baseTypeRef);
        }

        if (!baseTypeInfo->isStruct())
            return false;

        std::unordered_set<const SymbolStruct*> visited;
        return resolveUsingMemberPathRec(codeGen, baseTypeInfo->payloadSymStruct(), *ownerStruct, outSteps, visited);
    }

    struct AggregateMemberInfo
    {
        uint32_t offset        = 0;
        TypeRef  memberTypeRef = TypeRef::invalid();
    };

    TypeRef aliasEnumTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        typeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), typeRef);
        SWC_ASSERT(typeRef.isValid());
        return typeRef;
    }

    const TypeInfo& aliasEnumType(CodeGen& codeGen, const SemaNodeView& view)
    {
        return codeGen.typeMgr().get(aliasEnumTypeRef(codeGen, view.typeRef()));
    }

    bool resolveAggregateMemberInfo(CodeGen& codeGen, const TypeInfo& aggregateType, AstNodeRef memberRef, AggregateMemberInfo& outInfo)
    {
        if (!aggregateType.isAggregateStruct())
            return false;

        const auto& aggregate = aggregateType.payloadAggregate();
        const auto& types     = aggregate.types;
        SWC_ASSERT(aggregate.names.size() == types.size());

        const IdentifierRef idRef       = codeGen.sema().idMgr().addIdentifier(codeGen.ctx(), codeGen.node(memberRef).codeRef());
        size_t              memberIndex = 0;
        if (!aggregateType.tryGetAggregateMemberIndexByName(memberIndex, codeGen.ctx(), idRef) || memberIndex >= types.size())
            return false;

        uint64_t offset = 0;
        for (size_t i = 0; i <= memberIndex; ++i)
        {
            const TypeInfo& memberType  = codeGen.typeMgr().get(types[i]);
            const uint32_t  memberAlign = std::max<uint32_t>(memberType.alignOf(codeGen.ctx()), 1);
            const uint64_t  memberSize  = memberType.sizeOf(codeGen.ctx());
            if (memberSize)
                offset = ((offset + static_cast<uint64_t>(memberAlign) - 1) / static_cast<uint64_t>(memberAlign)) * static_cast<uint64_t>(memberAlign);

            if (i == memberIndex)
            {
                outInfo.offset        = static_cast<uint32_t>(offset);
                outInfo.memberTypeRef = types[i];
                return true;
            }

            offset += memberSize;
        }

        return false;
    }

    TypeRef resolveAggregateMemberOwnerTypeRef(CodeGen& codeGen, TypeRef leftTypeRef)
    {
        if (!leftTypeRef.isValid())
            return TypeRef::invalid();

        leftTypeRef                  = aliasEnumTypeRef(codeGen, leftTypeRef);
        const TypeInfo* leftTypeInfo = &codeGen.typeMgr().get(leftTypeRef);
        if (leftTypeInfo->isPointerOrReference())
        {
            leftTypeRef  = aliasEnumTypeRef(codeGen, leftTypeInfo->payloadTypeRef());
            leftTypeInfo = &codeGen.typeMgr().get(leftTypeRef);
        }

        if (!leftTypeInfo->isAggregateStruct())
            return TypeRef::invalid();

        return leftTypeRef;
    }

    MicroReg resolveAggregateMemberBaseAddress(CodeGen& codeGen, TypeRef leftTypeRef, const CodeGenNodePayload& leftPayload)
    {
        MicroBuilder&   builder      = codeGen.builder();
        const TypeInfo& leftTypeInfo = codeGen.typeMgr().get(aliasEnumTypeRef(codeGen, leftTypeRef));

        if (leftTypeInfo.isPointerOrReference() || leftTypeInfo.isTypeInfo())
        {
            if (leftPayload.isAddress())
            {
                const MicroReg baseAddressReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(baseAddressReg, leftPayload.reg, 0, MicroOpBits::B64);
                return baseAddressReg;
            }

            return leftPayload.reg;
        }

        if (leftPayload.isAddress())
            return leftPayload.reg;

        const uint64_t leftSize = leftTypeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(leftSize > 0);
        if (leftSize == 1 || leftSize == 2 || leftSize == 4 || leftSize == 8)
        {
            const MicroReg spillAddrReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
            builder.emitLoadMemReg(spillAddrReg, 0, leftPayload.reg, CodeGenTypeHelpers::bitsFromStorageSize(leftSize));
            return spillAddrReg;
        }

        return leftPayload.reg;
    }

    bool shouldTreatStructMemberLeftAsValue(CodeGen& codeGen, AstNodeRef leftRef, const CodeGenNodePayload& leftPayload)
    {
        const SemaNodeView leftTypeView = codeGen.viewType(leftRef);
        if (leftTypeView.type() && aliasEnumType(codeGen, leftTypeView).isReference())
            return false;

        return leftPayload.isValue();
    }

    Result codeGenStructMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        const CodeGenNodePayload& leftPayload  = codeGen.payload(node.nodeLeftRef);
        const SemaNodeView        leftTypeView = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView        rightView    = codeGen.viewSymbol(node.nodeRightRef);
        const Symbol*             rightSym     = rightView.sym();
        if (!rightSym)
            rightSym = recoverMemberAccessRightSymbol(codeGen, node.nodeRightRef);
        SWC_ASSERT(rightSym != nullptr);
        if (!rightSym)
            return Result::Error;
        const auto& semaSymVar  = rightSym->cast<SymbolVariable>();
        TypeRef     leftTypeRef = leftPayload.effectiveTypeRef(leftTypeView.typeRef());
        leftTypeRef             = CodeGenStructHelpers::resolveRuntimeLeftTypeRef(codeGen, node.nodeLeftRef, leftTypeRef);
        SWC_ASSERT(leftTypeRef.isValid());
        const TypeInfo& leftTypeInfo = codeGen.typeMgr().get(aliasEnumTypeRef(codeGen, leftTypeRef));

        // Runtime member accesses inside generic instances must use the field symbol of the active
        // specialization. Reusing the root generic field leaks stale offsets and field types into
        // codegen, which breaks layout-sensitive member/index chains.
        const SymbolVariable* concreteSymVar = CodeGenStructHelpers::tryResolveConcreteStructMemberSymbol(codeGen, leftTypeRef, semaSymVar);
        const SymbolVariable& symVar         = concreteSymVar ? *concreteSymVar : semaSymVar;

        const TypeRef                    memberTypeRef = symVar.typeRef();
        const CodeGenNodePayload&        payload       = codeGen.setPayloadAddress(codeGen.curNodeRef(), memberTypeRef);
        MicroBuilder&                    builder       = codeGen.builder();
        SmallVector<StructUsingPathStep> usingPath;
        if (leftTypeRef.isValid())
            resolveStructMemberPath(codeGen, leftTypeRef, symVar, usingPath);

        MicroReg baseAddressReg = leftPayload.reg;
        if (leftTypeInfo.isPointerOrReference() || leftTypeInfo.isTypeInfo())
        {
            // Member access through a pointer/reference or `typeinfo` works on the pointee object, not
            // on the storage that currently holds that pointer value.
            if (leftPayload.isAddress())
            {
                baseAddressReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(baseAddressReg, leftPayload.reg, 0, MicroOpBits::B64);
            }
        }
        else if (!shouldTreatStructMemberLeftAsValue(codeGen, node.nodeLeftRef, leftPayload))
        {
            baseAddressReg = leftPayload.reg;
        }
        else
        {
            const uint64_t leftSize = leftTypeInfo.sizeOf(codeGen.ctx());
            SWC_ASSERT(leftSize > 0);

            if (leftSize == 1 || leftSize == 2 || leftSize == 4 || leftSize == 8)
            {
                // Member access still needs an address, so spill small by-value aggregates to temporary
                // storage before computing the field offset.
                const MicroReg spillAddrReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
                builder.emitLoadMemReg(spillAddrReg, 0, leftPayload.reg, CodeGenTypeHelpers::bitsFromStorageSize(leftSize));
                baseAddressReg = spillAddrReg;
            }
        }

        // Replay the resolved `using` chain so the final member offset is computed from the subobject that
        // actually owns the requested field.
        for (const auto& step : usingPath)
        {
            SWC_ASSERT(step.field != nullptr);
            if (step.isPointer)
            {
                const MicroReg nextAddressReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(nextAddressReg, baseAddressReg, step.field->offset(), MicroOpBits::B64);
                baseAddressReg = nextAddressReg;
            }
            else
            {
                baseAddressReg = codeGen.offsetAddressReg(baseAddressReg, step.field->offset());
            }
        }

        builder.emitLoadAddressRegMem(payload.reg, baseAddressReg, symVar.offset(), MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenAggregateStructMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        const CodeGenNodePayload& leftPayload  = codeGen.payload(node.nodeLeftRef);
        const SemaNodeView        leftTypeView = codeGen.viewType(node.nodeLeftRef);
        SWC_ASSERT(leftTypeView.type() != nullptr);
        const TypeRef aggregateTypeRef = resolveAggregateMemberOwnerTypeRef(codeGen, leftPayload.effectiveTypeRef(leftTypeView.typeRef()));
        SWC_ASSERT(aggregateTypeRef.isValid());

        AggregateMemberInfo memberInfo;
        if (!resolveAggregateMemberInfo(codeGen, codeGen.typeMgr().get(aggregateTypeRef), node.nodeRightRef, memberInfo))
            SWC_UNREACHABLE();

        const CodeGenNodePayload& payload = codeGen.setPayloadAddress(codeGen.curNodeRef(), memberInfo.memberTypeRef);
        MicroBuilder&             builder = codeGen.builder();
        const MicroReg            baseReg = resolveAggregateMemberBaseAddress(codeGen, leftPayload.effectiveTypeRef(leftTypeView.typeRef()), leftPayload);
        builder.emitLoadAddressRegMem(payload.reg, baseReg, memberInfo.offset, MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenInterfaceMethodMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        MicroBuilder&             builder     = codeGen.builder();
        const CodeGenNodePayload& leftPayload = codeGen.payload(node.nodeLeftRef);

        const SemaNodeView rightView = codeGen.viewSymbol(node.nodeRightRef);
        const Symbol*      methodSym = rightView.sym();
        if (!methodSym)
            methodSym = recoverMemberAccessRightSymbol(codeGen, node.nodeRightRef);
        SWC_ASSERT(methodSym != nullptr);
        if (!methodSym)
            return Result::Error;
        const auto& methodFunc = methodSym->cast<SymbolFunction>();
        SWC_ASSERT(methodFunc.hasInterfaceMethodSlot());

        const CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef());
        const MicroReg            leftReg = leftPayload.reg;
        const MicroReg            dstReg  = payload.reg;
        builder.emitLoadRegMem(dstReg, leftReg, offsetof(Runtime::Interface, itable), MicroOpBits::B64);
        builder.emitLoadRegMem(dstReg, dstReg, (methodFunc.interfaceMethodSlot() + 1) * sizeof(void*), MicroOpBits::B64);
        return Result::Continue;
    }

    bool isRuntimeMemberAccessLeft(const SemaNodeView& leftView)
    {
        if (!leftView.sym())
            return true;
        return !leftView.sym()->isType() &&
               !leftView.sym()->isNamespace() &&
               !leftView.sym()->isModule() &&
               !leftView.sym()->isImpl();
    }

    bool isCompileTimeMemberAccessLeftNode(const AstNode& node)
    {
        return node.is(AstNodeId::Identifier) || node.is(AstNodeId::NamedType) || node.is(AstNodeId::SuffixLiteral);
    }

    bool canSkipCompileTimeMemberAccessLeft(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        const SemaNodeView leftView = codeGen.viewTypeSymbol(node.nodeLeftRef);
        if (!isRuntimeMemberAccessLeft(leftView))
            return true;

        if (leftView.sym() || !leftView.typeRef().isValid())
            return false;
        if (!isCompileTimeMemberAccessLeftNode(codeGen.node(node.nodeLeftRef)))
            return false;

        const SemaNodeView rightView = codeGen.viewSymbol(node.nodeRightRef);
        if (!rightView.sym())
            return false;

        return rightView.sym()->isFunction() ||
               rightView.sym()->isType() ||
               rightView.sym()->isNamespace() ||
               rightView.sym()->isModule() ||
               rightView.sym()->isImpl();
    }

    bool canMaterializeScopedRightSymbol(const Symbol& symbol)
    {
        if (!symbol.isVariable())
            return false;

        return symbol.cast<SymbolVariable>().hasGlobalStorage();
    }

    Result finalizeRuntimeMemberAccess(CodeGen& codeGen, const Result result)
    {
        if (result != Result::Continue)
            return result;

        const CodeGenNodePayload* payload = codeGen.safePayload(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->reg.isValid());
        return result;
    }
}

Result AstMemberAccessExpr::codeGenPreNodeChild(const CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef == nodeLeftRef)
    {
        if (canSkipCompileTimeMemberAccessLeft(const_cast<CodeGen&>(codeGen), *this))
            return Result::SkipChildren;
    }

    if (childRef == nodeRightRef)
        return Result::SkipChildren;
    return Result::Continue;
}

Result AstMemberAccessExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView leftView           = codeGen.viewTypeSymbol(nodeLeftRef);
    const bool         leftIsRuntimeValue = isRuntimeMemberAccessLeft(leftView);

    if (leftIsRuntimeValue && leftView.type() && leftView.type()->isInterface())
        return finalizeRuntimeMemberAccess(codeGen, codeGenInterfaceMethodMemberAccess(codeGen, *this));
    if (leftIsRuntimeValue && resolveAggregateMemberOwnerTypeRef(codeGen, leftView.typeRef()).isValid())
        return finalizeRuntimeMemberAccess(codeGen, codeGenAggregateStructMemberAccess(codeGen, *this));

    const SemaNodeView rightView = codeGen.viewSymbol(nodeRightRef);
    const Symbol*      rightSym  = rightView.sym();
    if (!rightSym)
        rightSym = recoverMemberAccessRightSymbol(codeGen, nodeRightRef);
    if (rightSym)
    {
        if (leftIsRuntimeValue && rightSym->isVariable())
            return finalizeRuntimeMemberAccess(codeGen, codeGenStructMemberAccess(codeGen, *this));
        if (rightSym->isFunction() || rightSym->isType() || rightSym->isNamespace() || rightSym->isModule() || rightSym->isImpl())
            return Result::Continue;
    }

    const CodeGenNodePayload* rightPayload = codeGen.safePayload(nodeRightRef);
    if ((!rightPayload || !rightPayload->reg.isValid()) && rightSym && canMaterializeScopedRightSymbol(*rightSym))
    {
        // Member access does not visit the RHS child during the normal walk. Scoped values such as
        // `Namespace.globalVar` still need the same payload materialization as a standalone identifier.
        SWC_RESULT(codeGen.emitNodeNow(nodeRightRef));
        rightPayload = codeGen.safePayload(nodeRightRef);
    }

    if (!rightPayload || !rightPayload->reg.isValid())
    {
        // Member access skips visiting the RHS at codegen time. If semantic analysis already rejected
        // that member, there may be no materialized payload to inherit, and codegen must not hard-assert.
        return Result::Continue;
    }

    codeGen.inheritPayload(codeGen.curNodeRef(), nodeRightRef, codeGen.transparentPayloadTypeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
