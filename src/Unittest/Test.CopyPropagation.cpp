#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.CopyPropagation.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runCopyPropagationPass(MicroBuilder& builder)
    {
        MicroCopyPropagationPass pass;
        MicroPassManager         passManager;
        passManager.addStartPass(pass);

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

    bool containsReg(MicroRegSpan regs, MicroReg reg)
    {
        for (const auto value : regs)
        {
            if (value == reg)
                return true;
        }

        return false;
    }
}

SWC_TEST_BEGIN(MicroCopyPropagation_ResolvesCopyChains)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);
    constexpr MicroReg r10 = MicroReg::intReg(10);
    constexpr MicroReg r11 = MicroReg::intReg(11);

    builder.emitLoadRegImm(r8, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(r9, r8, MicroOpBits::B64);
    builder.emitLoadRegReg(r10, r9, MicroOpBits::B64);
    builder.emitCmpRegReg(r11, r10, MicroOpBits::B64);

    SWC_RESULT(runCopyPropagationPass(builder));

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
    // A referenced label (jump target) must stop alias propagation.
    MicroBuilder        builder(ctx);
    constexpr MicroReg  r8  = MicroReg::intReg(8);
    constexpr MicroReg  r9  = MicroReg::intReg(9);
    constexpr MicroReg  r10 = MicroReg::intReg(10);
    const MicroLabelRef mid = builder.createLabel();

    builder.emitLoadRegImm(r8, ApInt(3, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(r9, r8, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, mid);
    builder.placeLabel(mid);
    builder.emitCmpRegReg(r10, r9, MicroOpBits::B64);

    SWC_RESULT(runCopyPropagationPass(builder));

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          inst4    = instructionAt(builder, 4);
    if (!inst4)
        return Result::Error;

    const MicroInstrOperand* ops4 = inst4->ops(operands);
    if (inst4->op != MicroInstrOpcode::CmpRegReg || ops4[1].reg != r9)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroCopyPropagation_PropagatesThroughUnreferencedLabel)
{
    // An unreferenced label (fall-through only) allows alias propagation.
    MicroBuilder        builder(ctx);
    constexpr MicroReg  r8  = MicroReg::intReg(8);
    constexpr MicroReg  r9  = MicroReg::intReg(9);
    constexpr MicroReg  r10 = MicroReg::intReg(10);
    const MicroLabelRef mid = builder.createLabel();

    builder.emitLoadRegImm(r8, ApInt(3, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(r9, r8, MicroOpBits::B64);
    builder.placeLabel(mid);
    builder.emitCmpRegReg(r10, r9, MicroOpBits::B64);

    SWC_RESULT(runCopyPropagationPass(builder));

    const MicroOperandStorage& operands = builder.operands();
    const MicroInstr*          inst3    = instructionAt(builder, 3);
    if (!inst3)
        return Result::Error;

    const MicroInstrOperand* ops3 = inst3->ops(operands);
    if (inst3->op != MicroInstrOpcode::CmpRegReg || ops3[1].reg != r8)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroCopyPropagation_CallUseDefDefinesTransientRegs)
{
    MicroBuilder builder(ctx);
    builder.emitCallReg(MicroReg::intReg(10), CallConvKind::Host);

    const MicroInstr* inst = instructionAt(builder, 0);
    if (!inst)
        return Result::Error;

    const MicroInstrUseDef useDef = inst->collectUseDef(builder.operands(), nullptr);
    if (!useDef.isCall)
        return Result::Error;

    const CallConv& conv = CallConv::host();
    for (const auto reg : conv.intArgRegs)
    {
        if (!containsReg(useDef.uses, reg))
            return Result::Error;
    }

    for (const auto reg : conv.floatArgRegs)
    {
        if (!containsReg(useDef.uses, reg))
            return Result::Error;
    }

    for (const auto reg : conv.intTransientRegs)
    {
        if (!containsReg(useDef.defs, reg))
            return Result::Error;
    }

    for (const auto reg : conv.floatTransientRegs)
    {
        if (!containsReg(useDef.defs, reg))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
