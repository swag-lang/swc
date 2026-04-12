#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/Passes/Pass.Peephole.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runDeadCodeEliminationPass(MicroBuilder& builder)
    {
        MicroDeadCodeEliminationPass pass;
        MicroPassManager             passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    Result runPeepholePass(MicroBuilder& builder, Encoder* encoder)
    {
        MicroPeepholePass pass;
        MicroPassManager  passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        return builder.runPasses(passManager, encoder, passContext);
    }

    uint32_t countInstruction(const MicroBuilder& builder, const MicroInstrOpcode opcode)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                ++count;
        }

        return count;
    }
}

SWC_TEST_BEGIN(MicroLivenessMetadata_RemovesDeadReturnRegisterWriteForVoidReturn)
{
    const CallConv& conv = CallConv::get(CallConvKind::Host);
    MicroBuilder    builder(ctx);

    builder.setRetUsesAbiRegs(false, false);
    builder.emitLoadRegImm(conv.intReturn, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runDeadCodeEliminationPass(builder));

    if (countInstruction(builder, MicroInstrOpcode::LoadRegImm) != 0)
        return Result::Error;
    if (countInstruction(builder, MicroInstrOpcode::Ret) != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroLivenessMetadata_RemovesDeadUnusedCallArgumentRegister)
{
    const CallConv& conv = CallConv::get(CallConvKind::Host);
    if (conv.intArgRegs.size() < 2)
        return Result::Continue;

    MicroBuilder builder(ctx);
    builder.setRetUsesAbiRegs(false, false);

    constexpr MicroReg calleeReg = MicroReg::intReg(11);
    const MicroReg     deadArgReg = conv.intArgRegs.back();

    uint8_t intArgMask = 0;
    const auto usedSlots = std::min<size_t>(conv.intArgRegs.size() - 1, 8);
    for (size_t i = 0; i < usedSlots; ++i)
        intArgMask |= static_cast<uint8_t>(1u << i);

    builder.emitLoadRegImm(deadArgReg, ApInt(11, 64), MicroOpBits::B64);
    builder.emitCallReg(calleeReg, CallConvKind::Host, intArgMask, 0);
    builder.emitRet();

    SWC_RESULT(runDeadCodeEliminationPass(builder));

    if (countInstruction(builder, MicroInstrOpcode::LoadRegImm) != 0)
        return Result::Error;
    if (countInstruction(builder, MicroInstrOpcode::CallIndirect) != 1)
        return Result::Error;
}
SWC_TEST_END()

#ifdef _M_X64
SWC_TEST_BEGIN(MicroLivenessMetadata_DoesNotFoldAmcLoadAcrossImplicitIndexClobber)
{
    MicroBuilder builder(ctx);

    builder.emitLoadRegMem(MicroReg::intReg(12), MicroReg::intReg(4), 0x160, MicroOpBits::B64);
    builder.emitLoadZeroExtendRegReg(MicroReg::intReg(3), MicroReg::intReg(12), MicroOpBits::B64, MicroOpBits::B32);
    builder.emitLoadRegMem(MicroReg::intReg(9), MicroReg::intReg(4), 0x138, MicroOpBits::B64);
    builder.emitLoadRegMem(MicroReg::intReg(10), MicroReg::intReg(9), 0, MicroOpBits::B64);
    builder.emitLoadAddressAmcRegMem(MicroReg::intReg(11), MicroOpBits::B64, MicroReg::intReg(10), MicroReg::intReg(3), 4, 0, MicroOpBits::B32);
    builder.emitLoadRegImm(MicroReg::intReg(8), ApInt(1000, 32), MicroOpBits::B32);
    builder.emitOpBinaryRegReg(MicroReg::intReg(0), MicroReg::intReg(8), MicroOp::MultiplyUnsigned, MicroOpBits::B32);
    builder.emitLoadRegMem(MicroReg::intReg(7), MicroReg::intReg(11), 0, MicroOpBits::B32);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPeepholePass(builder, &encoder));

    if (countInstruction(builder, MicroInstrOpcode::LoadAmcRegMem) != 0)
        return Result::Error;
    if (countInstruction(builder, MicroInstrOpcode::LoadAddrAmcRegMem) != 1)
        return Result::Error;
}
SWC_TEST_END()
#endif

SWC_END_NAMESPACE();

#endif
