#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.VecLoopPromote.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runVecLoopPromotePass(MicroBuilder& builder)
    {
        // The pass shares the vectorizer's build-configuration gate.
        Runtime::BuildCfgBackend backendCfg{};
        backendCfg.optimLevel = Runtime::BuildCfgBackendOptimLevel::O2;
        backendCfg.vectorize = true;
        builder.setBackendBuildCfg(backendCfg);

        MicroVecLoopPromotePass pass;
        MicroPassManager        passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    uint32_t countOpcode(const MicroBuilder& builder, const MicroInstrOpcode opcode)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                ++count;
        }

        return count;
    }

    // First linear position of an opcode, or UINT32_MAX.
    uint32_t firstPosition(const MicroBuilder& builder, const MicroInstrOpcode opcode)
    {
        uint32_t position = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                return position;
            ++position;
        }

        return std::numeric_limits<uint32_t>::max();
    }

    uint32_t lastPosition(const MicroBuilder& builder, const MicroInstrOpcode opcode)
    {
        uint32_t position = 0;
        uint32_t found    = std::numeric_limits<uint32_t>::max();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                found = position;
            ++position;
        }

        return found;
    }
}

// The canonical post-SLP loop: one packed load of a frame chunk at the top of
// the body, one packed store at the bottom. The load must move before the loop
// label, the store after the back-jump, and both body accesses must become
// 128-bit register copies of the promoted register.
SWC_TEST_BEGIN(VecLoopPromote_LoadStorePair_HoistsAndSinks)
{
    const MicroReg     sp   = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg vCnt = MicroReg::virtualIntReg(1);
    constexpr MicroReg vVec = MicroReg::virtualFloatReg(1);
    MicroBuilder       builder(ctx);

    const MicroLabelRef top = builder.createLabel();
    builder.emitLoadRegImm(vCnt, ApInt(0, 64), MicroOpBits::B64);
    builder.placeLabel(top);
    builder.emitLoadVecRegMem(vVec, sp, 0x40, MicroOpBits::B128);
    builder.emitOpBinaryRegReg(vVec, vVec, MicroOp::VecXor, MicroOpBits::B128);
    builder.emitStoreVecMemReg(sp, 0x40, vVec, MicroOpBits::B128);
    builder.emitOpBinaryRegImm(vCnt, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(vCnt, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runVecLoopPromotePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != 1)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 1)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 2)
        return Result::Error;

    const uint32_t posLoad  = firstPosition(builder, MicroInstrOpcode::LoadVecRegMem);
    const uint32_t posLabel = firstPosition(builder, MicroInstrOpcode::Label);
    const uint32_t posStore = firstPosition(builder, MicroInstrOpcode::StoreVecMemReg);
    const uint32_t posRet   = firstPosition(builder, MicroInstrOpcode::Ret);
    if (posLoad > posLabel)
        return Result::Error;
    if (posStore + 1 != posRet)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A scalar store into the middle of the chunk makes the packed pair
// non-exclusive: nothing may move.
SWC_TEST_BEGIN(VecLoopPromote_OverlappingScalarStore_Blocks)
{
    const MicroReg     sp   = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg vCnt = MicroReg::virtualIntReg(1);
    constexpr MicroReg vVec = MicroReg::virtualFloatReg(1);
    MicroBuilder       builder(ctx);

    const MicroLabelRef top = builder.createLabel();
    builder.emitLoadRegImm(vCnt, ApInt(0, 64), MicroOpBits::B64);
    builder.placeLabel(top);
    builder.emitLoadVecRegMem(vVec, sp, 0x40, MicroOpBits::B128);
    builder.emitOpBinaryRegReg(vVec, vVec, MicroOp::VecXor, MicroOpBits::B128);
    builder.emitLoadMemImm(sp, 0x44, ApInt(5, 32), MicroOpBits::B32);
    builder.emitStoreVecMemReg(sp, 0x40, vVec, MicroOpBits::B128);
    builder.emitOpBinaryRegImm(vCnt, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(vCnt, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runVecLoopPromotePass(builder));

    const uint32_t posLoad  = firstPosition(builder, MicroInstrOpcode::LoadVecRegMem);
    const uint32_t posLabel = firstPosition(builder, MicroInstrOpcode::Label);
    if (posLoad < posLabel)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A chunk the loop only reads is a pure hoist: the packed load moves to the
// preheader, no store is materialized on the exit.
SWC_TEST_BEGIN(VecLoopPromote_LoadOnlyChunk_HoistsWithoutStore)
{
    const MicroReg     sp   = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg vCnt = MicroReg::virtualIntReg(1);
    constexpr MicroReg vVec = MicroReg::virtualFloatReg(1);
    constexpr MicroReg vAcc = MicroReg::virtualFloatReg(2);
    MicroBuilder       builder(ctx);

    const MicroLabelRef top = builder.createLabel();
    builder.emitLoadRegImm(vCnt, ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadVecRegMem(vAcc, sp, 0x60, MicroOpBits::B128);
    builder.placeLabel(top);
    builder.emitLoadVecRegMem(vVec, sp, 0x40, MicroOpBits::B128);
    builder.emitOpBinaryRegReg(vAcc, vVec, MicroOp::VecXor, MicroOpBits::B128);
    builder.emitOpBinaryRegImm(vCnt, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(vCnt, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runVecLoopPromotePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadVecRegMem) != 2)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::StoreVecMemReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;

    const uint32_t posLastLoad = lastPosition(builder, MicroInstrOpcode::LoadVecRegMem);
    const uint32_t posLabel    = firstPosition(builder, MicroInstrOpcode::Label);
    if (posLastLoad > posLabel)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
