#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.ConstantFolding.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runConstantFoldingPass(MicroBuilder& builder)
    {
        MicroConstantFoldingPass pass;
        MicroPassManager         passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    uint32_t countOpcode(const MicroBuilder& builder, MicroInstrOpcode opcode)
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

// load v1, 5; add v1, 3  ->  load v1, 8 (folded semantically)
SWC_TEST_BEGIN(ConstantFolding_FoldBinaryRegImm)
{
    const MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(5, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runConstantFoldingPass(builder));

    // The add is folded into a LoadRegImm. The original load is now dead
    // (removed by DCE later). We expect: load v1,5; load v1,8; ret.
    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 2)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// load v1, 42; mov v2, v1  ->  load v1, 42; load v2, 42
SWC_TEST_BEGIN(ConstantFolding_FoldCopyFromKnown)
{
    const MicroReg v1 = MicroReg::virtualIntReg(1);
    const MicroReg v2 = MicroReg::virtualIntReg(2);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(42, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(v2, v1, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runConstantFoldingPass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 2)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// load v1, 5; add v1, 3; shl v1, 2  ->  three LoadRegImm (5, 8, 32)
SWC_TEST_BEGIN(ConstantFolding_ChainedFold)
{
    const MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(5, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(2, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runConstantFoldingPass(builder));

    // Each binary op is folded into a LoadRegImm. Dead loads removed by DCE later.
    // Result: load v1,5; load v1,8; load v1,32; ret.
    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 3)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// clear v1; add v1, 7  ->  load v1, 7  (ClearReg tracked as v1=0)
SWC_TEST_BEGIN(ConstantFolding_FoldFromClearReg)
{
    const MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder   builder(ctx);

    builder.emitClearReg(v1, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(7, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runConstantFoldingPass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
