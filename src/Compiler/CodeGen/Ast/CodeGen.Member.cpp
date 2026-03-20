#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct StructUsingPathStep
    {
        const SymbolVariable* field     = nullptr;
        bool                  isPointer = false;
    };

    bool resolveUsingMemberPathRec(CodeGen& codeGen, const SymbolStruct& currentStruct, const SymbolStruct& targetStruct, SmallVector<StructUsingPathStep>& outSteps, SmallVector<const SymbolStruct*>& visited)
    {
        if (&currentStruct == &targetStruct)
            return true;

        for (const SymbolStruct* visitedStruct : visited)
        {
            if (visitedStruct == &currentStruct)
                return false;
        }

        visited.push_back(&currentStruct);
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

        SmallVector<const SymbolStruct*> visited;
        return resolveUsingMemberPathRec(codeGen, baseTypeInfo->payloadSymStruct(), *ownerStruct, outSteps, visited);
    }

    struct AggregateMemberInfo
    {
        uint32_t offset        = 0;
        TypeRef  memberTypeRef = TypeRef::invalid();
    };

    bool resolveAggregateMemberInfo(CodeGen& codeGen, const TypeInfo& aggregateType, AstNodeRef memberRef, AggregateMemberInfo& outInfo)
    {
        if (!aggregateType.isAggregateStruct())
            return false;

        const auto& names = aggregateType.payloadAggregate().names;
        const auto& types = aggregateType.payloadAggregate().types;
        SWC_ASSERT(names.size() == types.size());

        const IdentifierRef    idRef  = codeGen.sema().idMgr().addIdentifier(codeGen.ctx(), codeGen.node(memberRef).codeRef());
        const std::string_view idName = codeGen.sema().idMgr().get(idRef).name;
        uint64_t               offset = 0;

        for (size_t i = 0; i < types.size(); ++i)
        {
            const TypeInfo& memberType  = codeGen.typeMgr().get(types[i]);
            const uint32_t  memberAlign = std::max<uint32_t>(memberType.alignOf(codeGen.ctx()), 1);
            const uint64_t  memberSize  = memberType.sizeOf(codeGen.ctx());
            if (memberSize)
                offset = ((offset + static_cast<uint64_t>(memberAlign) - 1) / static_cast<uint64_t>(memberAlign)) * static_cast<uint64_t>(memberAlign);

            bool found = false;
            if (names[i].isValid() && names[i] == idRef)
                found = true;
            else if (!names[i].isValid() && idName == ("item" + std::to_string(i)))
                found = idName == ("item" + std::to_string(i));

            if (found)
            {
                outInfo.offset        = static_cast<uint32_t>(offset);
                outInfo.memberTypeRef = types[i];
                return true;
            }

            offset += memberSize;
        }

        return false;
    }

    MicroReg resolveAggregateMemberBaseAddress(CodeGen& codeGen, const SemaNodeView& leftTypeView, const CodeGenNodePayload& leftPayload)
    {
        MicroBuilder& builder = codeGen.builder();

        if (leftTypeView.type() && leftTypeView.type()->isReference() && leftPayload.isAddress())
        {
            const MicroReg baseAddressReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(baseAddressReg, leftPayload.reg, 0, MicroOpBits::B64);
            return baseAddressReg;
        }

        if (leftPayload.isAddress())
            return leftPayload.reg;

        const uint64_t leftSize = leftTypeView.type()->sizeOf(codeGen.ctx());
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
        if (leftTypeView.type() && leftTypeView.type()->isReference())
            return false;

        if (leftPayload.isValue())
            return true;

        const SemaNodeView leftSymbolView = codeGen.viewSymbol(leftRef);
        if (!leftSymbolView.sym() || !leftSymbolView.sym()->isVariable())
            return false;

        const SymbolVariable& symVar = leftSymbolView.sym()->cast<SymbolVariable>();
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            return false;
        if (!symVar.hasParameterIndex())
            return false;

        const CodeGenFunctionHelpers::FunctionParameterInfo paramInfo = CodeGenFunctionHelpers::functionParameterInfo(codeGen, codeGen.function(), symVar);
        return !paramInfo.isIndirect;
    }

    Result codeGenStructMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        const CodeGenNodePayload& leftPayload  = codeGen.payload(node.nodeLeftRef);
        const SemaNodeView        leftTypeView = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView        rightView    = codeGen.viewSymbol(node.nodeRightRef);
        const Symbol*             rightSym     = (rightView.sym());
        const auto&               symVar       = rightSym->cast<SymbolVariable>();

        const TypeRef                    memberTypeRef = symVar.typeRef();
        const CodeGenNodePayload&        payload       = codeGen.setPayloadAddress(codeGen.curNodeRef(), memberTypeRef);
        MicroBuilder&                    builder       = codeGen.builder();
        SmallVector<StructUsingPathStep> usingPath;
        if (leftTypeView.typeRef().isValid())
            resolveStructMemberPath(codeGen, leftTypeView.typeRef(), symVar, usingPath);

        MicroReg baseAddressReg = leftPayload.reg;
        if (leftTypeView.type() && (leftTypeView.type()->isPointerOrReference() || leftTypeView.type()->isTypeInfo()))
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
            const SemaNodeView leftView = codeGen.viewType(node.nodeLeftRef);
            SWC_ASSERT(leftView.type());

            const uint64_t leftSize = leftView.type()->sizeOf(codeGen.ctx());
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

        AggregateMemberInfo memberInfo;
        if (!resolveAggregateMemberInfo(codeGen, *leftTypeView.type(), node.nodeRightRef, memberInfo))
            SWC_UNREACHABLE();

        const CodeGenNodePayload& payload = codeGen.setPayloadAddress(codeGen.curNodeRef(), memberInfo.memberTypeRef);
        MicroBuilder&             builder = codeGen.builder();
        const MicroReg            baseReg = resolveAggregateMemberBaseAddress(codeGen, leftTypeView, leftPayload);
        builder.emitLoadAddressRegMem(payload.reg, baseReg, memberInfo.offset, MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenInterfaceMethodMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        MicroBuilder&             builder     = codeGen.builder();
        const CodeGenNodePayload& leftPayload = codeGen.payload(node.nodeLeftRef);

        const SemaNodeView rightView  = codeGen.viewSymbol(node.nodeRightRef);
        const Symbol*      methodSym  = (rightView.sym());
        const auto&        methodFunc = methodSym->cast<SymbolFunction>();
        SWC_ASSERT(methodFunc.hasInterfaceMethodSlot());

        const CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef());
        const MicroReg            leftReg = leftPayload.reg;
        const MicroReg            dstReg  = payload.reg;
        builder.emitLoadRegMem(dstReg, leftReg, offsetof(Runtime::Interface, itable), MicroOpBits::B64);
        builder.emitLoadRegMem(dstReg, dstReg, methodFunc.interfaceMethodSlot() * sizeof(void*), MicroOpBits::B64);
        return Result::Continue;
    }
}

Result AstMemberAccessExpr::codeGenPreNodeChild(const CodeGen& codeGen, const AstNodeRef& childRef) const
{
    SWC_UNUSED(codeGen);
    if (childRef == nodeRightRef)
        return Result::SkipChildren;
    return Result::Continue;
}

Result AstMemberAccessExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView leftView = codeGen.viewTypeSymbol(nodeLeftRef);

    if (leftView.type() && leftView.type()->isInterface() && (!leftView.sym() || !leftView.sym()->isImpl()))
        return codeGenInterfaceMethodMemberAccess(codeGen, *this);
    if (leftView.type() && leftView.type()->isAggregateStruct())
        return codeGenAggregateStructMemberAccess(codeGen, *this);

    const SemaNodeView rightView = codeGen.viewSymbol(nodeRightRef);
    if (rightView.sym())
    {
        if (leftView.type() && rightView.sym()->isVariable())
            return codeGenStructMemberAccess(codeGen, *this);
        if (rightView.sym()->isFunction() || rightView.sym()->isType() || rightView.sym()->isNamespace() || rightView.sym()->isModule() || rightView.sym()->isImpl())
            return Result::Continue;
    }

    SWC_ASSERT(codeGen.safePayload(nodeRightRef));
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeRightRef, codeGen.curViewType().typeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
