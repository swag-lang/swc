#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroAbiCall.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isInterfaceMethod(const SymbolFunction& methodSym)
    {
        const SymbolMap* ownerSymMap = methodSym.ownerSymMap();
        if (!ownerSymMap)
            return false;
        return ownerSymMap->safeCast<SymbolInterface>() != nullptr;
    }

    bool tryResolveInterfaceReceiver(CodeGen& codeGen, AstNodeRef calleeRef, const SymbolFunction* calledFunction, AstNodeRef& outReceiverRef)
    {
        outReceiverRef = AstNodeRef::invalid();
        if (!calledFunction || !isInterfaceMethod(*calledFunction))
            return false;

        const AstMemberAccessExpr* memberAccessExpr = codeGen.node(calleeRef).safeCast<AstMemberAccessExpr>();
        if (!memberAccessExpr)
            return false;

        const auto leftView = codeGen.nodeView(memberAccessExpr->nodeLeftRef);
        if (!leftView.type || !leftView.type->isInterface())
            return false;

        outReceiverRef = memberAccessExpr->nodeLeftRef;
        return true;
    }
}

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    MicroInstrBuilder& builder = codeGen.builder();

    const auto calleeView = codeGen.nodeView(nodeExprRef);
    const auto* calleePayload = codeGen.payload(calleeView.nodeRef);
    SWC_ASSERT(calleePayload != nullptr);

    const SymbolFunction& calledFunction = codeGen.curNodeView().sym->cast<SymbolFunction>();
    const CallConvKind    callConvKind   = calledFunction.callConvKind();
    const CallConv&       callConv       = CallConv::get(callConvKind);

    SmallVector<AstNodeRef> args;
    collectArguments(args, codeGen.ast());
    SWC_ASSERT(args.empty()); // TODO: replace assert with a proper codegen diagnostic.

    uint32_t   numAbiArgs           = 0;
    AstNodeRef interfaceReceiverRef = AstNodeRef::invalid();
    if (tryResolveInterfaceReceiver(codeGen, calleeView.nodeRef, &calledFunction, interfaceReceiverRef))
    {
        SWC_ASSERT(!callConv.intArgRegs.empty());
        const auto* receiverPayload = codeGen.payload(interfaceReceiverRef);
        SWC_ASSERT(receiverPayload != nullptr);

        const MicroReg callArg0Reg  = callConv.intArgRegs[0];
        const MicroReg interfaceReg = codeGen.payloadVirtualReg(*receiverPayload);
        builder.encodeLoadRegMem(callArg0Reg, interfaceReg, offsetof(Runtime::Interface, obj), MicroOpBits::B64, EncodeFlagsE::Zero);
        numAbiArgs = 1;
    }

    const MicroReg calleeReg = codeGen.payloadVirtualReg(*calleePayload);
    emitMicroABICallByReg(builder, callConvKind, calleeReg, numAbiArgs);

    auto* resultStorage        = codeGen.ctx().compiler().allocate<uint64_t>();
    *resultStorage             = 0;
    const auto&    nodePayload = codeGen.setPayload(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);
    const MicroReg resultReg   = codeGen.payloadVirtualReg(nodePayload);
    builder.encodeLoadRegImm(resultReg, reinterpret_cast<uint64_t>(resultStorage), MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeLoadMemReg(resultReg, 0, callConv.intReturn, MicroOpBits::B64, EncodeFlagsE::Zero);

    return Result::Continue;
}

SWC_END_NAMESPACE();
