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

SWC_TEST_BEGIN(MicroSsa_RebuildForgetsErasedAndRecycledSlots)
{
    constexpr MicroReg value = MicroReg::virtualIntReg(1);
    constexpr MicroReg copy  = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);
    builder.emitLoadRegImm(value, ApInt(7, 64), MicroOpBits::B64);
    const auto initial = builder.instructions().lastInstructionRef();
    builder.emitOpBinaryRegImm(value, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    const auto removed = builder.instructions().lastInstructionRef();
    builder.emitRet();
    const auto end = builder.instructions().lastInstructionRef();

    MicroSsaState ssa;
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    if (ssa.reachingDef(value, end).instRef != removed || !ssa.isRegUsedAfter(value, initial))
        return Result::Error;

    builder.instructions().erase(removed);
    builder.invalidateControlFlowGraph();
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    uint32_t valueId = MicroSsaState::K_INVALID_VALUE;
    if (ssa.reachingDef(value, removed).valid() || ssa.instrUseDef(removed) || ssa.defValue(value, removed, valueId))
        return Result::Error;
    if (ssa.reachingDef(value, end).instRef != initial || ssa.isRegUsedAfter(value, initial))
        return Result::Error;

    builder.instructions().releaseErasedRefs();
    std::array<MicroInstrOperand, 3> ops;
    ops[0].reg          = copy;
    ops[1].reg          = value;
    ops[2].opBits       = MicroOpBits::B64;
    const auto recycled = builder.instructions().insertSyntheticBefore(builder.operands(), end, MicroInstrOpcode::LoadRegReg, ops);
    if (recycled != removed)
        return Result::Error;
    builder.invalidateControlFlowGraph();

    // Repeated builds must neither retain the old definition nor duplicate uses.
    for (uint32_t rebuild = 0; rebuild < 3; ++rebuild)
    {
        ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
        if (ssa.defValue(value, recycled, valueId) || !ssa.defValue(copy, recycled, valueId))
            return Result::Error;
        if (ssa.reachingDef(value, recycled).instRef != initial || ssa.reachingDef(copy, end).instRef != recycled)
            return Result::Error;
        if (!ssa.defValue(value, initial, valueId))
            return Result::Error;
        const auto* info = ssa.valueInfo(valueId);
        if (!info || info->uses.size() != 1 || info->uses.front().instRef != recycled)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSsa_PhiPropagationThroughNestedJoins)
{
    constexpr MicroReg value    = MicroReg::virtualIntReg(1);
    constexpr MicroReg terminal = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);
    const auto         right     = builder.createLabel();
    const auto         innerJoin = builder.createLabel();
    const auto         outerJoin = builder.createLabel();
    builder.emitLoadRegImm(value, ApInt(1, 64), MicroOpBits::B64);
    const auto initial = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, outerJoin);
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, right);
    builder.emitLoadRegImm(value, ApInt(2, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, innerJoin);
    builder.placeLabel(right);
    builder.emitLoadRegImm(value, ApInt(3, 64), MicroOpBits::B64);
    builder.placeLabel(innerJoin);
    const auto inner = builder.instructions().lastInstructionRef();
    builder.emitLoadMemReg(MicroReg::intReg(2), 0, value, MicroOpBits::B64);
    builder.placeLabel(outerJoin);
    const auto outer = builder.instructions().lastInstructionRef();
    builder.emitLoadMemReg(MicroReg::intReg(2), 8, value, MicroOpBits::B64);
    // Definitions in the terminal block have no frontier to propagate through.
    builder.emitLoadRegImm(value, ApInt(4, 64), MicroOpBits::B64);
    const auto finalValue = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(terminal, ApInt(5, 64), MicroOpBits::B64);
    builder.emitRet();
    const auto end = builder.instructions().lastInstructionRef();

    MicroSsaState ssa;
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    const auto innerValue = ssa.reachingDef(value, inner);
    const auto outerValue = ssa.reachingDef(value, outer);
    if (!innerValue.isPhi || !outerValue.isPhi || innerValue.valueId == outerValue.valueId || ssa.phis().size() != 2)
        return Result::Error;
    const auto* outerPhi     = ssa.phiInfoForValue(outerValue.valueId);
    uint32_t    initialValue = MicroSsaState::K_INVALID_VALUE;
    if (!ssa.defValue(value, initial, initialValue) || !outerPhi || outerPhi->incomingValueIds.size() != 2)
        return Result::Error;
    if (outerPhi->incomingValueIds[0] != initialValue || outerPhi->incomingValueIds[1] != innerValue.valueId)
        return Result::Error;
    if (ssa.reachingDef(value, end).instRef != finalValue || !ssa.reachingDef(terminal, end).valid())
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSsa_RepeatedDefinitionsRestoreBlockEntryValues)
{
    constexpr MicroReg value = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);
    const auto         sibling = builder.createLabel();
    const auto         child   = builder.createLabel();
    const auto         join    = builder.createLabel();
    builder.emitLoadRegImm(value, ApInt(1, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(value, ApInt(2, 64), MicroOpBits::B64);
    const auto parentDef = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, sibling);
    builder.emitLoadRegImm(value, ApInt(3, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegImm(value, ApInt(4, 64), MicroOp::Add, MicroOpBits::B64);
    const auto leftDef = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, child);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
    builder.placeLabel(child);
    const auto childUse = builder.instructions().lastInstructionRef();
    builder.emitLoadRegImm(value, ApInt(5, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(value, ApInt(6, 64), MicroOpBits::B64);
    const auto childDef = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
    builder.placeLabel(sibling);
    const auto siblingUse = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
    builder.placeLabel(join);
    const auto joinedUse = builder.instructions().lastInstructionRef();
    builder.emitOpBinaryRegImm(value, ApInt(7, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(value, ApInt(8, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();
    const auto end       = builder.instructions().lastInstructionRef();
    const auto joinedDef = builder.instructions().findPreviousInstructionRef(end);
    builder.emitLoadRegImm(value, ApInt(9, 64), MicroOpBits::B64);
    const auto otherRoot = builder.instructions().lastInstructionRef();
    builder.emitRet();

    MicroSsaState ssa;
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    if (ssa.reachingDef(value, childUse).instRef != leftDef || ssa.reachingDef(value, siblingUse).instRef != parentDef)
        return Result::Error;
    const auto  joined = ssa.reachingDef(value, joinedUse);
    const auto* phi    = ssa.phiInfoForValue(joined.valueId);
    if (!joined.isPhi || !phi || phi->incomingValueIds.size() != 3)
        return Result::Error;
    const std::array expected{leftDef, childDef, parentDef};
    for (uint32_t i = 0; i < expected.size(); ++i)
    {
        const auto* input = ssa.valueInfo(phi->incomingValueIds[i]);
        if (!input || input->instRef != expected[i])
            return Result::Error;
    }
    if (ssa.reachingDef(value, end).instRef != joinedDef || ssa.reachingDef(value, otherRoot).valid())
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSsa_RebuildWithOnlyPhysicalDefinitions)
{
    constexpr MicroReg value    = MicroReg::virtualIntReg(1);
    constexpr MicroReg physical = MicroReg::intReg(0);
    MicroBuilder       builder(ctx);
    const auto         right = builder.createLabel();
    const auto         join  = builder.createLabel();
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, right);
    builder.emitLoadRegImm(value, ApInt(1, 64), MicroOpBits::B64);
    const auto leftDef = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
    builder.placeLabel(right);
    builder.emitLoadRegImm(value, ApInt(2, 64), MicroOpBits::B64);
    const auto rightDef = builder.instructions().lastInstructionRef();
    builder.placeLabel(join);
    builder.emitOpBinaryRegReg(physical, value, MicroOp::Add, MicroOpBits::B64);
    const auto use = builder.instructions().lastInstructionRef();
    builder.emitRet();

    MicroSsaState ssa;
    for (const bool virtualDefs : {true, false, true, false})
    {
        builder.instructions().ptr(leftDef)->ops(builder.operands())[0].reg  = virtualDefs ? value : physical;
        builder.instructions().ptr(rightDef)->ops(builder.operands())[0].reg = virtualDefs ? value : physical;
        ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
        const auto* info = ssa.instrUseDef(use);
        if (!ssa.isValid() || !info || !microRegSpanContains(info->uses, value) || !microRegSpanContains(info->defs, physical))
            return Result::Error;
        uint32_t defId = MicroSsaState::K_INVALID_VALUE;
        if (virtualDefs)
        {
            if (!ssa.reachingDef(value, use).isPhi || ssa.phis().size() != 1 || !ssa.defValue(value, leftDef, defId))
                return Result::Error;
        }
        else if (!ssa.values().empty() || !ssa.phis().empty() || ssa.reachingDef(value, use).valid() ||
                 ssa.defValue(value, leftDef, defId) || ssa.isRegUsedAfter(value, leftDef))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSsa_DirectUseCountsAfterPhiRebuild)
{
    constexpr MicroReg value = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);
    const auto         right = builder.createLabel();
    const auto         join  = builder.createLabel();
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, right);
    builder.emitLoadRegImm(value, ApInt(1, 64), MicroOpBits::B64);
    const auto first = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
    builder.placeLabel(right);
    builder.emitLoadRegImm(value, ApInt(2, 64), MicroOpBits::B64);
    builder.placeLabel(join);
    builder.emitLoadMemReg(MicroReg::intReg(2), 0, value, MicroOpBits::B64);
    builder.emitRet();

    MicroSsaState ssa;
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    uint32_t initial = MicroSsaState::K_INVALID_VALUE;
    if (ssa.phis().empty() || !ssa.defValue(value, first, initial) || ssa.transitiveInstructionUseCount(initial, 16) != 1)
        return Result::Error;

    builder.instructions().clear();
    builder.operands().clear();
    std::array<MicroInstrRef, 3> defs;
    for (uint32_t i = 0; i < defs.size(); ++i)
    {
        builder.emitLoadRegImm(MicroReg::virtualIntReg(i + 1), ApInt(i, 64), MicroOpBits::B64);
        defs[i] = builder.instructions().lastInstructionRef();
    }
    for (uint32_t i = 0; i < defs.size(); ++i)
    {
        for (uint32_t use = 0; use < i; ++use)
            builder.emitLoadMemReg(MicroReg::intReg(2), use * 8, MicroReg::virtualIntReg(i + 1), MicroOpBits::B64);
    }
    builder.emitRet();
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    if (!ssa.phis().empty())
        return Result::Error;
    for (uint32_t i = 0; i < defs.size(); ++i)
    {
        uint32_t id = MicroSsaState::K_INVALID_VALUE;
        if (!ssa.defValue(MicroReg::virtualIntReg(i + 1), defs[i], id))
            return Result::Error;
        for (const uint32_t cap : {0u, 1u, 2u, 16u})
            if (ssa.transitiveInstructionUseCount(id, cap) != std::min(i, cap))
                return Result::Error;
    }
    if (ssa.transitiveInstructionUseCount(MicroSsaState::K_INVALID_VALUE, 16) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSsa_IndirectTargetsKeepDistinctAdjacentBlocks)
{
    constexpr MicroReg value = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);
    const auto         first  = builder.createLabel();
    const auto         second = builder.createLabel();
    const auto         other  = builder.createLabel();
    const auto         join   = builder.createLabel();
    builder.emitLoadRegImm(value, ApInt(1, 64), MicroOpBits::B64);
    const std::array targets{first, second, first, other, second};
    builder.emitJumpReg(MicroReg::virtualIntReg(2), targets);
    builder.placeLabel(first);
    builder.placeLabel(second);
    builder.emitOpBinaryRegImm(value, ApInt(2, 64), MicroOp::Add, MicroOpBits::B64);
    const auto adjacentDef = builder.instructions().lastInstructionRef();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
    builder.placeLabel(other);
    builder.emitLoadRegImm(value, ApInt(3, 64), MicroOpBits::B64);
    const auto otherDef = builder.instructions().lastInstructionRef();
    builder.placeLabel(join);
    const auto joined = builder.instructions().lastInstructionRef();
    builder.emitRet();

    MicroSsaState ssa;
    ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
    const auto  reaching = ssa.reachingDef(value, joined);
    const auto* phi      = ssa.phiInfoForValue(reaching.valueId);
    if (!reaching.isPhi || !phi || phi->incomingValueIds.size() != 2 || ssa.phis().size() != 1)
        return Result::Error;
    if (phi->blockIndex != 4 || phi->predecessorBlocks.size() != 2 || phi->predecessorBlocks[0] != 2 || phi->predecessorBlocks[1] != 3)
        return Result::Error;
    const auto* left  = ssa.valueInfo(phi->incomingValueIds[0]);
    const auto* right = ssa.valueInfo(phi->incomingValueIds[1]);
    if (!left || !right || left->instRef != adjacentDef || right->instRef != otherDef)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
