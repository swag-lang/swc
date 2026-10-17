#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.StoreForwardSplit.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(StoreForwardSplit_SplitsWideLoadsBehindNarrowStoresOfTheLoop)
{
    // A loop reads sixteen bytes at [object + 0x18]. Variants:
    //   0 - two 8-byte stores of the same trip write both halves: split.
    //   1 - one 16-byte store writes them: forwards whole, kept.
    //   2 - four 4-byte stores: a half still waits on two stores, kept.
    //   3 - an 8-byte store straddles the halves: kept.
    //   4 - the stores precede the loop: only the first trip waits, kept.
    //   5 - the stores write another object: kept.
    //   6 - a pointer steps 0x38 bytes per trip and the stores write the next element's
    //       halves: they meet on the following trip, split.
    //   7 - the same stepped pointer, stores to a field the load never reads: kept.
    for (uint32_t variant = 0; variant < 8; ++variant)
    {
        MicroBuilder             builder(ctx);
        X64Encoder               encoder(ctx);
        Runtime::BuildCfgBackend backendCfg{};
        backendCfg.optimLevel = Runtime::BuildCfgBackendOptimLevel::O2;
        builder.setBackendBuildCfg(backendCfg);

        const MicroReg object  = MicroReg::virtualIntReg(1);
        const MicroReg other   = MicroReg::virtualIntReg(2);
        const MicroReg element = MicroReg::virtualIntReg(3);
        const MicroReg counter = MicroReg::virtualIntReg(4);
        const MicroReg low     = MicroReg::virtualFloatReg(1);
        const MicroReg high    = MicroReg::virtualFloatReg(2);
        const MicroReg wide    = MicroReg::virtualFloatReg(3);
        const auto     header  = builder.createLabel();
        const bool     stepped = variant == 6 || variant == 7;

        builder.emitLoadRegReg(object, MicroReg::intReg(1), MicroOpBits::B64);
        builder.emitLoadRegReg(other, MicroReg::intReg(2), MicroOpBits::B64);
        builder.emitLoadRegReg(element, object, MicroOpBits::B64);
        builder.emitLoadRegImm(counter, ApInt(0, 64), MicroOpBits::B64);
        builder.emitLoadRegMem(low, object, 0, MicroOpBits::B64);
        builder.emitLoadRegMem(high, object, 8, MicroOpBits::B64);
        if (variant == 4)
        {
            builder.emitLoadMemReg(object, 0x18, low, MicroOpBits::B64);
            builder.emitLoadMemReg(object, 0x20, high, MicroOpBits::B64);
        }

        builder.placeLabel(header);
        switch (variant)
        {
            case 0:
                builder.emitLoadMemReg(object, 0x18, low, MicroOpBits::B64);
                builder.emitLoadMemReg(object, 0x20, high, MicroOpBits::B64);
                break;
            case 1:
                builder.emitStoreVecMemReg(object, 0x18, wide, MicroOpBits::B128);
                break;
            case 2:
                for (uint64_t offset = 0x18; offset < 0x28; offset += 4)
                    builder.emitLoadMemReg(object, offset, low, MicroOpBits::B32);
                break;
            case 3:
                builder.emitLoadMemReg(object, 0x1C, low, MicroOpBits::B64);
                break;
            case 5:
                builder.emitLoadMemReg(other, 0x18, low, MicroOpBits::B64);
                builder.emitLoadMemReg(other, 0x20, high, MicroOpBits::B64);
                break;
            case 6:
                builder.emitLoadMemReg(object, 0x18 + 0x38, low, MicroOpBits::B64);
                builder.emitLoadMemReg(object, 0x20 + 0x38, high, MicroOpBits::B64);
                break;
            case 7:
                builder.emitLoadMemReg(object, 0x30 + 0x38, low, MicroOpBits::B64);
                break;
            default:
                break;
        }
        builder.emitLoadVecRegMem(wide, stepped ? element : object, 0x18, MicroOpBits::B128);
        builder.emitStoreVecMemReg(stepped ? element : object, 0, wide, MicroOpBits::B128);
        if (stepped)
            builder.emitOpBinaryRegImm(element, ApInt(0x38, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(counter, ApInt(5, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, header);
        builder.emitRet();

        MicroPassContext passContext;
        passContext.taskContext  = &ctx;
        passContext.builder      = &builder;
        passContext.instructions = &builder.instructions();
        passContext.operands     = &builder.operands();
        passContext.encoder      = &encoder;
        MicroStoreForwardSplitPass pass;
        SWC_RESULT(pass.run(passContext));

        const bool split = variant == 0 || variant == 6;
        if (split != passContext.passChanged ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != (split ? 0u : 1u))
            return Result::Error;
        if (!split)
            continue;

        // The two halves are read where the wide load was, and joined in its register.
        uint32_t halves = 0;
        bool     joined = false;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const auto* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::LoadRegMem && ops[1].reg == (stepped ? element : object) && ops[2].opBits == MicroOpBits::B64)
                halves += ops[3].valueU64 == 0x18 || ops[3].valueU64 == 0x20;
            if (inst.op == MicroInstrOpcode::OpBinaryRegRegReg && ops[4].microOp == MicroOp::VecUnpackLo64)
                joined = ops[0].reg == wide;
        }
        if (halves != 2 || !joined)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
