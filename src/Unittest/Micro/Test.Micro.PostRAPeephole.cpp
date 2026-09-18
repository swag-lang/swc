#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.Legalize.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.h"
#include "Support/Core/DataSegment.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runPostRaPeepholePass(MicroBuilder& builder, Encoder* encoder = nullptr)
    {
        MicroPostRaPeepholePass pass;
        MicroPassManager        passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, encoder, passContext);
    }

    Result runLegalizePass(MicroBuilder& builder, Encoder& encoder)
    {
        MicroLegalizePass pass;
        MicroPassManager  passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, &encoder, passContext);
    }

    bool hasLoadRegReg(const MicroBuilder& builder, MicroReg dst, MicroReg src)
    {
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::LoadRegReg)
                continue;

            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                continue;

            if (ops[0].reg == dst && ops[1].reg == src)
                return true;
        }

        return false;
    }

    bool hasBinaryRegRegDst(const MicroBuilder& builder, MicroReg dst, MicroOp op, MicroOpBits bits)
    {
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegReg)
                continue;

            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                continue;

            if (ops[0].reg == dst && ops[2].opBits == bits && ops[3].microOp == op)
                return true;
        }

        return false;
    }
}

SWC_TEST_BEGIN(PostRAPeephole_CompareFlagsAcrossJump_Preserved)
{
    constexpr MicroReg value = MicroReg::intReg(0);
    constexpr MicroReg flag  = MicroReg::intReg(1);
    constexpr MicroReg base  = MicroReg::intReg(2);
    for (const bool reusableProducer : {false, true})
    {
        MicroBuilder builder(ctx);
        const auto target = builder.createLabel();
        builder.emitLoadRegMem(value, base, 0, MicroOpBits::B64);
        if (reusableProducer)
            builder.emitOpBinaryRegImm(value, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(value, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, target);
        builder.emitRet();
        builder.placeLabel(target);
        builder.emitSetCondReg(flag, MicroCond::Above);
        builder.emitLoadMemReg(base, 8, flag, MicroOpBits::B8);
        builder.emitRet();

        SWC_RESULT(runPostRaPeepholePass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ScaledAddUsesAddressThenAdd)
{
    constexpr MicroReg result = MicroReg::intReg(0);
    constexpr MicroReg other  = MicroReg::intReg(1);
    constexpr MicroReg scaled = MicroReg::intReg(3);

    MicroBuilder builder(ctx);
    builder.emitOpBinaryRegImm(scaled, ApInt(5, 64), MicroOp::MultiplySigned, MicroOpBits::B32);
    builder.emitLoadAddressAmcRegMem(result, MicroOpBits::B32, other, scaled, 1, 0, MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0 ||
        !hasBinaryRegRegDst(builder, result, MicroOp::Add, MicroOpBits::B32))
        return Result::Error;

    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::LoadAddrAmcRegMem && ops &&
            ops[0].reg == result && ops[1].reg == scaled && ops[2].reg == scaled && ops[5].valueU64 == 4)
            return Result::Continue;
    }
    return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_MultiplyShiftResultUsesCopyDestination)
{
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg rcx = MicroReg::intReg(2);

    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(rax, ApInt(0xAAAAAAAB, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(rcx, rax, MicroOp::MultiplySigned, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rcx, ApInt(33, 64), MicroOp::ShiftRight, MicroOpBits::B64);
    builder.emitLoadRegReg(rax, rcx, MicroOpBits::B32);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;

    bool retargetedMultiply = false;
    bool retargetedShift    = false;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::OpBinaryRegReg && ops &&
            ops[0].reg == rax && ops[1].reg == rcx && ops[3].microOp == MicroOp::MultiplySigned)
            retargetedMultiply = true;
        if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops &&
            ops[0].reg == rax && ops[2].microOp == MicroOp::ShiftRight && ops[3].valueU64 == 33)
            retargetedShift = true;
    }
    if (!retargetedMultiply || !retargetedShift)
        return Result::Error;

    // A 31-bit shift can leave bit 32 set. Keep the narrowing copy that clears
    // the upper half instead of retargeting the 64-bit chain.
    MicroBuilder narrow(ctx);
    narrow.emitLoadRegImm(rax, ApInt(0xAAAAAAAB, 64), MicroOpBits::B64);
    narrow.emitOpBinaryRegReg(rcx, rax, MicroOp::MultiplySigned, MicroOpBits::B64);
    narrow.emitOpBinaryRegImm(rcx, ApInt(31, 64), MicroOp::ShiftRight, MicroOpBits::B64);
    narrow.emitLoadRegReg(rax, rcx, MicroOpBits::B32);
    narrow.emitRet();
    X64Encoder narrowEncoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(narrow, &narrowEncoder));
    return Backend::Unittest::countOpcode(narrow, MicroInstrOpcode::LoadRegReg) == 1 ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_BooleanOrSelectUsesComparisonFlags)
{
    const MicroReg     rsp     = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg result  = MicroReg::intReg(0);
    constexpr MicroReg value   = MicroReg::intReg(2);
    constexpr MicroReg low     = MicroReg::intReg(3);
    constexpr MicroReg high    = MicroReg::intReg(8);
    constexpr MicroReg outside = MicroReg::intReg(9);

    MicroBuilder builder(ctx);
    builder.emitCmpRegReg(value, low, MicroOpBits::B32);
    builder.emitSetCondReg(result, MicroCond::Below);
    builder.emitCmpRegReg(value, high, MicroOpBits::B32);
    builder.emitSetCondReg(value, MicroCond::Above);
    builder.emitOpBinaryRegReg(result, value, MicroOp::Or, MicroOpBits::B8);
    builder.emitLoadRegMem(result, rsp, 40, MicroOpBits::B32);
    builder.emitLoadCondRegReg(result, outside, MicroCond::NotEqual, MicroOpBits::B32);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 2 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 2 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::SetCondReg) != 0 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_Nop_Erased)
{
    MicroBuilder builder(ctx);
    builder.emitNop();
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::Nop) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_DoesNotForwardFromStoreClaimedByImmediateFold)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rbx  = MicroReg::intReg(3);
    constexpr MicroReg r9   = MicroReg::intReg(9);

    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(rbx, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadMemReg(base, 24, rbx, MicroOpBits::B64);
    builder.emitLoadRegMem(r9, base, 24, MicroOpBits::B64);
    builder.emitLoadRegImm(rbx, ApInt(9, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemImm) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    if (hasLoadRegReg(builder, r9, rbx))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_CopyForward_DoesNotCrossClaimedStoreReload)
{
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rax   = MicroReg::intReg(0);
    constexpr MicroReg rcx   = MicroReg::intReg(2);
    constexpr MicroReg r14   = MicroReg::intReg(14);
    constexpr MicroReg r15   = MicroReg::intReg(15);

    MicroBuilder builder(ctx);
    builder.emitLoadMemReg(stack, 24, r14, MicroOpBits::B64);
    builder.emitLoadRegReg(rax, r15, MicroOpBits::B64);
    builder.emitLoadRegMem(rcx, stack, 24, MicroOpBits::B64);
    builder.emitLoadRegReg(r14, rax, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (!hasLoadRegReg(builder, rcx, r14))
        return Result::Error;
    if (!hasLoadRegReg(builder, r14, rax))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ErasesStoreOverwrittenBeforeMemoryAccess)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg r8   = MicroReg::intReg(8);
    constexpr MicroReg r9   = MicroReg::intReg(9);

    MicroBuilder builder(ctx);
    builder.emitLoadMemReg(base, 16, r8, MicroOpBits::B16);
    builder.emitOpBinaryRegImm(r8, ApInt(1, 16), MicroOp::Add, MicroOpBits::B16);
    builder.emitLoadMemReg(base, 16, r9, MicroOpBits::B16);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_DoesNotEraseOverwrittenNonFrameStore)
{
    constexpr MicroReg base = MicroReg::intReg(12);
    constexpr MicroReg r8   = MicroReg::intReg(8);
    constexpr MicroReg r9   = MicroReg::intReg(9);

    MicroBuilder builder(ctx);
    builder.emitLoadMemReg(base, 16, r8, MicroOpBits::B16);
    builder.emitOpBinaryRegImm(r8, ApInt(1, 16), MicroOp::Add, MicroOpBits::B16);
    builder.emitLoadMemReg(base, 16, r9, MicroOpBits::B16);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ErasesOwnStoreReloadOnConditionalFallthrough)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg r8   = MicroReg::intReg(8);

    MicroBuilder        builder(ctx);
    const MicroLabelRef doneLabel = builder.createLabel();
    builder.emitLoadMemReg(base, 24, r8, MicroOpBits::B16);
    builder.emitCmpRegImm(r8, ApInt(0, 16), MicroOpBits::B16);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
    builder.emitLoadRegMem(r8, base, 24, MicroOpBits::B16);
    builder.placeLabel(doneLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ForwardsStoredValueToReload)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg r8   = MicroReg::intReg(8);
    constexpr MicroReg r9   = MicroReg::intReg(9);

    MicroBuilder builder(ctx);
    builder.emitLoadMemReg(base, 24, r8, MicroOpBits::B16);
    builder.emitCmpRegImm(r8, ApInt(0, 16), MicroOpBits::B16);
    builder.emitLoadRegMem(r9, base, 24, MicroOpBits::B16);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    if (!hasLoadRegReg(builder, r9, r8))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_CopyForward_StopsAtEncoderImplicitDef)
{
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg rdx = MicroReg::intReg(3);
    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);
    constexpr MicroReg r12 = MicroReg::intReg(12);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(r9, r12, 0, MicroOpBits::B64);
    builder.emitLoadRegImm(rax, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(r8, ApInt(11, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(rax, r8, MicroOp::MultiplyUnsigned, MicroOpBits::B64);
    builder.emitLoadRegReg(rdx, r9, MicroOpBits::B64);
    builder.emitLoadRegMem(r9, r12, 8, MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (!hasLoadRegReg(builder, rdx, r9))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPassHelpers_PhysicalLivenessReuseReplacesInstructionEffectsAndExitRoots)
{
    using MicroPassHelpers::MicroPhysLiveness;
    const CallConv&   conv = CallConv::get(CallConvKind::WindowsX64);
    MicroPhysLiveness reused;
    const std::array  bodyLengths = {12u, 0u, 20u, 20u};
    for (uint32_t round = 0; round < bodyLengths.size(); ++round)
    {
        MicroBuilder builder(ctx);
        for (uint32_t i = 0; i < bodyLengths[round]; ++i)
        {
            if (i == 0)
            {
                if (round % 2 == 0)
                    builder.emitCallReg(conv.intReturn, CallConvKind::WindowsX64);
                else
                    builder.emitNop();
            }
            else if (round % 2 == 0)
                builder.emitLoadRegReg(MicroReg::intReg(8), MicroReg::intReg(9), MicroOpBits::B64);
            else
                builder.emitLoadRegReg(MicroReg::floatReg(8), MicroReg::floatReg(9), MicroOpBits::B64);
        }
        builder.emitRet();

        MicroPassContext passCtx;
        passCtx.builder                 = &builder;
        passCtx.instructions            = &builder.instructions();
        passCtx.operands                = &builder.operands();
        passCtx.callConvKind            = CallConvKind::WindowsX64;
        passCtx.usesIntReturnRegOnRet   = round == 0 || round == 2;
        passCtx.usesFloatReturnRegOnRet = round == 0 || round == 3;
        MicroPassHelpers::computePhysicalLiveness(reused, passCtx);
        MicroPhysLiveness fresh;
        MicroPassHelpers::computePhysicalLiveness(fresh, passCtx);
        if (!reused.valid || !fresh.valid || reused.useDefs.size() != bodyLengths[round] + 1 ||
            reused.liveIn != fresh.liveIn || reused.liveOut != fresh.liveOut)
            return Result::Error;
        for (size_t i = 0; i < reused.useDefs.size(); ++i)
        {
            const MicroInstrUseDef& actual   = reused.useDefs[i];
            const MicroInstrUseDef& expected = fresh.useDefs[i];
            if (actual.isCall != expected.isCall || actual.callConv != expected.callConv ||
                !std::ranges::equal(actual.uses, expected.uses) || !std::ranges::equal(actual.defs, expected.defs))
                return Result::Error;
        }

        uint64_t exitRoots = (1ull << MicroPhysLiveness::bitOf(conv.stackPointer)) |
                             (1ull << MicroPhysLiveness::bitOf(conv.framePointer));
        for (const MicroReg reg : conv.intPersistentRegs)
            exitRoots |= 1ull << MicroPhysLiveness::bitOf(reg);
        for (const MicroReg reg : conv.floatPersistentRegs)
            exitRoots |= 1ull << MicroPhysLiveness::bitOf(reg);
        if (passCtx.usesIntReturnRegOnRet)
            exitRoots |= 1ull << MicroPhysLiveness::bitOf(conv.intReturn);
        if (passCtx.usesFloatReturnRegOnRet)
            exitRoots |= 1ull << MicroPhysLiveness::bitOf(conv.floatReturn);
        if (reused.liveOut.back() != exitRoots || reused.liveIn.back() != exitRoots)
            return Result::Error;

        // A failed request must not expose the previously valid result.
        MicroPassHelpers::computePhysicalLiveness(reused, MicroPassContext{});
        if (reused.valid || !reused.isLiveOut(0, conv.intReturn))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPassHelpers_CombinedFreshIndicesMatchSingleClassBounds)
{
    MicroBuilder     builder(ctx);
    MicroPassContext passCtx;
    passCtx.instructions = &builder.instructions();
    passCtx.operands     = &builder.operands();
    const auto matches = [&](uint32_t expectedInt, uint32_t expectedFloat) {
        uint32_t nextInt   = 42;
        uint32_t nextFloat = 43;
        MicroPassHelpers::computeNextVirtualRegIndices(passCtx, nextInt, nextFloat);
        return nextInt == expectedInt && nextFloat == expectedFloat &&
               nextInt == MicroPassHelpers::computeNextVirtualIntRegIndex(passCtx) &&
               nextFloat == MicroPassHelpers::computeNextVirtualFloatRegIndex(passCtx);
    };
    if (!matches(1, 1))
        return Result::Error;

    builder.emitLoadRegReg(MicroReg::virtualIntReg(123456), MicroReg::intReg(MicroReg::K_MAX_INDEX), MicroOpBits::B64);
    builder.emitLoadRegReg(MicroReg::virtualFloatReg(345678), MicroReg::floatReg(3), MicroOpBits::B64);
    if (!matches(123457, 345679))
        return Result::Error;

    passCtx.builder = &builder;
    builder.addVirtualRegForbiddenPhysReg(MicroReg::virtualIntReg(900000), MicroReg::intReg(10));
    builder.addVirtualRegForbiddenPhysReg(MicroReg::virtualFloatReg(950000), MicroReg::floatReg(3));
    // Only integer allocation observes the builder's hint, including virtuals
    // that have restrictions but do not yet appear in the instruction stream.
    if (!matches(900001, 345679))
        return Result::Error;
    builder.addVirtualRegForbiddenPhysReg(MicroReg::virtualIntReg(MicroReg::K_MAX_INDEX), MicroReg::intReg(10));
    if (!matches(MicroReg::K_MAX_INDEX, 345679))
        return Result::Error;

    passCtx.builder = nullptr;
    builder.emitLoadRegReg(MicroReg::virtualIntReg(MicroReg::K_MAX_INDEX - 1), MicroReg::intReg(10), MicroOpBits::B64);
    builder.emitLoadRegReg(MicroReg::virtualFloatReg(MicroReg::K_MAX_INDEX), MicroReg::floatReg(3), MicroOpBits::B64);
    if (!matches(MicroReg::K_MAX_INDEX, MicroReg::K_MAX_INDEX))
        return Result::Error;
    builder.emitLoadRegReg(MicroReg::virtualIntReg(MicroReg::K_MAX_INDEX), MicroReg::intReg(10), MicroOpBits::B64);
    if (!matches(MicroReg::K_MAX_INDEX, MicroReg::K_MAX_INDEX))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Legalize_LateMixedIssuesPreserveScratchNames)
{
    constexpr auto r8   = MicroReg::intReg(8);
    constexpr auto r9   = MicroReg::intReg(9);
    constexpr auto r10  = MicroReg::intReg(10);
    constexpr auto xmm3 = MicroReg::floatReg(3);
    constexpr auto xmm4 = MicroReg::floatReg(4);
    for (const bool floatFirst : {false, true})
    {
        MicroBuilder builder(ctx);
        for (uint32_t i = 0; i < 24; ++i)
            builder.emitNop();
        for (uint32_t pair = 0; pair < 2; ++pair)
        {
            for (uint32_t kind = 0; kind < 2; ++kind)
            {
                if ((kind == 0) == floatFirst)
                    builder.emitOpBinaryMemReg(r10, pair * 8, xmm3, MicroOp::FloatAdd, MicroOpBits::B64);
                else
                    builder.emitOpBinaryRegImm(pair == 0 ? r8 : r9, ApInt(0x123456789ABCDEF0ull, 64), MicroOp::Add, MicroOpBits::B64);
            }
        }
        // Both maxima occur after every issue, regardless of which register
        // file needs the first scratch. Repeated issues must advance each file.
        builder.emitLoadRegReg(MicroReg::virtualIntReg(1000), r10, MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::virtualFloatReg(2000), xmm4, MicroOpBits::B64);
        builder.emitRet();

        X64Encoder encoder(ctx);
        SWC_RESULT(runLegalizePass(builder, encoder));
        const auto& exclusions = builder.virtualRegForbiddenPhysRegs();
        if (exclusions.size() != 4)
            return Result::Error;
        for (uint32_t pair = 0; pair < 2; ++pair)
        {
            const auto intScratch   = MicroReg::virtualIntReg(1001 + pair);
            const auto floatScratch = MicroReg::virtualFloatReg(2001 + pair);
            if (!exclusions.contains(intScratch) || !exclusions.contains(floatScratch))
                return Result::Error;
            if (!hasBinaryRegRegDst(builder, floatScratch, MicroOp::FloatAdd, MicroOpBits::B64))
                return Result::Error;

            bool foundIntUse = false;
            for (const MicroInstr& inst : builder.instructions().view())
            {
                if (inst.op != MicroInstrOpcode::OpBinaryRegReg)
                    continue;
                const auto* ops = inst.ops(builder.operands());
                if (ops[0].reg == (pair == 0 ? r8 : r9) && ops[1].reg == intScratch && ops[3].microOp == MicroOp::Add)
                    foundIntUse = true;
            }
            if (!foundIntUse)
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Legalize_ScratchExcludesFirstReadsInAbiOrder)
{
    constexpr MicroReg r8   = MicroReg::intReg(8);
    constexpr MicroReg r9   = MicroReg::intReg(9);
    constexpr MicroReg r10  = MicroReg::intReg(10);
    constexpr MicroReg r11  = MicroReg::intReg(11);
    constexpr MicroReg r12  = MicroReg::intReg(12);
    constexpr MicroReg xmm3 = MicroReg::floatReg(3);
    constexpr MicroReg xmm4 = MicroReg::floatReg(4);
    const MicroReg     sp   = CallConv::get(CallConvKind::Swag).stackPointer;
    MicroBuilder       builder(ctx);
    builder.emitNop();
    builder.emitOpBinaryRegImm(r8, ApInt(0x123456789ABCDEF0ull, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r10, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegReg(r12, r9, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(MicroReg::intReg(0), r9, MicroOp::DivideUnsigned, MicroOpBits::B64);
    builder.emitLoadRegReg(xmm4, xmm3, MicroOpBits::B64);
    builder.emitLoadRegImm(r11, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadMemReg(sp, 0, r11, MicroOpBits::B64);
    builder.emitLoadMemReg(sp, 8, r12, MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runLegalizePass(builder, encoder));

    const auto& exclusions = builder.virtualRegForbiddenPhysRegs();
    if (exclusions.size() != 1)
        return Result::Error;
    const auto& regs = exclusions.begin()->second;
    // r10's read-modify-write needs its incoming value. r11/r12/xmm4 have
    // a definition first. r9 precedes r10 in ABI order despite the read order.
    // Division also consumes RDX implicitly through the encoder use/def contract.
    const MicroReg expected[] = {r8, MicroReg::intReg(0), MicroReg::intReg(3), r9, r10, xmm3};
    if (regs.size() != std::size(expected))
        return Result::Error;
    for (uint32_t i = 0; i < regs.size(); ++i)
    {
        if (regs[i] != expected[i])
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Legalize_ScratchExclusionsStopBeforeBarrierUses)
{
    constexpr MicroReg r8 = MicroReg::intReg(8);
    constexpr MicroReg r9 = MicroReg::intReg(9);
    for (const MicroInstrOpcode barrier : {MicroInstrOpcode::Label, MicroInstrOpcode::JumpCond, MicroInstrOpcode::CallIndirect})
    {
        MicroBuilder        builder(ctx);
        const MicroLabelRef target = builder.createLabel();
        builder.emitOpBinaryRegImm(r8, ApInt(0x123456789ABCDEF0ull, 64), MicroOp::Add, MicroOpBits::B64);
        if (barrier == MicroInstrOpcode::Label)
            builder.placeLabel(target);
        else if (barrier == MicroInstrOpcode::JumpCond)
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, target);
        else
            builder.emitCallReg(r9, CallConvKind::Swag);
        builder.emitOpBinaryRegImm(r9, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        if (barrier == MicroInstrOpcode::JumpCond)
            builder.placeLabel(target);
        builder.emitRet();

        X64Encoder encoder(ctx);
        SWC_RESULT(runLegalizePass(builder, encoder));

        const auto& exclusions = builder.virtualRegForbiddenPhysRegs();
        if (exclusions.size() != 1)
            return Result::Error;
        const auto& regs = exclusions.begin()->second;
        // Even the call's target and implicit ABI arguments are behind the barrier.
        if (regs.size() != 1 || regs[0] != r8)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Legalize_DoesNotPreserveDeadShiftRegisterAcrossJump)
{
    constexpr MicroReg rcx = MicroReg::intReg(2);
    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);

    MicroBuilder        builder(ctx);
    const MicroLabelRef doneLabel = builder.createLabel();
    builder.emitLoadRegImm(rcx, ApInt(1, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(r8, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(r9, ApInt(3, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(r8, r9, MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(doneLabel);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runLegalizePass(builder, encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;
    if (!hasLoadRegReg(builder, rcx, r9))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Legalize_RewritesB8SignedMultiplyRegMemToRax)
{
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg r10 = MicroReg::intReg(10);
    constexpr MicroReg r14 = MicroReg::intReg(14);

    MicroBuilder builder(ctx);
    builder.emitOpBinaryRegMem(r14, r10, 0, MicroOp::MultiplySigned, MicroOpBits::B8);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runLegalizePass(builder, encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 0)
        return Result::Error;
    if (!hasBinaryRegRegDst(builder, rax, MicroOp::MultiplySigned, MicroOpBits::B8))
        return Result::Error;
    if (!hasLoadRegReg(builder, r14, rax))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Legalize_ClearsPositiveFloatZero)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        for (const MicroReg dst : {MicroReg::floatReg(2), MicroReg::virtualFloatReg(1)})
        {
            MicroBuilder builder(ctx);
            builder.emitLoadRegImm(dst, ApInt(0, 64), bits);
            builder.emitRet();

            X64Encoder encoder(ctx);
            SWC_RESULT(runLegalizePass(builder, encoder));

            if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) != 1 ||
                Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0 ||
                Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0 ||
                !builder.codeRelocations().empty())
                return Result::Error;

            for (const MicroInstr& inst : builder.instructions().view())
            {
                if (inst.op != MicroInstrOpcode::ClearReg)
                    continue;
                const MicroInstrOperand* ops = inst.ops(builder.operands());
                if (ops[0].reg != dst || ops[1].opBits != bits)
                    return Result::Error;
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Legalize_KeepsNonzeroFloatBitsAndAddresses)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        const uint64_t negativeZero = bits == MicroOpBits::B32 ? 0x80000000ULL : 0x8000000000000000ULL;
        for (const uint64_t value : {negativeZero, uint64_t{1}})
        {
            MicroBuilder builder(ctx);
            builder.emitLoadRegImm(MicroReg::floatReg(2), ApInt(value, 64), bits);
            builder.emitRet();

            X64Encoder encoder(ctx);
            SWC_RESULT(runLegalizePass(builder, encoder));

            if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) != 0 ||
                Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
                return Result::Error;
        }
    }

    MicroBuilder builder(ctx);
    builder.emitLoadRegPtrImm(MicroReg::floatReg(2), 0);
    builder.emitLoadRegDataSegmentReloc(MicroReg::floatReg(3), DataSegmentKind::GlobalZero, 0);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runLegalizePass(builder, encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) != 0 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegPtrImm) != 1 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegPtrReloc) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A memory-destination operation on virtual registers reaches the encoder as
// it is: legalization used to read a virtual register as "not an integer" and
// rewrite every such form back into a load, a register operation and a store.
SWC_TEST_BEGIN(Legalize_KeepsMemoryDestinationAdd)
{
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg value = MicroReg::virtualIntReg(2);

    MicroBuilder builder(ctx);
    builder.emitOpBinaryMemReg(base, 8, value, MicroOp::Add, MicroOpBits::B32);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runLegalizePass(builder, encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The atomic exchange in particular: its register rewrite is a plain
// read-modify-write, so it must stay `xchg [mem], reg`.
SWC_TEST_BEGIN(Legalize_KeepsMemoryExchange)
{
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg value = MicroReg::virtualIntReg(2);

    MicroBuilder builder(ctx);
    builder.emitOpBinaryMemReg(base, 0, value, MicroOp::Exchange, MicroOpBits::B32);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runLegalizePass(builder, encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_DoesNotForwardB8SignedMultiplyImmediate)
{
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg r8  = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(r8, ApInt(2, 64), MicroOpBits::B8);
    builder.emitOpBinaryRegReg(rax, r8, MicroOp::MultiplySigned, MicroOpBits::B8);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// An integer reload consumed once by an addition folds into the addition's
// memory operand, the way float reloads already do.
SWC_TEST_BEGIN(PostRAPeephole_FoldsIntegerReloadIntoBinary)
{
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rax   = MicroReg::intReg(0);
    constexpr MicroReg r8    = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(r8, stack, 16, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(rax, r8, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegImm(r8, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The reloaded register is read again after the consumer: the load stays.
SWC_TEST_BEGIN(PostRAPeephole_KeepsIntegerReloadReadAfterConsumer)
{
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rax   = MicroReg::intReg(0);
    constexpr MicroReg r8    = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(r8, stack, 16, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(rax, r8, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(stack, 24, r8, MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A reload compared on the left folds into `cmp [mem], reg`.
SWC_TEST_BEGIN(PostRAPeephole_FoldsIntegerReloadIntoCompare)
{
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rax   = MicroReg::intReg(0);
    constexpr MicroReg rcx   = MicroReg::intReg(2);
    constexpr MicroReg r8    = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(r8, stack, 16, MicroOpBits::B32);
    builder.emitCmpRegReg(r8, rax, MicroOpBits::B32);
    builder.emitSetCondReg(rcx, MicroCond::Below);
    builder.emitLoadRegImm(r8, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpMemReg) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The byte multiply reads memory through rax alone; the fold would only hand
// the encoder a legalization nothing runs any more.
SWC_TEST_BEGIN(PostRAPeephole_KeepsByteMultiplyReload)
{
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rax   = MicroReg::intReg(0);
    constexpr MicroReg r8    = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(r8, stack, 16, MicroOpBits::B8);
    builder.emitOpBinaryRegReg(rax, r8, MicroOp::MultiplySigned, MicroOpBits::B8);
    builder.emitLoadRegImm(r8, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_SelfCopy_B64_Erased)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    builder.emitLoadRegReg(conv.intReturn, conv.intReturn, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_SelfCopy_IntB32_Preserved)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    builder.emitLoadRegReg(conv.intReturn, conv.intReturn, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_FallthroughJumpSkipsTrivialGap)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef nextLabel = builder.createLabel();

    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, nextLabel);
    builder.emitNop();
    builder.emitLoadRegReg(conv.intReturn, conv.intReturn, MicroOpBits::B64);
    builder.placeLabel(nextLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::Nop) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_DeadCompareBeforeRet_Erased)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    builder.emitCmpRegReg(conv.intRegs[0], conv.intRegs[1], MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_DeadCompareAfterRedundantJump_Erased)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef nextLabel = builder.createLabel();

    builder.emitCmpRegReg(conv.intRegs[0], conv.intRegs[1], MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, nextLabel);
    builder.placeLabel(nextLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_LiveCompareForBranch_Preserved)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef takenLabel = builder.createLabel();

    builder.emitCmpRegReg(conv.intRegs[0], conv.intRegs[1], MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, takenLabel);
    builder.emitRet();
    builder.placeLabel(takenLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_LoadCondRegRegKeepsCopyBecauseDestinationIsUseDef)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    builder.emitLoadRegImm(conv.intRegs[0], ApInt(1, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(conv.intRegs[2], ApInt(2, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(conv.intRegs[1], ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadCondRegReg(conv.intRegs[0], conv.intRegs[1], MicroCond::AboveOrEqual, MicroOpBits::B64);
    builder.emitLoadRegReg(conv.intRegs[2], conv.intRegs[0], MicroOpBits::B64);
    builder.emitCmpRegImm(conv.intRegs[2], ApInt(0, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_FlagReuse_SubThenCompareZero_CompareErased)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef takenLabel = builder.createLabel();

    builder.emitOpBinaryRegImm(conv.intRegs[0], ApInt(5, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitCmpRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, takenLabel);
    builder.emitRet();
    builder.placeLabel(takenLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    // The sub already set ZF; the redundant compare against zero is gone, but
    // the branch that consumes the flags stays.
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_FlagReuse_UnsafeCondition_ComparePreserved)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef takenLabel = builder.createLabel();

    builder.emitOpBinaryRegImm(conv.intRegs[0], ApInt(5, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitCmpRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    // 'Below' depends on CF, which `cmp r,0` clears but `sub` may set: not reusable.
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, takenLabel);
    builder.emitRet();
    builder.placeLabel(takenLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_FlagReuse_NonFlagProducer_ComparePreserved)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef takenLabel = builder.createLabel();

    // A plain copy does not set CPU flags, so the compare is load-bearing.
    builder.emitLoadRegReg(conv.intRegs[0], conv.intRegs[1], MicroOpBits::B64);
    builder.emitCmpRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, takenLabel);
    builder.emitRet();
    builder.placeLabel(takenLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ZeroToClear_LiveFlagsDead_Converted)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    // The zero is materialized then used as a memory base (not a foldable
    // immediate slot), so it stays genuinely live and flags are unused: it
    // becomes an xor-zeroing.
    builder.emitLoadRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(conv.intRegs[1], conv.intRegs[0], 0, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ZeroToClear_DeadReg_NotConverted)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    // The zero is never read before being overwritten: it must NOT become a
    // ClearReg (whose flag write would defeat dead-code elimination); leave it
    // as a plain mov-immediate for DCE to remove.
    builder.emitLoadRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(conv.intRegs[0], ApInt(5, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ZeroToClear_FlagsLive_NotConverted)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    // reg0 is live (used as a memory base below), but a setcc reads the flags
    // that xor-zeroing would clobber, so the mov-immediate must be preserved.
    builder.emitLoadRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitSetCondReg(conv.intRegs[2], MicroCond::NotEqual);
    builder.emitLoadRegMem(conv.intRegs[1], conv.intRegs[0], 0, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_SelfOperand_FoldsWhenDestinationHoldsTheSlot)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg xmm3 = MicroReg::floatReg(3);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(xmm3, base, 0x54, MicroOpBits::B32);
    builder.emitOpBinaryRegMem(xmm3, base, 0x54, MicroOp::FloatMultiply, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The rule walks back a bounded number of instructions looking for the load
// of the slot into the destination. When the destination's last write sits
// beyond that window, nothing is known about what it holds: the memory
// operand has to stay.
SWC_TEST_BEGIN(PostRAPeephole_SelfOperand_KeepsMemoryOperandWhenWindowExhausted)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg xmm3 = MicroReg::floatReg(3);
    constexpr MicroReg xmm4 = MicroReg::floatReg(4);
    constexpr MicroReg xmm5 = MicroReg::floatReg(5);
    constexpr MicroReg xmm6 = MicroReg::floatReg(6);

    MicroBuilder builder(ctx);
    builder.emitLoadRegReg(xmm3, xmm4, MicroOpBits::B32);
    for (uint32_t i = 0; i < 16; ++i)
        builder.emitOpBinaryRegReg(xmm5, xmm6, MicroOp::FloatAdd, MicroOpBits::B32);
    builder.emitOpBinaryRegMem(xmm3, base, 0x54, MicroOp::FloatMultiply, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_PartialFlagWritersPreserveIncomingZero)
{
    const auto& conv = CallConv::get(CallConvKind::Swag);
    for (const auto bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        const uint64_t width = getNumBits(bits);
        for (const auto op : {MicroOp::ShiftLeft, MicroOp::ShiftRight, MicroOp::ShiftArithmeticRight, MicroOp::RotateLeft, MicroOp::RotateRight})
        {
            for (const uint64_t count : {0ull, 1ull, width, width + 1})
            {
                MicroBuilder builder(ctx);
                builder.emitCmpRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
                builder.emitOpBinaryRegImm(conv.intRegs[1], ApInt(count, 64), op, bits);
                builder.emitSetCondReg(conv.intRegs[2], MicroCond::Equal);
                builder.emitRet();
                SWC_RESULT(runPostRaPeepholePass(builder));
                const bool keepsZero = op == MicroOp::RotateLeft || op == MicroOp::RotateRight || (count & (width - 1)) == 0;
                if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != (keepsZero ? 1u : 0u))
                    return Result::Error;
            }

            MicroBuilder builder(ctx);
            builder.emitCmpRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
            builder.emitOpBinaryRegReg(conv.intRegs[1], conv.intRegs[2], op, bits);
            builder.emitSetCondReg(conv.intRegs[3], MicroCond::Equal);
            builder.emitRet();
            SWC_RESULT(runPostRaPeepholePass(builder));
            // A register count can be zero at runtime.
            if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

// A copy's source is never forwarded into an exchange: its second operand is
// written as well, so `mov r12, rdx; xchg rdi, r12` must keep swapping r12.
SWC_TEST_BEGIN(PostRAPeephole_CopySourceNotForwardedIntoExchange)
{
    const auto&    conv = CallConv::get(CallConvKind::Swag);
    const MicroReg src  = conv.intRegs[0];
    const MicroReg dst  = conv.intRegs[1];
    const MicroReg peer = conv.intRegs[2];
    MicroBuilder   builder(ctx);
    builder.emitLoadRegReg(dst, src, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(peer, dst, MicroOp::Exchange, MicroOpBits::B64);
    builder.emitLoadRegReg(conv.intReturn, dst, MicroOpBits::B64);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::OpBinaryRegReg && (ops[0].reg != peer || ops[1].reg != dst))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

// `mov r, a; add r, b; cmp r, 0; je` - either the compare goes and the add
// keeps setting the flags, or the add becomes a flag-free `lea` and the
// compare stays. Never both in one sweep.
SWC_TEST_BEGIN(PostRAPeephole_FlagReuseKeepsItsProducer)
{
    const auto&    conv  = CallConv::get(CallConvKind::Swag);
    const MicroReg sum   = conv.intRegs[0];
    const MicroReg left  = conv.intRegs[1];
    const MicroReg right = conv.intRegs[2];
    MicroBuilder   builder(ctx);
    const auto     label = builder.createLabel();
    builder.emitLoadRegReg(sum, left, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(sum, right, MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(sum, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, label);
    builder.emitLoadRegReg(conv.intReturn, left, MicroOpBits::B64);
    builder.placeLabel(label);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    const bool compareKept = Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) == 1;
    const bool addKept     = Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) == 1;
    if (!compareKept && !addKept)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    uint32_t countDwordSelfMoves(const MicroBuilder& builder, MicroReg reg)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::LoadRegReg && ops && ops[0].reg == reg && ops[1].reg == reg && ops[2].opBits == MicroOpBits::B32)
                ++count;
        }
        return count;
    }
}

// Both paths into the join leave r8 a 32-bit result: the upper-half clear is
// a no-op there.
SWC_TEST_BEGIN(PostRAPeephole_UpperHalfClearAfterDwordJoin_Erased)
{
    const auto&        conv = CallConv::get(CallConvKind::Swag);
    constexpr MicroReg r8   = MicroReg::intReg(8);
    MicroBuilder       builder(ctx);
    const auto         label = builder.createLabel();
    builder.emitLoadRegImm(r8, ApInt(0x811C9DC5, 64), MicroOpBits::B32);
    builder.emitCmpRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, label);
    builder.emitOpBinaryRegImm(r8, ApInt(0x1000193, 64), MicroOp::MultiplySigned, MicroOpBits::B32);
    builder.placeLabel(label);
    builder.emitLoadRegReg(r8, r8, MicroOpBits::B32);
    builder.emitLoadRegReg(conv.intReturn, r8, MicroOpBits::B64);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    if (countDwordSelfMoves(builder, r8) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// One path widens r8 to a 64-bit sum: the join must still clear the upper half.
SWC_TEST_BEGIN(PostRAPeephole_UpperHalfClearAfterQwordPath_Kept)
{
    const auto&        conv = CallConv::get(CallConvKind::Swag);
    constexpr MicroReg r8   = MicroReg::intReg(8);
    MicroBuilder       builder(ctx);
    const auto         label = builder.createLabel();
    builder.emitLoadRegImm(r8, ApInt(7, 64), MicroOpBits::B32);
    builder.emitCmpRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, label);
    builder.emitOpBinaryRegReg(r8, conv.intRegs[1], MicroOp::Add, MicroOpBits::B64);
    builder.placeLabel(label);
    builder.emitLoadRegReg(r8, r8, MicroOpBits::B32);
    builder.emitLoadRegReg(conv.intReturn, r8, MicroOpBits::B64);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    if (countDwordSelfMoves(builder, r8) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A call forgets what the register held before it.
SWC_TEST_BEGIN(PostRAPeephole_UpperHalfClearAfterCall_Kept)
{
    const auto&        conv = CallConv::get(CallConvKind::Swag);
    constexpr MicroReg r10  = MicroReg::intReg(10);
    MicroBuilder       builder(ctx);
    builder.emitLoadRegImm(conv.intReturn, ApInt(7, 64), MicroOpBits::B32);
    builder.emitCallReg(r10, CallConvKind::Swag);
    builder.emitLoadRegReg(conv.intReturn, conv.intReturn, MicroOpBits::B32);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    if (countDwordSelfMoves(builder, conv.intReturn) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// r9 holds a 32-bit result, so the 32-bit copy into rsi copies all of it and
// the full-width reader can take r9 directly.
SWC_TEST_BEGIN(PostRAPeephole_DwordCopyOfClearUpperHalf_ForwardsToWideReader)
{
    const auto&        conv = CallConv::get(CallConvKind::Swag);
    constexpr MicroReg r9   = MicroReg::intReg(9);
    constexpr MicroReg r10  = MicroReg::intReg(10);
    constexpr MicroReg rsi  = MicroReg::intReg(6);
    MicroBuilder       builder(ctx);
    builder.emitLoadRegMem(r9, conv.intRegs[0], 0, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(r9, r10, MicroOp::Add, MicroOpBits::B32);
    builder.emitLoadRegReg(rsi, r9, MicroOpBits::B32);
    builder.emitLoadRegReg(conv.intReturn, rsi, MicroOpBits::B64);
    builder.emitLoadMemReg(conv.intRegs[0], 8, r9, MicroOpBits::B64);
    builder.emitLoadMemReg(conv.intRegs[0], 16, rsi, MicroOpBits::B64);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    if (!hasLoadRegReg(builder, conv.intReturn, r9))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Without the 32-bit producer the upper half of r9 is unknown: the reader
// must keep the truncated copy.
SWC_TEST_BEGIN(PostRAPeephole_DwordCopyOfWideValue_NotForwardedToWideReader)
{
    const auto&        conv = CallConv::get(CallConvKind::Swag);
    constexpr MicroReg r9   = MicroReg::intReg(9);
    constexpr MicroReg rsi  = MicroReg::intReg(6);
    MicroBuilder       builder(ctx);
    builder.emitLoadRegMem(r9, conv.intRegs[0], 0, MicroOpBits::B64);
    builder.emitLoadRegReg(rsi, r9, MicroOpBits::B32);
    builder.emitLoadRegReg(conv.intReturn, rsi, MicroOpBits::B64);
    builder.emitLoadMemReg(conv.intRegs[0], 8, r9, MicroOpBits::B64);
    builder.emitLoadMemReg(conv.intRegs[0], 16, rsi, MicroOpBits::B64);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    if (hasLoadRegReg(builder, conv.intReturn, r9))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A byte copy feeding a byte extension: the extension reads the source.
SWC_TEST_BEGIN(PostRAPeephole_ByteCopyForwardsIntoByteExtend)
{
    const auto&  conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder builder(ctx);
    builder.emitLoadRegReg(conv.intReturn, conv.intRegs[0], MicroOpBits::B8);
    builder.emitLoadZeroExtendRegReg(conv.intReturn, conv.intReturn, MicroOpBits::B32, MicroOpBits::B8);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    bool extendsSource = false;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::LoadZeroExtRegReg && ops && ops[1].reg == conv.intRegs[0])
            extendsSource = true;
    }
    if (!extendsSource)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A byte copy read at 32 bits: the reader keeps the copy.
SWC_TEST_BEGIN(PostRAPeephole_ByteCopyNotForwardedToDwordReader)
{
    const auto&  conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder builder(ctx);
    builder.emitLoadRegReg(conv.intRegs[1], conv.intRegs[0], MicroOpBits::B8);
    builder.emitLoadRegReg(conv.intReturn, conv.intRegs[1], MicroOpBits::B32);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    if (hasLoadRegReg(builder, conv.intReturn, conv.intRegs[0]))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A copy used only as the value of a memory update: the update reads the source.
SWC_TEST_BEGIN(PostRAPeephole_CopyForwardsIntoMemoryUpdate)
{
    const auto&  conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder builder(ctx);
    builder.emitLoadRegReg(conv.intReturn, conv.intRegs[1], MicroOpBits::B32);
    builder.emitOpBinaryMemReg(conv.intRegs[0], 0, conv.intReturn, MicroOp::Add, MicroOpBits::B32);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    bool readsSource = false;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::OpBinaryMemReg && ops && ops[1].reg == conv.intRegs[1])
            readsSource = true;
    }
    if (!readsSource)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A byte copy stored at 32 bits: the store keeps reading the copy.
SWC_TEST_BEGIN(PostRAPeephole_ByteCopyNotForwardedIntoDwordStore)
{
    const auto&  conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder builder(ctx);
    builder.emitLoadRegReg(conv.intReturn, conv.intRegs[1], MicroOpBits::B8);
    builder.emitLoadMemReg(conv.intRegs[0], 0, conv.intReturn, MicroOpBits::B32);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::LoadMemReg && ops && ops[1].reg == conv.intRegs[1])
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_RipFloatLoadFoldsIntoThreeOperandOp)
{
    constexpr MicroReg xmm0 = MicroReg::floatReg(0);
    constexpr MicroReg xmm1 = MicroReg::floatReg(1);
    const MicroReg     rip  = MicroReg::instructionPointer();

    MicroBuilder builder(ctx);
    builder.emitClearReg(xmm1, MicroOpBits::B32);
    builder.emitLoadRegMem(xmm1, rip, 0, MicroOpBits::B32);

    MicroInstrRef loadRef = MicroInstrRef::invalid();
    for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
        if (it->op == MicroInstrOpcode::LoadRegMem)
            loadRef = it.current;
    if (loadRef.isInvalid())
        return Result::Error;

    builder.addRelocation({
        .kind           = MicroRelocation::Kind::ConstantAddress,
        .form           = MicroRelocation::Form::Relative32,
        .instructionRef = loadRef,
        .constantShard  = 0,
        .constantOffset = 0,
    });
    builder.emitOpBinaryRegRegReg(xmm0, xmm0, xmm1, MicroOp::FloatMultiply, MicroOpBits::B32);

    builder.emitLoadRegReg(xmm1, xmm0, MicroOpBits::B64);
    builder.emitLoadRegMem(xmm0, rip, 0, MicroOpBits::B64);
    MicroInstrRef restoredLoadRef = MicroInstrRef::invalid();
    for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
        if (it->op == MicroInstrOpcode::LoadRegMem)
            restoredLoadRef = it.current;
    if (restoredLoadRef.isInvalid() || restoredLoadRef == loadRef)
        return Result::Error;
    builder.addRelocation({
        .kind           = MicroRelocation::Kind::ConstantAddress,
        .form           = MicroRelocation::Form::Relative32,
        .instructionRef = restoredLoadRef,
        .constantShard  = 0,
        .constantOffset = 8,
    });
    builder.emitOpBinaryRegRegReg(xmm0, xmm1, xmm0, MicroOp::FloatMultiply, MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) != 0 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegRegReg) != 0 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 2)
        return Result::Error;

    for (const MicroRelocation& relocation : builder.codeRelocations())
    {
        const MicroInstr* relocated = builder.instructions().ptr(relocation.instructionRef);
        if (!relocated || relocated->op != MicroInstrOpcode::OpBinaryRegMem)
            return Result::Error;
        const MicroInstrOperand* ops = relocated->ops(builder.operands());
        if (!ops || ops[0].reg != xmm0 || !ops[1].reg.isInstructionPointer() ||
            (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64) ||
            ops[3].microOp != MicroOp::FloatMultiply)
            return Result::Error;
    }

    // ANDPS/ANDPD read a full 128-bit memory operand while the relocated
    // scalar constant only owns four or eight bytes. Keep its scalar load.
    MicroBuilder bitwise(ctx);
    bitwise.emitClearReg(xmm1, MicroOpBits::B64);
    bitwise.emitLoadRegMem(xmm1, rip, 0, MicroOpBits::B64);
    MicroInstrRef maskLoadRef = MicroInstrRef::invalid();
    for (auto it = bitwise.instructions().view().begin(); it != bitwise.instructions().view().end(); ++it)
        if (it->op == MicroInstrOpcode::LoadRegMem)
            maskLoadRef = it.current;
    if (maskLoadRef.isInvalid())
        return Result::Error;
    bitwise.addRelocation({
        .kind           = MicroRelocation::Kind::ConstantAddress,
        .form           = MicroRelocation::Form::Relative32,
        .instructionRef = maskLoadRef,
        .constantShard  = 0,
        .constantOffset = 16,
    });
    bitwise.emitOpBinaryRegRegReg(xmm0, xmm0, xmm1, MicroOp::FloatAnd, MicroOpBits::B64);
    bitwise.emitRet();
    X64Encoder bitwiseEncoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(bitwise, &bitwiseEncoder));
    if (Backend::Unittest::countOpcode(bitwise, MicroInstrOpcode::LoadRegMem) != 1 ||
        Backend::Unittest::countOpcode(bitwise, MicroInstrOpcode::OpBinaryRegRegReg) != 1 ||
        bitwise.codeRelocations().front().instructionRef != maskLoadRef)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A scalar float copied only as the second operand of a three-operand
// operation: the operation reads the source.
SWC_TEST_BEGIN(PostRAPeephole_FloatCopyForwardsIntoThreeOperandOp)
{
    constexpr MicroReg xmm0 = MicroReg::floatReg(0);
    constexpr MicroReg xmm1 = MicroReg::floatReg(1);
    constexpr MicroReg xmm2 = MicroReg::floatReg(2);
    MicroBuilder       builder(ctx);
    builder.emitLoadRegReg(xmm1, xmm2, MicroOpBits::B32);
    builder.emitOpBinaryRegRegReg(xmm0, xmm0, xmm1, MicroOp::FloatMultiply, MicroOpBits::B32);
    builder.emitRet();
    SWC_RESULT(runPostRaPeepholePass(builder));

    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::OpBinaryRegRegReg && ops && ops[2].reg == xmm2)
            return Result::Continue;
    }
    return Result::Error;
}
SWC_TEST_END()

namespace
{
    // cmp rcx, 0xF0 ; mov rax, K ; mov rdx, other ; cmov(cond) rax, rdx ;
    // [rdx read again] ; ret
    void emitCarrySelect(MicroBuilder& builder, uint64_t kept, uint64_t selected, MicroCond cond, bool otherLive)
    {
        constexpr MicroReg rax = MicroReg::intReg(0);
        constexpr MicroReg rcx = MicroReg::intReg(1);
        constexpr MicroReg rdx = MicroReg::intReg(3);
        constexpr MicroReg r8  = MicroReg::intReg(8);

        builder.emitCmpRegImm(rcx, ApInt(0xF0, 64), MicroOpBits::B8);
        builder.emitLoadRegImm(rax, ApInt(kept, 64), MicroOpBits::B32);
        builder.emitLoadRegImm(rdx, ApInt(selected, 64), MicroOpBits::B32);
        builder.emitLoadCondRegReg(rax, rdx, cond, MicroOpBits::B32);
        if (otherLive)
            builder.emitLoadMemReg(r8, 0, rdx, MicroOpBits::B32);
        builder.emitRet();
    }

    // The carry instruction left in place of the select, and the constant
    // loaded into rax.
    bool findCarryResult(const MicroBuilder& builder, MicroInstrOpcode& outOp, uint64_t& outBase)
    {
        constexpr MicroReg rax = MicroReg::intReg(0);
        outOp                  = MicroInstrOpcode::Nop;
        outBase                = UINT64_MAX;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::LoadRegImm && ops[0].reg == rax)
                outBase = ops[2].valueU64;
            if (inst.op == MicroInstrOpcode::SubtractBorrowRegImm || inst.op == MicroInstrOpcode::AddCarryRegImm)
                outOp = inst.op;
            if (inst.op == MicroInstrOpcode::LoadCondRegReg)
                return false;
        }
        return outOp != MicroInstrOpcode::Nop;
    }
}

// `c < 0xF0 ? 3 : 4` subtracts the carry from 4.
SWC_TEST_BEGIN(PostRAPeephole_CarrySelectOfConstants_Borrows)
{
    MicroBuilder builder(ctx);
    emitCarrySelect(builder, 4, 3, MicroCond::Below, false);
    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    MicroInstrOpcode op   = MicroInstrOpcode::Nop;
    uint64_t         base = 0;
    if (!findCarryResult(builder, op, base) || op != MicroInstrOpcode::SubtractBorrowRegImm || base != 4)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// `c >= 0xF0 ? 8 : 7` subtracts the carry from 8, the constant selected
// without carry.
SWC_TEST_BEGIN(PostRAPeephole_CarrySelectOfConstants_BorrowsFromSelectedBase)
{
    MicroBuilder builder(ctx);
    emitCarrySelect(builder, 7, 8, MicroCond::AboveOrEqual, false);
    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    MicroInstrOpcode op   = MicroInstrOpcode::Nop;
    uint64_t         base = 0;
    if (!findCarryResult(builder, op, base) || op != MicroInstrOpcode::SubtractBorrowRegImm || base != 8)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// `c < 0xF0 ? 5 : 4` adds the carry to 4.
SWC_TEST_BEGIN(PostRAPeephole_CarrySelectOfConstants_Adds)
{
    MicroBuilder builder(ctx);
    emitCarrySelect(builder, 4, 5, MicroCond::Below, false);
    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    MicroInstrOpcode op   = MicroInstrOpcode::Nop;
    uint64_t         base = 0;
    if (!findCarryResult(builder, op, base) || op != MicroInstrOpcode::AddCarryRegImm || base != 4)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Constants two apart, or a selected register still read, keep the select.
SWC_TEST_BEGIN(PostRAPeephole_CarrySelectOfConstants_Kept)
{
    for (const bool otherLive : {false, true})
    {
        MicroBuilder builder(ctx);
        emitCarrySelect(builder, 4, otherLive ? 3 : 2, MicroCond::Below, otherLive);
        X64Encoder encoder(ctx);
        SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

        MicroInstrOpcode op   = MicroInstrOpcode::Nop;
        uint64_t         base = 0;
        if (findCarryResult(builder, op, base))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // xor eax, eax ; cmp ecx, <rhs> ; set(cond) al ; add eax, offset
    void emitCarryOffset(MicroBuilder& builder, MicroCond cond, bool compareWithZero, uint64_t offset)
    {
        constexpr MicroReg rax = MicroReg::intReg(0);
        constexpr MicroReg rcx = MicroReg::intReg(1);
        constexpr MicroReg rdx = MicroReg::intReg(3);
        constexpr MicroReg r8  = MicroReg::intReg(8);

        builder.emitClearReg(rax, MicroOpBits::B32);
        if (compareWithZero)
            builder.emitCmpRegImm(rcx, ApInt(uint64_t{0}, 64), MicroOpBits::B32);
        else
            builder.emitCmpRegReg(rcx, rdx, MicroOpBits::B32);
        builder.emitSetCondReg(rax, cond);
        builder.emitOpBinaryRegImm(rax, ApInt(offset, 64), MicroOp::Add, MicroOpBits::B32);
        builder.emitLoadMemReg(r8, 0, rax, MicroOpBits::B32);
        builder.emitRet();
    }

    bool hasCarryImmediate(const MicroBuilder& builder, MicroInstrOpcode op, uint64_t value)
    {
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == op && inst.ops(builder.operands())[2].valueU64 == value)
                return true;
        }
        return false;
    }
}

// setae al ; add eax, 9 is 10 - CF: SBB by -10, in the dword's own width.
SWC_TEST_BEGIN(PostRAPeephole_InverseCarryOffset_Borrows)
{
    MicroBuilder builder(ctx);
    emitCarryOffset(builder, MicroCond::AboveOrEqual, false, 9);
    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (!hasCarryImmediate(builder, MicroInstrOpcode::SubtractBorrowRegImm, 0xFFFFFFF6))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// sete al ; add eax, -10 turns into cmp ecx, 1 ; adc eax, -10, whose
// immediate stays within the dword the encoder takes.
SWC_TEST_BEGIN(PostRAPeephole_ZeroTestNegativeOffset_AddsDwordImmediate)
{
    MicroBuilder builder(ctx);
    emitCarryOffset(builder, MicroCond::Equal, true, 0xFFFFFFFFFFFFFFF6);
    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (!hasCarryImmediate(builder, MicroInstrOpcode::AddCarryRegImm, 0xFFFFFFF6))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// mov rax, rcx ; imul rax, K becomes the three-operand multiply.
SWC_TEST_BEGIN(PostRAPeephole_CopyIntoIntegerMultiply_TakesThreeOperands)
{
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg rcx = MicroReg::intReg(1);
    constexpr MicroReg r8  = MicroReg::intReg(8);

    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        MicroBuilder builder(ctx);
        builder.emitLoadRegReg(rax, rcx, bits);
        builder.emitOpBinaryRegImm(rax, ApInt(16843010, 64), MicroOp::MultiplySigned, bits);
        builder.emitLoadMemReg(r8, 0, rax, bits);
        builder.emitRet();

        X64Encoder encoder(ctx);
        SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

        bool folded = false;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == MicroInstrOpcode::LoadRegReg)
                return Result::Error;
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::OpBinaryRegRegImm && ops[0].reg == rax && ops[1].reg == rcx &&
                ops[2].opBits == bits && ops[4].valueU64 == 16843010)
                folded = true;
        }
        if (!folded)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

// An immediate past a signed dword has no three-operand form.
SWC_TEST_BEGIN(PostRAPeephole_WideMultiplyImmediate_Kept)
{
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg rcx = MicroReg::intReg(1);
    constexpr MicroReg r8  = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegReg(rax, rcx, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rax, ApInt(0x123456789ull, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
    builder.emitLoadMemReg(r8, 0, rax, MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegRegImm) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// imul rcx, K ; mov rax, rcx names the product where it is wanted.
SWC_TEST_BEGIN(PostRAPeephole_MultiplyIntoResultCopy_TakesThreeOperands)
{
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg rcx = MicroReg::intReg(1);
    constexpr MicroReg r8  = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(rcx, r8, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rcx, ApInt(16843010, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
    builder.emitLoadRegReg(rax, rcx, MicroOpBits::B64);
    // The multiplied register is reloaded, so nothing can read the product
    // through it and the copy cannot be forwarded away.
    builder.emitLoadRegMem(rcx, r8, 16, MicroOpBits::B64);
    builder.emitLoadMemReg(r8, 8, rax, MicroOpBits::B64);
    builder.emitLoadMemReg(r8, 24, rcx, MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    bool folded = false;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::LoadRegReg && ops[0].reg == rax && ops[1].reg == rcx)
            return Result::Error;
        if (inst.op == MicroInstrOpcode::OpBinaryRegRegImm && ops[0].reg == rax && ops[1].reg == rcx && ops[4].valueU64 == 16843010)
            folded = true;
    }
    return folded ? Result::Continue : Result::Error;
}
SWC_TEST_END()

// A multiplied register still read afterwards keeps its product.
SWC_TEST_BEGIN(PostRAPeephole_MultiplyStillRead_KeepsCopy)
{
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg rcx = MicroReg::intReg(1);
    constexpr MicroReg r8  = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(rcx, r8, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rcx, ApInt(16843010, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
    builder.emitLoadRegReg(rax, rcx, MicroOpBits::B64);
    builder.emitLoadMemReg(r8, 16, rcx, MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegRegImm) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // cmp rcx, rdx ; je .L ; [cmp again] ; setae al ; .L: ret
    void emitCompareAroundBranch(MicroBuilder& builder, bool sameCompare)
    {
        constexpr MicroReg rax = MicroReg::intReg(0);
        constexpr MicroReg rcx = MicroReg::intReg(1);
        constexpr MicroReg rdx = MicroReg::intReg(3);
        constexpr MicroReg r8  = MicroReg::intReg(8);

        const MicroLabelRef exit = builder.createLabel();
        builder.emitCmpRegReg(rcx, rdx, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, exit);
        builder.emitCmpRegReg(rcx, sameCompare ? rdx : r8, MicroOpBits::B64);
        builder.emitSetCondReg(rax, MicroCond::AboveOrEqual);
        builder.placeLabel(exit);
        builder.emitRet();
    }
}

// The exit block reads the flags the loop's compare left.
SWC_TEST_BEGIN(PostRAPeephole_CompareRepeatedAfterBranch_Erased)
{
    MicroBuilder builder(ctx);
    emitCompareAroundBranch(builder, true);
    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A comparison of other values is its own.
SWC_TEST_BEGIN(PostRAPeephole_DifferentCompareAfterBranch_Kept)
{
    MicroBuilder builder(ctx);
    emitCompareAroundBranch(builder, false);
    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
