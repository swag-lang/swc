#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Member.Payload.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    CodeGenNodePayload resolveMemberRuntimeStoragePayload(CodeGen& codeGen, const SymbolVariable& storageSym)
    {
        if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(storageSym))
            return *symbolPayload;

        SWC_ASSERT(storageSym.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());

        CodeGenNodePayload localPayload;
        localPayload.typeRef = storageSym.typeRef();
        localPayload.setIsAddress();
        if (!storageSym.offset())
        {
            localPayload.reg = codeGen.localStackBaseReg();
        }
        else
        {
            MicroBuilder& builder = codeGen.builder();
            localPayload.reg      = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(localPayload.reg, codeGen.localStackBaseReg(), MicroOpBits::B64);
            builder.emitOpBinaryRegImm(localPayload.reg, ApInt(storageSym.offset(), 64), MicroOp::Add, MicroOpBits::B64);
        }

        codeGen.setVariablePayload(storageSym, localPayload);
        return localPayload;
    }

    MicroReg memberRuntimeStorageAddressReg(CodeGen& codeGen)
    {
        const auto* payload = codeGen.sema().codeGenPayload<MemberAccessExprCodeGenPayload>(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->runtimeStorageSym != nullptr);
        const CodeGenNodePayload storagePayload = resolveMemberRuntimeStoragePayload(codeGen, *SWC_NOT_NULL(payload->runtimeStorageSym));
        SWC_ASSERT(storagePayload.isAddress());
        return storagePayload.reg;
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

        const CodeGenHelpers::FunctionParameterInfo paramInfo = CodeGenHelpers::functionParameterInfo(codeGen, codeGen.function(), symVar);
        return !paramInfo.isIndirect;
    }

    Result codeGenStructMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        const CodeGenNodePayload& leftPayload = codeGen.payload(node.nodeLeftRef);
        const SemaNodeView        rightView   = codeGen.viewSymbol(node.nodeRightRef);
        const Symbol*             rightSym    = SWC_NOT_NULL(rightView.sym());
        const auto&               symVar      = rightSym->cast<SymbolVariable>();

        const TypeRef             memberTypeRef = codeGen.curViewType().typeRef();
        const CodeGenNodePayload& payload       = codeGen.setPayloadAddress(codeGen.curNodeRef(), memberTypeRef);
        MicroBuilder&             builder       = codeGen.builder();

        if (!shouldTreatStructMemberLeftAsValue(codeGen, node.nodeLeftRef, leftPayload))
        {
            builder.emitLoadAddressRegMem(payload.reg, leftPayload.reg, symVar.offset(), MicroOpBits::B64);
            return Result::Continue;
        }

        const SemaNodeView leftView = codeGen.viewType(node.nodeLeftRef);
        SWC_ASSERT(leftView.type());

        const uint64_t leftSize = leftView.type()->sizeOf(codeGen.ctx());
        SWC_ASSERT(leftSize > 0);

        MicroReg baseAddressReg = leftPayload.reg;
        if (leftSize == 1 || leftSize == 2 || leftSize == 4 || leftSize == 8)
        {
            const MicroReg spillAddrReg = memberRuntimeStorageAddressReg(codeGen);
            builder.emitLoadMemReg(spillAddrReg, 0, leftPayload.reg, microOpBitsFromChunkSize(static_cast<uint32_t>(leftSize)));
            baseAddressReg = spillAddrReg;
        }

        builder.emitLoadAddressRegMem(payload.reg, baseAddressReg, symVar.offset(), MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenInterfaceMethodMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        MicroBuilder&             builder     = codeGen.builder();
        const CodeGenNodePayload& leftPayload = codeGen.payload(node.nodeLeftRef);

        const SemaNodeView rightView  = codeGen.viewSymbol(node.nodeRightRef);
        const Symbol*      methodSym  = SWC_NOT_NULL(rightView.sym());
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
    const SemaNodeView leftView = codeGen.viewType(nodeLeftRef);

    if (leftView.type() && leftView.type()->isInterface())
        return codeGenInterfaceMethodMemberAccess(codeGen, *this);

    const SemaNodeView rightView = codeGen.viewSymbol(nodeRightRef);
    if (leftView.type() && rightView.sym() && rightView.sym()->isVariable())
        return codeGenStructMemberAccess(codeGen, *this);
    if (rightView.sym() && (rightView.sym()->isFunction() || rightView.sym()->isType() || rightView.sym()->isNamespace() || rightView.sym()->isModule()))
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
