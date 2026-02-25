#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    Result runLoadStoreForwardingPass(MicroBuilder& builder)
    {
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

    RESULT_VERIFY(runLoadStoreForwardingPass(builder));

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

    RESULT_VERIFY(runLoadStoreForwardingPass(builder));

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          inst1    = instructionAt(builder, 1);
    if (!inst1)
        return Result::Error;

    const MicroInstrOperand* ops = inst1->ops(operands);
    if (inst1->op != MicroInstrOpcode::LoadRegImm || ops[1].opBits != MicroOpBits::B64 || ops[2].valueU64 != 123)
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
