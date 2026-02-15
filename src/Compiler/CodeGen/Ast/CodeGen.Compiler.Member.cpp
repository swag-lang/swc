#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

Result AstMemberAccessExpr::codeGenPostNode(CodeGen& codeGen) const
{
    MicroInstrBuilder& builder     = codeGen.builder();
    const auto*        leftPayload = SWC_CHECK_NOT_NULL(codeGen.payload(nodeLeftRef));

    const auto    rightView  = codeGen.nodeView(nodeRightRef);
    const Symbol* methodSym  = SWC_CHECK_NOT_NULL(rightView.sym);
    const auto&   methodFunc = *SWC_CHECK_NOT_NULL(methodSym->safeCast<SymbolFunction>()); // TODO: replace assert with a proper codegen diagnostic.
    SWC_ASSERT(methodFunc.hasInterfaceMethodSlot()); // TODO: replace assert with a proper codegen diagnostic.

    const auto&    payload = codeGen.setPayload(codeGen.curNodeRef());
    const MicroReg leftReg = codeGen.payloadVirtualReg(*leftPayload);
    const MicroReg dstReg  = codeGen.payloadVirtualReg(payload);
    builder.encodeLoadRegMem(dstReg, leftReg, offsetof(Runtime::Interface, itable), MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeLoadRegMem(dstReg, dstReg, methodFunc.interfaceMethodSlot() * sizeof(void*), MicroOpBits::B64, EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
