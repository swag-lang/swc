#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.SlpVectorize.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runSlpPass(MicroBuilder& builder, MicroSsaState& ssa, X64Encoder& encoder)
    {
        Runtime::BuildCfgBackend backendCfg{};
        backendCfg.optimLevel = Runtime::BuildCfgBackendOptimLevel::O2;
        backendCfg.vectorize  = true;
        builder.setBackendBuildCfg(backendCfg);

        MicroPassContext passContext;
        passContext.builder      = &builder;
        passContext.instructions = &builder.instructions();
        passContext.operands     = &builder.operands();
        passContext.encoder      = &encoder;
        passContext.ssaState     = &ssa;
        MicroSlpVectorizePass pass;
        return pass.run(passContext);
    }
}

SWC_TEST_BEGIN(SlpVectorize_UnpackableStores_DoesNotBuildSsa)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp = encoder.stackPointerReg();
    for (uint32_t lane = 0; lane < 4; ++lane)
    {
        const MicroReg value = MicroReg::virtualIntReg(lane + 1);
        builder.emitLoadRegImm(value, ApInt(lane, 32), MicroOpBits::B32);
        builder.emitLoadMemReg(sp, 0x40 + lane * 4, value, MicroOpBits::B32);
    }
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    if (ssa.isValid() || !ssa.values().empty())
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 4)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_PacksFloatMemoryArithmetic)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp = encoder.stackPointerReg();
    for (uint32_t lane = 0; lane < 4; ++lane)
    {
        const MicroReg value = MicroReg::virtualFloatReg(lane + 1);
        builder.emitLoadRegMem(value, sp, 0x40 + lane * 4, MicroOpBits::B32);
        builder.emitOpBinaryRegMem(value, sp, 0x60 + lane * 4, MicroOp::FloatAdd, MicroOpBits::B32);
        builder.emitLoadMemReg(sp, 0x80 + lane * 4, value, MicroOpBits::B32);
    }
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    uint32_t adds = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const auto* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::OpBinaryRegRegReg && ops[4].microOp == MicroOp::VecAddF32)
            ++adds;
    }
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != 2 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 1 || adds != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_PacksFloatMultiplyMemoryArithmetic)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp = encoder.stackPointerReg();
    for (uint32_t lane = 0; lane < 4; ++lane)
    {
        const MicroReg value = MicroReg::virtualFloatReg(lane + 1);
        builder.emitLoadRegMem(value, sp, 0x40 + lane * 4, MicroOpBits::B32);
        builder.emitOpBinaryRegMem(value, sp, 0x60 + lane * 4, MicroOp::FloatMultiply, MicroOpBits::B32);
        builder.emitLoadMemReg(sp, 0x80 + lane * 4, value, MicroOpBits::B32);
    }
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    uint32_t muls = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const auto* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::OpBinaryRegRegReg && ops[4].microOp == MicroOp::VecMulF32)
            ++muls;
    }
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != 2 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 1 || muls != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_PacksFloatDivideMemoryArithmetic)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp = encoder.stackPointerReg();
    for (uint32_t lane = 0; lane < 4; ++lane)
    {
        const MicroReg value = MicroReg::virtualFloatReg(lane + 1);
        builder.emitLoadRegMem(value, sp, 0x40 + lane * 4, MicroOpBits::B32);
        builder.emitOpBinaryRegMem(value, sp, 0x60 + lane * 4, MicroOp::FloatDivide, MicroOpBits::B32);
        builder.emitLoadMemReg(sp, 0x80 + lane * 4, value, MicroOpBits::B32);
    }
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    uint32_t divs = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const auto* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::OpBinaryRegRegReg && ops[4].microOp == MicroOp::VecDivF32)
            ++divs;
    }
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != 2 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 1 || divs != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_PacksFloatMinMemoryArithmetic)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp = encoder.stackPointerReg();
    for (uint32_t lane = 0; lane < 4; ++lane)
    {
        const MicroReg value = MicroReg::virtualFloatReg(lane + 1);
        builder.emitLoadRegMem(value, sp, 0x40 + lane * 4, MicroOpBits::B32);
        builder.emitOpBinaryRegMem(value, sp, 0x60 + lane * 4, MicroOp::FloatMin, MicroOpBits::B32);
        builder.emitLoadMemReg(sp, 0x80 + lane * 4, value, MicroOpBits::B32);
    }
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    uint32_t mins = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const auto* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::OpBinaryRegRegReg && ops[4].microOp == MicroOp::VecMinF32)
            ++mins;
    }
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != 2 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 1 || mins != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_PacksFloatSqrt)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp = encoder.stackPointerReg();
    for (uint32_t lane = 0; lane < 4; ++lane)
    {
        const MicroReg value = MicroReg::virtualFloatReg(lane + 1);
        builder.emitLoadRegMem(value, sp, 0x40 + lane * 4, MicroOpBits::B32);
        builder.emitOpBinaryRegReg(value, value, MicroOp::FloatSqrt, MicroOpBits::B32);
        builder.emitLoadMemReg(sp, 0x80 + lane * 4, value, MicroOpBits::B32);
    }
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    uint32_t sqrts = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const auto* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::VecUnaryRegReg && ops[3].microOp == MicroOp::VecSqrtF32)
            ++sqrts;
    }
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != 1 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 1 || sqrts != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_PacksFloatTruncToS32)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp = encoder.stackPointerReg();
    for (uint32_t lane = 0; lane < 4; ++lane)
    {
        const MicroReg input  = MicroReg::virtualFloatReg(lane + 1);
        const MicroReg output = MicroReg::virtualIntReg(lane + 1);
        builder.emitLoadRegMem(input, sp, 0x40 + lane * 4, MicroOpBits::B32);
        builder.emitOpBinaryRegReg(output, input, MicroOp::ConvertFloatToInt, MicroOpBits::B32);
        builder.emitLoadMemReg(sp, 0x80 + lane * 4, output, MicroOpBits::B32);
    }
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    uint32_t truncs = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const auto* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::VecUnaryRegReg && ops[3].microOp == MicroOp::VecTruncF32ToS32)
            ++truncs;
    }
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != 1 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 1 || truncs != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_PacksFloatAndWithScalarMask)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp   = encoder.stackPointerReg();
    const MicroReg mask = MicroReg::virtualFloatReg(20);
    builder.emitLoadRegImm(mask, ApInt(0x7FFFFFFF, 32), MicroOpBits::B32);
    for (uint32_t lane = 0; lane < 4; ++lane)
    {
        const MicroReg input  = MicroReg::virtualFloatReg(lane + 1);
        const MicroReg output = MicroReg::virtualFloatReg(lane + 5);
        builder.emitLoadRegMem(input, sp, 0x40 + lane * 4, MicroOpBits::B32);
        builder.emitLoadRegReg(output, input, MicroOpBits::B32);
        builder.emitOpBinaryRegReg(output, mask, MicroOp::FloatAnd, MicroOpBits::B32);
        builder.emitLoadMemReg(sp, 0x80 + lane * 4, output, MicroOpBits::B32);
    }
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    uint32_t splats = 0;
    uint32_t ands   = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const auto* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::VecShuffleRegRegImm && ops[3].valueU64 == 0)
            ++splats;
        if (inst.op == MicroInstrOpcode::OpBinaryRegRegReg && ops[4].microOp == MicroOp::VecAnd)
            ++ands;
    }
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != 1 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 1 || splats != 1 || ands != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_SplatsSharedArithmeticImmediate)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp = encoder.stackPointerReg();
    for (uint32_t group = 0; group < 2; ++group)
    {
        for (uint32_t lane = 0; lane < 4; ++lane)
        {
            const MicroReg value  = MicroReg::virtualIntReg(group * 4 + lane + 1);
            const uint64_t offset = group * 0x20 + lane * 4;
            builder.emitLoadRegMem(value, sp, 0x40 + offset, MicroOpBits::B32);
            builder.emitOpBinaryRegImm(value, ApInt(5, 32), MicroOp::Add, MicroOpBits::B32);
            builder.emitLoadMemReg(sp, 0x80 + offset, value, MicroOpBits::B32);
        }
    }
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    uint32_t splats = 0;
    uint32_t adds   = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const auto* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::VecShuffleRegRegImm && ops[3].valueU64 == 0)
            ++splats;
        if (inst.op == MicroInstrOpcode::OpBinaryRegRegReg && ops[4].microOp == MicroOp::VecAdd32)
            ++adds;
    }
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != 2 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 2 || splats != 1 || adds != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_KeepsSeedOrderAcrossRejectedMiddleGroup)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp = encoder.stackPointerReg();
    builder.emitClearReg(MicroReg::virtualFloatReg(100), MicroOpBits::B128);
    for (uint32_t group = 0; group < 3; ++group)
    {
        for (uint32_t lane = 0; lane < 4; ++lane)
        {
            const MicroReg value = MicroReg::virtualIntReg(1 + group * 4 + lane);
            if (group == 1)
                builder.emitLoadRegImm(value, ApInt(lane + 1, 32), MicroOpBits::B32);
            else
            {
                builder.emitLoadRegMem(value, sp, 0x40 + group * 16 + lane * 4, MicroOpBits::B32);
                builder.emitOpBinaryRegImm(value, ApInt(1, 8), MicroOp::ShiftLeft, MicroOpBits::B32);
            }
            builder.emitLoadMemReg(sp, 0x100 + group * 16 + lane * 4, value, MicroOpBits::B32);
        }
    }
    builder.emitClearReg(MicroReg::intReg(10), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    uint32_t packedStores = 0;
    uint32_t scalarStores = 0;
    uint32_t packedLoads  = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const auto* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::LoadVecRegMem)
        {
            if (packedLoads >= 2 || ops[3].valueU64 != 0x40 + packedLoads * 32 || ops[0].reg.index() <= 100)
                return Result::Error;
            ++packedLoads;
        }
        if (inst.op == MicroInstrOpcode::StoreVecMemReg)
        {
            if (packedStores >= 2 || ops[3].valueU64 != 0x100 + packedStores * 32)
                return Result::Error;
            ++packedStores;
        }
        if (inst.op == MicroInstrOpcode::LoadMemReg)
        {
            if (scalarStores >= 4 || ops[3].valueU64 != 0x110 + scalarStores * 4)
                return Result::Error;
            ++scalarStores;
        }
    }
    if (packedStores != 2 || packedLoads != 2 || scalarStores != 4)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_PermutationsKeepTheFirstMaterializedTuple)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp = encoder.stackPointerReg();
    for (uint32_t lane = 0; lane < 4; ++lane)
    {
        const MicroReg value = MicroReg::virtualIntReg(lane + 1);
        builder.emitLoadRegMem(value, sp, 0x40 + lane * 4, MicroOpBits::B32);
        builder.emitOpBinaryRegImm(value, ApInt(1, 8), MicroOp::ShiftLeft, MicroOpBits::B32);
    }
    constexpr std::array<std::array<uint32_t, 4>, 3> permutations = {{{0, 1, 2, 3}, {1, 0, 3, 2}, {3, 2, 1, 0}}};
    for (uint32_t group = 0; group < permutations.size(); ++group)
    {
        for (uint32_t lane = 0; lane < 4; ++lane)
            builder.emitLoadMemReg(sp, 0x100 + group * 16 + lane * 4, MicroReg::virtualIntReg(permutations[group][lane] + 1), MicroOpBits::B32);
    }
    builder.emitClearReg(MicroReg::intReg(10), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    std::array<MicroReg, 3>           storedRegs;
    std::array<MicroReg, 2>           shuffledRegs;
    uint32_t                          stores     = 0;
    uint32_t                          shuffles   = 0;
    MicroReg                          firstTuple = MicroReg::invalid();
    constexpr std::array<uint64_t, 2> controls   = {0xB1, 0x1B};
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const auto* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::VecShuffleRegRegImm)
        {
            if (shuffles >= controls.size() || ops[3].valueU64 != controls[shuffles])
                return Result::Error;
            if (shuffles == 0)
                firstTuple = ops[1].reg;
            else if (ops[1].reg != firstTuple)
                return Result::Error;
            shuffledRegs[shuffles++] = ops[0].reg;
        }
        else if (inst.op == MicroInstrOpcode::StoreVecMemReg)
        {
            if (stores >= storedRegs.size() || ops[3].valueU64 != 0x100 + stores * 16)
                return Result::Error;
            storedRegs[stores++] = ops[1].reg;
        }
    }
    if (stores != 3 || shuffles != 2 || storedRegs[0] != firstTuple || storedRegs[1] != shuffledRegs[0] || storedRegs[2] != shuffledRegs[1])
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != 1 ||
        Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_PermutedLeafLoadsKeepCanonicalLaneOrder)
{
    for (const bool foldedRead : {false, true})
    {
        MicroBuilder                      builder(ctx);
        X64Encoder                        encoder(ctx);
        MicroSsaState                     ssa;
        const MicroReg                    sp    = encoder.stackPointerReg();
        constexpr std::array<uint32_t, 4> order = {2, 0, 3, 1};
        for (uint32_t lane = 0; lane < order.size(); ++lane)
        {
            const MicroReg value  = MicroReg::virtualIntReg(lane + 1);
            const uint64_t offset = 0x40 + order[lane] * 4;
            if (foldedRead)
            {
                builder.emitLoadRegMem(value, sp, 0x80 + lane * 4, MicroOpBits::B32);
                builder.emitOpBinaryRegMem(value, sp, offset, MicroOp::Add, MicroOpBits::B32);
            }
            else
            {
                builder.emitLoadRegMem(value, sp, offset, MicroOpBits::B32);
                builder.emitOpBinaryRegImm(value, ApInt(1, 8), MicroOp::ShiftLeft, MicroOpBits::B32);
            }
            builder.emitLoadMemReg(sp, 0x100 + lane * 4, value, MicroOpBits::B32);
        }
        builder.emitClearReg(MicroReg::intReg(10), MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runSlpPass(builder, ssa, encoder));
        MicroReg permutedLoad = MicroReg::invalid();
        uint32_t loads        = 0;
        uint32_t shuffles     = 0;
        uint32_t stores       = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const auto* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::LoadVecRegMem)
            {
                const uint64_t expectedOffset = foldedRead && loads == 0 ? 0x80 : 0x40;
                if (loads >= (foldedRead ? 2u : 1u) || ops[1].reg != sp || ops[3].valueU64 != expectedOffset)
                    return Result::Error;
                if (expectedOffset == 0x40)
                    permutedLoad = ops[0].reg;
                ++loads;
            }
            else if (inst.op == MicroInstrOpcode::VecShuffleRegRegImm)
            {
                // Recreate lanes 2,0,3,1 from the canonical packed load.
                if (shuffles++ != 0 || !permutedLoad.isValid() || ops[1].reg != permutedLoad || ops[3].valueU64 != 0x72)
                    return Result::Error;
            }
            else if (inst.op == MicroInstrOpcode::StoreVecMemReg)
            {
                if (stores++ != 0 || ops[0].reg != sp || ops[3].valueU64 != 0x100)
                    return Result::Error;
            }
        }
        if (loads != (foldedRead ? 2u : 1u) || shuffles != 1 || stores != 1 ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 0)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_StackAndOneParameterAreTheRootLimit)
{
    for (const bool secondParameter : {false, true})
    {
        MicroBuilder   builder(ctx);
        X64Encoder     encoder(ctx);
        MicroSsaState  ssa;
        const MicroReg sp     = encoder.stackPointerReg();
        const MicroReg first  = MicroReg::virtualIntReg(100);
        const MicroReg second = MicroReg::virtualIntReg(101);
        builder.emitLoadRegReg(first, MicroReg::intReg(2), MicroOpBits::B64);
        builder.emitLoadRegReg(second, MicroReg::intReg(3), MicroOpBits::B64);
        for (uint32_t lane = 0; lane < 4; ++lane)
        {
            const MicroReg value = MicroReg::virtualIntReg(lane + 1);
            builder.emitLoadRegMem(value, first, lane * 4, MicroOpBits::B32);
            builder.emitOpBinaryRegImm(value, ApInt(1, 8), MicroOp::ShiftLeft, MicroOpBits::B32);
            builder.emitLoadMemReg(sp, 0x60 + lane * 4, value, MicroOpBits::B32);
        }
        // This read does not feed the packed plan, but its root still counts.
        builder.emitLoadRegMem(MicroReg::virtualIntReg(99), secondParameter ? second : first, 0x80, MicroOpBits::B32);
        const auto extraRead = builder.instructions().lastInstructionRef();
        builder.emitClearReg(MicroReg::intReg(10), MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runSlpPass(builder, ssa, encoder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != (secondParameter ? 0u : 1u) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != (secondParameter ? 4u : 0u))
            return Result::Error;
        const auto* extraInst = builder.instructions().ptr(extraRead);
        if (!extraInst || extraInst->op != MicroInstrOpcode::LoadRegMem ||
            extraInst->ops(builder.operands())[1].reg != (secondParameter ? second : first))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_SurvivingStoresRespectPackedLoadInsertion)
{
    // A preceding store blocks an overlapping load; a later one cannot block it.
    for (uint32_t storeMode = 0; storeMode < 3; ++storeMode)
    {
        MicroBuilder   builder(ctx);
        X64Encoder     encoder(ctx);
        MicroSsaState  ssa;
        const MicroReg sp = encoder.stackPointerReg();
        for (uint32_t lane = 0; lane < 4; ++lane)
            builder.emitLoadRegMem(MicroReg::virtualIntReg(lane + 1), sp, 0x40 + lane * 4, MicroOpBits::B32);

        MicroInstrRef survivingStore = MicroInstrRef::invalid();
        if (storeMode != 2)
        {
            builder.emitLoadMemImm(sp, storeMode == 0 ? 0x80 : 0x40, ApInt(7, 8), MicroOpBits::B8);
            survivingStore = builder.instructions().lastInstructionRef();
        }
        for (uint32_t lane = 0; lane < 4; ++lane)
        {
            const MicroReg value = MicroReg::virtualIntReg(lane + 1);
            builder.emitOpBinaryRegImm(value, ApInt(1, 8), MicroOp::ShiftLeft, MicroOpBits::B32);
            builder.emitLoadMemReg(sp, 0x60 + lane * 4, value, MicroOpBits::B32);
        }
        if (storeMode == 2)
        {
            builder.emitLoadMemImm(sp, 0x40, ApInt(7, 8), MicroOpBits::B8);
            survivingStore = builder.instructions().lastInstructionRef();
        }
        builder.emitClearReg(MicroReg::intReg(10), MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runSlpPass(builder, ssa, encoder));
        const bool vectorized = storeMode != 1;
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != (vectorized ? 1u : 0u) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != (vectorized ? 0u : 4u))
            return Result::Error;
        if (builder.instructions().ptr(survivingStore)->op != MicroInstrOpcode::LoadMemImm)
            return Result::Error;
        bool passedStore = false;
        for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
        {
            if (it.current == survivingStore)
                passedStore = true;
            if (it->op == MicroInstrOpcode::LoadVecRegMem && passedStore != (storeMode == 0))
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_RejectedBlockKeepsFollowingBlockVectorizable)
{
    // Reject a short store group, an unresolved read, and an unresolved write.
    for (uint32_t rejection = 0; rejection < 3; ++rejection)
    {
        MicroBuilder   builder(ctx);
        X64Encoder     encoder(ctx);
        MicroSsaState  ssa;
        const MicroReg sp        = encoder.stackPointerReg();
        const MicroReg parameter = MicroReg::virtualIntReg(100);
        builder.emitLoadRegReg(parameter, MicroReg::intReg(2), MicroOpBits::B64);

        const uint32_t             laneCount = rejection == 0 ? 3 : 4;
        std::vector<MicroInstrRef> rejectedStores;
        for (uint32_t lane = 0; lane < laneCount; ++lane)
        {
            const MicroReg value = MicroReg::virtualIntReg(lane + 1);
            builder.emitLoadRegMem(value, parameter, 0x40 + lane * 4, MicroOpBits::B32);
            builder.emitOpBinaryRegImm(value, ApInt(1, 8), MicroOp::ShiftLeft, MicroOpBits::B32);
            builder.emitLoadMemReg(parameter, 0x60 + lane * 4, value, MicroOpBits::B32);
            rejectedStores.push_back(builder.instructions().lastInstructionRef());
        }
        if (rejection == 1)
            builder.emitLoadRegMem(MicroReg::virtualIntReg(99), MicroReg::intReg(10), 0, MicroOpBits::B32);
        else if (rejection == 2)
            builder.emitLoadMemReg(MicroReg::intReg(10), 0, MicroReg::virtualIntReg(1), MicroOpBits::B32);
        builder.emitClearReg(MicroReg::intReg(10), MicroOpBits::B64);
        builder.placeLabel(builder.createLabel());

        for (uint32_t lane = 0; lane < 4; ++lane)
        {
            const MicroReg value = MicroReg::virtualIntReg(lane + 10);
            builder.emitLoadRegMem(value, sp, 0x40 + lane * 4, MicroOpBits::B32);
            builder.emitOpBinaryRegImm(value, ApInt(1, 8), MicroOp::ShiftLeft, MicroOpBits::B32);
            builder.emitLoadMemReg(sp, 0x60 + lane * 4, value, MicroOpBits::B32);
        }
        builder.emitClearReg(MicroReg::intReg(10), MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runSlpPass(builder, ssa, encoder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 1 ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != laneCount + (rejection == 2 ? 1 : 0))
            return Result::Error;
        for (const MicroInstrRef storeRef : rejectedStores)
        {
            const MicroInstr* inst = builder.instructions().ptr(storeRef);
            if (!inst || inst->op != MicroInstrOpcode::LoadMemReg || inst->ops(builder.operands())[0].reg != parameter)
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SlpVectorize_MultipleBlocks_PreservesSnapshotAndFreshRegisters)
{
    MicroBuilder   builder(ctx);
    X64Encoder     encoder(ctx);
    MicroSsaState  ssa;
    const MicroReg sp = encoder.stackPointerReg();
    builder.emitClearReg(MicroReg::virtualFloatReg(100), MicroOpBits::B128);
    builder.placeLabel(builder.createLabel());
    for (uint32_t block = 0; block < 2; ++block)
    {
        for (uint32_t lane = 0; lane < 4; ++lane)
        {
            const MicroReg value = MicroReg::virtualIntReg(1 + block * 4 + lane);
            builder.emitLoadRegMem(value, sp, 0x40 + block * 0x80 + lane * 4, MicroOpBits::B32);
            builder.emitOpBinaryRegImm(value, ApInt(1, 8), MicroOp::ShiftLeft, MicroOpBits::B32);
            builder.emitLoadMemReg(sp, 0x60 + block * 0x80 + lane * 4, value, MicroOpBits::B32);
        }
        builder.emitClearReg(MicroReg::intReg(10), MicroOpBits::B64);
        builder.placeLabel(builder.createLabel());
    }
    builder.emitRet();

    SWC_RESULT(runSlpPass(builder, ssa, encoder));
    if (!ssa.isValid())
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 2)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 0)
        return Result::Error;
    std::unordered_set<uint32_t> vectorLoads;
    for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
    {
        if (it->op != MicroInstrOpcode::LoadVecRegMem)
            continue;
        const MicroReg reg     = it->ops(builder.operands())[0].reg;
        uint32_t       valueId = MicroSsaState::K_INVALID_VALUE;
        // Neither block's newly inserted values belong to the scalar snapshot.
        if (reg.index() <= 100 || !vectorLoads.insert(reg.packed).second || ssa.defValue(reg, it.current, valueId))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
