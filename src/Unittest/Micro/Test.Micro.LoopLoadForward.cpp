#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.LoopLoadForward.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(LoopLoadForward_CarriesTheStoredElementIntoTheNextTrip)
{
    // `v = row[i]; ...; row[i + 1] = v'` in a rotated loop: the load reads
    // what the previous trip stored, so the value is carried in a register
    // and the preheader loads the first element. Variants:
    //   0 - the plain recurrence: forwarded.
    //   1 - another row of the same frame, 0x200 bytes away, is also stored:
    //       provably disjoint, forwarded.
    //   2 - a store through an unrelated pointer: may alias, kept.
    //   3 - a store to the loaded element itself: kept.
    //   4 - the loop is also entered by a jump: no preheader, kept.
    //   5 - the store runs before the load: not the previous trip's value, kept.
    for (uint32_t variant = 0; variant < 6; ++variant)
    {
        MicroBuilder   builder(ctx);
        X64Encoder     encoder(ctx);
        const MicroReg sp     = encoder.stackPointerReg();
        const MicroReg frame  = MicroReg::virtualIntReg(1);
        const MicroReg index  = MicroReg::virtualIntReg(2);
        const MicroReg value  = MicroReg::virtualIntReg(3);
        const MicroReg other  = MicroReg::virtualIntReg(4);
        const MicroReg row1   = MicroReg::virtualIntReg(5);
        const auto     header = builder.createLabel();
        builder.emitLoadRegReg(frame, sp, MicroOpBits::B64);
        builder.emitLoadRegReg(other, MicroReg::intReg(2), MicroOpBits::B64);
        builder.emitLoadAddressRegMem(row1, frame, 0x200, MicroOpBits::B64);
        builder.emitLoadRegImm(index, ApInt(0, 64), MicroOpBits::B64);
        if (variant == 4)
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, header);
        builder.placeLabel(header);
        if (variant == 5)
            builder.emitLoadAmcMemReg(frame, index, 8, 8, MicroOpBits::B64, value, MicroOpBits::B64);
        builder.emitLoadAmcRegMem(value, MicroOpBits::B64, frame, index, 8, 0, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(value, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
        if (variant != 5)
            builder.emitLoadAmcMemReg(frame, index, 8, 8, MicroOpBits::B64, value, MicroOpBits::B64);
        if (variant == 1)
            builder.emitLoadAmcMemReg(row1, index, 8, 8, MicroOpBits::B64, value, MicroOpBits::B64);
        if (variant == 2)
            builder.emitLoadAmcMemReg(other, index, 8, 0, MicroOpBits::B64, value, MicroOpBits::B64);
        if (variant == 3)
            builder.emitLoadAmcMemReg(frame, index, 8, 0, MicroOpBits::B64, value, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(index, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(index, ApInt(10, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, header);
        builder.emitRet();

        MicroPassContext passContext;
        passContext.taskContext  = &ctx;
        passContext.builder      = &builder;
        passContext.instructions = &builder.instructions();
        passContext.operands     = &builder.operands();
        passContext.encoder      = &encoder;
        MicroLoopLoadForwardPass pass;
        SWC_RESULT(pass.run(passContext));

        uint32_t loadsBefore = 0;
        uint32_t loadsAfter  = 0;
        bool     inLoop      = false;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == MicroInstrOpcode::Label)
                inLoop = true;
            if (inst.op == MicroInstrOpcode::LoadAmcRegMem)
                (inLoop ? loadsAfter : loadsBefore)++;
        }

        const bool forwarded = variant == 0 || variant == 1;
        if (forwarded != passContext.passChanged || loadsBefore != (forwarded ? 1u : 0u) || loadsAfter != (forwarded ? 0u : 1u))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
