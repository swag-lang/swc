#include "pch.h"
#include "Backend/Micro/Passes/Pass.BranchSimplify.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.SsaValuePropagation.Internal.h"
#include "Support/Math/ApsInt.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA branch simplification and CFG cleanup.
//
// The pass focuses on monotonic structural rewrites that compose well with the
// fixed-point loop in MicroPassManager:
//
//   - Fold conditional branches whose compare inputs are known constants.
//   - Thread jumps through empty trampoline blocks (`L0: jmp L1`).
//   - Erase jumps whose target is the immediate fall-through label run.
//   - Remove instructions that become unreachable after a terminator.
//   - Drop CFG-unreachable instructions when the builder can rebuild a precise CFG.
//
// The pass never invents new blocks or labels. It only retargets / erases
// existing jumps and then lets the surrounding optimization loop rebuild SSA.

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID_ORDINAL = std::numeric_limits<uint32_t>::max();

    struct KnownValue
    {
        uint64_t    value  = 0;
        MicroOpBits opBits = MicroOpBits::B64;
    };

    struct KnownValueTraits
    {
        static bool isValid(const KnownValue&)
        {
            return true;
        }

        static bool same(const KnownValue& lhs, const KnownValue& rhs)
        {
            return lhs.value == rhs.value && lhs.opBits == rhs.opBits;
        }
    };

    struct KnownValueContext
    {
        const MicroSsaState*       ssaState = nullptr;
        const MicroStorage*        storage  = nullptr;
        const MicroOperandStorage* operands = nullptr;
    };

    struct ProgramLayout
    {
        std::vector<MicroInstrRef>             order;
        std::vector<uint32_t>                  ordinalByRef;
        std::unordered_map<uint32_t, uint32_t> labelOrdinalById;
    };

    bool tryGetKnownReachingValue(KnownValue& outValue, const KnownValueContext& context, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, MicroReg reg, MicroInstrRef instRef)
    {
        SWC_ASSERT(context.ssaState != nullptr);
        return tryGetSsaReachingValue<KnownValue, KnownValueTraits>(outValue, *context.ssaState, knownValues, knownFlags, reg, instRef);
    }

    bool tryInferInstructionConstant(KnownValue& outValue, const KnownValueContext& context, const uint32_t, const MicroSsaState::ValueInfo& valueInfo, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags)
    {
        if (!valueInfo.instRef.isValid())
            return false;

        SWC_ASSERT(context.storage != nullptr);
        SWC_ASSERT(context.operands != nullptr);

        const MicroInstr* inst = context.storage->ptr(valueInfo.instRef);
        if (!inst)
            return false;

        const MicroInstrOperand* ops = inst->ops(*context.operands);
        if (!ops)
            return false;

        switch (inst->op)
        {
            case MicroInstrOpcode::LoadRegImm:
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                outValue.value  = ops[2].valueU64;
                outValue.opBits = ops[1].opBits;
                return true;

            case MicroInstrOpcode::ClearReg:
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                outValue.value  = 0;
                outValue.opBits = ops[1].opBits;
                return true;

            case MicroInstrOpcode::LoadRegReg:
            {
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt() || ops[2].opBits != MicroOpBits::B64)
                    return false;

                return tryGetKnownReachingValue(outValue, context, knownValues, knownFlags, ops[1].reg, valueInfo.instRef);
            }

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                KnownValue inputValue;
                if (!tryGetKnownReachingValue(inputValue, context, knownValues, knownFlags, ops[0].reg, valueInfo.instRef))
                    return false;

                uint64_t   foldedValue = 0;
                const auto status      = MicroPassHelpers::foldBinaryImmediate(foldedValue, inputValue.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits);
                if (status != Math::FoldStatus::Ok)
                    return false;

                outValue.value  = foldedValue;
                outValue.opBits = ops[1].opBits;
                return true;
            }

            case MicroInstrOpcode::OpBinaryRegReg:
            {
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                KnownValue lhs;
                KnownValue rhs;
                if (!tryGetKnownReachingValue(lhs, context, knownValues, knownFlags, ops[0].reg, valueInfo.instRef))
                    return false;
                if (!tryGetKnownReachingValue(rhs, context, knownValues, knownFlags, ops[1].reg, valueInfo.instRef))
                    return false;

                uint64_t   foldedValue = 0;
                const auto status      = MicroPassHelpers::foldBinaryImmediate(foldedValue, lhs.value, rhs.value, ops[3].microOp, ops[2].opBits);
                if (status != Math::FoldStatus::Ok)
                    return false;

                outValue.value  = foldedValue;
                outValue.opBits = ops[2].opBits;
                return true;
            }

            default:
                break;
        }

        return false;
    }

    void computeKnownValues(std::vector<KnownValue>& outValues, std::vector<uint8_t>& outFlags, const MicroSsaState& ssaState, const MicroStorage& storage, const MicroOperandStorage& operands)
    {
        const KnownValueContext context{&ssaState, &storage, &operands};
        computeSsaValueFixedPoint<KnownValue, KnownValueTraits>(outValues, outFlags, ssaState, context, tryInferInstructionConstant);
    }

    bool tryGetLabelId(uint32_t& outLabelId, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        outLabelId = 0;
        if (inst.op != MicroInstrOpcode::Label || !ops || ops[0].valueU64 > std::numeric_limits<uint32_t>::max())
            return false;

        outLabelId = static_cast<uint32_t>(ops[0].valueU64);
        return true;
    }

    bool tryGetJumpTargetLabelId(uint32_t& outLabelId, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        outLabelId = 0;
        if (inst.op != MicroInstrOpcode::JumpCond || !ops || ops[2].valueU64 > std::numeric_limits<uint32_t>::max())
            return false;

        outLabelId = static_cast<uint32_t>(ops[2].valueU64);
        return true;
    }

    void buildProgramLayout(ProgramLayout& outLayout, const MicroStorage& storage, const MicroOperandStorage& operands)
    {
        outLayout.order.clear();
        outLayout.order.reserve(storage.count());
        outLayout.ordinalByRef.assign(storage.slotCount(), K_INVALID_ORDINAL);
        outLayout.labelOrdinalById.clear();

        uint32_t ordinal = 0;
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it, ++ordinal)
        {
            outLayout.order.push_back(it.current);
            outLayout.ordinalByRef[it.current.get()] = ordinal;

            uint32_t labelId = 0;
            if (tryGetLabelId(labelId, *it, it->ops(operands)))
                outLayout.labelOrdinalById[labelId] = ordinal;
        }
    }

    bool isTargetInImmediateLabelRun(const ProgramLayout& layout, const MicroStorage& storage, const MicroOperandStorage& operands, const MicroInstrRef jumpRef, const uint32_t targetLabelId)
    {
        if (jumpRef.get() >= layout.ordinalByRef.size())
            return false;

        const uint32_t jumpOrdinal = layout.ordinalByRef[jumpRef.get()];
        if (jumpOrdinal == K_INVALID_ORDINAL)
            return false;

        for (uint32_t ordinal = jumpOrdinal + 1; ordinal < layout.order.size(); ++ordinal)
        {
            const MicroInstr* nextInst = storage.ptr(layout.order[ordinal]);
            if (!nextInst)
                return false;

            const MicroInstrOperand* nextOps = nextInst->ops(operands);
            if (nextInst->op != MicroInstrOpcode::Label)
                return false;

            uint32_t labelId = 0;
            if (!tryGetLabelId(labelId, *nextInst, nextOps))
                return false;

            if (labelId == targetLabelId)
                return true;
        }

        return false;
    }

    bool tryGetTrampolineTarget(uint32_t& outTargetLabelId, const ProgramLayout& layout, const MicroStorage& storage, const MicroOperandStorage& operands, const uint32_t labelId)
    {
        outTargetLabelId   = 0;
        const auto labelIt = layout.labelOrdinalById.find(labelId);
        if (labelIt == layout.labelOrdinalById.end())
            return false;

        for (uint32_t ordinal = labelIt->second + 1; ordinal < layout.order.size(); ++ordinal)
        {
            const MicroInstr* inst = storage.ptr(layout.order[ordinal]);
            if (!inst)
                return false;

            const MicroInstrOperand* ops = inst->ops(operands);
            if (inst->op == MicroInstrOpcode::Label)
                continue;

            if (!MicroInstrInfo::isUnconditionalJumpInstruction(*inst, ops))
                return false;

            return tryGetJumpTargetLabelId(outTargetLabelId, *inst, ops);
        }

        return false;
    }

    bool tryResolveTrampolineTarget(uint32_t& outFinalTargetLabelId, const ProgramLayout& layout, const MicroStorage& storage, const MicroOperandStorage& operands, const uint32_t startLabelId)
    {
        uint32_t                     currentLabelId = startLabelId;
        std::unordered_set<uint32_t> visited;
        visited.reserve(4);

        while (visited.insert(currentLabelId).second)
        {
            uint32_t nextLabelId = 0;
            if (!tryGetTrampolineTarget(nextLabelId, layout, storage, operands, currentLabelId))
            {
                outFinalTargetLabelId = currentLabelId;
                return currentLabelId != startLabelId;
            }

            currentLabelId = nextLabelId;
        }

        return false;
    }

    bool tryEvaluateCompareCondition(bool& outTaken, const uint64_t lhsValue, const uint64_t rhsValue, const MicroOpBits opBits, const MicroCond cond)
    {
        const uint32_t bitWidth = getNumBits(opBits);
        if (!bitWidth)
            return false;

        const ApsInt lhsUnsigned(lhsValue, bitWidth, true);
        const ApsInt rhsUnsigned(rhsValue, bitWidth, true);
        const ApsInt lhsSigned(lhsValue, bitWidth, false);
        const ApsInt rhsSigned(rhsValue, bitWidth, false);

        switch (cond)
        {
            case MicroCond::Equal:
            case MicroCond::Zero:
                outTaken = lhsUnsigned.eq(rhsUnsigned);
                return true;

            case MicroCond::NotEqual:
            case MicroCond::NotZero:
                outTaken = !lhsUnsigned.eq(rhsUnsigned);
                return true;

            case MicroCond::Above:
                outTaken = lhsUnsigned.gt(rhsUnsigned);
                return true;

            case MicroCond::AboveOrEqual:
                outTaken = lhsUnsigned.ge(rhsUnsigned);
                return true;

            case MicroCond::Below:
                outTaken = lhsUnsigned.lt(rhsUnsigned);
                return true;

            case MicroCond::BelowOrEqual:
            case MicroCond::NotAbove:
                outTaken = lhsUnsigned.le(rhsUnsigned);
                return true;

            case MicroCond::Greater:
                outTaken = lhsSigned.gt(rhsSigned);
                return true;

            case MicroCond::GreaterOrEqual:
                outTaken = lhsSigned.ge(rhsSigned);
                return true;

            case MicroCond::Less:
                outTaken = lhsSigned.lt(rhsSigned);
                return true;

            case MicroCond::LessOrEqual:
                outTaken = lhsSigned.le(rhsSigned);
                return true;

            case MicroCond::Unconditional:
                outTaken = true;
                return true;

            default:
                break;
        }

        return false;
    }

    bool tryEvaluateKnownBranch(bool& outTaken, const KnownValueContext& context, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags, MicroInstrRef flagDefRef, MicroCond jumpCond)
    {
        outTaken = false;
        if (!flagDefRef.isValid())
            return false;

        SWC_ASSERT(context.storage != nullptr);
        SWC_ASSERT(context.operands != nullptr);

        const MicroInstr* flagDefInst = context.storage->ptr(flagDefRef);
        if (!flagDefInst)
            return false;

        const MicroInstrOperand* flagOps = flagDefInst->ops(*context.operands);
        if (!flagOps)
            return false;

        switch (flagDefInst->op)
        {
            case MicroInstrOpcode::CmpRegImm:
            {
                if (!flagOps[0].reg.isVirtualInt())
                    return false;

                KnownValue lhsValue;
                if (!tryGetKnownReachingValue(lhsValue, context, knownValues, knownFlags, flagOps[0].reg, flagDefRef))
                    return false;

                return tryEvaluateCompareCondition(outTaken, lhsValue.value, flagOps[2].valueU64, flagOps[1].opBits, jumpCond);
            }

            case MicroInstrOpcode::CmpRegReg:
            {
                if (!flagOps[0].reg.isVirtualInt() || !flagOps[1].reg.isVirtualInt())
                    return false;

                KnownValue lhsValue;
                KnownValue rhsValue;
                if (!tryGetKnownReachingValue(lhsValue, context, knownValues, knownFlags, flagOps[0].reg, flagDefRef))
                    return false;
                if (!tryGetKnownReachingValue(rhsValue, context, knownValues, knownFlags, flagOps[1].reg, flagDefRef))
                    return false;

                return tryEvaluateCompareCondition(outTaken, lhsValue.value, rhsValue.value, flagOps[2].opBits, jumpCond);
            }

            case MicroInstrOpcode::ClearReg:
                return tryEvaluateCompareCondition(outTaken, 0, 0, flagOps[1].opBits, jumpCond);

            default:
                break;
        }

        return false;
    }

    bool foldKnownBranches(MicroStorage& storage, MicroOperandStorage& operands, const MicroSsaState& ssaState, const std::vector<KnownValue>& knownValues, const std::vector<uint8_t>& knownFlags)
    {
        ProgramLayout layout;
        buildProgramLayout(layout, storage, operands);
        const KnownValueContext context{&ssaState, &storage, &operands};

        bool          changed        = false;
        MicroInstrRef currentFlagDef = MicroInstrRef::invalid();

        for (auto it = storage.view().begin(); it != storage.view().end();)
        {
            const MicroInstrRef instRef = it.current;
            MicroInstr&         inst    = *it;
            ++it;

            const MicroInstrOperand* ops = inst.ops(operands);
            if (inst.op == MicroInstrOpcode::Label)
            {
                currentFlagDef = MicroInstrRef::invalid();
                continue;
            }

            if (inst.op == MicroInstrOpcode::JumpCond && ops && ops[0].cpuCond != MicroCond::Unconditional)
            {
                bool branchTaken = false;
                if (tryEvaluateKnownBranch(branchTaken, context, knownValues, knownFlags, currentFlagDef, ops[0].cpuCond))
                {
                    uint32_t   targetLabelId = 0;
                    const bool hasTarget     = tryGetJumpTargetLabelId(targetLabelId, inst, ops);

                    if (!branchTaken)
                    {
                        changed |= storage.erase(instRef);
                    }
                    else
                    {
                        if (hasTarget && isTargetInImmediateLabelRun(layout, storage, operands, instRef, targetLabelId))
                        {
                            changed |= storage.erase(instRef);
                        }
                        else
                        {
                            MicroInstrOperand* mutableOps = inst.ops(operands);
                            mutableOps[0].cpuCond         = MicroCond::Unconditional;
                            changed                       = true;
                        }
                    }

                    currentFlagDef = MicroInstrRef::invalid();
                    continue;
                }
            }

            if (MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::DefinesCpuFlags))
                currentFlagDef = instRef;

            if (MicroInstrInfo::isTerminatorInstruction(inst))
                currentFlagDef = MicroInstrRef::invalid();
        }

        return changed;
    }

    bool redirectJumpChains(MicroStorage& storage, MicroOperandStorage& operands)
    {
        ProgramLayout layout;
        buildProgramLayout(layout, storage, operands);

        bool changed = false;
        for (MicroInstr& inst : storage.view())
        {
            if (inst.op != MicroInstrOpcode::JumpCond)
                continue;

            MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                continue;

            uint32_t targetLabelId = 0;
            if (!tryGetJumpTargetLabelId(targetLabelId, inst, ops))
                continue;

            uint32_t resolvedLabelId = 0;
            if (!tryResolveTrampolineTarget(resolvedLabelId, layout, storage, operands, targetLabelId))
                continue;
            if (resolvedLabelId == targetLabelId)
                continue;

            ops[2].valueU64 = resolvedLabelId;
            changed         = true;
        }

        return changed;
    }

    bool eraseJumpsToImmediateLabels(MicroStorage& storage, MicroOperandStorage& operands)
    {
        ProgramLayout layout;
        buildProgramLayout(layout, storage, operands);

        bool changed = false;
        for (auto it = storage.view().begin(); it != storage.view().end();)
        {
            const MicroInstrRef instRef = it.current;
            const MicroInstr&   inst    = *it;
            ++it;

            if (inst.op != MicroInstrOpcode::JumpCond)
                continue;

            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                continue;

            uint32_t targetLabelId = 0;
            if (!tryGetJumpTargetLabelId(targetLabelId, inst, ops))
                continue;

            if (!isTargetInImmediateLabelRun(layout, storage, operands, instRef, targetLabelId))
                continue;

            changed |= storage.erase(instRef);
        }

        return changed;
    }

    bool instructionHasNoFallthrough(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!MicroInstrInfo::isTerminatorInstruction(inst))
            return false;

        if (MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::JumpInstruction))
            return MicroInstrInfo::isUnconditionalJumpInstruction(inst, ops);

        return true;
    }

    bool eraseDeadInstructionsAfterTerminators(MicroStorage& storage, const MicroOperandStorage& operands)
    {
        bool changed      = false;
        bool inDeadRegion = false;

        for (auto it = storage.view().begin(); it != storage.view().end();)
        {
            const MicroInstrRef instRef = it.current;
            const MicroInstr&   inst    = *it;
            ++it;

            if (inst.op == MicroInstrOpcode::Label)
            {
                inDeadRegion = false;
                continue;
            }

            if (inDeadRegion)
            {
                changed |= storage.erase(instRef);
                continue;
            }

            if (instructionHasNoFallthrough(inst, inst.ops(operands)))
                inDeadRegion = true;
        }

        return changed;
    }

    bool eraseCfgUnreachable(MicroBuilder& builder, MicroStorage& storage)
    {
        const MicroControlFlowGraph& cfg = builder.controlFlowGraph();
        if (!cfg.instructionCount() || cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
            return false;

        std::vector<uint8_t>  reachable(cfg.instructionCount(), 0);
        std::vector<uint32_t> stack;
        stack.push_back(0);
        reachable[0] = 1;

        while (!stack.empty())
        {
            const uint32_t currentIndex = stack.back();
            stack.pop_back();

            for (const uint32_t successorIndex : cfg.successors(currentIndex))
            {
                if (successorIndex >= reachable.size() || reachable[successorIndex])
                    continue;

                reachable[successorIndex] = 1;
                stack.push_back(successorIndex);
            }
        }

        bool       changed         = false;
        const auto instructionRefs = cfg.instructionRefs();
        for (uint32_t instructionIndex = 0; instructionIndex < instructionRefs.size(); ++instructionIndex)
        {
            if (reachable[instructionIndex])
                continue;

            changed |= storage.erase(instructionRefs[instructionIndex]);
        }

        return changed;
    }
}

Result MicroBranchSimplifyPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/BranchSimplify");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;

    MicroSsaState        localSsaState;
    const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);

    std::vector<KnownValue> knownValues;
    std::vector<uint8_t>    knownFlags;
    if (ssaState && ssaState->isValid())
        computeKnownValues(knownValues, knownFlags, *ssaState, storage, operands);

    bool changed = false;
    if (ssaState && ssaState->isValid())
        changed |= foldKnownBranches(storage, operands, *ssaState, knownValues, knownFlags);

    bool structuralChanged = true;
    while (structuralChanged)
    {
        structuralChanged = false;

        structuralChanged |= redirectJumpChains(storage, operands);
        structuralChanged |= eraseJumpsToImmediateLabels(storage, operands);
        structuralChanged |= eraseDeadInstructionsAfterTerminators(storage, operands);

        if (structuralChanged && context.builder)
            context.builder->invalidateControlFlowGraph();

        if (context.builder)
        {
            const bool erasedUnreachable = eraseCfgUnreachable(*context.builder, storage);
            if (erasedUnreachable)
            {
                context.builder->invalidateControlFlowGraph();
                structuralChanged = true;
            }
        }

        changed |= structuralChanged;
    }

    if (changed)
        context.passChanged = true;

    return Result::Continue;
}

SWC_END_NAMESPACE();
