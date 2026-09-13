#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.PostRADeadCodeElim.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runPostRaDeadCodeElimPass(MicroBuilder& builder, bool returnsValue = true)
    {
        MicroPostRaDeadCodeElimPass pass;
        MicroPassManager            passManager;
        passManager.addStartPass(pass);

        builder.setRetUsesAbiRegs(returnsValue, returnsValue);
        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }
}

SWC_TEST_BEGIN(PostRADeadCodeElim_PreservesAbiLiveOut)
{
    const CallConv&            conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder               builder(ctx);
    SmallVector<MicroInstrRef> liveDefinitions;
    for (const MicroReg reg : {conv.intReturn, conv.floatReturn, conv.stackPointer, conv.framePointer, conv.intPersistentRegs[0], conv.floatPersistentRegs[0]})
    {
        builder.emitLoadRegImm(reg, ApInt(7, 64), MicroOpBits::B64);
        liveDefinitions.push_back(builder.instructions().lastInstructionRef());
    }
    builder.emitLoadRegImm(conv.intTransientRegs[3], ApInt(9, 64), MicroOpBits::B64);
    const auto deadDefinition = builder.instructions().lastInstructionRef();
    builder.emitRet();

    SWC_RESULT(runPostRaDeadCodeElimPass(builder));
    for (const auto ref : liveDefinitions)
    {
        if (!builder.instructions().ptr(ref))
            return Result::Error;
    }
    if (builder.instructions().ptr(deadDefinition))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRADeadCodeElim_UnusedReturnRegistersAreDead)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);
    builder.emitLoadRegImm(conv.intReturn, ApInt(7, 64), MicroOpBits::B64);
    const auto intDefinition = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(conv.floatReturn, ApInt(9, 64), MicroOpBits::B64);
    const auto floatDefinition = builder.instructions().lastInstructionRef();
    builder.emitRet();

    SWC_RESULT(runPostRaDeadCodeElimPass(builder, false));
    if (builder.instructions().ptr(intDefinition) || builder.instructions().ptr(floatDefinition))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRADeadCodeElim_LoopBackEdgeKeepsCarriedDefinition)
{
    const CallConv&     conv    = CallConv::get(CallConvKind::Swag);
    const MicroReg      carried = conv.intTransientRegs[3];
    const MicroReg      dead    = conv.intTransientRegs[4];
    MicroBuilder        builder(ctx);
    const MicroLabelRef top = builder.createLabel();
    builder.emitLoadRegImm(carried, ApInt(7, 64), MicroOpBits::B64);
    const auto seed = builder.instructions().lastInstructionRef();
    builder.placeLabel(top);
    builder.emitCmpRegImm(carried, ApInt(10, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(carried, ApInt(8, 64), MicroOpBits::B64);
    const auto backEdgeValue = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(dead, ApInt(9, 64), MicroOpBits::B64);
    const auto deadDefinition = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runPostRaDeadCodeElimPass(builder));
    if (!builder.instructions().ptr(seed) || !builder.instructions().ptr(backEdgeValue))
        return Result::Error;
    if (builder.instructions().ptr(deadDefinition))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
