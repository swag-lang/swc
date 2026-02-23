#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/Passes/Pass.CopyPropagation.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    void runCopyPropagationPass(MicroBuilder& builder)
    {
        MicroCopyPropagationPass pass;
        MicroPassManager         passManager;
        passManager.add(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        builder.runPasses(passManager, nullptr, passContext);
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

SWC_TEST_BEGIN(MicroCopyPropagation_ResolvesCopyChains)
{
    MicroBuilder builder(ctx);
    const MicroReg r8  = MicroReg::intReg(8);
    const MicroReg r9  = MicroReg::intReg(9);
    const MicroReg r10 = MicroReg::intReg(10);
    const MicroReg r11 = MicroReg::intReg(11);

    builder.emitLoadRegImm(r8, ApInt(uint64_t{7}, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(r9, r8, MicroOpBits::B64);
    builder.emitLoadRegReg(r10, r9, MicroOpBits::B64);
    builder.emitCmpRegReg(r11, r10, MicroOpBits::B64);

    runCopyPropagationPass(builder);

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          inst2    = instructionAt(builder, 2);
    const MicroInstr*          inst3    = instructionAt(builder, 3);
    if (!inst2 || !inst3)
        return Result::Error;

    const MicroInstrOperand* ops2 = inst2->ops(operands);
    if (inst2->op != MicroInstrOpcode::LoadRegReg || ops2[1].reg != r8)
        return Result::Error;

    const MicroInstrOperand* ops3 = inst3->ops(operands);
    if (inst3->op != MicroInstrOpcode::CmpRegReg || ops3[1].reg != r8)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroCopyPropagation_StopsAtLabel)
{
    MicroBuilder builder(ctx);
    const MicroReg r8  = MicroReg::intReg(8);
    const MicroReg r9  = MicroReg::intReg(9);
    const MicroReg r10 = MicroReg::intReg(10);
    const Ref      mid = builder.createLabel();

    builder.emitLoadRegImm(r8, ApInt(uint64_t{3}, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(r9, r8, MicroOpBits::B64);
    builder.placeLabel(mid);
    builder.emitCmpRegReg(r10, r9, MicroOpBits::B64);

    runCopyPropagationPass(builder);

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          inst3    = instructionAt(builder, 3);
    if (!inst3)
        return Result::Error;

    const MicroInstrOperand* ops3 = inst3->ops(operands);
    if (inst3->op != MicroInstrOpcode::CmpRegReg || ops3[1].reg != r9)
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
