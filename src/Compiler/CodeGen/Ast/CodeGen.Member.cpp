#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool shouldTreatStructMemberLeftAsValue(CodeGen& codeGen, AstNodeRef leftRef, const CodeGenNodePayload& leftPayload)
    {
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
        const CodeGenNodePayload* leftPayload = SWC_CHECK_NOT_NULL(codeGen.payload(node.nodeLeftRef));
        const SemaNodeView        rightView   = codeGen.viewSymbol(node.nodeRightRef);
        const Symbol*             rightSym    = SWC_CHECK_NOT_NULL(rightView.sym());
        const SymbolVariable*     symVar      = rightSym->safeCast<SymbolVariable>();
        SWC_ASSERT(symVar != nullptr);

        const TypeRef       memberTypeRef = codeGen.curViewType().typeRef();
        CodeGenNodePayload& payload       = codeGen.setPayloadAddress(codeGen.curNodeRef(), memberTypeRef);
        MicroBuilder&       builder       = codeGen.builder();

        if (!shouldTreatStructMemberLeftAsValue(codeGen, node.nodeLeftRef, *leftPayload))
        {
            builder.emitLoadAddressRegMem(payload.reg, leftPayload->reg, symVar->offset(), MicroOpBits::B64);
            return Result::Continue;
        }

        const SemaNodeView leftView = codeGen.viewType(node.nodeLeftRef);
        SWC_ASSERT(leftView.type());

        const uint64_t leftSize = leftView.type()->sizeOf(codeGen.ctx());
        SWC_ASSERT(leftSize > 0 && leftSize <= 8);

        std::byte* spillData = codeGen.compiler().allocateArray<std::byte>(static_cast<size_t>(leftSize));
        std::memset(spillData, 0, static_cast<size_t>(leftSize));

        const MicroReg spillAddrReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrImm(spillAddrReg, reinterpret_cast<uint64_t>(spillData));
        builder.emitLoadMemReg(spillAddrReg, 0, leftPayload->reg, microOpBitsFromChunkSize(static_cast<uint32_t>(leftSize)));
        builder.emitLoadAddressRegMem(payload.reg, spillAddrReg, symVar->offset(), MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenInterfaceMethodMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        MicroBuilder&             builder     = codeGen.builder();
        const CodeGenNodePayload* leftPayload = SWC_CHECK_NOT_NULL(codeGen.payload(node.nodeLeftRef));

        const SemaNodeView rightView  = codeGen.viewSymbol(node.nodeRightRef);
        const Symbol*      methodSym  = SWC_CHECK_NOT_NULL(rightView.sym());
        const auto&        methodFunc = *SWC_CHECK_NOT_NULL(methodSym->safeCast<SymbolFunction>());
        SWC_ASSERT(methodFunc.hasInterfaceMethodSlot());

        const CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef());
        const MicroReg            leftReg = leftPayload->reg;
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
    SWC_ASSERT(leftView.type());

    if (leftView.type()->isInterface())
        return codeGenInterfaceMethodMemberAccess(codeGen, *this);

    const SemaNodeView rightView = codeGen.viewSymbol(nodeRightRef);
    if (rightView.sym() && rightView.sym()->isVariable())
        return codeGenStructMemberAccess(codeGen, *this);

    if (codeGen.payload(nodeRightRef))
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
