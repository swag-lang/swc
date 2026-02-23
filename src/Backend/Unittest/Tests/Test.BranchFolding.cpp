#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/Passes/Pass.BranchFolding.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    void runBranchFoldingPass(MicroBuilder& builder)
    {
        MicroBranchFoldingPass pass;
        MicroPassManager       passManager;
        passManager.add(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        builder.runPasses(passManager, nullptr, passContext);
    }

    uint32_t instructionCount(const MicroBuilder& builder, MicroInstrOpcode opcode)
    {
        uint32_t result = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                ++result;
        }

        return result;
    }
}

SWC_TEST_BEGIN(MicroBranchFolding_ConstantConditions)
{
    MicroBuilder builder(ctx);
    const MicroReg r8         = MicroReg::intReg(8);
    const MicroReg r9         = MicroReg::intReg(9);
    const Ref      takenLabel = builder.createLabel();
    const Ref      doneLabel  = builder.createLabel();

    builder.emitLoadRegImm(r8, ApInt(uint64_t{4}, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(r8, ApInt(uint64_t{4}, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, takenLabel);

    builder.placeLabel(takenLabel);
    builder.emitLoadRegImm(r9, ApInt(uint64_t{1}, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(r9, ApInt(uint64_t{2}, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

    builder.placeLabel(doneLabel);
    builder.emitRet();

    runBranchFoldingPass(builder);

    if (instructionCount(builder, MicroInstrOpcode::JumpCond) != 1)
        return Result::Error;

    const MicroOperandStorage& operands = builder.operands();
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op != MicroInstrOpcode::JumpCond)
            continue;

        const MicroInstrOperand* ops = inst.ops(operands);
        if (ops[0].cpuCond != MicroCond::Unconditional)
            return Result::Error;
    }
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
