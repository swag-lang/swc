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
    uint32_t emitPreparedCallArguments(CodeGen& codeGen, const SymbolFunction& calledFunction, std::span<const ResolvedCallArgument> args)
    {
        const CallConvKind callConvKind = calledFunction.callConvKind();
        const CallConv&    callConv     = CallConv::get(callConvKind);

        MicroInstrBuilder& builder = codeGen.builder();
        SWC_ASSERT(args.size() <= callConv.intArgRegs.size());

        for (uint32_t i = 0; i < args.size(); ++i)
        {
            const auto&      arg        = args[i];
            const AstNodeRef argRef     = arg.argRef;
            const auto*      argPayload = codeGen.payload(argRef);
            SWC_ASSERT(argPayload != nullptr);

            const MicroReg argReg = callConv.intArgRegs[i];
            switch (arg.passKind)
            {
                case CallArgumentPassKind::Direct:
                    builder.encodeLoadRegReg(argReg, CodeGen::payloadVirtualReg(*argPayload), MicroOpBits::B64, EncodeFlagsE::Zero);
                    break;

                case CallArgumentPassKind::InterfaceObject:
                {
                    SWC_ASSERT(i == 0);
                    const MicroReg interfaceReg = CodeGen::payloadVirtualReg(*argPayload);
                    builder.encodeLoadRegMem(argReg, interfaceReg, offsetof(Runtime::Interface, obj), MicroOpBits::B64, EncodeFlagsE::Zero);
                    break;
                }

                default:
                    SWC_UNREACHABLE();
            }
        }

        return static_cast<uint32_t>(args.size());
    }
}

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    MicroInstrBuilder& builder = codeGen.builder();

    const auto  calleeView    = codeGen.nodeView(nodeExprRef);
    const auto* calleePayload = codeGen.payload(calleeView.nodeRef);
    SWC_ASSERT(calleePayload != nullptr);

    const SymbolFunction& calledFunction = codeGen.curNodeView().sym->cast<SymbolFunction>();
    const CallConvKind    callConvKind   = calledFunction.callConvKind();
    const CallConv&       callConv       = CallConv::get(callConvKind);

    SmallVector<ResolvedCallArgument> args;
    codeGen.sema().appendResolvedCallArguments(codeGen.curNodeRef(), args);
    const uint32_t numAbiArgs = emitPreparedCallArguments(codeGen, calledFunction, args);

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
