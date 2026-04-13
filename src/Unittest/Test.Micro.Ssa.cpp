#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroInstrRef findFirstInstructionRef(const MicroBuilder& builder, const MicroInstrOpcode opcode)
    {
        for (auto it = builder.instructions().view().begin(); it != builder.instructions().view().end(); ++it)
        {
            if (it->op == opcode)
                return it.current;
        }

        return MicroInstrRef::invalid();
    }
}

SWC_TEST_BEGIN(MicroSsa_PhiAtJoin)
{
    const MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder   builder(ctx);

    const MicroLabelRef labelThen = builder.createLabel();
    const MicroLabelRef labelJoin = builder.createLabel();

    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, labelThen);
    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, labelJoin);
    builder.placeLabel(labelThen);
    builder.emitLoadRegImm(v1, ApInt(9, 64), MicroOpBits::B64);
    builder.placeLabel(labelJoin);
    builder.emitOpBinaryRegImm(v1, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    MicroSsaState ssaState;
    ssaState.build(builder, builder.instructions(), builder.operands(), nullptr);

    const MicroInstrRef addRef = findFirstInstructionRef(builder, MicroInstrOpcode::OpBinaryRegImm);
    if (addRef.isInvalid())
        return Result::Error;

    const auto reachingDef = ssaState.reachingDef(v1, addRef);
    if (!reachingDef.valid() || !reachingDef.isPhi)
        return Result::Error;

    const auto* phiInfo = ssaState.phiInfoForValue(reachingDef.valueId);
    if (!phiInfo)
        return Result::Error;
    if (phiInfo->incomingValueIds.size() != 2)
        return Result::Error;
    if (phiInfo->incomingValueIds[0] == MicroSsaState::K_INVALID_VALUE)
        return Result::Error;
    if (phiInfo->incomingValueIds[1] == MicroSsaState::K_INVALID_VALUE)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSsa_Dominators_HandleEntryAndDescendantJoin)
{
    const MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder   builder(ctx);

    const MicroLabelRef labelJoin = builder.createLabel();

    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, labelJoin);
    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, labelJoin);
    builder.placeLabel(labelJoin);
    builder.emitOpBinaryRegImm(v1, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    MicroSsaState ssaState;
    ssaState.build(builder, builder.instructions(), builder.operands(), nullptr);

    const MicroInstrRef addRef = findFirstInstructionRef(builder, MicroInstrOpcode::OpBinaryRegImm);
    if (addRef.isInvalid())
        return Result::Error;

    const auto reachingDef = ssaState.reachingDef(v1, addRef);
    if (!reachingDef.valid())
        return Result::Error;
    if (!reachingDef.isPhi)
        return Result::Error;

    const auto* phiInfo = ssaState.phiInfoForValue(reachingDef.valueId);
    if (!phiInfo)
        return Result::Error;
    if (phiInfo->incomingValueIds.size() != 2)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
