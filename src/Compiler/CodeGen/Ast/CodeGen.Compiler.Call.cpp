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
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint32_t emitPreparedCallArguments(CodeGen& codeGen, const SymbolFunction& calledFunction, const CallConv& callConv, std::span<const AstNodeRef> args)
    {
        MicroInstrBuilder& builder = codeGen.builder();
        SWC_ASSERT(args.size() <= callConv.intArgRegs.size());

        for (uint32_t i = 0; i < args.size(); ++i)
        {
            const AstNodeRef argRef     = args[i];
            const auto*      argPayload = codeGen.payload(argRef);
            SWC_ASSERT(argPayload != nullptr);

            const MicroReg argReg = callConv.intArgRegs[i];
            const auto     argView = codeGen.nodeView(argRef);
            if (i == 0 && calledFunction.hasInterfaceMethodSlot() && argView.type && argView.type->isInterface())
            {
                const MicroReg interfaceReg = CodeGen::payloadVirtualReg(*argPayload);
                builder.encodeLoadRegMem(argReg, interfaceReg, offsetof(Runtime::Interface, obj), MicroOpBits::B64, EncodeFlagsE::Zero);
            }
            else
            {
                builder.encodeLoadRegReg(argReg, CodeGen::payloadVirtualReg(*argPayload), MicroOpBits::B64, EncodeFlagsE::Zero);
            }
        }

        return static_cast<uint32_t>(args.size());
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
    codeGen.sema().appendResolvedCallArguments(codeGen.curNodeRef(), args);
    const uint32_t numAbiArgs = emitPreparedCallArguments(codeGen, calledFunction, callConv, args);

    const MicroReg calleeReg = CodeGen::payloadVirtualReg(*calleePayload);
    emitMicroABICallByReg(builder, callConvKind, calleeReg, numAbiArgs);

    auto* resultStorage        = codeGen.ctx().compiler().allocate<uint64_t>();
    *resultStorage             = 0;
    const auto&    nodePayload = codeGen.setPayload(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);
    const MicroReg resultReg   = CodeGen::payloadVirtualReg(nodePayload);
    builder.encodeLoadRegImm(resultReg, reinterpret_cast<uint64_t>(resultStorage), MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeLoadMemReg(resultReg, 0, callConv.intReturn, MicroOpBits::B64, EncodeFlagsE::Zero);

    return Result::Continue;
}

SWC_END_NAMESPACE();
