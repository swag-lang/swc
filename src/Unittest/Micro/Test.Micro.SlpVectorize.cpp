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
