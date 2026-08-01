#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
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
        passContext.callConvKind = CallConvKind::Swag;
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

    uint32_t countBinaryRegRegOp(const MicroBuilder& builder, MicroOp op)
    {
        const MicroOperandStorage& operands = builder.operands();
        uint32_t                   count    = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegReg)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (ops && ops[3].microOp == op)
                ++count;
        }

        return count;
    }

    uint32_t countBinaryRegImmOp(const MicroBuilder& builder, MicroOp op)
    {
        const MicroOperandStorage& operands = builder.operands();
        uint32_t                   count    = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (ops && ops[2].microOp == op)
                ++count;
        }

        return count;
    }

    bool hasBinaryRegImm(const MicroBuilder& builder, MicroOp op, uint64_t value)
    {
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (ops && ops[2].microOp == op && ops[3].valueU64 == value)
                return true;
        }

        return false;
    }

    bool hasLoadRegImmValue(const MicroBuilder& builder, uint64_t value)
    {
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::LoadRegImm)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (ops && ops[2].valueU64 == value)
                return true;
        }

        return false;
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

// mul r, 8 is not reduced when the following branch still reads OF.
SWC_TEST_BEGIN(StrengthReduction_MultiplyPowerOfTwoKeepsLiveFlags)
{
    constexpr MicroReg r8 = MicroReg::intReg(8);
    MicroBuilder       builder(ctx);

    const MicroLabelRef done = builder.createLabel();

    builder.emitOpBinaryRegImm(r8, ApInt(8, 64), MicroOp::MultiplyUnsigned, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::NotOverflow, MicroOpBits::B32, done);
    builder.placeLabel(done);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (getFirstBinaryOp(builder) != MicroOp::MultiplyUnsigned)
        return Result::Error;
    if (getFirstBinaryImm(builder) != 8)
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

// div_u v1, 10 -> mulhi with the canonical magic constant, then shr 3.
SWC_TEST_BEGIN(StrengthReduction_UnsignedDivideMagicNoFixup)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(v1, ApInt(10, 64), MicroOp::DivideUnsigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (countBinaryRegImmOp(builder, MicroOp::DivideUnsigned) != 0)
        return Result::Error;
    if (countBinaryRegRegOp(builder, MicroOp::MultiplyHighUnsigned) != 1)
        return Result::Error;
    if (!hasLoadRegImmValue(builder, 0xCCCCCCCCCCCCCCCDull))
        return Result::Error;
    if (!hasBinaryRegImm(builder, MicroOp::ShiftRight, 3))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// div_u v1, 7 needs the add-fixup sequence: mulhi, sub, shr 1, add, shr.
SWC_TEST_BEGIN(StrengthReduction_UnsignedDivideMagicFixup)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(v1, ApInt(7, 64), MicroOp::DivideUnsigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (countBinaryRegImmOp(builder, MicroOp::DivideUnsigned) != 0)
        return Result::Error;
    if (countBinaryRegRegOp(builder, MicroOp::MultiplyHighUnsigned) != 1)
        return Result::Error;
    if (countBinaryRegRegOp(builder, MicroOp::Subtract) != 1)
        return Result::Error;
    if (countBinaryRegRegOp(builder, MicroOp::Add) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// idiv v1, 8 -> sign-bias sequence: sar 63, shr 61, add, sar 3.
SWC_TEST_BEGIN(StrengthReduction_SignedDividePow2)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(v1, ApInt(8, 64), MicroOp::DivideSigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (countBinaryRegImmOp(builder, MicroOp::DivideSigned) != 0)
        return Result::Error;
    if (!hasBinaryRegImm(builder, MicroOp::ShiftArithmeticRight, 3))
        return Result::Error;
    if (!hasBinaryRegImm(builder, MicroOp::ShiftRight, 61))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// idiv v1, 7 -> signed multiply-high expansion.
SWC_TEST_BEGIN(StrengthReduction_SignedDivideMagic)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(v1, ApInt(7, 64), MicroOp::DivideSigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (countBinaryRegImmOp(builder, MicroOp::DivideSigned) != 0)
        return Result::Error;
    if (countBinaryRegRegOp(builder, MicroOp::MultiplyHighSigned) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// mod_u v1, 10 -> divide expansion followed by r = n - q * 10.
SWC_TEST_BEGIN(StrengthReduction_UnsignedModuloMagic)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(v1, ApInt(10, 64), MicroOp::ModuloUnsigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (countBinaryRegImmOp(builder, MicroOp::ModuloUnsigned) != 0)
        return Result::Error;
    if (countBinaryRegRegOp(builder, MicroOp::MultiplyHighUnsigned) != 1)
        return Result::Error;
    if (!hasBinaryRegImm(builder, MicroOp::MultiplySigned, 10))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A negative signed divisor keeps the hardware divide.
SWC_TEST_BEGIN(StrengthReduction_SignedDivideNegativeConstantUnchanged)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(v1, ApInt(static_cast<uint64_t>(-3), 64), MicroOp::DivideSigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (countBinaryRegImmOp(builder, MicroOp::DivideSigned) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// Division by zero keeps the hardware divide (and its trap).
SWC_TEST_BEGIN(StrengthReduction_DivideByZeroUnchanged)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(v1, ApInt(uint64_t{0}, 64), MicroOp::DivideUnsigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (countBinaryRegImmOp(builder, MicroOp::DivideUnsigned) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// Narrow operand widths are not expanded.
SWC_TEST_BEGIN(StrengthReduction_NarrowDivideUnchanged)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitOpBinaryRegImm(v1, ApInt(10, 16), MicroOp::DivideUnsigned, MicroOpBits::B16);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (countBinaryRegImmOp(builder, MicroOp::DivideUnsigned) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// add v1, 0 in one branch should be removed when the defined value is dead at the join.
SWC_TEST_BEGIN(StrengthReduction_RemoveAddZeroDeadAcrossJoin)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    const MicroLabelRef labelThen = builder.createLabel();
    const MicroLabelRef labelJoin = builder.createLabel();

    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, labelThen);
    builder.emitLoadRegImm(v1, ApInt(1, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(0, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, labelJoin);
    builder.placeLabel(labelThen);
    builder.emitLoadRegImm(v1, ApInt(2, 64), MicroOpBits::B64);
    builder.placeLabel(labelJoin);
    builder.emitRet();

    SWC_RESULT(runStrengthReductionPass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
