#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result codeGenInterfaceMethodMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        MicroInstrBuilder& builder     = codeGen.builder();
        const auto*        leftPayload = SWC_CHECK_NOT_NULL(codeGen.payload(node.nodeLeftRef));

        const auto    rightView  = codeGen.nodeView(node.nodeRightRef);
        const Symbol* methodSym  = SWC_CHECK_NOT_NULL(rightView.sym);
        const auto&   methodFunc = *SWC_CHECK_NOT_NULL(methodSym->safeCast<SymbolFunction>());
        SWC_ASSERT(methodFunc.hasInterfaceMethodSlot());

        const auto&    payload = codeGen.setPayload(codeGen.curNodeRef());
        const MicroReg leftReg = leftPayload->reg;
        const MicroReg dstReg  = payload.reg;
        builder.encodeLoadRegMem(dstReg, leftReg, offsetof(Runtime::Interface, itable), MicroOpBits::B64);
        builder.encodeLoadRegMem(dstReg, dstReg, methodFunc.interfaceMethodSlot() * sizeof(void*), MicroOpBits::B64);
        return Result::Continue;
    }
}

Result AstMemberAccessExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const auto leftView = codeGen.nodeView(nodeLeftRef);
    SWC_ASSERT(leftView.type);

    if (leftView.type->isInterface())
        return codeGenInterfaceMethodMemberAccess(codeGen, *this);

    if (codeGen.payload(nodeRightRef))
    {
        codeGen.inheritPayload(codeGen.curNodeRef(), nodeRightRef, codeGen.curNodeView().typeRef);
        return Result::Continue;
    }

    if (codeGen.curNodeView().cst)
        return Result::Continue;

    // TODO
    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
