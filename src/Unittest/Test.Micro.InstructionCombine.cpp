#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runInstCombinePass(MicroBuilder& builder)
    {
        MicroInstructionCombinePass pass;
        MicroPassManager            passManager;
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

    bool firstBinaryRegImm(const MicroBuilder& builder, MicroOp& outOp, uint64_t& outImm)
    {
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                return false;
            outOp  = ops[2].microOp;
            outImm = ops[3].valueU64;
            return true;
        }
        return false;
    }
}

// add v, 0  -> erased when v is dead.
SWC_TEST_BEGIN(InstCombine_Identity_AddZero_Erased)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(uint64_t{0}, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// and v, 0  -> ClearReg.
SWC_TEST_BEGIN(InstCombine_Absorbing_AndZero_BecomesClear)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(uint64_t{0}, 64), MicroOp::And, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::ClearReg) == 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// or v, ~0  -> LoadRegImm v, ~0.
SWC_TEST_BEGIN(InstCombine_Absorbing_OrAllOnes_BecomesLoadImm)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(~uint64_t{0}, 64), MicroOp::Or, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// add v, c1 ; add v, c2  -> add v, c1+c2.
SWC_TEST_BEGIN(InstCombine_Reassociate_AddAdd)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(4, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 1)
        return Result::Error;
    auto     op  = MicroOp::Add;
    uint64_t imm = 0;
    if (!firstBinaryRegImm(builder, op, imm))
        return Result::Error;
    if (op != MicroOp::Add || imm != 7)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// add v, 5 ; sub v, 3  -> add v, 2.
SWC_TEST_BEGIN(InstCombine_Reassociate_AddSub_PicksAdd)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(5, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 1)
        return Result::Error;
    auto     op  = MicroOp::Add;
    uint64_t imm = 0;
    if (!firstBinaryRegImm(builder, op, imm))
        return Result::Error;
    if (op != MicroOp::Add || imm != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// shl v, 2 ; shl v, 3  -> shl v, 5.
SWC_TEST_BEGIN(InstCombine_Reassociate_ShiftLeftChain)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(1, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(2, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 1)
        return Result::Error;
    auto     op  = MicroOp::Add;
    uint64_t imm = 0;
    if (!firstBinaryRegImm(builder, op, imm))
        return Result::Error;
    if (op != MicroOp::ShiftLeft || imm != 5)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// shl v, 60 ; shl v, 8  -> not folded (sum >= 64 for B64).
SWC_TEST_BEGIN(InstCombine_Reassociate_ShiftOverflow_NotFolded)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(1, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(60, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(8, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// xor v, v  -> ClearReg.
SWC_TEST_BEGIN(InstCombine_RegReg_XorSelf_BecomesClear)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v1, MicroOp::Xor, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::ClearReg) == 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// sub v, v  -> ClearReg.
SWC_TEST_BEGIN(InstCombine_RegReg_SubSelf_BecomesClear)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v1, MicroOp::Subtract, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::ClearReg) == 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// and v, v  -> erased when v is dead.
SWC_TEST_BEGIN(InstCombine_RegReg_AndSelf_DeadErased)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v1, MicroOp::And, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// mul v, c1 ; mul v, c2  -> mul v, c1*c2 (signed).
SWC_TEST_BEGIN(InstCombine_Reassociate_MulMulSigned)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(2, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(3, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(5, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 1)
        return Result::Error;
    auto     op  = MicroOp::Add;
    uint64_t imm = 0;
    if (!firstBinaryRegImm(builder, op, imm))
        return Result::Error;
    if (op != MicroOp::MultiplySigned || imm != 15)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// or v, c1 ; or v, c2  -> or v, c1|c2.
SWC_TEST_BEGIN(InstCombine_Reassociate_OrOr)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(0x0F, 64), MicroOp::Or, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(v1, ApInt(0xF0, 64), MicroOp::Or, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 1)
        return Result::Error;
    auto     op  = MicroOp::Add;
    uint64_t imm = 0;
    if (!firstBinaryRegImm(builder, op, imm))
        return Result::Error;
    if (op != MicroOp::Or || imm != 0xFF)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// LoadRegMem ; OpBinaryRegImm ; LoadMemReg  ->  OpBinaryMemImm
SWC_TEST_BEGIN(InstCombine_MemFold_Imm_Consecutive)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(2);
    constexpr MicroReg vt   = MicroReg::virtualIntReg(3);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegPtrImm(base, 0x1000);
    builder.emitLoadRegMem(vt, base, 8, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(vt, ApInt(7, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 8, vt, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::OpBinaryMemImm) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// LoadRegMem ; OpBinaryRegReg ; LoadMemReg  ->  OpBinaryMemReg
SWC_TEST_BEGIN(InstCombine_MemFold_Reg_Consecutive)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(2);
    constexpr MicroReg vt   = MicroReg::virtualIntReg(3);
    constexpr MicroReg rhs  = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegPtrImm(base, 0x1000);
    builder.emitLoadRegImm(rhs, ApInt(5, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(vt, base, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(vt, rhs, MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 0, vt, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Load ; <unrelated instr> ; Op ; Store  -> still folds (windowed scan).
SWC_TEST_BEGIN(InstCombine_MemFold_NonConsecutive)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(2);
    constexpr MicroReg vt   = MicroReg::virtualIntReg(3);
    constexpr MicroReg rhs  = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegPtrImm(base, 0x1000);
    builder.emitLoadRegMem(vt, base, 0, MicroOpBits::B64);
    // Materialize rhs between the load and the op (mimics the codegen shape).
    builder.emitLoadRegImm(rhs, ApInt(11, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(vt, rhs, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 0, vt, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// vt is read after the store -> must NOT fold.
SWC_TEST_BEGIN(InstCombine_MemFold_VtReadAfterStore_NotFolded)
{
    constexpr MicroReg base = MicroReg::virtualIntReg(2);
    constexpr MicroReg vt   = MicroReg::virtualIntReg(3);
    constexpr MicroReg out  = MicroReg::virtualIntReg(4);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegPtrImm(base, 0x1000);
    builder.emitLoadRegMem(vt, base, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(vt, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(base, 0, vt, MicroOpBits::B64);
    builder.emitLoadRegReg(out, vt, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runInstCombinePass(builder));

    // The triple cannot be folded because vt's post-op SSA value has 2 uses
    // (the store and the subsequent copy).
    if (countOpcode(builder, MicroInstrOpcode::OpBinaryMemImm) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
