#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result codeGenInterfaceMethodMemberAccess(CodeGen& codeGen, const AstMemberAccessExpr& node)
    {
        MicroBuilder&             builder     = codeGen.builder();
        const CodeGenNodePayload* leftPayload = SWC_CHECK_NOT_NULL(codeGen.payload(node.nodeLeftRef));

        const SemaNodeView rightView  = codeGen.sema().nodeViewSymbol(node.nodeRightRef);
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

Result AstMemberAccessExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView leftView = codeGen.sema().nodeViewType(nodeLeftRef);
    SWC_ASSERT(leftView.type());

    if (leftView.type()->isInterface())
        return codeGenInterfaceMethodMemberAccess(codeGen, *this);

    if (codeGen.payload(nodeRightRef))
    {
        codeGen.inheritPayload(codeGen.curNodeRef(), nodeRightRef, codeGen.sema().nodeViewType(codeGen.curNodeRef()).typeRef());
        return Result::Continue;
    }

    if (codeGen.sema().nodeViewConstant(codeGen.curNodeRef()).hasConstant())
        return Result::Continue;

    // TODO
    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();



