#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroAbiCall.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void buildPreparedABIArguments(CodeGen& codeGen, std::span<const ResolvedCallArgument> args, SmallVector<MicroABICall::PreparedArg>& outArgs)
    {
        outArgs.clear();
        outArgs.reserve(args.size());

        for (const auto& arg : args)
        {
            const AstNodeRef argRef = arg.argRef;
            const auto*      argPayload = codeGen.payload(argRef);
            SWC_ASSERT(argPayload != nullptr);

            MicroABICall::PreparedArg preparedArg;
            preparedArg.srcReg = CodeGen::payloadVirtualReg(*argPayload);

            const auto argView = codeGen.nodeView(argRef);
            if (argView.type)
            {
                preparedArg.isFloat = argView.type->isFloat();
                if (preparedArg.isFloat)
                    preparedArg.numBits = static_cast<uint8_t>(argView.type->payloadFloatBits());
            }

            switch (arg.passKind)
            {
                case CallArgumentPassKind::Direct:
                    preparedArg.kind = MicroABICall::PreparedArgKind::Direct;
                    break;

                case CallArgumentPassKind::InterfaceObject:
                    preparedArg.kind = MicroABICall::PreparedArgKind::InterfaceObject;
                    break;

                default:
                    SWC_UNREACHABLE();
            }

            outArgs.push_back(preparedArg);
        }
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
    SmallVector<MicroABICall::PreparedArg> preparedArgs;
    buildPreparedABIArguments(codeGen, args, preparedArgs);
    const uint32_t numAbiArgs = MicroABICall::prepareArgs(builder, callConvKind, preparedArgs);

    const MicroReg calleeReg = CodeGen::payloadVirtualReg(*calleePayload);
    MicroABICall::callByReg(builder, callConvKind, calleeReg, numAbiArgs);

    auto* resultStorage        = codeGen.ctx().compiler().allocate<uint64_t>();
    *resultStorage             = 0;
    const auto&    nodePayload = codeGen.setPayload(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);
    const MicroReg resultReg   = CodeGen::payloadVirtualReg(nodePayload);
    builder.encodeLoadRegImm(resultReg, reinterpret_cast<uint64_t>(resultStorage), MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeLoadMemReg(resultReg, 0, callConv.intReturn, MicroOpBits::B64, EncodeFlagsE::Zero);

    return Result::Continue;
}

SWC_END_NAMESPACE();
