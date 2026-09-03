#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.LoopInvariantCodeMotion.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runLicmPass(MicroBuilder& builder)
    {
        MicroLoopInvariantCodeMotionPass pass;
        MicroPassManager                 passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    // Position of the first instruction with this opcode, or UINT32_MAX.
    uint32_t firstPositionOf(const MicroBuilder& builder, MicroInstrOpcode op)
    {
        uint32_t position = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == op)
                return position;
            ++position;
        }

        return std::numeric_limits<uint32_t>::max();
    }

    // A counted loop reading one word through a pointer parameter. The load
    // is emitted with `emitLoad`, so the same shape can carry a plain or a
    // volatile load.
    template<typename EmitLoad>
    void buildPollingLoop(MicroBuilder& builder, EmitLoad emitLoad)
    {
        constexpr MicroReg rcx   = MicroReg::intReg(2);
        constexpr MicroReg rax   = MicroReg::intReg(0);
        constexpr MicroReg base  = MicroReg::virtualIntReg(1);
        constexpr MicroReg count = MicroReg::virtualIntReg(2);
        constexpr MicroReg value = MicroReg::virtualIntReg(3);
        constexpr MicroReg acc   = MicroReg::virtualIntReg(4);

        const MicroLabelRef loopLabel = builder.createLabel();
        builder.emitLoadRegReg(base, rcx, MicroOpBits::B64);
        builder.emitLoadRegImm(count, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
        builder.emitLoadRegImm(acc, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        emitLoad(builder, value, base);
        builder.emitOpBinaryRegReg(acc, value, MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(count, ApInt(uint64_t{1}, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(count, ApInt(uint64_t{4}, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, loopLabel);
        builder.emitLoadRegReg(rax, acc, MicroOpBits::B64);
        builder.emitRet();
    }
}

// Control: a load nothing in the loop can alias moves to the preheader.
SWC_TEST_BEGIN(LICM_HoistsInvariantLoad)
{
    MicroBuilder builder(ctx);
    buildPollingLoop(builder, [](MicroBuilder& b, MicroReg value, MicroReg base) {
        b.emitLoadRegMem(value, base, 8, MicroOpBits::B64);
    });

    SWC_RESULT(runLicmPass(builder));

    if (firstPositionOf(builder, MicroInstrOpcode::LoadRegMem) > firstPositionOf(builder, MicroInstrOpcode::Label))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A volatile load reads memory on every iteration: the same loop keeps it.
SWC_TEST_BEGIN(LICM_KeepsVolatileLoadInLoop)
{
    MicroBuilder builder(ctx);
    buildPollingLoop(builder, [](MicroBuilder& b, MicroReg value, MicroReg base) {
        b.emitLoadVolatileRegMem(value, base, 8, MicroOpBits::B64);
    });

    SWC_RESULT(runLicmPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVolatileRegMem) != 1)
        return Result::Error;
    if (firstPositionOf(builder, MicroInstrOpcode::LoadVolatileRegMem) < firstPositionOf(builder, MicroInstrOpcode::Label))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
