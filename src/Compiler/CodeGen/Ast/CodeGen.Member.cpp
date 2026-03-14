#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
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

    bool isUsingMemberDecl(const AstNode* decl)
    {
        if (!decl)
            return false;
        if (decl->is(AstNodeId::SingleVarDecl))
            return decl->cast<AstSingleVarDecl>().hasFlag(AstVarDeclFlagsE::Using);
        if (decl->is(AstNodeId::MultiVarDecl))
            return decl->cast<AstMultiVarDecl>().hasFlag(AstVarDeclFlagsE::Using);
        return false;
    }

    const SymbolStruct* resolveUsingTargetStruct(CodeGen& codeGen, const SymbolVariable& symVar, bool& outIsPointer)
    {
        outIsPointer = false;

        const TaskContext& ctx      = codeGen.ctx();
        const TypeManager& typeMgr  = codeGen.typeMgr();
        const TypeRef      typeRef  = typeMgr.get(symVar.typeRef()).unwrap(ctx, symVar.typeRef(), TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo&    typeInfo = typeMgr.get(typeRef);
        if (typeInfo.isStruct())
            return &typeInfo.payloadSymStruct();

        if (!typeInfo.isAnyPointer())
            return nullptr;

        const TypeRef   pointeeTypeRef = typeMgr.get(typeInfo.payloadTypeRef()).unwrap(ctx, typeInfo.payloadTypeRef(), TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo& pointeeType    = typeMgr.get(pointeeTypeRef);
        if (!pointeeType.isStruct())
            return nullptr;

        outIsPointer = true;
        return &pointeeType.payloadSymStruct();
    }

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
        for (const Symbol* fieldSym : currentStruct.fields())
        {
            const auto* field = fieldSym ? fieldSym->safeCast<SymbolVariable>() : nullptr;
            if (!field || !isUsingMemberDecl(field->decl()))
                continue;

            bool                usingFieldIsPointer = false;
            const SymbolStruct* usingTargetStruct   = resolveUsingTargetStruct(codeGen, *field, usingFieldIsPointer);
            if (!usingTargetStruct)
                continue;

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

        TypeRef baseTypeRef = codeGen.typeMgr().get(leftTypeRef).unwrap(codeGen.ctx(), leftTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (baseTypeRef.isInvalid())
            return false;

        const TypeInfo* baseTypeInfo = &codeGen.typeMgr().get(baseTypeRef);
        if (baseTypeInfo->isAnyPointer() || baseTypeInfo->isReference())
        {
            baseTypeRef  = codeGen.typeMgr().get(baseTypeInfo->payloadTypeRef()).unwrap(codeGen.ctx(), baseTypeInfo->payloadTypeRef(), TypeExpandE::Alias | TypeExpandE::Enum);
            baseTypeInfo = &codeGen.typeMgr().get(baseTypeRef);
        }

        if (!baseTypeInfo->isStruct())
            return false;

        SmallVector<const SymbolStruct*> visited;
        return resolveUsingMemberPathRec(codeGen, baseTypeInfo->payloadSymStruct(), *ownerStruct, outSteps, visited);
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
        if (leftTypeView.type() && (leftTypeView.type()->isAnyPointer() || leftTypeView.type()->isReference()))
        {
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
                const MicroReg spillAddrReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
                builder.emitLoadMemReg(spillAddrReg, 0, leftPayload.reg, microOpBitsFromChunkSize(static_cast<uint32_t>(leftSize)));
                baseAddressReg = spillAddrReg;
            }
        }

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

    const SemaNodeView rightView = codeGen.viewSymbol(nodeRightRef);
    if (leftView.type() && rightView.sym() && rightView.sym()->isVariable())
        return codeGenStructMemberAccess(codeGen, *this);
    if (rightView.sym() &&
        (rightView.sym()->isFunction() || rightView.sym()->isType() || rightView.sym()->isNamespace() || rightView.sym()->isModule() || rightView.sym()->isImpl()))
        return Result::Continue;

    if (codeGen.safePayload(nodeRightRef))
    {
        codeGen.inheritPayload(codeGen.curNodeRef(), nodeRightRef, codeGen.curViewType().typeRef());
        return Result::Continue;
    }

    if (codeGen.curViewConstant().hasConstant())
        return Result::Continue;

    // TODO
    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
