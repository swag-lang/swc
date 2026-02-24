#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/Passes/Pass.ControlFlowSimplification.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    void runControlFlowSimplificationPass(MicroBuilder& builder)
    {
        MicroControlFlowSimplificationPass pass;
        MicroPassManager                   passManager;
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

SWC_TEST_BEGIN(MicroControlFlowSimplification_RemovesRedundantFlow)
{
    MicroBuilder   builder(ctx);
    const MicroReg r8        = MicroReg::intReg(8);
    const MicroReg r9        = MicroReg::intReg(9);
    const Ref      bodyLabel = builder.createLabel();
    const Ref      deadLabel = builder.createLabel();

    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, bodyLabel);
    builder.placeLabel(bodyLabel);
    builder.emitLoadRegImm(r8, ApInt(uint64_t{1}, 64), MicroOpBits::B64);
    builder.emitRet();
    builder.emitLoadRegImm(r9, ApInt(uint64_t{2}, 64), MicroOpBits::B64);
    builder.placeLabel(deadLabel);

    runControlFlowSimplificationPass(builder);

    if (builder.instructions().count() != 2)
        return Result::Error;

    const MicroInstr* inst0 = instructionAt(builder, 0);
    const MicroInstr* inst1 = instructionAt(builder, 1);
    if (!inst0 || !inst1)
        return Result::Error;

    if (inst0->op != MicroInstrOpcode::LoadRegImm || inst1->op != MicroInstrOpcode::Ret)
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
