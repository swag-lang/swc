#include "pch.h"
#include "Backend/Micro/Passes/Pass.BranchSimplify.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.SsaValuePropagation.Internal.h"
#include "Support/Math/ApsInt.h"
#include "Support/Report/Assert.h"

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
//   - If-convert the smallest branch shapes into conditional moves.
//
// The pass never invents new blocks or labels. It only retargets / erases
// existing jumps and then lets the surrounding optimization loop rebuild SSA.

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID_ORDINAL = std::numeric_limits<uint32_t>::max();

    // A register value known at compile time, and the WIDTH it is known at: a narrower
    // definition says nothing about the bits above it, which a wider reader would observe.
    // Every producer records the width it actually wrote and every consumer refuses to read
    // wider than that.
    struct KnownValue
    {
        uint64_t    value  = 0;
        MicroOpBits opBits = MicroOpBits::B64;
    };

    KnownValue makeKnownValue(uint64_t value, MicroOpBits opBits)
    {
        return {.value = value & getBitsMask(opBits), .opBits = opBits};
    }

    // The part of a known value a definition of 'writeBits' leaves behind: the copy carries
    // the low 'writeBits' bits, and anything the source itself did not define stays unknown.
    KnownValue narrowKnownValue(const KnownValue& source, MicroOpBits writeBits)
    {
        const MicroOpBits resultBits = getNumBits(writeBits) < getNumBits(source.opBits) ? writeBits : source.opBits;
        return makeKnownValue(source.value, resultBits);
    }

    bool isKnownAtLeast(const KnownValue& value, MicroOpBits readBits)
    {
        return getNumBits(value.opBits) >= getNumBits(readBits);
    }

    struct KnownValueTraits
    {
        [[maybe_unused]] static bool isValid(const KnownValue&)
        {
            return true;
        }

        [[maybe_unused]] static bool same(const KnownValue& lhs, const KnownValue& rhs)
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

                outValue = makeKnownValue(ops[2].valueU64, ops[1].opBits);
                return true;

            case MicroInstrOpcode::ClearReg:
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                outValue = makeKnownValue(0, ops[1].opBits);
                return true;

            case MicroInstrOpcode::LoadRegReg:
            {
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                // A narrower copy still carries a known value, just a narrower one. This is the
                // shape every materialized boolean takes ('%2 = 1' then a 'b8' copy into the
                // register the guard compares), so refusing it would leave the guard unfolded
                // until another pass happens to collapse the copy.
                KnownValue inputValue;
                if (!tryGetKnownReachingValue(inputValue, context, knownValues, knownFlags, ops[1].reg, valueInfo.instRef))
                    return false;

                outValue = narrowKnownValue(inputValue, ops[2].opBits);
                return true;
            }

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                if (ops[0].reg != valueInfo.reg || !valueInfo.reg.isVirtualInt())
                    return false;

                KnownValue inputValue;
                if (!tryGetKnownReachingValue(inputValue, context, knownValues, knownFlags, ops[0].reg, valueInfo.instRef))
                    return false;
                if (!isKnownAtLeast(inputValue, ops[1].opBits))
                    return false;

                uint64_t   foldedValue = 0;
                const auto status      = MicroPassHelpers::foldBinaryImmediate(foldedValue, inputValue.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits);
                if (status != Math::FoldStatus::Ok)
                    return false;

                outValue = makeKnownValue(foldedValue, ops[1].opBits);
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
                if (!isKnownAtLeast(lhs, ops[2].opBits) || !isKnownAtLeast(rhs, ops[2].opBits))
                    return false;

                uint64_t   foldedValue = 0;
                const auto status      = MicroPassHelpers::foldBinaryImmediate(foldedValue, lhs.value, rhs.value, ops[3].microOp, ops[2].opBits);
                if (status != Math::FoldStatus::Ok)
                    return false;

                outValue = makeKnownValue(foldedValue, ops[2].opBits);
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

        const ApsInt lhsUnsigned(std::bit_cast<int64_t>(lhsValue), bitWidth, true);
        const ApsInt rhsUnsigned(std::bit_cast<int64_t>(rhsValue), bitWidth, true);
        const ApsInt lhsSigned(std::bit_cast<int64_t>(lhsValue), bitWidth, false);
        const ApsInt rhsSigned(std::bit_cast<int64_t>(rhsValue), bitWidth, false);

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
                if (!isKnownAtLeast(lhsValue, flagOps[1].opBits))
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
                if (!isKnownAtLeast(lhsValue, flagOps[2].opBits) || !isKnownAtLeast(rhsValue, flagOps[2].opBits))
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

    // Logical complement of a branch condition at the CPU-flag level. The pairs
    // are exact complements over (CF, ZF, SF, OF, PF), so flipping is valid for
    // both integer and floating-point (unordered) comparisons. `Sign` has no
    // representable complement in the enum, so it (and anything unexpected)
    // reports failure and blocks the rewrite.
    bool invertBranchCondition(MicroCond cond, MicroCond& outInverted)
    {
        switch (cond)
        {
            case MicroCond::Equal: outInverted = MicroCond::NotEqual; return true;
            case MicroCond::NotEqual: outInverted = MicroCond::Equal; return true;
            case MicroCond::Zero: outInverted = MicroCond::NotZero; return true;
            case MicroCond::NotZero: outInverted = MicroCond::Zero; return true;
            case MicroCond::Less: outInverted = MicroCond::GreaterOrEqual; return true;
            case MicroCond::GreaterOrEqual: outInverted = MicroCond::Less; return true;
            case MicroCond::Greater: outInverted = MicroCond::LessOrEqual; return true;
            case MicroCond::LessOrEqual: outInverted = MicroCond::Greater; return true;
            case MicroCond::Below: outInverted = MicroCond::AboveOrEqual; return true;
            case MicroCond::AboveOrEqual: outInverted = MicroCond::Below; return true;
            case MicroCond::Above: outInverted = MicroCond::BelowOrEqual; return true;
            case MicroCond::BelowOrEqual: outInverted = MicroCond::Above; return true;
            case MicroCond::NotAbove: outInverted = MicroCond::Above; return true;
            case MicroCond::Overflow: outInverted = MicroCond::NotOverflow; return true;
            case MicroCond::NotOverflow: outInverted = MicroCond::Overflow; return true;
            case MicroCond::Parity: outInverted = MicroCond::NotParity; return true;
            case MicroCond::NotParity: outInverted = MicroCond::Parity; return true;
            case MicroCond::EvenParity: outInverted = MicroCond::NotEvenParity; return true;
            case MicroCond::NotEvenParity: outInverted = MicroCond::EvenParity; return true;
            default: return false;
        }
    }

    // Fuse a materialized-boolean branch back onto the comparison flags that
    // produced it:
    //
    //     cmp   a, b              cmp   a, b
    //     setcc CC, Rb            (Rb left for DCE)
    //     [zext Rb, Rb]      ->   (left for DCE)
    //     cmp   Rb, 0            (erased)
    //     je/jne .L              j(~CC)/j(CC) .L      ; tests a?b flags directly
    //
    // `setcc` and the optional widening never touch CPU flags, so once the
    // `cmp Rb, 0` is removed the branch observes exactly the flags `setcc`
    // consumed. Testing the boolean for zero is the logical complement of `CC`
    // (`je`), testing for non-zero is `CC` itself (`jne`). The boolean
    // definition is not erased here: dead-code elimination drops it on the next
    // sweep once `Rb` has no remaining users, which keeps this rewrite free of
    // liveness reasoning while still folding the common case.
    //
    // Chain members do not need to be adjacent: a boolean produced for a
    // short-circuit condition typically also feeds a copy or a spill store for
    // its consumer at the join, and those sit inside the chain. Instructions in
    // between are skipped as long as they leave the CPU flags, the boolean
    // register and the control flow alone; anything else ends the search and
    // blocks the fold.

    // Previous instruction that either touches the CPU flags, redefines
    // `trackedReg`, or (when `stopOnFlagUse`) reads the flags. Control-flow
    // boundaries (labels, terminators, jumps, calls) report failure.
    MicroInstrRef previousFlagChainInstruction(MicroStorage& storage, const MicroOperandStorage& operands, MicroInstrRef fromRef, MicroReg trackedReg, bool stopOnFlagUse)
    {
        for (MicroInstrRef scanRef = storage.findPreviousInstructionRef(fromRef); scanRef.isValid(); scanRef = storage.findPreviousInstructionRef(scanRef))
        {
            const MicroInstr* scanInst = storage.ptr(scanRef);
            if (!scanInst)
                return MicroInstrRef::invalid();

            const MicroInstrFlags flags = MicroInstr::info(scanInst->op).flags;
            if (scanInst->op == MicroInstrOpcode::Label ||
                flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return MicroInstrRef::invalid();

            if (flags.has(MicroInstrFlagsE::DefinesCpuFlags))
                return scanRef;
            if (stopOnFlagUse && flags.has(MicroInstrFlagsE::UsesCpuFlags))
                return scanRef;

            if (trackedReg.isValid())
            {
                const MicroInstrUseDef useDef         = scanInst->collectUseDef(operands, nullptr);
                bool                   definesTracked = false;
                for (const MicroReg def : useDef.defs)
                {
                    if (def == trackedReg)
                    {
                        definesTracked = true;
                        break;
                    }
                }
                if (definesTracked)
                    return scanRef;
            }
        }

        return MicroInstrRef::invalid();
    }

    bool fuseMaterializedBoolBranches(MicroStorage& storage, MicroOperandStorage& operands)
    {
        bool changed = false;
        for (auto it = storage.view().begin(); it != storage.view().end();)
        {
            const MicroInstrRef jumpRef  = it.current;
            MicroInstr&         jumpInst = *it;
            ++it;

            if (jumpInst.op != MicroInstrOpcode::JumpCond)
                continue;

            MicroInstrOperand* jumpOps = jumpInst.ops(operands);
            if (!jumpOps)
                continue;

            const MicroCond jumpCond = jumpOps[0].cpuCond;
            bool            branchOnBoolZero;
            if (jumpCond == MicroCond::Equal || jumpCond == MicroCond::Zero)
                branchOnBoolZero = true;
            else if (jumpCond == MicroCond::NotEqual || jumpCond == MicroCond::NotZero)
                branchOnBoolZero = false;
            else
                continue;

            // The next flag-relevant instruction upstream must be the boolean
            // test; a flag reader in between would lose the erased compare.
            const MicroInstrRef cmpRef = previousFlagChainInstruction(storage, operands, jumpRef, MicroReg::invalid(), true);
            if (!cmpRef.isValid())
                continue;
            const MicroInstr* cmpInst = storage.ptr(cmpRef);
            if (!cmpInst || cmpInst->op != MicroInstrOpcode::CmpRegImm)
                continue;
            const MicroInstrOperand* cmpOps = cmpInst->ops(operands);
            if (!cmpOps || cmpOps[2].hasWideImmediateValue() || cmpOps[2].valueU64 != 0)
                continue;

            const MicroReg boolReg = cmpOps[0].reg;
            if (!boolReg.isVirtual())
                continue;

            // The fall-through path keeps observing the flags at the jump, so
            // the compare can only go when nothing downstream reads them.
            if (!MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, jumpRef))
                continue;

            // Readers between the setcc and the compare still see the original
            // comparison's flags, so only flag writers end the walk here.
            MicroInstrRef     defRef  = previousFlagChainInstruction(storage, operands, cmpRef, boolReg, false);
            const MicroInstr* defInst = defRef.isValid() ? storage.ptr(defRef) : nullptr;
            if (!defInst)
                continue;

            if (defInst->op == MicroInstrOpcode::LoadZeroExtRegReg || defInst->op == MicroInstrOpcode::LoadSignedExtRegReg)
            {
                const MicroInstrOperand* extOps = defInst->ops(operands);
                if (!extOps || extOps[0].reg != boolReg || extOps[1].reg != boolReg)
                    continue;
                defRef  = previousFlagChainInstruction(storage, operands, defRef, boolReg, false);
                defInst = defRef.isValid() ? storage.ptr(defRef) : nullptr;
                if (!defInst)
                    continue;
            }

            if (defInst->op != MicroInstrOpcode::SetCondReg)
                continue;
            const MicroInstrOperand* setOps = defInst->ops(operands);
            if (!setOps || setOps[0].reg != boolReg)
                continue;

            const MicroCond setCond = setOps[1].cpuCond;
            MicroCond       newCond = setCond;
            if (branchOnBoolZero && !invertBranchCondition(setCond, newCond))
                continue;

            jumpOps[0].cpuCond = newCond;
            changed |= storage.erase(cmpRef);
        }

        return changed;
    }

    // Threads a short-circuit exit through the boolean merge it decides.
    //
    // The `and`/`or` lowering materializes its result and branches around the
    // rhs on the lhs comparison flags:
    //
    //     cmp   a, b                          cmp   a, b
    //     setcc CC, B                         setcc CC, B     (left for DCE)
    //     [zext B] [mov B', ..]               ...
    //     j(~CC) .JOIN                        j(~CC) .EXIT    ; B is 0 there
    //     <rhs>                               <rhs>
    //     .JOIN:                       ->     .JOIN:
    //     cmp   B, 0                          cmp   B, 0
    //     je    .EXIT                         je    .EXIT
    //
    // On the taken edge the boolean's value is pinned by the branch condition
    // itself, so the join's test is already decided: the jump goes straight to
    // the join's own target. Once the threaded edge no longer reaches the
    // join, the remaining single-definition chain is the shape
    // fuseMaterializedBoolBranches folds, and the loop condition ends up as
    // two plain compare-and-branch pairs.
    bool threadShortCircuitExits(MicroStorage& storage, MicroOperandStorage& operands)
    {
        ProgramLayout layout;
        buildProgramLayout(layout, storage, operands);

        bool changed = false;
        for (const MicroInstrRef jumpRef : layout.order)
        {
            MicroInstr* jumpInst = storage.ptr(jumpRef);
            if (!jumpInst || jumpInst->op != MicroInstrOpcode::JumpCond)
                continue;
            MicroInstrOperand* jumpOps = jumpInst->ops(operands);
            if (!jumpOps || jumpOps[0].cpuCond == MicroCond::Unconditional)
                continue;
            uint32_t joinLabelId = 0;
            if (!tryGetJumpTargetLabelId(joinLabelId, *jumpInst, jumpOps))
                continue;

            // Walk the boolean chain immediately preceding the jump:
            // an optional plain copy, an optional self zero-extend, then the
            // setcc that consumed the same flags the jump reads. None of these
            // touch the flags, so the jump still observes the setcc's compare.
            MicroInstrRef     curRef  = storage.findPreviousInstructionRef(jumpRef);
            const MicroInstr* curInst = curRef.isValid() ? storage.ptr(curRef) : nullptr;
            if (!curInst)
                continue;

            MicroReg boolReg = MicroReg::invalid();
            MicroReg chainReg;
            if (curInst->op == MicroInstrOpcode::LoadRegReg)
            {
                const MicroInstrOperand* copyOps = curInst->ops(operands);
                if (!copyOps || !copyOps[0].reg.isVirtual())
                    continue;
                boolReg  = copyOps[0].reg;
                chainReg = copyOps[1].reg;
                curRef   = storage.findPreviousInstructionRef(curRef);
                curInst  = curRef.isValid() ? storage.ptr(curRef) : nullptr;
                if (!curInst)
                    continue;
            }
            if (curInst->op == MicroInstrOpcode::LoadZeroExtRegReg)
            {
                const MicroInstrOperand* extOps = curInst->ops(operands);
                if (!extOps || extOps[0].reg != extOps[1].reg)
                    continue;
                if (boolReg.isValid() && extOps[0].reg != chainReg)
                    continue;
                if (!boolReg.isValid())
                {
                    boolReg  = extOps[0].reg;
                    chainReg = extOps[0].reg;
                }
                curRef  = storage.findPreviousInstructionRef(curRef);
                curInst = curRef.isValid() ? storage.ptr(curRef) : nullptr;
                if (!curInst)
                    continue;
            }
            if (curInst->op != MicroInstrOpcode::SetCondReg)
                continue;
            const MicroInstrOperand* setOps = curInst->ops(operands);
            if (!setOps)
                continue;
            if (boolReg.isValid() && setOps[0].reg != chainReg)
                continue;
            if (!boolReg.isValid())
                boolReg = setOps[0].reg;
            if (!boolReg.isVirtual())
                continue;

            // The branch condition pins the boolean's value on the taken edge.
            const MicroCond setCond = setOps[1].cpuCond;
            MicroCond       invCond = MicroCond::Unconditional;
            bool            boolOne = false;
            if (setCond == jumpOps[0].cpuCond)
                boolOne = true;
            else if (!invertBranchCondition(setCond, invCond) || invCond != jumpOps[0].cpuCond)
                continue;

            // The join must be exactly `cmp boolReg, 0` + a conditional jump.
            const auto labelIt = layout.labelOrdinalById.find(joinLabelId);
            if (labelIt == layout.labelOrdinalById.end() || labelIt->second + 2 >= layout.order.size())
                continue;
            const MicroInstr* joinCmp = storage.ptr(layout.order[labelIt->second + 1]);
            if (!joinCmp || joinCmp->op != MicroInstrOpcode::CmpRegImm)
                continue;
            const MicroInstrOperand* joinCmpOps = joinCmp->ops(operands);
            if (!joinCmpOps || joinCmpOps[0].reg != boolReg || joinCmpOps[2].hasWideImmediateValue() || joinCmpOps[2].valueU64 != 0)
                continue;
            const MicroInstr* joinJump = storage.ptr(layout.order[labelIt->second + 2]);
            if (!joinJump || joinJump->op != MicroInstrOpcode::JumpCond)
                continue;
            const MicroInstrOperand* joinJumpOps = joinJump->ops(operands);
            if (!joinJumpOps)
                continue;

            const MicroCond joinCond = joinJumpOps[0].cpuCond;
            const bool      joinTakenOnZero =
                joinCond == MicroCond::Equal || joinCond == MicroCond::Zero;
            const bool joinTakenOnOne =
                joinCond == MicroCond::NotEqual || joinCond == MicroCond::NotZero;
            if (!(boolOne ? joinTakenOnOne : joinTakenOnZero))
                continue;

            uint32_t joinTargetId = 0;
            if (!tryGetJumpTargetLabelId(joinTargetId, *joinJump, joinJumpOps) || joinTargetId == joinLabelId)
                continue;

            jumpOps[2].valueU64 = joinTargetId;
            changed             = true;
        }

        return changed;
    }

    // Labels no jump references are pure fall-through markers, but they stop
    // every straight-line pattern walk (the materialized-boolean fusion in
    // particular). The sweep collects the targets of every label-consuming
    // jump form and stands down entirely next to computed jumps or
    // instruction-anchored relocations, whose targets it cannot see.
    bool eraseUnreferencedLabels(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        std::unordered_set<uint64_t> referencedLabels;
        std::unordered_set<uint32_t> relocInstrRefs;
        SmallVector<MicroInstrRef>   labelRefs;

        if (context.builder)
        {
            for (const MicroRelocation& reloc : context.builder->codeRelocations())
            {
                if (reloc.instructionRef.isValid())
                    relocInstrRefs.insert(reloc.instructionRef.get());
            }
        }

        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstr& inst = *it;
            if (inst.op == MicroInstrOpcode::JumpReg)
                return false;
            if (inst.op == MicroInstrOpcode::Label)
            {
                if (!relocInstrRefs.contains(it.current.get()))
                    labelRefs.push_back(it.current);
                continue;
            }
            if (inst.op != MicroInstrOpcode::JumpCond && inst.op != MicroInstrOpcode::JumpCondImm)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops || inst.numOperands < 3)
                return false;
            referencedLabels.insert(ops[2].valueU64);
        }

        bool changed = false;
        for (const MicroInstrRef labelRef : labelRefs)
        {
            const MicroInstr*        labelInst = storage.ptr(labelRef);
            const MicroInstrOperand* labelOps  = labelInst ? labelInst->ops(operands) : nullptr;
            if (!labelOps || referencedLabels.contains(labelOps[0].valueU64))
                continue;
            changed |= storage.erase(labelRef);
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

    // A conditional jump over an unconditional one folds into a single
    // inverted branch when the conditional's target is the label run right
    // after the pair:
    //
    //     jcc  CC, .Lnext              jcc  ~CC, .Lfar
    //     jmp  .Lfar            =>     .Lnext:
    //     .Lnext:
    //
    // This is what `if cond do continue` inside a loop lowers to, so without
    // the fold the hot path pays a taken jump on every iteration. Flag
    // conditions come in exact complement pairs (unordered float compares
    // included), so the inversion is semantics-preserving at the flags level.
    bool invertJumpOverAdjacentJump(MicroStorage& storage, MicroOperandStorage& operands)
    {
        ProgramLayout layout;
        buildProgramLayout(layout, storage, operands);

        bool changed = false;
        for (auto it = storage.view().begin(); it != storage.view().end();)
        {
            MicroInstr& condInst = *it;
            ++it;

            if (condInst.op != MicroInstrOpcode::JumpCond)
                continue;
            MicroInstrOperand* condOps = condInst.ops(operands);
            if (!condOps || condInst.numOperands < 3 || condOps[0].cpuCond == MicroCond::Unconditional)
                continue;

            if (it == storage.view().end())
                break;

            const MicroInstrRef jumpRef  = it.current;
            const MicroInstr&   jumpInst = *it;
            if (jumpInst.op != MicroInstrOpcode::JumpCond)
                continue;
            const MicroInstrOperand* jumpOps = jumpInst.ops(operands);
            if (!jumpOps || jumpInst.numOperands < 3 || jumpOps[0].cpuCond != MicroCond::Unconditional)
                continue;

            uint32_t condTarget = 0;
            uint32_t jumpTarget = 0;
            if (!tryGetJumpTargetLabelId(condTarget, condInst, condOps))
                continue;
            if (!tryGetJumpTargetLabelId(jumpTarget, jumpInst, jumpOps))
                continue;
            if (condTarget == jumpTarget)
                continue;

            if (!isTargetInImmediateLabelRun(layout, storage, operands, jumpRef, condTarget))
                continue;

            MicroCond inverted = MicroCond::Unconditional;
            if (!invertBranchCondition(condOps[0].cpuCond, inverted))
                continue;

            ++it;
            condOps[0].cpuCond  = inverted;
            condOps[2].valueU64 = jumpTarget;
            changed |= storage.erase(jumpRef);
        }

        return changed;
    }

    // Conditions the cmov encoder can express. Every condition
    // invertBranchCondition can produce is encodable; this only fences off
    // the unconditional marker defensively.
    bool conditionSupportsConditionalMove(const MicroCond cond)
    {
        return cond != MicroCond::Unconditional;
    }

    // If-conversion of the smallest diamond-free branch:
    //
    //     jcc   CC, .L                cmov(~CC) D, S      ; or: mov T, imm
    //     mov   D, S             ->                       ;     cmov(~CC) D, T
    //     .L:                         .L:
    //
    // The skipped body runs exactly when CC is false, which is what the
    // conditional move with the inverted condition expresses; the label stays
    // for any other jump that targets it. A single-copy body converts
    // directly. A single immediate-load body converts by materializing the
    // immediate into a fresh scratch register above the branch — an immediate
    // load never touches the CPU flags the move consumes. This removes the
    // classic min/max and conditional-constant branches, which are the least
    // predictable ones in the numeric kernels.
    bool convertBranchesToConditionalMoves(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        struct Conversion
        {
            MicroInstrRef jumpRef  = MicroInstrRef::invalid();
            MicroInstrRef bodyRef  = MicroInstrRef::invalid();
            MicroInstrRef labelRef = MicroInstrRef::invalid();
            MicroCond     cond     = MicroCond::Unconditional;
            bool          fromImm  = false;
        };

        SmallVector<Conversion> conversions;

        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstr& jumpInst = *it;
            if (jumpInst.op != MicroInstrOpcode::JumpCond)
                continue;
            const MicroInstrOperand* jumpOps = jumpInst.ops(operands);
            if (!jumpOps || jumpOps[0].cpuCond == MicroCond::Unconditional)
                continue;

            const MicroInstrRef bodyRef = storage.findNextInstructionRef(it.current);
            if (!bodyRef.isValid())
                continue;
            const MicroInstr* bodyInst = storage.ptr(bodyRef);
            if (!bodyInst)
                continue;

            bool fromImm = false;
            if (bodyInst->op == MicroInstrOpcode::LoadRegImm)
                fromImm = true;
            else if (bodyInst->op != MicroInstrOpcode::LoadRegReg)
                continue;

            const MicroInstrOperand* bodyOps = bodyInst->ops(operands);
            if (!bodyOps)
                continue;

            // cmov exists for 32/64-bit integer registers only.
            const MicroOpBits bodyBits = fromImm ? bodyOps[1].opBits : bodyOps[2].opBits;
            if (getNumBits(bodyBits) < 32)
                continue;
            const MicroReg dstReg = bodyOps[0].reg;
            if (!dstReg.isVirtualInt() && !dstReg.isInt())
                continue;
            if (!fromImm)
            {
                const MicroReg srcReg = bodyOps[1].reg;
                if (!srcReg.isVirtualInt() && !srcReg.isInt())
                    continue;
            }
            // A >64-bit immediate cannot be re-materialized from the stored word.
            if (fromImm && bodyOps[2].valueInt.bitWidth() > 64)
                continue;

            const MicroInstrRef labelRef = storage.findNextInstructionRef(bodyRef);
            if (!labelRef.isValid())
                continue;
            const MicroInstr* labelInst = storage.ptr(labelRef);
            if (!labelInst)
                continue;
            uint32_t labelId = 0;
            if (!tryGetLabelId(labelId, *labelInst, labelInst->ops(operands)))
                continue;
            uint32_t targetLabelId = 0;
            if (!tryGetJumpTargetLabelId(targetLabelId, jumpInst, jumpOps) || targetLabelId != labelId)
                continue;

            MicroCond inverted = MicroCond::Unconditional;
            if (!invertBranchCondition(jumpOps[0].cpuCond, inverted) || !conditionSupportsConditionalMove(inverted))
                continue;

            conversions.push_back({.jumpRef = it.current, .bodyRef = bodyRef, .labelRef = labelRef, .cond = inverted, .fromImm = fromImm});
        }

        if (conversions.empty())
            return false;

        uint32_t nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);

        for (const Conversion& conversion : conversions)
        {
            const MicroInstr*        bodyInst = storage.ptr(conversion.bodyRef);
            const MicroInstrOperand* bodyOps  = bodyInst ? bodyInst->ops(operands) : nullptr;
            if (!bodyOps)
                continue;

            const MicroReg    dstReg   = bodyOps[0].reg;
            const MicroOpBits bodyBits = conversion.fromImm ? bodyOps[1].opBits : bodyOps[2].opBits;
            MicroReg          srcReg   = MicroReg::invalid();

            if (conversion.fromImm)
            {
                srcReg = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);

                MicroInstrOperand immOps[3];
                immOps[0].reg    = srcReg;
                immOps[1].opBits = bodyBits;
                immOps[2].setImmediateValue(bodyOps[2].immediateValue());
                storage.insertDerivedBefore(operands, conversion.jumpRef, MicroInstrOpcode::LoadRegImm, immOps);
            }
            else
            {
                srcReg = bodyOps[1].reg;
            }

            MicroInstrOperand movOps[4];
            movOps[0].reg     = dstReg;
            movOps[1].reg     = srcReg;
            movOps[2].cpuCond = conversion.cond;
            movOps[3].opBits  = bodyBits;
            storage.insertDerivedBefore(operands, conversion.labelRef, MicroInstrOpcode::LoadCondRegReg, movOps);

            storage.erase(conversion.jumpRef);
            storage.erase(conversion.bodyRef);
        }

        return true;
    }

    // Speculative if-conversion of the two-armed diamond a ternary lowers to:
    //
    //     cmp   X, Y                    A...                ; unchanged
    //     jcc   CC, .Lb                 B'...               ; every D in B renamed D'
    //     A...  (defines D)       ->    [cmp X, Y]          ; re-issued when an arm wrote the flags
    //     jmp   .Ljoin                  cmov(CC) D, D'
    //   .Lb:                          .Ljoin:
    //     B...  (defines D)
    //   .Ljoin:
    //
    // Both arms run and the condition picks the result, which is what clang
    // and MSVC emit for `c ? a : b`, `Math.clamp` and every integer select in
    // a pixel loop. Running an arm on the path that used to skip it is only
    // sound when every instruction in it is pure and cannot fault — no memory
    // access, no call, no division — when the arm leaves nothing behind but D,
    // and when the arm the branch used to skip reads nothing the other arm
    // overwrote. Short arms only: past a handful of instructions the work of
    // the untaken arm costs more than the branch it replaces. The single-arm
    // triangle is convertBranchesToConditionalMoves above; a diamond whose
    // arms hold their own selects converts from the inside out, one
    // fixed-point iteration per nesting level.
    constexpr uint32_t K_MAX_IF_CONVERT_ARM_INSTR = 6;

    bool isSpeculatableMicroOp(const MicroOp op)
    {
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::Subtract:
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticLeft:
            case MicroOp::ShiftArithmeticRight:
            case MicroOp::RotateLeft:
            case MicroOp::RotateRight:
            case MicroOp::MultiplySigned:
            case MicroOp::Negate:
            case MicroOp::BitwiseNot:
                return true;
            default:
                return false;
        }
    }

    // An instruction that can run on a path that used to skip it: no memory
    // read (a guarded load may fault), no write, no call, no trap, and
    // integer register results the conditional move can join.
    bool isSpeculatableArmInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!ops)
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadAddrRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
            case MicroInstrOpcode::CmpRegReg:
            case MicroInstrOpcode::CmpRegImm:
            case MicroInstrOpcode::LoadCondRegReg:
            case MicroInstrOpcode::ClearReg:
                return true;
            case MicroInstrOpcode::OpBinaryRegReg:
                return isSpeculatableMicroOp(ops[3].microOp);
            case MicroInstrOpcode::OpBinaryRegImm:
                return isSpeculatableMicroOp(ops[2].microOp);
            case MicroInstrOpcode::OpBinaryRegRegReg:
                return isSpeculatableMicroOp(ops[4].microOp);
            case MicroInstrOpcode::OpBinaryRegRegImm:
                return isSpeculatableMicroOp(ops[3].microOp);
            case MicroInstrOpcode::OpUnaryReg:
                return isSpeculatableMicroOp(ops[2].microOp);
            default:
                return false;
        }
    }

    // The width an arm instruction writes its destination at. Zero for the
    // compares, which define no register.
    MicroOpBits armInstructionWriteBits(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::ClearReg:
            case MicroInstrOpcode::OpBinaryRegImm:
            case MicroInstrOpcode::OpUnaryReg:
                return ops[1].opBits;
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadAddrRegMem:
            case MicroInstrOpcode::OpBinaryRegReg:
            case MicroInstrOpcode::OpBinaryRegRegImm:
                return ops[2].opBits;
            case MicroInstrOpcode::LoadAddrAmcRegMem:
            case MicroInstrOpcode::LoadCondRegReg:
            case MicroInstrOpcode::OpBinaryRegRegReg:
                return ops[3].opBits;
            default:
                return MicroOpBits::Zero;
        }
    }

    struct DiamondArm
    {
        SmallVector<MicroInstrRef, 8> refs;
        SmallVector<MicroReg, 8>      defs;
        MicroOpBits                   resultBits      = MicroOpBits::Zero;
        bool                          definesFlags    = false;
        bool                          readsEntryFlags = false;
    };

    struct Diamond
    {
        MicroInstrRef flagsRef     = MicroInstrRef::invalid();
        MicroInstrRef jumpRef      = MicroInstrRef::invalid();
        MicroInstrRef joinJumpRef  = MicroInstrRef::invalid();
        MicroInstrRef armLabelRef  = MicroInstrRef::invalid();
        MicroInstrRef joinLabelRef = MicroInstrRef::invalid();
        DiamondArm    fallthroughArm;
        DiamondArm    jumpArm;
        MicroCond     cond        = MicroCond::Unconditional;
        MicroReg      result      = MicroReg::invalid();
        MicroOpBits   moveBits    = MicroOpBits::B64;
        bool          sinkCompare = false;
    };

    struct DiamondScan
    {
        const MicroSsaState*                   ssa      = nullptr;
        const MicroStorage*                    storage  = nullptr;
        const MicroOperandStorage*             operands = nullptr;
        std::unordered_map<uint64_t, uint32_t> labelReferences;
        std::unordered_set<uint32_t>           relocated;
    };

    // Collect up to K_MAX_IF_CONVERT_ARM_INSTR speculatable instructions after
    // `fromRef`, stopping at the first one that is not; that instruction comes
    // back in `outStopRef` for the caller to classify.
    bool collectDiamondArm(DiamondArm& outArm, MicroInstrRef& outStopRef, const DiamondScan& scan, MicroInstrRef fromRef)
    {
        outStopRef = scan.storage->findNextInstructionRef(fromRef);
        while (outStopRef.isValid())
        {
            const MicroInstr*        inst = scan.storage->ptr(outStopRef);
            const MicroInstrOperand* ops  = inst ? inst->ops(*scan.operands) : nullptr;
            if (!inst || !isSpeculatableArmInstruction(*inst, ops))
                return true;
            if (outArm.refs.size() >= K_MAX_IF_CONVERT_ARM_INSTR || scan.relocated.contains(outStopRef.get()))
                return false;
            outArm.refs.push_back(outStopRef);
            outStopRef = scan.storage->findNextInstructionRef(outStopRef);
        }
        return false;
    }

    // The two arms and the three control instructions, by position alone. The
    // SSA-backed checks come after, once a function is known to hold a diamond
    // at all, so the analysis is not rebuilt for the many that hold none.
    bool tryMatchDiamondShape(Diamond& out, const DiamondScan& scan, MicroInstrRef jumpRef, const MicroInstr& jumpInst, const MicroInstrOperand* jumpOps)
    {
        uint32_t armLabelId = 0;
        if (!tryGetJumpTargetLabelId(armLabelId, jumpInst, jumpOps))
            return false;

        // The fall-through arm, ended by the jump to the join.
        MicroInstrRef stopRef;
        if (!collectDiamondArm(out.fallthroughArm, stopRef, scan, jumpRef) || out.fallthroughArm.refs.empty())
            return false;
        const MicroInstr*        joinJumpInst = scan.storage->ptr(stopRef);
        const MicroInstrOperand* joinJumpOps  = joinJumpInst->ops(*scan.operands);
        uint32_t                 joinLabelId  = 0;
        if (joinJumpInst->op != MicroInstrOpcode::JumpCond || !joinJumpOps || joinJumpOps[0].cpuCond != MicroCond::Unconditional)
            return false;
        if (!tryGetJumpTargetLabelId(joinLabelId, *joinJumpInst, joinJumpOps) || joinLabelId == armLabelId)
            return false;
        out.joinJumpRef = stopRef;

        // The jump arm's label is reached from this branch alone, so folding
        // the arm into the straight line strands no other path.
        out.armLabelRef = scan.storage->findNextInstructionRef(out.joinJumpRef);
        if (!out.armLabelRef.isValid() || scan.relocated.contains(out.armLabelRef.get()))
            return false;
        const MicroInstr* armLabelInst = scan.storage->ptr(out.armLabelRef);
        uint32_t          labelId      = 0;
        if (!tryGetLabelId(labelId, *armLabelInst, armLabelInst->ops(*scan.operands)) || labelId != armLabelId)
            return false;
        const auto referenceIt = scan.labelReferences.find(armLabelId);
        if (referenceIt == scan.labelReferences.end() || referenceIt->second != 1)
            return false;

        // The jump arm, ended by the join label.
        if (!collectDiamondArm(out.jumpArm, stopRef, scan, out.armLabelRef) || out.jumpArm.refs.empty())
            return false;
        const MicroInstr* joinLabelInst = scan.storage->ptr(stopRef);
        if (!tryGetLabelId(labelId, *joinLabelInst, joinLabelInst->ops(*scan.operands)) || labelId != joinLabelId)
            return false;
        out.joinLabelRef = stopRef;

        out.jumpRef = jumpRef;
        out.cond    = jumpOps[0].cpuCond;
        return true;
    }

    // True when something outside `insideRefs` reads the value — directly, or
    // through the phis that merge it with the other arm's result at the join.
    bool isValueReadOutside(const MicroSsaState& ssa, uint32_t valueId, const std::unordered_set<uint32_t>& insideRefs, SmallVector<uint32_t>& visitedPhis)
    {
        const MicroSsaState::ValueInfo* info = ssa.valueInfo(valueId);
        if (!info)
            return true;

        for (const MicroSsaState::UseSite& use : info->uses)
        {
            if (use.kind == MicroSsaState::UseSite::Kind::Instruction)
            {
                if (!insideRefs.contains(use.instRef.get()))
                    return true;
                continue;
            }

            if (std::ranges::find(visitedPhis, use.phiIndex) != visitedPhis.end())
                continue;
            if (visitedPhis.size() >= 16)
                return true;
            visitedPhis.push_back(use.phiIndex);

            const MicroSsaState::PhiInfo* phi = ssa.phiInfo(use.phiIndex);
            if (!phi || phi->resultValueId == MicroSsaState::K_INVALID_VALUE)
                return true;
            if (isValueReadOutside(ssa, phi->resultValueId, insideRefs, visitedPhis))
                return true;
        }

        return false;
    }

    // Classify one arm: what it writes, whether it touches the flags, and the
    // single register it hands to the join. Fails when the arm leaks anything
    // other than that one register.
    bool analyzeDiamondArm(DiamondArm& arm, MicroReg& outResult, const DiamondScan& scan)
    {
        std::unordered_set<uint32_t> insideRefs;
        for (const MicroInstrRef ref : arm.refs)
            insideRefs.insert(ref.get());

        outResult              = MicroReg::invalid();
        bool definedFlagsSoFar = false;
        for (const MicroInstrRef ref : arm.refs)
        {
            const MicroInstr*        inst = scan.storage->ptr(ref);
            const MicroInstrOperand* ops  = inst->ops(*scan.operands);
            const MicroInstrDef&     info = MicroInstr::info(inst->op);
            if (info.flags.has(MicroInstrFlagsE::UsesCpuFlags) && !definedFlagsSoFar)
                arm.readsEntryFlags = true;
            if (info.flags.has(MicroInstrFlagsE::DefinesCpuFlags))
            {
                arm.definesFlags  = true;
                definedFlagsSoFar = true;
            }

            const MicroInstrUseDef* useDef = scan.ssa->instrUseDef(ref);
            if (!useDef)
                return false;

            for (const MicroReg def : useDef->defs)
            {
                if (!def.isVirtualInt())
                    return false;
                arm.defs.push_back(def);

                uint32_t valueId = MicroSsaState::K_INVALID_VALUE;
                if (!scan.ssa->defValue(def, ref, valueId))
                    return false;

                SmallVector<uint32_t> visitedPhis;
                if (!isValueReadOutside(*scan.ssa, valueId, insideRefs, visitedPhis))
                    continue;

                // Exactly one register may leave the arm, and only its last
                // write can reach the join, so the width seen here is final.
                if (outResult.isValid() && outResult != def)
                    return false;
                outResult      = def;
                arm.resultBits = armInstructionWriteBits(*inst, ops);
            }
        }

        return outResult.isValid();
    }

    // True when `arm` reads `reg` before writing it, i.e. observes the value
    // live at its entry.
    bool armReadsRegisterLiveIn(const DiamondArm& arm, const DiamondScan& scan, const MicroReg reg)
    {
        for (const MicroInstrRef ref : arm.refs)
        {
            const MicroInstrUseDef* useDef = scan.ssa->instrUseDef(ref);
            if (std::ranges::find(useDef->uses, reg) != useDef->uses.end())
                return true;
            if (std::ranges::find(useDef->defs, reg) != useDef->defs.end())
                return false;
        }
        return false;
    }

    bool qualifyDiamond(Diamond& diamond, const DiamondScan& scan)
    {
        MicroReg fallthroughResult;
        MicroReg jumpResult;
        if (!analyzeDiamondArm(diamond.fallthroughArm, fallthroughResult, scan))
            return false;
        if (!analyzeDiamondArm(diamond.jumpArm, jumpResult, scan))
            return false;
        if (fallthroughResult != jumpResult)
            return false;
        diamond.result = fallthroughResult;

        // cmov exists for 32/64-bit registers only. The move must carry every
        // bit either arm defined: a 32-bit write zero-extends, so the wider of
        // the two final writes is the width that keeps both results intact.
        const uint32_t fallthroughBits = getNumBits(diamond.fallthroughArm.resultBits);
        const uint32_t jumpBits        = getNumBits(diamond.jumpArm.resultBits);
        if (fallthroughBits < 32 || jumpBits < 32)
            return false;
        diamond.moveBits = fallthroughBits == 64 || jumpBits == 64 ? MicroOpBits::B64 : MicroOpBits::B32;

        // The jump arm now runs after the fall-through arm. Its first touch of
        // the result must be a write (the rename to D' then covers every
        // occurrence), and it must not read anything the other arm wrote.
        if (armReadsRegisterLiveIn(diamond.jumpArm, scan, diamond.result))
            return false;
        for (const MicroReg def : diamond.fallthroughArm.defs)
        {
            if (def != diamond.result && armReadsRegisterLiveIn(diamond.jumpArm, scan, def))
                return false;
        }

        // When neither arm writes the flags, the conditional move at the join
        // still observes the compare that fed the branch, wherever it sits.
        // Otherwise the compare is re-issued right before the move: it must be
        // the instruction feeding the branch, a pure register compare whose
        // inputs neither arm overwrites, and no arm may read the flags it
        // enters with, since those flags will no longer be the compare's.
        diamond.sinkCompare = diamond.fallthroughArm.definesFlags || diamond.jumpArm.definesFlags;
        if (!diamond.sinkCompare)
            return true;
        if (diamond.fallthroughArm.readsEntryFlags || diamond.jumpArm.readsEntryFlags)
            return false;

        diamond.flagsRef = scan.storage->findPreviousInstructionRef(diamond.jumpRef);
        if (!diamond.flagsRef.isValid() || scan.relocated.contains(diamond.flagsRef.get()))
            return false;
        const MicroInstr* flagsInst = scan.storage->ptr(diamond.flagsRef);
        if (flagsInst->op != MicroInstrOpcode::CmpRegReg && flagsInst->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const MicroInstrUseDef* flagsUseDef = scan.ssa->instrUseDef(diamond.flagsRef);
        if (!flagsUseDef)
            return false;
        for (const MicroReg use : flagsUseDef->uses)
        {
            if (std::ranges::find(diamond.fallthroughArm.defs, use) != diamond.fallthroughArm.defs.end())
                return false;
            if (std::ranges::find(diamond.jumpArm.defs, use) != diamond.jumpArm.defs.end())
                return false;
        }

        // After the join the flags used to be whichever arm last wrote them;
        // now they are the compare's. Nothing may depend on either.
        return MicroPassHelpers::areCpuFlagsDeadAfter(*scan.storage, *scan.operands, diamond.joinLabelRef);
    }

    bool convertDiamondsToConditionalMoves(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context, MicroSsaState& localSsaState)
    {
        DiamondScan scan;
        scan.storage  = &storage;
        scan.operands = &operands;

        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstr& inst = *it;
            if (inst.op == MicroInstrOpcode::JumpReg)
                return false;
            if (inst.op != MicroInstrOpcode::JumpCond && inst.op != MicroInstrOpcode::JumpCondImm)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops || inst.numOperands < 3)
                return false;
            ++scan.labelReferences[ops[2].valueU64];
        }

        if (context.builder)
        {
            for (const MicroRelocation& reloc : context.builder->codeRelocations())
            {
                if (reloc.instructionRef.isValid())
                    scan.relocated.insert(reloc.instructionRef.get());
            }
        }

        std::vector<Diamond> diamonds;
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstr& jumpInst = *it;
            if (jumpInst.op != MicroInstrOpcode::JumpCond)
                continue;
            const MicroInstrOperand* jumpOps = jumpInst.ops(operands);
            if (!jumpOps || jumpOps[0].cpuCond == MicroCond::Unconditional)
                continue;

            Diamond diamond;
            if (tryMatchDiamondShape(diamond, scan, it.current, jumpInst, jumpOps))
                diamonds.push_back(std::move(diamond));
        }

        if (diamonds.empty())
            return false;

        scan.ssa = MicroSsaState::ensureFor(context, localSsaState);
        if (!scan.ssa || !scan.ssa->isValid())
            return false;

        std::erase_if(diamonds, [&scan](Diamond& diamond) { return !qualifyDiamond(diamond, scan); });
        if (diamonds.empty())
            return false;

        uint32_t nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        for (const Diamond& diamond : diamonds)
        {
            const MicroReg renamedResult = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);

            SmallVector<MicroInstrRegOperandRef> regOperands;
            for (const MicroInstrRef ref : diamond.jumpArm.refs)
            {
                regOperands.clear();
                storage.ptr(ref)->collectRegOperands(operands, regOperands, context.encoder);
                for (const MicroInstrRegOperandRef& regOperand : regOperands)
                {
                    if (*regOperand.reg == diamond.result)
                        *regOperand.reg = renamedResult;
                }
            }

            if (diamond.sinkCompare)
            {
                const MicroInstr*        flagsInst = storage.ptr(diamond.flagsRef);
                const MicroInstrOperand* flagsOps  = flagsInst->ops(operands);
                MicroInstrOperand        sunkOps[3];
                SWC_ASSERT(flagsInst->numOperands <= 3);
                for (uint32_t i = 0; i < flagsInst->numOperands; ++i)
                    sunkOps[i] = flagsOps[i];
                storage.insertDerivedBefore(operands, diamond.joinLabelRef, flagsInst->op, std::span<const MicroInstrOperand>(sunkOps, flagsInst->numOperands));
                storage.erase(diamond.flagsRef);
            }

            MicroInstrOperand movOps[4];
            movOps[0].reg     = diamond.result;
            movOps[1].reg     = renamedResult;
            movOps[2].cpuCond = diamond.cond;
            movOps[3].opBits  = diamond.moveBits;
            storage.insertDerivedBefore(operands, diamond.joinLabelRef, MicroInstrOpcode::LoadCondRegReg, movOps);

            storage.erase(diamond.jumpRef);
            storage.erase(diamond.joinJumpRef);
            storage.erase(diamond.armLabelRef);
        }

        return true;
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

    changed |= fuseMaterializedBoolBranches(storage, operands);
    changed |= threadShortCircuitExits(storage, operands);
    changed |= eraseUnreferencedLabels(storage, operands, context);

    if (convertBranchesToConditionalMoves(storage, operands, context))
    {
        changed = true;
        if (context.builder)
            context.builder->invalidateControlFlowGraph();
    }

    bool structuralChanged = true;
    while (structuralChanged)
    {
        structuralChanged = false;

        structuralChanged |= redirectJumpChains(storage, operands);
        structuralChanged |= eraseJumpsToImmediateLabels(storage, operands);
        structuralChanged |= invertJumpOverAdjacentJump(storage, operands);
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

    // Diamond if-conversion reads the liveness of what each arm writes off
    // SSA, so it runs on the settled IR; the analysis built above is stale
    // once anything changed, and is rebuilt lazily only for a function that
    // actually holds a diamond.
    if (changed)
    {
        if (context.ssaState)
            context.ssaState->invalidate();
        localSsaState.invalidate();
    }
    if (convertDiamondsToConditionalMoves(storage, operands, context, localSsaState))
    {
        changed = true;
        if (context.builder)
            context.builder->invalidateControlFlowGraph();
    }

    if (changed)
        context.passChanged = true;

    return Result::Continue;
}

SWC_END_NAMESPACE();
