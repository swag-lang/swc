#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/MicroUseDefMap.h"
#include "Backend/Micro/Passes/Pass.StrengthReduction.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runStrengthReductionPass(MicroBuilder& builder)
    {
        MicroStrengthReductionPass pass;
        MicroPassManager           passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Host;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    MicroOp getFirstBinaryOp(const MicroBuilder& builder)
    {
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (ops)
                return ops[2].microOp;
        }

        return MicroOp::Add;
    }

    uint64_t getFirstBinaryImm(const MicroBuilder& builder)
    {
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (ops)
                return ops[3].valueU64;
        }

        return 0;
    }
}

// mul r, 8 -> shl r, 3
SWC_TEST_BEGIN(StrengthReduction_MultiplyPowerOfTwo)
{
    constexpr MicroReg r8 = MicroReg::intReg(8);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(r8, ApInt(8, 64), MicroOp::MultiplyUnsigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (getFirstBinaryOp(builder) != MicroOp::ShiftLeft)
        return Result::Error;
    if (getFirstBinaryImm(builder) != 3)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// mul r, 0 -> and r, 0
SWC_TEST_BEGIN(StrengthReduction_MultiplyByZero)
{
    constexpr MicroReg r8 = MicroReg::intReg(8);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(r8, ApInt(uint64_t{0}, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (getFirstBinaryOp(builder) != MicroOp::And)
        return Result::Error;
    if (getFirstBinaryImm(builder) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// mul r, 1 -> add r, 0
SWC_TEST_BEGIN(StrengthReduction_MultiplyByOne)
{
    constexpr MicroReg r8 = MicroReg::intReg(8);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(r8, ApInt(1, 64), MicroOp::MultiplyUnsigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (getFirstBinaryOp(builder) != MicroOp::Add)
        return Result::Error;
    if (getFirstBinaryImm(builder) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// mul r, 7 -> unchanged (not a power of two)
SWC_TEST_BEGIN(StrengthReduction_MultiplyNonPowerOfTwoUnchanged)
{
    constexpr MicroReg r8 = MicroReg::intReg(8);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(r8, ApInt(7, 64), MicroOp::MultiplyUnsigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (getFirstBinaryOp(builder) != MicroOp::MultiplyUnsigned)
        return Result::Error;
    if (getFirstBinaryImm(builder) != 7)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
