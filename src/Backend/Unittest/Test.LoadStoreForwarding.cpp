#include "pch.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    Result runLoadStoreForwardingPass(MicroBuilder& builder)
    {
        CallConv::setup();

        MicroLoadStoreForwardingPass pass;
        MicroPassManager             passManager;
        passManager.add(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    const MicroInstr* instructionAt(const MicroBuilder& builder, uint32_t index)
    {
        uint32_t currentIndex = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (currentIndex == index)
                return &inst;
            ++currentIndex;
        }

        return nullptr;
    }
}

SWC_TEST_BEGIN(MicroLoadStoreForwarding_ForwardsRegisterStore)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg baseReg = MicroReg::intReg(5);
    constexpr MicroReg srcReg  = MicroReg::intReg(8);
    constexpr MicroReg dstReg  = MicroReg::intReg(9);

    builder.emitLoadMemReg(baseReg, 16, srcReg, MicroOpBits::B64);
    builder.emitLoadRegMem(dstReg, baseReg, 16, MicroOpBits::B64);

    SWC_RESULT_VERIFY(runLoadStoreForwardingPass(builder));

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          inst1    = instructionAt(builder, 1);
    if (!inst1)
        return Result::Error;

    const MicroInstrOperand* ops = inst1->ops(operands);
    if (inst1->op != MicroInstrOpcode::LoadRegReg || ops[1].reg != srcReg || ops[2].opBits != MicroOpBits::B64)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroLoadStoreForwarding_ForwardsImmediateStore)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg baseReg = MicroReg::intReg(5);
    constexpr MicroReg dstReg  = MicroReg::intReg(10);

    builder.emitLoadMemImm(baseReg, 24, ApInt(123, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(dstReg, baseReg, 24, MicroOpBits::B64);

    SWC_RESULT_VERIFY(runLoadStoreForwardingPass(builder));

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          inst1    = instructionAt(builder, 1);
    if (!inst1)
        return Result::Error;

    const MicroInstrOperand* ops = inst1->ops(operands);
    if (inst1->op != MicroInstrOpcode::LoadRegImm || ops[1].opBits != MicroOpBits::B64 || ops[2].valueU64 != 123)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroLoadStoreForwarding_PromotesStackLoadsFromTrackedSlot)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg rsp  = MicroReg::intReg(4);
    constexpr MicroReg src  = MicroReg::intReg(8);
    constexpr MicroReg mid  = MicroReg::intReg(10);
    constexpr MicroReg dst0 = MicroReg::intReg(11);
    constexpr MicroReg dst1 = MicroReg::intReg(12);

    builder.emitLoadMemReg(rsp, 32, src, MicroOpBits::B64);
    builder.emitLoadRegMem(dst0, rsp, 32, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(mid, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegMem(dst1, rsp, 32, MicroOpBits::B64);

    SWC_RESULT_VERIFY(runLoadStoreForwardingPass(builder));

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          inst1    = instructionAt(builder, 1);
    const MicroInstr*          inst3    = instructionAt(builder, 3);
    if (!inst1 || !inst3)
        return Result::Error;

    const MicroInstrOperand* ops1 = inst1->ops(operands);
    const MicroInstrOperand* ops3 = inst3->ops(operands);
    if (!ops1 || !ops3)
        return Result::Error;

    if (inst1->op != MicroInstrOpcode::LoadRegReg || ops1[1].reg != src || ops1[2].opBits != MicroOpBits::B64)
        return Result::Error;
    if (inst3->op != MicroInstrOpcode::LoadRegReg || ops3[1].reg != src || ops3[2].opBits != MicroOpBits::B64)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroLoadStoreForwarding_DoesNotPromoteWhenSourceRegRedefined)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg src = MicroReg::intReg(8);
    constexpr MicroReg dst = MicroReg::intReg(11);

    builder.emitLoadMemReg(rsp, 32, src, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(src, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegMem(dst, rsp, 32, MicroOpBits::B64);

    SWC_RESULT_VERIFY(runLoadStoreForwardingPass(builder));

    const MicroInstr* inst2 = instructionAt(builder, 2);
    if (!inst2)
        return Result::Error;
    if (inst2->op != MicroInstrOpcode::LoadRegMem)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroLoadStoreForwarding_DoesNotPromoteAcrossLabelBarrier)
{
    MicroBuilder        builder(ctx);
    constexpr MicroReg  rsp      = MicroReg::intReg(4);
    constexpr MicroReg  src      = MicroReg::intReg(8);
    constexpr MicroReg  dst      = MicroReg::intReg(11);
    const MicroLabelRef labelRef = builder.createLabel();

    builder.emitLoadMemReg(rsp, 32, src, MicroOpBits::B64);
    builder.placeLabel(labelRef);
    builder.emitLoadRegMem(dst, rsp, 32, MicroOpBits::B64);

    SWC_RESULT_VERIFY(runLoadStoreForwardingPass(builder));

    const MicroInstr* inst2 = instructionAt(builder, 2);
    if (!inst2)
        return Result::Error;
    if (inst2->op != MicroInstrOpcode::LoadRegMem)
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
