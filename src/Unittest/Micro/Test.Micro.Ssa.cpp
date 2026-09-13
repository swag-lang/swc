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
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

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
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

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

SWC_TEST_BEGIN(MicroSsa_ReachingDef_BeforeWritesAndAtNonUses)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    constexpr MicroReg v2 = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    const auto first = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(v2, ApInt(3, 64), MicroOpBits::B64);
    const auto nonUse = builder.instructions().lastInstructionRef();
    builder.emitOpBinaryRegImm(v1, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    const auto overwrite = builder.instructions().lastInstructionRef();
    builder.emitRet();
    const auto end = builder.instructions().lastInstructionRef();

    MicroSsaState ssa;
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    if (ssa.reachingDef(v1, first).valid() || ssa.reachingDef(v2, nonUse).valid())
        return Result::Error;
    if (ssa.reachingDef(v1, nonUse).instRef != first || ssa.reachingDef(v1, overwrite).instRef != first)
        return Result::Error;
    if (ssa.reachingDef(v1, end).instRef != overwrite)
        return Result::Error;

    // A rebuild must forget the removed definition, including its instruction slot.
    builder.instructions().erase(overwrite);
    builder.invalidateControlFlowGraph();
    ssa.invalidate();
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    if (ssa.reachingDef(v1, end).instRef != first || ssa.instrUseDef(overwrite))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSsa_ReachingDef_DominatorSiblings)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    constexpr MicroReg v2 = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);
    const auto         other = builder.createLabel();
    const auto         join  = builder.createLabel();

    builder.emitLoadRegImm(v1, ApInt(7, 64), MicroOpBits::B64);
    const auto entry = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, other);
    builder.emitLoadRegImm(v1, ApInt(9, 64), MicroOpBits::B64);
    const auto left = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(v2, ApInt(1, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
    const auto leftEnd = builder.instructions().lastInstructionRef();
    builder.placeLabel(other);
    const auto right = builder.instructions().lastInstructionRef();
    builder.placeLabel(join);
    const auto merge = builder.instructions().lastInstructionRef();
    builder.emitRet();

    MicroSsaState ssa;
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    if (ssa.reachingDef(v1, leftEnd).instRef != left || ssa.reachingDef(v1, right).instRef != entry)
        return Result::Error;
    if (ssa.reachingDef(v2, right).valid())
        return Result::Error;
    const auto reaching = ssa.reachingDef(v1, merge);
    if (!reaching.isPhi)
        return Result::Error;
    const auto* phi = ssa.phiInfoForValue(reaching.valueId);
    if (!phi || phi->incomingValueIds.size() != 2)
        return Result::Error;
    for (const auto incoming : phi->incomingValueIds)
    {
        const auto* value = ssa.valueInfo(incoming);
        if (!value || (value->instRef != entry && value->instRef != left))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSsa_ReachingDef_LoopAndUnreachableRoot)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);
    const auto         loop = builder.createLabel();

    builder.emitLoadRegImm(v1, ApInt(0, 64), MicroOpBits::B64);
    builder.placeLabel(loop);
    const auto header = builder.instructions().lastInstructionRef();
    builder.emitOpBinaryRegImm(v1, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    const auto update = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B64, loop);
    builder.emitRet();
    const auto exit = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(v1, ApInt(42, 64), MicroOpBits::B64);
    const auto unreachable = builder.instructions().lastInstructionRef();
    builder.emitRet();
    const auto unreachableEnd = builder.instructions().lastInstructionRef();

    MicroSsaState ssa;
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    const auto phi = ssa.reachingDef(v1, header);
    if (!phi.isPhi || ssa.reachingDef(v1, update).valueId != phi.valueId)
        return Result::Error;
    if (ssa.reachingDef(v1, exit).instRef != update)
        return Result::Error;
    if (ssa.reachingDef(v1, unreachable).valid() || ssa.reachingDef(v1, unreachableEnd).instRef != unreachable)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSsa_PhiAtJoinWithSharedPredecessorDominator)
{
    constexpr MicroReg reg = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);
    const auto         other = builder.createLabel();
    const auto         join  = builder.createLabel();

    builder.emitLoadRegImm(reg, ApInt(1, 64), MicroOpBits::B64);
    const auto entryValue = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, join);
    builder.emitLoadRegImm(reg, ApInt(2, 64), MicroOpBits::B64);
    const auto nestedValue = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, other);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
    builder.placeLabel(other);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
    builder.placeLabel(join);
    const auto merge = builder.instructions().lastInstructionRef();
    builder.emitRet();

    MicroSsaState ssa;
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    const auto  reaching = ssa.reachingDef(reg, merge);
    const auto* phi      = ssa.phiInfoForValue(reaching.valueId);
    if (!reaching.isPhi || !phi || phi->incomingValueIds.size() != 3 || ssa.phis().size() != 1)
        return Result::Error;
    uint32_t entryInputs  = 0;
    uint32_t nestedInputs = 0;
    for (const auto incoming : phi->incomingValueIds)
    {
        const auto* value = ssa.valueInfo(incoming);
        if (!value || value->isPhi())
            return Result::Error;
        entryInputs += value->instRef == entryValue;
        nestedInputs += value->instRef == nestedValue;
    }
    if (entryInputs != 1 || nestedInputs != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSsa_PhiInputsFollowManyPredecessors)
{
    constexpr uint32_t               count = 32;
    constexpr MicroReg               value = MicroReg::virtualIntReg(1);
    MicroBuilder                     builder(ctx);
    const MicroLabelRef              join = builder.createLabel();
    std::array<MicroInstrRef, count> definitions;
    for (uint32_t i = 0; i < count; ++i)
    {
        const MicroLabelRef alternate = builder.createLabel();
        if (i + 1 < count)
            builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, alternate);
        builder.emitLoadRegImm(value, ApInt(i, 64), MicroOpBits::B64);
        definitions[i] = builder.instructions().lastInstructionRef();
        if (i + 1 < count)
        {
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
            builder.placeLabel(alternate);
        }
    }
    builder.placeLabel(join);
    builder.emitLoadMemReg(MicroReg::intReg(2), 0, value, MicroOpBits::B64);
    const auto use = builder.instructions().lastInstructionRef();
    builder.emitRet();

    MicroSsaState ssa;
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    const auto  reaching = ssa.reachingDef(value, use);
    const auto* phi      = ssa.phiInfoForValue(reaching.valueId);
    if (!reaching.isPhi || !phi || phi->incomingValueIds.size() != count)
        return Result::Error;
    for (uint32_t i = 0; i < count; ++i)
    {
        uint32_t expected = MicroSsaState::K_INVALID_VALUE;
        if (!ssa.defValue(value, definitions[i], expected) || phi->incomingValueIds[i] != expected)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSsa_RebuildAddsFrontierAfterLinearBlocks)
{
    constexpr MicroReg value = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);
    builder.emitLoadRegImm(value, ApInt(7, 64), MicroOpBits::B64);
    const auto initialDef   = builder.instructions().lastInstructionRef();
    const auto linearTarget = builder.createLabel();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, linearTarget);
    builder.emitRet();
    builder.placeLabel(linearTarget);
    builder.emitLoadMemReg(MicroReg::intReg(2), 0, value, MicroOpBits::B64);
    const auto initialUse = builder.instructions().lastInstructionRef();
    builder.emitRet();

    MicroSsaState ssa;
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    if (!ssa.phis().empty() || ssa.reachingDef(value, initialUse).instRef != initialDef)
        return Result::Error;

    // A new disconnected component introduces a frontier on the next build.
    const auto right = builder.createLabel();
    const auto join  = builder.createLabel();
    builder.placeLabel(builder.createLabel());
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, right);
    builder.emitLoadRegImm(value, ApInt(11, 64), MicroOpBits::B64);
    const auto leftDef = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
    builder.placeLabel(right);
    builder.emitLoadRegImm(value, ApInt(13, 64), MicroOpBits::B64);
    const auto rightDef = builder.instructions().lastInstructionRef();
    builder.placeLabel(join);
    builder.emitLoadMemReg(MicroReg::intReg(2), 0, value, MicroOpBits::B64);
    const auto joinedUse = builder.instructions().lastInstructionRef();
    builder.emitRet();

    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    const auto  reaching = ssa.reachingDef(value, joinedUse);
    const auto* phi      = ssa.phiInfoForValue(reaching.valueId);
    if (!reaching.isPhi || !phi || phi->incomingValueIds.size() != 2 || ssa.phis().size() != 1)
        return Result::Error;
    uint32_t leftValue  = MicroSsaState::K_INVALID_VALUE;
    uint32_t rightValue = MicroSsaState::K_INVALID_VALUE;
    if (!ssa.defValue(value, leftDef, leftValue) || !ssa.defValue(value, rightDef, rightValue))
        return Result::Error;
    if (phi->incomingValueIds[0] != leftValue || phi->incomingValueIds[1] != rightValue)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
