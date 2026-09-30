#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.WebRename.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result renameWebs(MicroBuilder& builder, X64Encoder& encoder)
    {
        MicroSsaState    ssa;
        MicroPassContext context;
        context.builder      = &builder;
        context.instructions = &builder.instructions();
        context.operands     = &builder.operands();
        context.encoder      = &encoder;
        context.ssaState     = &ssa;
        MicroWebRenamePass pass;
        return pass.run(context);
    }
}

SWC_TEST_BEGIN(WebRename_SplitsOnlyStoredValuesHiddenByRegisterReuse)
{
    for (uint32_t variant = 0; variant < 4; ++variant)
    {
        MicroBuilder   builder(ctx);
        X64Encoder     encoder(ctx);
        const MicroReg sp       = encoder.stackPointerReg();
        const MicroReg value    = MicroReg::virtualFloatReg(1);
        const MicroReg readback = MicroReg::virtualFloatReg(2);
        builder.emitLoadRegMem(value, sp, 0x40, MicroOpBits::B64);
        builder.emitLoadMemReg(sp, 0x80, value, MicroOpBits::B64);
        builder.emitLoadRegMem(value, sp, 0x48, MicroOpBits::B64);
        const auto secondDefinition = builder.instructions().lastInstructionRef();
        builder.emitLoadMemReg(sp, 0x88, value, MicroOpBits::B64);
        const auto secondStore = builder.instructions().lastInstructionRef();
        if (variant != 1)
            builder.emitLoadRegMem(readback, sp, 0x80, MicroOpBits::B64);
        if (variant == 2)
            builder.emitLoadMemReg(sp, 0xA0, value, MicroOpBits::B128);
        if (variant == 3)
            builder.addVirtualRegForbiddenPhysReg(value, MicroReg::floatReg(0));
        builder.emitRet();
        SWC_RESULT(renameWebs(builder, encoder));
        const auto renamed = builder.instructions().ptr(secondDefinition)->ops(builder.operands())[0].reg;
        const auto stored  = builder.instructions().ptr(secondStore)->ops(builder.operands())[1].reg;
        if (renamed != stored || (renamed != value) != (variant == 0))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(WebRename_PreservesLiveJoinsAndDestructiveUpdates)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    const MicroReg sp          = encoder.stackPointerReg();
    const MicroReg value       = MicroReg::virtualFloatReg(1);
    const MicroReg readback    = MicroReg::virtualFloatReg(2);
    const auto     alternative = builder.createLabel();
    const auto     join        = builder.createLabel();
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B32, alternative);
    builder.emitLoadRegMem(value, sp, 0x40, MicroOpBits::B64);
    const auto firstDefinition = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, join);
    builder.placeLabel(alternative);
    builder.emitLoadRegMem(value, sp, 0x48, MicroOpBits::B64);
    const auto secondDefinition = builder.instructions().lastInstructionRef();
    builder.placeLabel(join);
    builder.emitOpBinaryRegReg(value, value, MicroOp::FloatMultiply, MicroOpBits::B64);
    const auto update = builder.instructions().lastInstructionRef();
    builder.emitLoadMemReg(sp, 0x80, value, MicroOpBits::B64);
    builder.emitLoadRegMem(value, sp, 0x50, MicroOpBits::B64);
    const auto independent = builder.instructions().lastInstructionRef();
    builder.emitLoadRegMem(readback, sp, 0x80, MicroOpBits::B64);
    builder.emitRet();
    SWC_RESULT(renameWebs(builder, encoder));
    const auto  first    = builder.instructions().ptr(firstDefinition)->ops(builder.operands())[0].reg;
    const auto  second   = builder.instructions().ptr(secondDefinition)->ops(builder.operands())[0].reg;
    const auto* updated  = builder.instructions().ptr(update)->ops(builder.operands());
    const auto  separate = builder.instructions().ptr(independent)->ops(builder.operands())[0].reg;
    if (first != second || updated[0].reg != first || updated[1].reg != first || separate == first)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
