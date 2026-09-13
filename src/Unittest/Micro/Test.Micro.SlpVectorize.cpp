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
