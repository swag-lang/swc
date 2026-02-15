#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/Abi/ABICall.h"
#include "Backend/MachineCode/Abi/ABITypeNormalize.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void buildPreparedABIArguments(CodeGen& codeGen, std::span<const ResolvedCallArgument> args, SmallVector<ABICall::PreparedArg>& outArgs)
    {
        outArgs.clear();
        outArgs.reserve(args.size());

        for (const auto& arg : args)
        {
            const AstNodeRef argRef     = arg.argRef;
            const auto*      argPayload = codeGen.payload(argRef);
            SWC_ASSERT(argPayload != nullptr);

            ABICall::PreparedArg preparedArg;
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
                    preparedArg.kind = ABICall::PreparedArgKind::Direct;
                    break;

                case CallArgumentPassKind::InterfaceObject:
                    preparedArg.kind = ABICall::PreparedArgKind::InterfaceObject;
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
    MicroInstrBuilder&    builder        = codeGen.builder();
    const auto            calleeView     = codeGen.nodeView(nodeExprRef);
    const auto*           calleePayload  = codeGen.payload(calleeView.nodeRef);
    SWC_ASSERT(calleePayload != nullptr);
    const SymbolFunction& calledFunction = codeGen.curNodeView().sym->cast<SymbolFunction>();
    const CallConvKind    callConvKind   = calledFunction.callConvKind();
    const CallConv&       callConv       = CallConv::get(callConvKind);
    const auto            normalizedRet  = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.curNodeView().typeRef, ABITypeNormalize::Usage::Return);

    SmallVector<ResolvedCallArgument>      args;
    SmallVector<ABICall::PreparedArg> preparedArgs;
    codeGen.sema().appendResolvedCallArguments(codeGen.curNodeRef(), args);
    buildPreparedABIArguments(codeGen, args, preparedArgs);
    if (normalizedRet.isIndirect)
    {
        SWC_ASSERT(!callConv.intArgRegs.empty());
        SWC_ASSERT(normalizedRet.indirectSize != 0);

        void* indirectRetStorage = codeGen.ctx().compiler().allocateArray<uint8_t>(normalizedRet.indirectSize);

        MicroReg hiddenRetArgSrcReg = MicroReg::invalid();
        MicroReg hiddenRetArgTmpReg = MicroReg::invalid();
        SWC_ASSERT(callConv.tryPickIntScratchRegs(hiddenRetArgSrcReg, hiddenRetArgTmpReg));
        builder.encodeLoadRegImm(hiddenRetArgSrcReg, reinterpret_cast<uint64_t>(indirectRetStorage), MicroOpBits::B64, EncodeFlagsE::Zero);

        ABICall::PreparedArg hiddenRetArg;
        hiddenRetArg.srcReg  = hiddenRetArgSrcReg;
        hiddenRetArg.kind    = ABICall::PreparedArgKind::Direct;
        hiddenRetArg.isFloat = false;
        hiddenRetArg.numBits = 64;
        preparedArgs.insert(preparedArgs.begin(), hiddenRetArg);
    }

    const uint32_t numAbiArgs  = ABICall::prepareArgs(builder, callConvKind, preparedArgs);
    const auto&    nodePayload = codeGen.setPayload(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);
    const MicroReg resultReg   = CodeGen::payloadVirtualReg(nodePayload);

    auto* resultStorage = codeGen.ctx().compiler().allocate<uint64_t>();
    *resultStorage      = 0;

    ABICall::Return retMeta;
    retMeta.valuePtr   = resultStorage;
    retMeta.isVoid     = normalizedRet.isVoid;
    retMeta.isFloat    = normalizedRet.isFloat;
    retMeta.isIndirect = normalizedRet.isIndirect;
    retMeta.numBits    = normalizedRet.numBits;
    const MicroReg calleeReg = CodeGen::payloadVirtualReg(*calleePayload);
    ABICall::callByReg(builder, callConvKind, calleeReg, numAbiArgs, retMeta);

    if (normalizedRet.isIndirect)
    {
        builder.encodeLoadRegImm(resultReg, reinterpret_cast<uint64_t>(resultStorage), MicroOpBits::B64, EncodeFlagsE::Zero);
        builder.encodeLoadMemReg(resultReg, 0, callConv.intReturn, MicroOpBits::B64, EncodeFlagsE::Zero);
        return Result::Continue;
    }

    builder.encodeLoadRegImm(resultReg, reinterpret_cast<uint64_t>(resultStorage), MicroOpBits::B64, EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
