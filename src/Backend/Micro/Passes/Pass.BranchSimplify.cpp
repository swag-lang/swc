#include "pch.h"
#include "Backend/Micro/Passes/Pass.BranchSimplify.h"
#include "Backend/ABI/CallConv.h"
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

            // An XMM clear shares its opcode with integer XOR, but preserves the
            // comparison flags a fused boolean branch still observes.
            if (MicroPassHelpers::instructionActuallyDefinesCpuFlags(inst, ops))
                currentFlagDef = instRef;

            if (MicroInstrInfo::isTerminatorInstruction(inst))
                currentFlagDef = MicroInstrRef::invalid();
        }

        return changed;
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

            // What the operation does, not what its opcode may do: a bitwise
            // complement, a move and an address computation share an opcode
            // with arithmetic that writes the flags, and leave them alone.
            if (MicroPassHelpers::instructionActuallyDefinesCpuFlags(*scanInst, scanInst->ops(operands)))
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

    bool fuseMaterializedBoolBranches(MicroStorage& storage, MicroOperandStorage& operands, MicroBuilder* builder)
    {
        bool changed = false;
        for (auto it = storage.view().begin(); it != storage.view().end();)
        {
            const MicroInstrRef jumpRef  = it.current;
            MicroInstr&         jumpInst = *it;
            ++it;

            // A conditional move reads the flags exactly as a conditional jump
            // does, and a select whose condition was named by the source
            // arrives the same way: the comparison, a setcc, then a test of
            // that byte in front of every use of it. The arithmetic decoder
            // selects three values on one comparison and paid three tests for
            // it; the condition the setcc carries is the one the moves want.
            const bool isConditionalMove = jumpInst.op == MicroInstrOpcode::LoadCondRegReg;
            if (jumpInst.op != MicroInstrOpcode::JumpCond && !isConditionalMove)
                continue;

            MicroInstrOperand* jumpOps = jumpInst.ops(operands);
            if (!jumpOps)
                continue;

            // LoadCondRegReg: [dst, src, cond, opBits]; JumpCond: [cond, ...].
            const uint8_t   condIdx  = isConditionalMove ? 2 : 0;
            const MicroCond jumpCond = jumpOps[condIdx].cpuCond;
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

            // Jumps and conditional moves preserve the flags they read. The
            // boolean compare can only go when no later reader observes it.
            // Repeated selects with their own boolean compares still qualify:
            // each next compare overwrites the flags before the next reader.
            if (!builder || !MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*builder, jumpRef))
                continue;

            // Readers between the setcc and the compare still see the original
            // comparison's flags, so only flag writers end the walk here.
            MicroInstrRef     defRef  = previousFlagChainInstruction(storage, operands, cmpRef, boolReg, false);
            const MicroInstr* defInst = defRef.isValid() ? storage.ptr(defRef) : nullptr;
            if (!defInst)
                continue;

            // The boolean reaches its test through whatever the lowering put
            // between: a widening of the byte the setcc wrote, and a copy of
            // it per reader when several read it - which is exactly the shape
            // a condition named once and used by three selects takes.
            MicroReg trackedBool = boolReg;
            for (uint32_t hop = 0; defInst && hop < 4; ++hop)
            {
                const MicroInstrOperand* stepOps = defInst->ops(operands);
                if (!stepOps)
                    break;

                if ((defInst->op == MicroInstrOpcode::LoadZeroExtRegReg || defInst->op == MicroInstrOpcode::LoadSignedExtRegReg) &&
                    stepOps[0].reg == trackedBool && stepOps[1].reg == trackedBool)
                {
                    defRef  = previousFlagChainInstruction(storage, operands, defRef, trackedBool, false);
                    defInst = defRef.isValid() ? storage.ptr(defRef) : nullptr;
                    continue;
                }

                if (defInst->op == MicroInstrOpcode::LoadRegReg && stepOps[0].reg == trackedBool && stepOps[1].reg.isVirtual())
                {
                    trackedBool = stepOps[1].reg;
                    defRef      = previousFlagChainInstruction(storage, operands, defRef, trackedBool, false);
                    defInst     = defRef.isValid() ? storage.ptr(defRef) : nullptr;
                    continue;
                }

                break;
            }

            if (!defInst)
                continue;

            if (defInst->op != MicroInstrOpcode::SetCondReg)
                continue;
            const MicroInstrOperand* setOps = defInst->ops(operands);
            if (!setOps || setOps[0].reg != trackedBool)
                continue;

            const MicroCond setCond = setOps[1].cpuCond;
            MicroCond       newCond = setCond;
            if (branchOnBoolZero && !MicroPassHelpers::invertCondition(newCond, setCond))
                continue;

            jumpOps[condIdx].cpuCond = newCond;
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
    // the join's own target, as LLVM's jump threading does. Once the threaded
    // edge no longer reaches the join, the remaining single-definition chain
    // is the shape fuseMaterializedBoolBranches folds, and a chain of `and`s
    // ends up as plain compare-and-branch pairs. When the pinned value makes
    // the join fall through instead, as the `and` inside `(a and b) or c`
    // does, the jump goes past the join's test, to a label placed there if
    // none is, provided the fall-through redefines the flags before reading
    // them and is no link the branchless `or` conversion would take.
    // The low bits of each register known to hold the boolean: a setcc
    // writes eight, a 32-bit move clears the upper half, a narrower one keeps
    // the destination's own upper bits.
    using BoolBits = SmallVector<std::pair<MicroReg, uint32_t>, 4>;

    uint32_t boolBitsOf(const BoolBits& bits, const MicroReg reg)
    {
        for (const auto& [known, count] : bits)
        {
            if (known == reg)
                return count;
        }
        return 0;
    }

    void setBoolBits(BoolBits& bits, const MicroReg reg, const uint32_t count)
    {
        for (auto& entry : bits)
        {
            if (entry.first == reg)
            {
                entry.second = count;
                return;
            }
        }
        if (count)
            bits.push_back({reg, count});
    }

    bool applyBoolChainStep(BoolBits& bits, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!ops || !ops[0].reg.isVirtualInt())
            return false;
        if (inst.op == MicroInstrOpcode::LoadRegReg)
        {
            const uint32_t width  = getNumBits(ops[2].opBits);
            uint32_t       source = boolBitsOf(bits, ops[1].reg);
            source                = std::min(source, width);
            if (width == 32 && source == 32)
                source = 64;
            setBoolBits(bits, ops[0].reg, source);
            return true;
        }
        if (inst.op == MicroInstrOpcode::LoadZeroExtRegReg && ops[0].reg == ops[1].reg)
        {
            const uint32_t known = boolBitsOf(bits, ops[0].reg);
            uint32_t       wide  = getNumBits(ops[2].opBits);
            if (wide == 32)
                wide = 64;
            setBoolBits(bits, ops[0].reg, known >= getNumBits(ops[3].opBits) ? wide : 0);
            return true;
        }
        return false;
    }

    // How many low bits of `reg` the instruction reads, or 0 when the read is
    // not one of the plain copies, compares and extensions a boolean meets.
    uint32_t booleanReadBits(const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg reg)
    {
        if (!ops)
            return 0;
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
                return ops[1].reg == reg && ops[0].reg != reg ? getNumBits(ops[2].opBits) : 0;
            case MicroInstrOpcode::CmpRegImm:
                return getNumBits(ops[1].opBits);
            case MicroInstrOpcode::CmpRegReg:
                return getNumBits(ops[2].opBits);
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadSignedExtRegReg:
                return ops[1].reg == reg ? getNumBits(ops[3].opBits) : 0;
            default:
                return 0;
        }
    }

    bool endsBlock(const MicroInstr& inst)
    {
        const auto& info = MicroInstr::info(inst.op);
        return inst.op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
               info.flags.has(MicroInstrFlagsE::TerminatorInstruction);
    }

    // Gives the results of a chain of `and`s or `or`s one register.
    //
    // Each operator merges its result into a register of its own, and the
    // join of the enclosing operator copies it into the next one:
    //
    //     setcc T; D = T; j(~CC) .J          setcc T; D = T; j(~CC) .J
    //     <rhs, ending with D = T'>          <rhs, ending with D = T'>
    //     .J:                         ->     .J:
    //     E = D                              cmp D, 0
    //     cmp D, 0                           je  .K
    //     je  .K                             ... every E reads D
    //
    // D lives only from the operator to its join, and nothing reads E before
    // the join writes it, so the two never hold different values at once: one
    // register serves both, as a coalescing allocator would decide. The join
    // is left as the bare test threadShortCircuitExits decides, and a chain of
    // any length settles without a copy per exit. Joins are visited last to
    // first so each result register takes over the next one's readers.
    bool coalesceShortCircuitResults(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        ProgramLayout layout;
        buildProgramLayout(layout, storage, operands);
        const size_t count = layout.order.size();

        std::unordered_set<uint32_t> relocated;
        if (context.builder)
        {
            for (const MicroRelocation& reloc : context.builder->codeRelocations())
            {
                if (reloc.instructionRef.isValid())
                    relocated.insert(reloc.instructionRef.get());
            }
        }

        struct RegSites
        {
            SmallVector<uint32_t, 4> uses;
            SmallVector<uint32_t, 4> defs;
        };
        std::unordered_map<uint32_t, RegSites> sites;
        std::unordered_map<uint32_t, uint32_t> labelReferences;
        for (uint32_t ordinal = 0; ordinal < count; ++ordinal)
        {
            const MicroInstr* inst = storage.ptr(layout.order[ordinal]);
            if (!inst)
                continue;
            if (inst->op == MicroInstrOpcode::JumpReg || inst->op == MicroInstrOpcode::LoadLabelAddress)
                return false;
            uint32_t labelId = 0;
            if (tryGetJumpTargetLabelId(labelId, *inst, inst->ops(operands)))
                ++labelReferences[labelId];

            const MicroInstrUseDef useDef = inst->collectUseDef(operands, nullptr);
            for (const MicroReg reg : useDef.uses)
            {
                if (reg.isVirtualInt())
                    sites[reg.index()].uses.push_back(ordinal);
            }
            for (const MicroReg reg : useDef.defs)
            {
                if (reg.isVirtualInt())
                    sites[reg.index()].defs.push_back(ordinal);
            }
        }

        const auto allWithin = [](const SmallVector<uint32_t, 4>& list, const uint32_t lo, const uint32_t hi) {
            for (const uint32_t ordinal : list)
            {
                if (ordinal < lo || ordinal >= hi)
                    return false;
            }
            return true;
        };
        const auto noneWithin = [](const SmallVector<uint32_t, 4>& list, const uint32_t lo, const uint32_t hi) {
            for (const uint32_t ordinal : list)
            {
                if (ordinal >= lo && ordinal < hi)
                    return false;
            }
            return true;
        };

        bool changed = false;
        for (uint32_t jumpOrdinal = static_cast<uint32_t>(count); jumpOrdinal > 0; --jumpOrdinal)
        {
            const uint32_t    p        = jumpOrdinal - 1;
            const MicroInstr* jumpInst = storage.ptr(layout.order[p]);
            if (!jumpInst || jumpInst->op != MicroInstrOpcode::JumpCond)
                continue;
            const MicroInstrOperand* jumpOps = jumpInst->ops(operands);
            uint32_t                 labelId = 0;
            if (!jumpOps || jumpOps[0].cpuCond == MicroCond::Unconditional || !tryGetJumpTargetLabelId(labelId, *jumpInst, jumpOps))
                continue;
            const auto labelIt = layout.labelOrdinalById.find(labelId);
            if (labelIt == layout.labelOrdinalById.end() || labelIt->second <= p || labelReferences[labelId] != 1 ||
                relocated.contains(layout.order[labelIt->second].get()))
                continue;
            const uint32_t j = labelIt->second;

            // The rhs runs straight into the join.
            bool straight = true;
            for (uint32_t mid = p + 1; mid < j && straight; ++mid)
            {
                const MicroInstr* midInst = storage.ptr(layout.order[mid]);
                straight                  = midInst && !endsBlock(*midInst);
            }
            if (!straight)
                continue;

            // The join: copies, `cmp D, 0`, a conditional jump.
            uint32_t cmpOrdinal = j + 1;
            while (cmpOrdinal < count)
            {
                const MicroInstr* inst = storage.ptr(layout.order[cmpOrdinal]);
                if (!inst || inst->op != MicroInstrOpcode::LoadRegReg)
                    break;
                ++cmpOrdinal;
            }
            if (cmpOrdinal + 1 >= count)
                continue;
            const MicroInstr* cmpInst  = storage.ptr(layout.order[cmpOrdinal]);
            const MicroInstr* nextJump = storage.ptr(layout.order[cmpOrdinal + 1]);
            if (!cmpInst || cmpInst->op != MicroInstrOpcode::CmpRegImm || !nextJump || nextJump->op != MicroInstrOpcode::JumpCond)
                continue;
            const MicroInstrOperand* cmpOps = cmpInst->ops(operands);
            if (!cmpOps || cmpOps[2].hasWideImmediateValue() || cmpOps[2].valueU64 != 0 || !cmpOps[0].reg.isVirtualInt())
                continue;
            const MicroReg d = cmpOps[0].reg;

            uint32_t copyOrdinal = 0;
            MicroReg e;
            uint32_t width = 0;
            for (uint32_t ordinal = j + 1; ordinal < cmpOrdinal; ++ordinal)
            {
                const MicroInstrOperand* copyOps = storage.ptr(layout.order[ordinal])->ops(operands);
                if (copyOps && copyOps[1].reg == d && copyOps[0].reg.isVirtualInt() && copyOps[0].reg != d)
                {
                    copyOrdinal = ordinal;
                    e           = copyOps[0].reg;
                    width       = getNumBits(copyOps[2].opBits);
                    break;
                }
            }
            if (!copyOrdinal || width < getNumBits(cmpOps[1].opBits))
                continue;

            uint32_t start = p;
            while (start > 0)
            {
                const MicroInstr* inst = storage.ptr(layout.order[start - 1]);
                if (!inst || endsBlock(*inst))
                    break;
                --start;
            }

            // D is written in the operator's block or the rhs and read only in
            // the join; nothing touches E from there up to the copy; every
            // reader of either takes no more bits than the copy moves.
            const RegSites& dSites = sites[d.index()];
            const RegSites& eSites = sites[e.index()];
            if (!allWithin(dSites.defs, start, j) || !allWithin(dSites.uses, j + 1, cmpOrdinal + 1) ||
                !noneWithin(eSites.uses, start, copyOrdinal) || !noneWithin(eSites.defs, start, copyOrdinal))
                continue;
            bool narrowReaders = true;
            for (const SmallVector<uint32_t, 4>* list : {&dSites.uses, &eSites.uses})
            {
                for (const uint32_t ordinal : *list)
                {
                    if (ordinal == copyOrdinal)
                        continue;
                    const MicroInstr* reader = storage.ptr(layout.order[ordinal]);
                    const MicroReg    reg    = list == &dSites.uses ? d : e;
                    const uint32_t    bits   = reader ? booleanReadBits(*reader, reader->ops(operands), reg) : 0;
                    if (!bits || bits > width)
                        narrowReaders = false;
                }
            }
            if (!narrowReaders)
                continue;

            SmallVector<MicroInstrRegOperandRef> regRefs;
            for (const uint32_t ordinal : eSites.uses)
            {
                regRefs.clear();
                storage.ptr(layout.order[ordinal])->collectRegOperands(operands, regRefs, nullptr);
                for (const MicroInstrRegOperandRef& ref : regRefs)
                {
                    if (ref.reg && *ref.reg == e)
                        *ref.reg = d;
                }
            }
            for (const uint32_t ordinal : eSites.defs)
            {
                if (ordinal == copyOrdinal)
                    continue;
                regRefs.clear();
                storage.ptr(layout.order[ordinal])->collectRegOperands(operands, regRefs, nullptr);
                for (const MicroInstrRegOperandRef& ref : regRefs)
                {
                    if (ref.reg && *ref.reg == e)
                        *ref.reg = d;
                }
            }
            storage.erase(layout.order[copyOrdinal]);

            RegSites merged = sites[d.index()];
            for (const uint32_t ordinal : sites[e.index()].uses)
                merged.uses.push_back(ordinal);
            for (const uint32_t ordinal : sites[e.index()].defs)
            {
                if (ordinal != copyOrdinal)
                    merged.defs.push_back(ordinal);
            }
            SmallVector<uint32_t, 4> uses;
            for (const uint32_t ordinal : merged.uses)
            {
                if (ordinal != copyOrdinal)
                    uses.push_back(ordinal);
            }
            merged.uses = uses;
            sites.erase(e.index());
            sites[d.index()] = merged;
            changed          = true;
        }

        return changed;
    }

    bool isPureChainInstruction(const MicroInstr& inst, const MicroInstrOperand* ops);

    // Whether the link a join falls into holds only what the branchless `or`
    // conversion runs unconditionally: that conversion reads the join as it
    // stands, possibly a sweep later, so the join is left to it.
    bool fallsIntoBranchlessLink(const ProgramLayout& layout, const MicroStorage& storage, const MicroOperandStorage& operands, size_t ordinal)
    {
        constexpr size_t K_MAX_LINK = 8;

        for (size_t step = 0; step < K_MAX_LINK && ordinal + step < layout.order.size(); ++step)
        {
            const MicroInstr* inst = storage.ptr(layout.order[ordinal + step]);
            if (!inst)
                return false;
            if (inst->op == MicroInstrOpcode::SetCondReg)
                return true;
            if (!isPureChainInstruction(*inst, inst->ops(operands)))
                return false;
        }
        return false;
    }

    bool threadShortCircuitExits(MicroStorage& storage, MicroOperandStorage& operands, MicroBuilder* builder)
    {
        constexpr uint32_t K_MAX_CHAIN = 6;

        ProgramLayout layout;
        buildProgramLayout(layout, storage, operands);

        // Labels placed past a join's test, by the join's jump.
        std::unordered_map<uint32_t, uint32_t> fallThroughLabels;

        bool changed = false;
        for (size_t ordinal = 0; ordinal < layout.order.size(); ++ordinal)
        {
            const MicroInstrRef jumpRef  = layout.order[ordinal];
            MicroInstr*         jumpInst = storage.ptr(jumpRef);
            if (!jumpInst || jumpInst->op != MicroInstrOpcode::JumpCond)
                continue;
            MicroInstrOperand* jumpOps = jumpInst->ops(operands);
            if (!jumpOps || jumpOps[0].cpuCond == MicroCond::Unconditional)
                continue;
            uint32_t joinLabelId = 0;
            if (!tryGetJumpTargetLabelId(joinLabelId, *jumpInst, jumpOps))
                continue;

            // Walk the boolean chain immediately preceding the jump back to
            // the setcc that consumed the flags the jump reads. Copies and
            // self-extensions do not touch the flags.
            SmallVector<MicroInstrRef, K_MAX_CHAIN> chain;
            MicroInstrRef                            setRef = storage.findPreviousInstructionRef(jumpRef);
            const MicroInstr*                        setInst = setRef.isValid() ? storage.ptr(setRef) : nullptr;
            while (setInst && setInst->op != MicroInstrOpcode::SetCondReg && chain.size() < K_MAX_CHAIN &&
                   (setInst->op == MicroInstrOpcode::LoadRegReg || setInst->op == MicroInstrOpcode::LoadZeroExtRegReg))
            {
                chain.push_back(setRef);
                setRef  = storage.findPreviousInstructionRef(setRef);
                setInst = setRef.isValid() ? storage.ptr(setRef) : nullptr;
            }
            if (!setInst || setInst->op != MicroInstrOpcode::SetCondReg)
                continue;
            const MicroInstrOperand* setOps = setInst->ops(operands);
            if (!setOps || !setOps[0].reg.isVirtualInt())
                continue;

            BoolBits bits;
            setBoolBits(bits, setOps[0].reg, 8);
            bool chainOk = true;
            for (size_t i = chain.size(); i > 0 && chainOk; --i)
            {
                const MicroInstr* step = storage.ptr(chain[i - 1]);
                chainOk                = step && applyBoolChainStep(bits, *step, step->ops(operands));
            }
            if (!chainOk)
                continue;

            // The branch condition pins the boolean's value on the taken edge.
            const MicroCond setCond = setOps[1].cpuCond;
            MicroCond       invCond = MicroCond::Unconditional;
            bool            boolOne = false;
            if (setCond == jumpOps[0].cpuCond)
                boolOne = true;
            else if (!MicroPassHelpers::invertCondition(invCond, setCond) || invCond != jumpOps[0].cpuCond)
                continue;

            // The join: copies of the boolean, `cmp B, 0`, a conditional jump.
            const auto labelIt = layout.labelOrdinalById.find(joinLabelId);
            if (labelIt == layout.labelOrdinalById.end())
                continue;
            const size_t      joinOrdinal = labelIt->second + 1;
            const MicroInstr* joinInst    = joinOrdinal < layout.order.size() ? storage.ptr(layout.order[joinOrdinal]) : nullptr;
            if (!joinInst || joinInst->op != MicroInstrOpcode::CmpRegImm || joinOrdinal + 1 >= layout.order.size())
                continue;
            const MicroInstrOperand* joinCmpOps = joinInst->ops(operands);
            if (!joinCmpOps || joinCmpOps[2].hasWideImmediateValue() || joinCmpOps[2].valueU64 != 0 ||
                boolBitsOf(bits, joinCmpOps[0].reg) < getNumBits(joinCmpOps[1].opBits))
                continue;
            const MicroInstrRef joinJumpRef = layout.order[joinOrdinal + 1];
            const MicroInstr*   joinJump    = storage.ptr(joinJumpRef);
            if (!joinJump || joinJump->op != MicroInstrOpcode::JumpCond)
                continue;
            const MicroInstrOperand* joinJumpOps = joinJump->ops(operands);
            if (!joinJumpOps)
                continue;

            const MicroCond joinCond        = joinJumpOps[0].cpuCond;
            const bool      joinTakenOnZero = joinCond == MicroCond::Equal || joinCond == MicroCond::Zero;
            const bool      joinTakenOnOne  = joinCond == MicroCond::NotEqual || joinCond == MicroCond::NotZero;
            if (!joinTakenOnZero && !joinTakenOnOne)
                continue;
            if (boolOne ? joinTakenOnZero : joinTakenOnOne)
            {
                // The join falls through on this edge.
                if (!builder || joinOrdinal + 2 >= layout.order.size() ||
                    !MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(storage, operands, joinJumpRef) ||
                    fallsIntoBranchlessLink(layout, storage, operands, joinOrdinal + 2))
                    continue;
                uint32_t   pastLabelId = 0;
                const auto known       = fallThroughLabels.find(joinJumpRef.get());
                if (known != fallThroughLabels.end())
                {
                    pastLabelId = known->second;
                }
                else
                {
                    const MicroInstrRef pastRef = layout.order[joinOrdinal + 2];
                    const MicroInstr*   past    = storage.ptr(pastRef);
                    if (!past)
                        continue;
                    if (!tryGetLabelId(pastLabelId, *past, past->ops(operands)))
                    {
                        pastLabelId = builder->createLabel().get();
                        MicroInstrOperand labelOps[1];
                        labelOps[0].valueU64 = pastLabelId;
                        storage.insertDerivedBefore(operands, pastRef, MicroInstrOpcode::Label, labelOps);
                    }
                    fallThroughLabels.emplace(joinJumpRef.get(), pastLabelId);
                }
                if (pastLabelId == joinLabelId)
                    continue;
                storage.ptr(jumpRef)->ops(operands)[2].valueU64 = pastLabelId;
                changed = true;
                continue;
            }

            uint32_t joinTargetId = 0;
            if (!tryGetJumpTargetLabelId(joinTargetId, *joinJump, joinJumpOps) || joinTargetId == joinLabelId)
                continue;
            jumpOps[2].valueU64 = joinTargetId;
            changed             = true;
        }

        return changed;
    }

    // A chain of equality tests of one value against constants, as `c == ' '
    // or c == '\t' or c == '\n'` leaves it once its exits are threaded:
    //
    //     cmp X, C1; sete T1; D = T1; je .END        I = X [- LO]
    //     cmp X, C2; sete T2; D = T2; je .END        cmp I, HI - LO; setbe R
    //     ...                                  ->    M = MASK; M >>= I
    //     cmp X, Cn; sete Tn; D = Tn                 R &= M
    //     .END:                                      D = R
    //
    // is one bit test when the constants span less than a word, as LLVM's
    // SimplifyBranchOnICmpChain and switch bit-test lowering produce. The
    // dual `c != C1 and c != C2 ...` (setne, the same exits) is its complement.
    bool convertEqualityChainsToBitTests(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        constexpr uint32_t K_MIN_CHAIN = 3;
        constexpr uint32_t K_MAX_CHAIN = 64;

        if (!context.builder)
            return false;

        ProgramLayout layout;
        buildProgramLayout(layout, storage, operands);

        std::unordered_map<uint32_t, uint32_t> labelReferences;
        std::unordered_map<uint32_t, uint32_t> mentions;
        SmallVector<MicroInstrRegOperandRef>   regOperands;
        for (const MicroInstrRef ref : layout.order)
        {
            MicroInstr* inst = storage.ptr(ref);
            if (!inst)
                continue;
            if (inst->op == MicroInstrOpcode::JumpReg || inst->op == MicroInstrOpcode::LoadLabelAddress)
                return false;
            uint32_t labelId = 0;
            if (tryGetJumpTargetLabelId(labelId, *inst, inst->ops(operands)))
                ++labelReferences[labelId];
            regOperands.clear();
            inst->collectRegOperands(operands, regOperands, nullptr);
            for (const MicroInstrRegOperandRef& regOperand : regOperands)
            {
                if (regOperand.reg && regOperand.reg->isVirtualInt())
                    ++mentions[regOperand.reg->index()];
            }
        }

        std::unordered_set<uint32_t> relocated;
        for (const MicroRelocation& reloc : context.builder->codeRelocations())
        {
            if (reloc.instructionRef.isValid())
                relocated.insert(reloc.instructionRef.get());
        }

        struct Link
        {
            uint32_t cmp   = 0;
            uint64_t value = 0;
        };

        bool     changed                = false;
        uint32_t nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        size_t   ordinal                = 0;
        while (ordinal < layout.order.size())
        {
            const size_t start = ordinal++;

            // One link: cmp X, C; setcc T; D = T; then a je to the end or the end label itself.
            MicroReg             value;
            MicroReg             result;
            MicroOpBits          bits    = MicroOpBits::Zero;
            MicroCond            setCond = MicroCond::Unconditional;
            uint32_t             endId   = 0;
            bool                 hasEnd  = false;
            bool                 closed  = false;
            SmallVector<Link, 8> links;
            SmallVector<size_t>  body;
            size_t               at = start;
            while (at + 3 < layout.order.size() && links.size() < K_MAX_CHAIN)
            {
                // A link may test a copy of the value made for it alone.
                MicroReg          alias;
                const MicroInstr* first = storage.ptr(layout.order[at]);
                if (first && first->op == MicroInstrOpcode::LoadRegReg && at + 4 < layout.order.size())
                {
                    const MicroInstrOperand* aliasOps = first->ops(operands);
                    if (links.empty() || aliasOps[1].reg != value || !aliasOps[0].reg.isVirtualInt() ||
                        getNumBits(aliasOps[2].opBits) < getNumBits(bits) || mentions[aliasOps[0].reg.index()] != 2)
                        break;
                    alias = aliasOps[0].reg;
                    body.push_back(at);
                    ++at;
                }

                const MicroInstr* cmp  = storage.ptr(layout.order[at]);
                const MicroInstr* set  = storage.ptr(layout.order[at + 1]);
                const MicroInstr* copy = storage.ptr(layout.order[at + 2]);
                const MicroInstr* next = storage.ptr(layout.order[at + 3]);
                if (!cmp || !set || !copy || !next || cmp->op != MicroInstrOpcode::CmpRegImm || set->op != MicroInstrOpcode::SetCondReg ||
                    copy->op != MicroInstrOpcode::LoadRegReg)
                    break;
                const MicroInstrOperand* cmpOps  = cmp->ops(operands);
                const MicroInstrOperand* setOps  = set->ops(operands);
                const MicroInstrOperand* copyOps = copy->ops(operands);
                if (alias.isValid() && cmpOps[0].reg != alias)
                    break;
                const MicroReg tested = alias.isValid() ? value : cmpOps[0].reg;
                if (!cmpOps[0].reg.isVirtualInt() || cmpOps[2].hasWideImmediateValue() ||
                    (setOps[1].cpuCond != MicroCond::Equal && setOps[1].cpuCond != MicroCond::NotEqual) ||
                    !setOps[0].reg.isVirtualInt() || copyOps[1].reg != setOps[0].reg || copyOps[2].opBits != MicroOpBits::B8 ||
                    !copyOps[0].reg.isVirtualInt() || copyOps[0].reg == tested || mentions[setOps[0].reg.index()] != 2)
                    break;
                if (links.empty())
                {
                    value   = tested;
                    bits    = cmpOps[1].opBits;
                    setCond = setOps[1].cpuCond;
                    result  = copyOps[0].reg;
                }
                else if (tested != value || cmpOps[1].opBits != bits || setOps[1].cpuCond != setCond || copyOps[0].reg != result)
                    break;

                const uint64_t mask = getNumBits(bits) == 64 ? UINT64_MAX : (1ULL << getNumBits(bits)) - 1;
                links.push_back({.cmp = static_cast<uint32_t>(at), .value = cmpOps[2].valueU64 & mask});
                body.push_back(at);
                body.push_back(at + 1);
                body.push_back(at + 2);

                uint32_t labelId = 0;
                if (next->op == MicroInstrOpcode::JumpCond)
                {
                    const MicroInstrOperand* jumpOps = next->ops(operands);
                    if (jumpOps[0].cpuCond != MicroCond::Equal || !tryGetJumpTargetLabelId(labelId, *next, jumpOps) || (hasEnd && labelId != endId))
                        break;
                    endId  = labelId;
                    hasEnd = true;
                    body.push_back(at + 3);
                    at += 4;
                    continue;
                }
                if (tryGetLabelId(labelId, *next, next->ops(operands)) && hasEnd && labelId == endId)
                    closed = true;
                break;
            }
            if (!closed || links.size() < K_MIN_CHAIN || labelReferences[endId] != links.size() - 1 ||
                relocated.contains(layout.order[body.back() + 1].get()))
                continue;

            uint64_t lo = UINT64_MAX;
            uint64_t hi = 0;
            for (const Link& link : links)
            {
                lo = std::min(lo, link.value);
                hi = std::max(hi, link.value);
            }
            if (hi < 64)
                lo = 0;
            if (hi - lo >= 64)
                continue;
            const MicroInstrRef lastRef = layout.order[body.back()];
            if (!MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*context.builder, lastRef))
                continue;

            uint64_t bitMask = 0;
            for (const Link& link : links)
                bitMask |= 1ULL << (link.value - lo);

            const MicroInstrRef firstRef = layout.order[links.front().cmp];
            MicroReg            index    = value;
            if (lo)
            {
                index = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
                MicroInstrOperand copyOps[3];
                copyOps[0].reg    = index;
                copyOps[1].reg    = value;
                copyOps[2].opBits = bits;
                storage.insertDerivedBefore(operands, firstRef, MicroInstrOpcode::LoadRegReg, copyOps);
                MicroInstrOperand subOps[4];
                subOps[0].reg     = index;
                subOps[1].opBits  = bits;
                subOps[2].microOp = MicroOp::Subtract;
                subOps[3].setImmediateValue(ApInt(lo, getNumBits(bits)));
                storage.insertDerivedBefore(operands, firstRef, MicroInstrOpcode::OpBinaryRegImm, subOps);
            }

            const MicroReg    inRange = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
            MicroInstrOperand cmpOps[3];
            cmpOps[0].reg = index;
            cmpOps[1].opBits = bits;
            cmpOps[2].setImmediateValue(ApInt(hi - lo, getNumBits(bits)));
            storage.insertDerivedBefore(operands, firstRef, MicroInstrOpcode::CmpRegImm, cmpOps);
            MicroInstrOperand setOps[2];
            setOps[0].reg     = inRange;
            setOps[1].cpuCond = MicroCond::BelowOrEqual;
            storage.insertDerivedBefore(operands, firstRef, MicroInstrOpcode::SetCondReg, setOps);

            const MicroReg    table = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
            MicroInstrOperand tableOps[3];
            tableOps[0].reg = table;
            tableOps[1].opBits = MicroOpBits::B64;
            tableOps[2].setImmediateValue(ApInt(bitMask, 64));
            storage.insertDerivedBefore(operands, firstRef, MicroInstrOpcode::LoadRegImm, tableOps);
            MicroInstrOperand shiftOps[4];
            shiftOps[0].reg     = table;
            shiftOps[1].reg     = index;
            shiftOps[2].opBits  = MicroOpBits::B64;
            shiftOps[3].microOp = MicroOp::ShiftRight;
            storage.insertDerivedBefore(operands, firstRef, MicroInstrOpcode::OpBinaryRegReg, shiftOps);
            MicroInstrOperand andOps[4];
            andOps[0].reg     = inRange;
            andOps[1].reg     = table;
            andOps[2].opBits  = MicroOpBits::B8;
            andOps[3].microOp = MicroOp::And;
            storage.insertDerivedBefore(operands, firstRef, MicroInstrOpcode::OpBinaryRegReg, andOps);
            if (setCond == MicroCond::NotEqual)
            {
                MicroInstrOperand flipOps[4];
                flipOps[0].reg     = inRange;
                flipOps[1].opBits  = MicroOpBits::B8;
                flipOps[2].microOp = MicroOp::Xor;
                flipOps[3].setImmediateValue(ApInt(1, 8));
                storage.insertDerivedBefore(operands, firstRef, MicroInstrOpcode::OpBinaryRegImm, flipOps);
            }
            MicroInstrOperand resultOps[3];
            resultOps[0].reg    = result;
            resultOps[1].reg    = inRange;
            resultOps[2].opBits = MicroOpBits::B8;
            storage.insertDerivedBefore(operands, firstRef, MicroInstrOpcode::LoadRegReg, resultOps);

            for (const size_t index2 : body)
                storage.erase(layout.order[index2]);
            changed = true;
            ordinal = body.back() + 1;
        }

        if (changed)
            context.builder->invalidateControlFlowGraph();
        return changed;
    }

    // A chain of byte tests joined by early exits, as `(c >= 'a' and c <= 'z')
    // or (c >= 'A' and c <= 'Z') or ...` leaves it once its ranges fold:
    //
    //     <B1> setcc T1; D = T1; jcc .END          <B1> setcc T1; D = T1
    //     <B2> setcc T2; D = T2; jcc .END    ->    <B2> setcc T2; D |= T2
    //     <B3> setcc T3; D = T3                    <B3> setcc T3; D |= T3
    //     .END:                                    .END:
    //
    // Each jcc tests the flags its setcc read, so it leaves exactly when that
    // byte is 1 and D is already the OR of the bytes so far. The links after
    // the first are a few register-only instructions that cannot fault and
    // whose results only the link reads, so running them on every path is
    // unobservable, and the branches go, as SimplifyCFG folds branches to a
    // common destination into one `or`.
    bool isPureChainInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::CmpRegImm:
            case MicroInstrOpcode::CmpRegReg:
                return true;
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadAddrRegMem:
                return ops[0].reg.isVirtualInt();
            case MicroInstrOpcode::OpBinaryRegImm:
                if (!ops[0].reg.isVirtualInt())
                    return false;
                switch (ops[2].microOp)
                {
                    case MicroOp::Add:
                    case MicroOp::Subtract:
                    case MicroOp::And:
                    case MicroOp::Or:
                    case MicroOp::Xor:
                        return true;
                    default:
                        return false;
                }
            default:
                return false;
        }
    }

    bool isChainCompare(const MicroInstr* inst)
    {
        return inst && (inst->op == MicroInstrOpcode::CmpRegImm || inst->op == MicroInstrOpcode::CmpRegReg);
    }

    bool convertOrChainsToBranchless(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        constexpr uint32_t K_MAX_LINKS = 4;
        constexpr uint32_t K_MAX_BODY  = 3;

        if (!context.builder)
            return false;

        ProgramLayout layout;
        buildProgramLayout(layout, storage, operands);

        std::unordered_map<uint32_t, uint32_t> labelReferences;
        std::unordered_map<uint32_t, uint32_t> mentions;
        SmallVector<MicroInstrRegOperandRef>   regOperands;
        for (const MicroInstrRef ref : layout.order)
        {
            const MicroInstr* inst = storage.ptr(ref);
            if (!inst)
                continue;
            if (inst->op == MicroInstrOpcode::JumpReg || inst->op == MicroInstrOpcode::LoadLabelAddress)
                return false;
            uint32_t labelId = 0;
            if (tryGetJumpTargetLabelId(labelId, *inst, inst->ops(operands)))
                ++labelReferences[labelId];
            regOperands.clear();
            inst->collectRegOperands(operands, regOperands, nullptr);
            for (const MicroInstrRegOperandRef& regOperand : regOperands)
            {
                if (regOperand.reg && regOperand.reg->isVirtualInt())
                    ++mentions[regOperand.reg->index()];
            }
        }

        struct Link
        {
            size_t merge   = 0;
            size_t jump    = 0;
            bool   hasJump = false;
        };

        const size_t count  = layout.order.size();
        const auto   instAt = [&](size_t index) -> const MicroInstr* {
            return index < count ? storage.ptr(layout.order[index]) : nullptr;
        };

        bool changed = false;
        for (size_t start = 1; start < count; ++start)
        {
            const MicroInstr* firstSet = instAt(start);
            if (!firstSet || firstSet->op != MicroInstrOpcode::SetCondReg || !isChainCompare(instAt(start - 1)))
                continue;

            MicroReg             result;
            uint32_t             endId  = 0;
            bool                 hasEnd = false;
            bool                 closed = false;
            SmallVector<Link, 4> links;
            size_t               at = start;
            while (links.size() < K_MAX_LINKS)
            {
                // The body of a later link, then the compare its setcc reads.
                size_t setAt = at;
                while (!links.empty() && setAt < count && setAt - at < K_MAX_BODY)
                {
                    const MicroInstr* inst = instAt(setAt);
                    if (!inst || inst->op == MicroInstrOpcode::SetCondReg || !isPureChainInstruction(*inst, inst->ops(operands)))
                        break;
                    ++setAt;
                }

                const MicroInstr* set  = instAt(setAt);
                const MicroInstr* copy = instAt(setAt + 1);
                if (!set || !copy || setAt == 0 || set->op != MicroInstrOpcode::SetCondReg || copy->op != MicroInstrOpcode::LoadRegReg ||
                    !isChainCompare(instAt(setAt - 1)) || (!links.empty() && setAt == at))
                    break;
                const MicroInstrOperand* setOps  = set->ops(operands);
                const MicroInstrOperand* copyOps = copy->ops(operands);
                if (!setOps[0].reg.isVirtualInt() || copyOps[1].reg != setOps[0].reg || copyOps[2].opBits != MicroOpBits::B8)
                    break;

                // T reaches D directly or through one more byte.
                Link   link;
                size_t next = setAt + 2;
                link.merge  = setAt + 1;
                if (links.empty())
                    result = copyOps[0].reg;
                if (!result.isVirtualInt())
                    break;
                if (copyOps[0].reg != result)
                {
                    const MicroInstr* second = instAt(next);
                    if (!second || second->op != MicroInstrOpcode::LoadRegReg)
                        break;
                    const MicroInstrOperand* secondOps = second->ops(operands);
                    if (secondOps[1].reg != copyOps[0].reg || secondOps[0].reg != result)
                        break;
                    link.merge = next++;
                }

                // What a later link defines, other than D, only that link reads.
                if (!links.empty())
                {
                    std::unordered_map<uint32_t, uint32_t> inside;
                    for (size_t index = at; index <= link.merge; ++index)
                    {
                        regOperands.clear();
                        instAt(index)->collectRegOperands(operands, regOperands, nullptr);
                        for (const MicroInstrRegOperandRef& regOperand : regOperands)
                        {
                            if (regOperand.reg && regOperand.reg->isVirtualInt())
                                ++inside[regOperand.reg->index()];
                        }
                    }

                    bool local = inside[result.index()] == 1;
                    for (size_t index = at; index <= link.merge && local; ++index)
                    {
                        const MicroInstr* inst = instAt(index);
                        if (isChainCompare(inst))
                            continue;
                        const MicroReg defined = inst->ops(operands)[0].reg;
                        if (defined == result && index == link.merge)
                            continue;
                        if (!defined.isVirtualInt() || defined == result || inside[defined.index()] != mentions[defined.index()])
                            local = false;
                    }
                    if (!local)
                        break;
                }

                const MicroInstr* exit    = instAt(next);
                uint32_t          labelId = 0;
                if (exit && exit->op == MicroInstrOpcode::JumpCond)
                {
                    const MicroInstrOperand* jumpOps = exit->ops(operands);
                    if (jumpOps[0].cpuCond != setOps[1].cpuCond || !tryGetJumpTargetLabelId(labelId, *exit, jumpOps) || (hasEnd && labelId != endId))
                        break;
                    endId        = labelId;
                    hasEnd       = true;
                    link.jump    = next;
                    link.hasJump = true;
                    links.push_back(link);
                    at = next + 1;
                    continue;
                }

                if (exit && hasEnd && tryGetLabelId(labelId, *exit, exit->ops(operands)) && labelId == endId)
                {
                    links.push_back(link);
                    closed = true;
                }
                break;
            }

            if (!closed || links.size() < 2 || labelReferences[endId] != links.size() - 1)
                continue;

            // D leaves the chain as a byte, read once right after the join.
            const size_t      endAt  = links.back().merge + 1;
            const MicroInstr* reader = instAt(endAt + 1);
            if (!reader || mentions[result.index()] != links.size() + 1)
                continue;
            const MicroInstrOperand* readerOps = reader->ops(operands);
            const bool               byteRead  = (reader->op == MicroInstrOpcode::LoadZeroExtRegReg && readerOps[3].opBits == MicroOpBits::B8) ||
                                   (reader->op == MicroInstrOpcode::LoadRegReg && readerOps[2].opBits == MicroOpBits::B8);
            if (!byteRead || readerOps[1].reg != result || readerOps[0].reg == result)
                continue;

            if (!MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*context.builder, layout.order[links.back().merge]))
                continue;

            for (size_t index = 0; index < links.size(); ++index)
            {
                const Link& link = links[index];
                if (index)
                {
                    const MicroInstrRef mergeRef = layout.order[link.merge];
                    MicroInstrOperand   orOps[4];
                    orOps[0].reg     = result;
                    orOps[1].reg     = storage.ptr(mergeRef)->ops(operands)[1].reg;
                    orOps[2].opBits  = MicroOpBits::B8;
                    orOps[3].microOp = MicroOp::Or;
                    storage.insertDerivedBefore(operands, mergeRef, MicroInstrOpcode::OpBinaryRegReg, orOps);
                    storage.erase(mergeRef);
                }
                if (link.hasJump)
                    storage.erase(layout.order[link.jump]);
            }

            changed = true;
            start   = endAt;
        }

        if (changed)
            context.builder->invalidateControlFlowGraph();
        return changed;
    }

    // `x > y ? 1 : (x < y ? -1 : 0)`, the three-way sign, leaves a diamond
    // whose other arm negates the `x < y` byte:
    //
    //     cmp X, Y                            cmp X, Y
    //     jle .ELSE                           setg A
    //     D = 1                               setl B
    //     jmp .END                      ->    A -= B          (bytes)
    //   .ELSE:                                D = sext(A)
    //     cmp X, Y
    //     setl T; Z = zext(T); neg Z
    //     D = Z
    //   .END:
    //
    // LLVM matches the same pair of selects as `scmp` and lowers it to the two
    // setcc bytes. The unsigned form tests `jbe`, `seta` and `setb`. The
    // mirrored order, `x < y ? -1 : (x > y ? 1 : 0)`, branches with `jge`,
    // loads -1 and keeps the `x > y` byte without negating it.
    bool isSameCompare(const MicroInstr& left, const MicroInstrOperand* leftOps, const MicroInstr& right, const MicroInstrOperand* rightOps)
    {
        if (left.op != right.op || leftOps[0].reg != rightOps[0].reg || leftOps[1].opBits != rightOps[1].opBits)
            return false;
        if (left.op == MicroInstrOpcode::CmpRegReg)
            return leftOps[1].reg == rightOps[1].reg && leftOps[2].opBits == rightOps[2].opBits;
        return left.op == MicroInstrOpcode::CmpRegImm && !leftOps[2].hasWideImmediateValue() && !rightOps[2].hasWideImmediateValue() &&
               leftOps[2].valueU64 == rightOps[2].valueU64;
    }

    bool convertThreeWaySignDiamonds(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        if (!context.builder)
            return false;

        ProgramLayout layout;
        buildProgramLayout(layout, storage, operands);

        std::unordered_map<uint32_t, uint32_t> labelReferences;
        std::unordered_map<uint32_t, uint32_t> mentions;
        SmallVector<MicroInstrRegOperandRef>   regOperands;
        for (const MicroInstrRef ref : layout.order)
        {
            const MicroInstr* inst = storage.ptr(ref);
            if (!inst)
                continue;
            if (inst->op == MicroInstrOpcode::JumpReg || inst->op == MicroInstrOpcode::LoadLabelAddress)
                return false;
            uint32_t labelId = 0;
            if (tryGetJumpTargetLabelId(labelId, *inst, inst->ops(operands)))
                ++labelReferences[labelId];
            regOperands.clear();
            inst->collectRegOperands(operands, regOperands, nullptr);
            for (const MicroInstrRegOperandRef& regOperand : regOperands)
            {
                if (regOperand.reg && regOperand.reg->isVirtualInt())
                    ++mentions[regOperand.reg->index()];
            }
        }

        std::unordered_set<uint32_t> relocated;
        for (const MicroRelocation& reloc : context.builder->codeRelocations())
        {
            if (reloc.instructionRef.isValid())
                relocated.insert(reloc.instructionRef.get());
        }

        constexpr size_t K_MAX_SHAPE = 11;
        const size_t     count       = layout.order.size();
        const auto       instAt  = [&](size_t index) -> const MicroInstr* {
            return index < count ? storage.ptr(layout.order[index]) : nullptr;
        };

        bool     changed                = false;
        uint32_t nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        for (size_t at = 0; at + K_MAX_SHAPE - 1 <= count; ++at)
        {
            const MicroInstr* cmp    = instAt(at);
            const MicroInstr* branch = instAt(at + 1);
            if (!cmp || !branch || (cmp->op != MicroInstrOpcode::CmpRegReg && cmp->op != MicroInstrOpcode::CmpRegImm) ||
                branch->op != MicroInstrOpcode::JumpCond)
                continue;

            // `jle`/`jbe` leaves the 1 for the negated `x < y` byte; `jge`/`jae`
            // leaves the -1 for the `x > y` byte.
            const MicroInstrOperand* branchOps = branch->ops(operands);
            MicroCond                greater   = MicroCond::Unconditional;
            MicroCond                less      = MicroCond::Unconditional;
            bool                     negated   = true;
            switch (branchOps[0].cpuCond)
            {
                case MicroCond::LessOrEqual:
                    greater = MicroCond::Greater;
                    less    = MicroCond::Less;
                    break;
                case MicroCond::BelowOrEqual:
                    greater = MicroCond::Above;
                    less    = MicroCond::Below;
                    break;
                case MicroCond::GreaterOrEqual:
                    greater = MicroCond::Greater;
                    less    = MicroCond::Less;
                    negated = false;
                    break;
                case MicroCond::AboveOrEqual:
                    greater = MicroCond::Above;
                    less    = MicroCond::Below;
                    negated = false;
                    break;
                default:
                    continue;
            }
            const size_t shapeSize = negated ? K_MAX_SHAPE : K_MAX_SHAPE - 1;
            if (at + shapeSize > count)
                continue;

            const MicroInstr* one     = instAt(at + 2);
            const MicroInstr* skip    = instAt(at + 3);
            const MicroInstr* elseLbl = instAt(at + 4);
            const MicroInstr* again   = instAt(at + 5);
            const MicroInstr* set     = instAt(at + 6);
            const MicroInstr* extend  = instAt(at + 7);
            const MicroInstr* negate  = negated ? instAt(at + 8) : nullptr;
            const MicroInstr* merge   = instAt(at + shapeSize - 2);
            const MicroInstr* endLbl  = instAt(at + shapeSize - 1);
            if (!one || !skip || !elseLbl || !again || !set || !extend || (negated && !negate) || !merge || !endLbl)
                continue;
            if (one->op != MicroInstrOpcode::LoadRegImm || skip->op != MicroInstrOpcode::JumpCond || set->op != MicroInstrOpcode::SetCondReg ||
                extend->op != MicroInstrOpcode::LoadZeroExtRegReg || (negated && negate->op != MicroInstrOpcode::OpUnaryReg) ||
                merge->op != MicroInstrOpcode::LoadRegReg)
                continue;

            const MicroInstrOperand* cmpOps   = cmp->ops(operands);
            const MicroInstrOperand* oneOps   = one->ops(operands);
            const MicroInstrOperand* skipOps  = skip->ops(operands);
            const MicroInstrOperand* setOps   = set->ops(operands);
            const MicroInstrOperand* extOps   = extend->ops(operands);
            const MicroInstrOperand* mergeOps = merge->ops(operands);
            if (!isSameCompare(*cmp, cmpOps, *again, again->ops(operands)))
                continue;

            uint32_t elseId = 0;
            uint32_t endId  = 0;
            uint32_t label  = 0;
            if (!tryGetJumpTargetLabelId(elseId, *branch, branchOps) || skipOps[0].cpuCond != MicroCond::Unconditional ||
                !tryGetJumpTargetLabelId(endId, *skip, skipOps) || elseId == endId)
                continue;
            if (!tryGetLabelId(label, *elseLbl, elseLbl->ops(operands)) || label != elseId)
                continue;
            if (!tryGetLabelId(label, *endLbl, endLbl->ops(operands)) || label != endId)
                continue;
            if (labelReferences[elseId] != 1 || labelReferences[endId] != 1)
                continue;

            // D = 1 on one side and D = -zext(x < y) on the other, or D = -1 and
            // D = zext(x > y), at one width.
            const MicroReg    result = oneOps[0].reg;
            const MicroOpBits bits   = oneOps[1].opBits;
            const uint64_t    loaded = negated ? 1 : getBitsMask(bits);
            if (!result.isVirtualInt() || (bits != MicroOpBits::B32 && bits != MicroOpBits::B64) || oneOps[2].hasWideImmediateValue() ||
                (oneOps[2].valueU64 & getBitsMask(bits)) != loaded)
                continue;
            const MicroReg flag  = setOps[0].reg;
            const MicroReg value = extOps[0].reg;
            if (setOps[1].cpuCond != (negated ? less : greater) || !flag.isVirtualInt() || !value.isVirtualInt() || extOps[1].reg != flag ||
                extOps[2].opBits != bits || extOps[3].opBits != MicroOpBits::B8)
                continue;
            if (negated)
            {
                const MicroInstrOperand* negOps = negate->ops(operands);
                if (negOps[0].reg != value || negOps[1].opBits != bits || negOps[2].microOp != MicroOp::Negate)
                    continue;
            }
            if (mergeOps[0].reg != result || mergeOps[1].reg != value || mergeOps[2].opBits != bits)
                continue;
            if (value == result || flag == result)
                continue;

            // The byte and its negation live in the arm alone.
            const uint32_t valueUses   = negated ? 3 : 2;
            const uint32_t flagInside  = flag == value ? valueUses + 2 : 2;
            const uint32_t valueInside = flag == value ? valueUses + 2 : valueUses;
            if (mentions[flag.index()] != flagInside || mentions[value.index()] != valueInside)
                continue;

            bool hasRelocation = false;
            for (size_t index = at + 1; index < at + shapeSize; ++index)
                hasRelocation |= relocated.contains(layout.order[index].get());
            if (hasRelocation || !MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*context.builder, layout.order[at + shapeSize - 2]))
                continue;

            const MicroInstrRef insertRef = layout.order[at + 1];
            const MicroReg      high      = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
            const MicroReg      low       = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);

            MicroInstrOperand highOps[2];
            highOps[0].reg     = high;
            highOps[1].cpuCond = greater;
            storage.insertDerivedBefore(operands, insertRef, MicroInstrOpcode::SetCondReg, highOps);
            MicroInstrOperand lowOps[2];
            lowOps[0].reg     = low;
            lowOps[1].cpuCond = less;
            storage.insertDerivedBefore(operands, insertRef, MicroInstrOpcode::SetCondReg, lowOps);
            MicroInstrOperand subOps[4];
            subOps[0].reg     = high;
            subOps[1].reg     = low;
            subOps[2].opBits  = MicroOpBits::B8;
            subOps[3].microOp = MicroOp::Subtract;
            storage.insertDerivedBefore(operands, insertRef, MicroInstrOpcode::OpBinaryRegReg, subOps);
            MicroInstrOperand signOps[4];
            signOps[0].reg    = result;
            signOps[1].reg    = high;
            signOps[2].opBits = bits;
            signOps[3].opBits = MicroOpBits::B8;
            storage.insertDerivedBefore(operands, insertRef, MicroInstrOpcode::LoadSignedExtRegReg, signOps);

            for (size_t index = at + 1; index < at + shapeSize; ++index)
                storage.erase(layout.order[index]);

            changed = true;
            at += shapeSize - 1;
        }

        if (changed)
            context.builder->invalidateControlFlowGraph();
        return changed;
    }

    // A switch that only picks a constant, as `switch k { case .A: return 1
    // case .B: return 4 ... default: return 16 }`, is a dispatch chain whose
    // targets each load one immediate into the same register:
    //
    //     cmp X, C0; je .L0                 I = X - LO
    //     cmp X, C1; je .L1                 cmp I, N - 1; cmova I, DEFAULT
    //     ...                               I *= W
    //     jmp .LD                     ->    T = PACKED >> I
    //   .L0: D = V0; ret                    T = low W bits of T
    //     ...                               D = T
    //   .LD: D = VD; ret                    ret
    //
    // LLVM's SwitchToLookupTable packs such a table into a register when its
    // entries fit (a bitmap table): one shift reads every value and the chain
    // of branches goes. An index past the cases is clamped to an entry that
    // holds the default, a hole or entry N, which also keeps the shift inside
    // the register. The cases may also join after their loads, the default
    // then being what D held before the chain.
    bool convertSwitchesToPackedTables(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        constexpr size_t   K_MIN_CASES    = 3;
        constexpr uint64_t K_MAX_ENTRIES  = 63;
        constexpr size_t   K_MAX_LOOKBACK = 4;

        if (!context.builder)
            return false;

        ProgramLayout layout;
        buildProgramLayout(layout, storage, operands);

        std::unordered_map<uint32_t, uint32_t> labelReferences;
        for (const MicroInstrRef ref : layout.order)
        {
            const MicroInstr* inst = storage.ptr(ref);
            if (!inst)
                continue;
            if (inst->op == MicroInstrOpcode::JumpReg || inst->op == MicroInstrOpcode::LoadLabelAddress)
                return false;
            uint32_t labelId = 0;
            if (tryGetJumpTargetLabelId(labelId, *inst, inst->ops(operands)))
                ++labelReferences[labelId];
        }

        std::unordered_set<uint32_t> relocated;
        for (const MicroRelocation& reloc : context.builder->codeRelocations())
        {
            if (reloc.instructionRef.isValid())
                relocated.insert(reloc.instructionRef.get());
        }

        const size_t count  = layout.order.size();
        const auto   instAt = [&](size_t index) -> const MicroInstr* {
            return index < count ? storage.ptr(layout.order[index]) : nullptr;
        };
        const auto isUnconditionalJump = [&](const MicroInstr* inst) {
            return inst && inst->op == MicroInstrOpcode::JumpCond && inst->ops(operands)[0].cpuCond == MicroCond::Unconditional;
        };

        struct Arm
        {
            size_t   labelAt = 0;
            uint64_t value   = 0;
            bool     falls   = false;
        };

        bool     changed                = false;
        uint32_t nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        for (size_t start = 0; start < count; ++start)
        {
            const MicroInstr* first = instAt(start);
            if (!first || first->op != MicroInstrOpcode::CmpRegImm)
                continue;
            const MicroReg    key     = first->ops(operands)[0].reg;
            const MicroOpBits keyBits = first->ops(operands)[1].opBits;
            if (!key.isVirtualInt())
                continue;

            // The chain: compares of the key, each taking its case on equality,
            // or a case range `cmp X, LO; jb .SKIP; cmp X, HI; jbe .L; .SKIP:`.
            SmallVector<std::pair<uint64_t, uint32_t>, 16> cases;
            std::unordered_map<uint32_t, uint32_t>         chainJumps;
            size_t                                         at            = start;
            bool                                           fallsIntoCase = false;
            uint32_t                                       fallDefaultId = 0;
            while (true)
            {
                const MicroInstr* cmp  = instAt(at);
                const MicroInstr* jump = instAt(at + 1);
                if (!cmp || !jump || cmp->op != MicroInstrOpcode::CmpRegImm || jump->op != MicroInstrOpcode::JumpCond)
                    break;
                const MicroInstrOperand* cmpOps  = cmp->ops(operands);
                const MicroInstrOperand* jumpOps = jump->ops(operands);
                uint32_t                 target  = 0;
                // The last case may leave for the default on inequality and fall
                // into its own arm.
                if (jumpOps[0].cpuCond == MicroCond::NotEqual)
                {
                    const MicroInstr* arm   = instAt(at + 2);
                    uint32_t          armId = 0;
                    if (cmpOps[0].reg != key || cmpOps[1].opBits != keyBits || cmpOps[2].hasWideImmediateValue() || !arm ||
                        !tryGetLabelId(armId, *arm, arm->ops(operands)) || !tryGetJumpTargetLabelId(fallDefaultId, *jump, jumpOps))
                        break;
                    cases.push_back({cmpOps[2].valueU64 & getBitsMask(keyBits), armId});
                    fallsIntoCase = true;
                    at += 1;
                    break;
                }
                if (jumpOps[0].cpuCond == MicroCond::Below)
                {
                    const MicroInstr* highCmp  = instAt(at + 2);
                    const MicroInstr* highJump = instAt(at + 3);
                    const MicroInstr* skip     = instAt(at + 4);
                    uint32_t          skipId   = 0;
                    uint32_t          placedId = 0;
                    if (!highCmp || !highJump || !skip || highCmp->op != MicroInstrOpcode::CmpRegImm || highJump->op != MicroInstrOpcode::JumpCond ||
                        !tryGetJumpTargetLabelId(skipId, *jump, jumpOps) || !tryGetLabelId(placedId, *skip, skip->ops(operands)) || placedId != skipId ||
                        labelReferences[skipId] != 1)
                        break;
                    const MicroInstrOperand* highOps     = highCmp->ops(operands);
                    const MicroInstrOperand* highJumpOps = highJump->ops(operands);
                    if (cmpOps[0].reg != key || cmpOps[1].opBits != keyBits || cmpOps[2].hasWideImmediateValue() || highOps[0].reg != key ||
                        highOps[1].opBits != keyBits || highOps[2].hasWideImmediateValue() || highJumpOps[0].cpuCond != MicroCond::BelowOrEqual ||
                        !tryGetJumpTargetLabelId(target, *highJump, highJumpOps))
                        break;
                    const uint64_t rangeLow  = cmpOps[2].valueU64 & getBitsMask(keyBits);
                    const uint64_t rangeHigh = highOps[2].valueU64 & getBitsMask(keyBits);
                    if (rangeHigh < rangeLow || rangeHigh - rangeLow >= K_MAX_ENTRIES)
                        break;
                    for (uint64_t caseValue = rangeLow; caseValue <= rangeHigh; ++caseValue)
                        cases.push_back({caseValue, target});
                    ++chainJumps[target];
                    at += 5;
                    continue;
                }
                if (cmpOps[0].reg != key || cmpOps[1].opBits != keyBits || cmpOps[2].hasWideImmediateValue() || jumpOps[0].cpuCond != MicroCond::Equal ||
                    !tryGetJumpTargetLabelId(target, *jump, jumpOps))
                    break;
                cases.push_back({cmpOps[2].valueU64 & getBitsMask(keyBits), target});
                ++chainJumps[target];
                at += 2;
            }
            if (cases.size() < K_MIN_CASES)
                continue;

            const size_t      tailAt    = at;
            const MicroInstr* tail      = instAt(tailAt);
            uint32_t          defaultId = fallDefaultId;
            if (!fallsIntoCase && (!isUnconditionalJump(tail) || !tryGetJumpTargetLabelId(defaultId, *tail, tail->ops(operands))))
                continue;

            // Every case loads one immediate into the same register, then
            // returns, or joins at one label.
            MicroReg                          result;
            MicroOpBits                       resultBits = MicroOpBits::Zero;
            bool                              returns    = false;
            bool                              joins      = false;
            uint32_t                          endId      = 0;
            const auto                        matchArm   = [&](uint32_t labelId, Arm& arm) {
                const auto found = layout.labelOrdinalById.find(labelId);
                if (found == layout.labelOrdinalById.end() || found->second == 0)
                    return false;
                const size_t      labelAt = found->second;
                const MicroInstr* before  = instAt(labelAt - 1);
                const MicroInstr* load    = instAt(labelAt + 1);
                const MicroInstr* exit    = instAt(labelAt + 2);
                const bool fallenInto = fallsIntoCase && labelAt == tailAt + 1;
                if (!before || !load || !exit || (!fallenInto && before->op != MicroInstrOpcode::Ret && !isUnconditionalJump(before)))
                    return false;
                if (load->op != MicroInstrOpcode::LoadRegImm || (labelAt >= start && labelAt <= tailAt))
                    return false;
                const MicroInstrOperand* loadOps = load->ops(operands);
                if (loadOps[2].hasWideImmediateValue() || !loadOps[0].reg.isAnyInt() || loadOps[0].reg == key)
                    return false;
                if (!result.isValid())
                {
                    result     = loadOps[0].reg;
                    resultBits = loadOps[1].opBits;
                }
                else if (loadOps[0].reg != result || loadOps[1].opBits != resultBits)
                    return false;
                if (relocated.contains(layout.order[labelAt + 1].get()) || relocated.contains(layout.order[labelAt + 2].get()))
                    return false;

                arm.labelAt = labelAt;
                arm.value   = loadOps[2].valueU64 & getBitsMask(resultBits);
                arm.falls   = false;
                if (exit->op == MicroInstrOpcode::Ret)
                {
                    returns = true;
                    return !joins;
                }

                uint32_t exitId = 0;
                if (isUnconditionalJump(exit))
                {
                    if (!tryGetJumpTargetLabelId(exitId, *exit, exit->ops(operands)))
                        return false;
                }
                else if (tryGetLabelId(exitId, *exit, exit->ops(operands)))
                    arm.falls = true;
                else
                    return false;
                if (returns || (joins && exitId != endId))
                    return false;
                joins = true;
                endId = exitId;
                return true;
            };

            std::unordered_map<uint32_t, Arm> arms;
            bool                              valid = true;
            for (const auto& [caseValue, labelId] : cases)
            {
                if (arms.contains(labelId))
                    continue;
                Arm arm;
                if (!matchArm(labelId, arm) || labelReferences[labelId] != chainJumps[labelId])
                {
                    valid = false;
                    break;
                }
                arms[labelId] = arm;
            }
            if (!valid || arms.contains(defaultId))
                continue;

            // The default: its own constant arm, or what D held before the chain
            // when the chain's last jump goes straight to the join.
            uint64_t defaultValue = 0;
            Arm      defaultArm;
            bool     defaultIsArm = false;
            if (joins && defaultId == endId)
            {
                bool found = false;
                for (size_t back = 1; back <= K_MAX_LOOKBACK && back <= start && !found; ++back)
                {
                    const MicroInstr* inst = instAt(start - back);
                    if (!inst)
                        break;
                    const MicroInstrFlags flags = MicroInstr::info(inst->op).flags;
                    if (inst->op == MicroInstrOpcode::Label || flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                        flags.has(MicroInstrFlagsE::JumpInstruction) || flags.has(MicroInstrFlagsE::IsCallInstruction))
                        break;
                    const MicroInstrOperand* ops = inst->ops(operands);
                    if (inst->op == MicroInstrOpcode::LoadRegImm && ops[0].reg == result && ops[1].opBits == resultBits && !ops[2].hasWideImmediateValue())
                    {
                        defaultValue = ops[2].valueU64 & getBitsMask(resultBits);
                        found        = true;
                        break;
                    }
                    SmallVector<MicroInstrRegOperandRef> regOperands;
                    inst->collectRegOperands(operands, regOperands, nullptr);
                    bool touches = false;
                    for (const MicroInstrRegOperandRef& regOperand : regOperands)
                        touches |= regOperand.reg && *regOperand.reg == result;
                    if (touches)
                        break;
                }
                if (!found)
                    continue;
            }
            else
            {
                if (!matchArm(defaultId, defaultArm) || labelReferences[defaultId] != 1)
                    continue;
                defaultValue = defaultArm.value;
                defaultIsArm = true;
            }
            if (!result.isValid() || (!returns && !joins))
                continue;
            if (joins && !MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*context.builder, layout.order[tailAt]))
                continue;

            // The table: a hole holds the default already, else entry N does,
            // and the entries must fit a register.
            uint64_t low  = UINT64_MAX;
            uint64_t high = 0;
            for (const auto& [caseValue, labelId] : cases)
            {
                low  = std::min(low, caseValue);
                high = std::max(high, caseValue);
            }
            // The span first: the keys may cover the whole word.
            if (high - low >= K_MAX_ENTRIES)
                continue;
            const uint64_t entries = high - low + 1;

            SmallVector<uint64_t, 64> table;
            SmallVector<uint8_t, 64>  isSet;
            table.resize(entries + 1, defaultValue);
            isSet.resize(entries + 1, 0);
            for (const auto& [caseValue, labelId] : cases)
            {
                const uint64_t index = caseValue - low;
                if (isSet[index])
                    continue;
                table[index] = arms[labelId].value;
                isSet[index] = 1;
            }

            uint64_t clampIndex = entries;
            for (uint64_t index = 0; index < entries; ++index)
            {
                if (!isSet[index])
                {
                    clampIndex = index;
                    table.resize(entries);
                    break;
                }
            }

            const uint32_t resultWidth = getNumBits(resultBits);
            uint32_t       unsignedWidth = 1;
            uint32_t       signedWidth   = 1;
            for (const uint64_t entry : table)
            {
                const int64_t signedEntry = static_cast<int64_t>(entry << (64 - resultWidth)) >> (64 - resultWidth);
                unsignedWidth             = std::max(unsignedWidth, static_cast<uint32_t>(64 - std::countl_zero(entry | 1)));
                const uint64_t magnitude  = signedEntry < 0 ? ~static_cast<uint64_t>(signedEntry) : static_cast<uint64_t>(signedEntry);
                signedWidth               = std::max(signedWidth, static_cast<uint32_t>(65 - std::countl_zero(magnitude)));
            }
            const bool     isSigned = signedWidth < unsignedWidth;
            const uint32_t width    = isSigned ? signedWidth : unsignedWidth;
            if (width >= resultWidth || static_cast<uint64_t>(width) * table.size() > 64)
                continue;

            uint64_t packed = 0;
            for (size_t index = 0; index < table.size(); ++index)
                packed |= (table[index] & ((1ULL << width) - 1)) << (index * width);

            // Emit before the chain, then drop the chain and its arms.
            const MicroInstrRef anchor    = layout.order[start];
            const MicroOpBits   indexBits = keyBits == MicroOpBits::B64 ? MicroOpBits::B64 : MicroOpBits::B32;
            const MicroReg      index     = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
            const MicroReg      clamp     = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
            const MicroReg      bits      = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
            const auto          insert    = [&](MicroInstrOpcode op, std::span<const MicroInstrOperand> ops) {
                storage.insertDerivedBefore(operands, anchor, op, ops);
            };

            if (keyBits == MicroOpBits::B8 || keyBits == MicroOpBits::B16)
            {
                MicroInstrOperand ops[4];
                ops[0].reg    = index;
                ops[1].reg    = key;
                ops[2].opBits = MicroOpBits::B32;
                ops[3].opBits = keyBits;
                insert(MicroInstrOpcode::LoadZeroExtRegReg, ops);
            }
            else
            {
                MicroInstrOperand ops[3];
                ops[0].reg    = index;
                ops[1].reg    = key;
                ops[2].opBits = indexBits;
                insert(MicroInstrOpcode::LoadRegReg, ops);
            }
            if (low)
            {
                MicroInstrOperand ops[4];
                ops[0].reg     = index;
                ops[1].opBits  = indexBits;
                ops[2].microOp = MicroOp::Subtract;
                ops[3].setImmediateValue(ApInt(low, getNumBits(indexBits)));
                insert(MicroInstrOpcode::OpBinaryRegImm, ops);
            }
            {
                MicroInstrOperand loadOps[3];
                loadOps[0].reg    = clamp;
                loadOps[1].opBits = indexBits;
                loadOps[2].setImmediateValue(ApInt(clampIndex, getNumBits(indexBits)));
                insert(MicroInstrOpcode::LoadRegImm, loadOps);
                MicroInstrOperand cmpOps[3];
                cmpOps[0].reg    = index;
                cmpOps[1].opBits = indexBits;
                cmpOps[2].setImmediateValue(ApInt(entries - 1, getNumBits(indexBits)));
                insert(MicroInstrOpcode::CmpRegImm, cmpOps);
                MicroInstrOperand moveOps[4];
                moveOps[0].reg     = index;
                moveOps[1].reg     = clamp;
                moveOps[2].cpuCond = MicroCond::Above;
                moveOps[3].opBits  = indexBits;
                insert(MicroInstrOpcode::LoadCondRegReg, moveOps);
            }
            if (width > 1)
            {
                MicroInstrOperand ops[4];
                ops[0].reg = index;
                ops[1].opBits = indexBits;
                if (std::has_single_bit(width))
                {
                    ops[2].microOp = MicroOp::ShiftLeft;
                    ops[3].setImmediateValue(ApInt(std::countr_zero(width), getNumBits(indexBits)));
                }
                else
                {
                    ops[2].microOp = MicroOp::MultiplySigned;
                    ops[3].setImmediateValue(ApInt(width, getNumBits(indexBits)));
                }
                insert(MicroInstrOpcode::OpBinaryRegImm, ops);
            }
            {
                MicroInstrOperand loadOps[3];
                loadOps[0].reg    = bits;
                loadOps[1].opBits = MicroOpBits::B64;
                loadOps[2].setImmediateValue(ApInt(packed, 64));
                insert(MicroInstrOpcode::LoadRegImm, loadOps);
                MicroInstrOperand shiftOps[4];
                shiftOps[0].reg     = bits;
                shiftOps[1].reg     = index;
                shiftOps[2].opBits  = MicroOpBits::B64;
                shiftOps[3].microOp = MicroOp::ShiftRight;
                insert(MicroInstrOpcode::OpBinaryRegReg, shiftOps);
            }
            if (isSigned && (width == 8 || width == 16 || width == 32))
            {
                MicroInstrOperand ops[4];
                ops[0].reg    = bits;
                ops[1].reg    = bits;
                ops[2].opBits = MicroOpBits::B64;
                ops[3].opBits = width == 8 ? MicroOpBits::B8 : width == 16 ? MicroOpBits::B16 : MicroOpBits::B32;
                insert(MicroInstrOpcode::LoadSignedExtRegReg, ops);
            }
            else if (isSigned)
            {
                for (const MicroOp op : {MicroOp::ShiftLeft, MicroOp::ShiftArithmeticRight})
                {
                    MicroInstrOperand ops[4];
                    ops[0].reg     = bits;
                    ops[1].opBits  = MicroOpBits::B64;
                    ops[2].microOp = op;
                    ops[3].setImmediateValue(ApInt(64 - width, 64));
                    insert(MicroInstrOpcode::OpBinaryRegImm, ops);
                }
            }
            else
            {
                MicroInstrOperand ops[4];
                ops[0].reg     = bits;
                ops[1].opBits  = MicroOpBits::B64;
                ops[2].microOp = MicroOp::And;
                ops[3].setImmediateValue(ApInt((1ULL << width) - 1, 64));
                insert(MicroInstrOpcode::OpBinaryRegImm, ops);
            }
            {
                MicroInstrOperand ops[3];
                ops[0].reg    = result;
                ops[1].reg    = bits;
                ops[2].opBits = resultBits;
                insert(MicroInstrOpcode::LoadRegReg, ops);
            }
            // The chain's last jump leaves for the join; returning arms return here.
            if (returns)
            {
                storage.insertDerivedBefore(operands, anchor, MicroInstrOpcode::Ret, std::span<const MicroInstrOperand>{});
                storage.erase(layout.order[tailAt]);
            }
            else
            {
                MicroInstrOperand* tailOps = storage.ptr(layout.order[tailAt])->ops(operands);
                tailOps[0].cpuCond         = MicroCond::Unconditional;
                tailOps[2].valueU64        = endId;
            }

            for (size_t chainAt = start; chainAt < tailAt; ++chainAt)
                storage.erase(layout.order[chainAt]);

            const auto eraseArm = [&](const Arm& arm) {
                storage.erase(layout.order[arm.labelAt]);
                storage.erase(layout.order[arm.labelAt + 1]);
                if (!arm.falls)
                    storage.erase(layout.order[arm.labelAt + 2]);
            };
            for (const auto& [labelId, arm] : arms)
                eraseArm(arm);
            if (defaultIsArm)
                eraseArm(defaultArm);

            changed = true;
            break;
        }

        if (changed)
            context.builder->invalidateControlFlowGraph();
        return changed;
    }

    // A range test lowered as two exits to the same label:
    //
    //     cmp  X, LO                      T = X
    //     jb   .Lout                      T -= LO
    //     cmp  X, HI              ->      cmp  T, HI - LO
    //     ja   .Lout                      ja   .Lout            ; unsigned
    //
    // `c >= '0' and c <= '9'` in a scanner lowers to this. It is LLVM's
    // range-check fold (InstCombine's foldAndOrOfICmpsUsingRanges): X lies in
    // [LO, HI] exactly when X - LO, wrapped, is at most HI - LO. The signed
    // pair (jl, jg) folds the same way once LO <= HI as signed values. Either
    // exit may come first. The flags the exits leave differ afterwards, so no
    // successor may read them.
    bool isRangeExitPair(bool& outSigned, const MicroCond lowExit, const MicroCond highExit)
    {
        if (lowExit == MicroCond::Below && highExit == MicroCond::Above)
        {
            outSigned = false;
            return true;
        }

        if (lowExit == MicroCond::Less && highExit == MicroCond::Greater)
        {
            outSigned = true;
            return true;
        }

        return false;
    }

    bool foldRangeChecks(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        if (!context.builder)
            return false;

        struct RangeCheck
        {
            MicroInstrRef firstCmpRef  = MicroInstrRef::invalid();
            MicroInstrRef firstJumpRef = MicroInstrRef::invalid();
            MicroInstrRef lastCmpRef   = MicroInstrRef::invalid();
            MicroInstrRef lastJumpRef  = MicroInstrRef::invalid();
            MicroReg      value;
            MicroOpBits   bits  = MicroOpBits::Zero;
            uint64_t      low   = 0;
            uint64_t      range = 0;
        };

        SmallVector<RangeCheck> checks;
        std::unordered_set<uint32_t> used;
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            RangeCheck check;
            check.firstCmpRef  = it.current;
            check.firstJumpRef = storage.findNextInstructionRef(check.firstCmpRef);
            check.lastCmpRef   = check.firstJumpRef.isValid() ? storage.findNextInstructionRef(check.firstJumpRef) : MicroInstrRef::invalid();
            check.lastJumpRef  = check.lastCmpRef.isValid() ? storage.findNextInstructionRef(check.lastCmpRef) : MicroInstrRef::invalid();
            if (!check.lastJumpRef.isValid() || used.contains(check.firstCmpRef.get()))
                continue;

            const MicroInstr* firstCmp  = storage.ptr(check.firstCmpRef);
            const MicroInstr* firstJump = storage.ptr(check.firstJumpRef);
            const MicroInstr* lastCmp   = storage.ptr(check.lastCmpRef);
            const MicroInstr* lastJump  = storage.ptr(check.lastJumpRef);
            if (firstCmp->op != MicroInstrOpcode::CmpRegImm || lastCmp->op != MicroInstrOpcode::CmpRegImm ||
                firstJump->op != MicroInstrOpcode::JumpCond || lastJump->op != MicroInstrOpcode::JumpCond)
                continue;

            const MicroInstrOperand* firstCmpOps  = firstCmp->ops(operands);
            const MicroInstrOperand* lastCmpOps   = lastCmp->ops(operands);
            const MicroInstrOperand* firstJumpOps = firstJump->ops(operands);
            const MicroInstrOperand* lastJumpOps  = lastJump->ops(operands);
            uint32_t                 firstTarget  = 0;
            uint32_t                 lastTarget   = 0;
            if (!tryGetJumpTargetLabelId(firstTarget, *firstJump, firstJumpOps) || !tryGetJumpTargetLabelId(lastTarget, *lastJump, lastJumpOps) || firstTarget != lastTarget)
                continue;

            check.value = firstCmpOps[0].reg;
            check.bits  = firstCmpOps[1].opBits;
            if (!check.value.isVirtualInt() || lastCmpOps[0].reg != check.value || lastCmpOps[1].opBits != check.bits)
                continue;
            if (firstCmpOps[2].hasWideImmediateValue() || lastCmpOps[2].hasWideImmediateValue())
                continue;
            if (firstJumpOps[1].opBits != lastJumpOps[1].opBits)
                continue;

            const uint64_t mask      = getBitsMask(check.bits);
            uint64_t       low       = firstCmpOps[2].valueU64 & mask;
            uint64_t       high      = lastCmpOps[2].valueU64 & mask;
            MicroCond      lowExit   = firstJumpOps[0].cpuCond;
            MicroCond      highExit  = lastJumpOps[0].cpuCond;
            bool           isSigned  = false;
            if (!isRangeExitPair(isSigned, lowExit, highExit))
            {
                if (!isRangeExitPair(isSigned, highExit, lowExit))
                    continue;
                std::swap(low, high);
            }

            // An empty range would fold to a test that always passes.
            if (isSigned)
            {
                const uint32_t numBits = getNumBits(check.bits);
                const int64_t  lowS    = static_cast<int64_t>(low << (64 - numBits)) >> (64 - numBits);
                const int64_t  highS   = static_cast<int64_t>(high << (64 - numBits)) >> (64 - numBits);
                if (lowS > highS)
                    continue;
            }
            else if (low > high)
                continue;

            if (context.builder && !MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*context.builder, check.lastJumpRef))
                continue;

            check.low   = low;
            check.range = (high - low) & mask;
            used.insert(check.lastCmpRef.get());
            checks.push_back(check);
        }

        if (checks.empty())
            return false;

        uint32_t nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        for (const RangeCheck& check : checks)
        {
            const MicroReg offset = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);

            MicroInstrOperand copyOps[3];
            copyOps[0].reg    = offset;
            copyOps[1].reg    = check.value;
            copyOps[2].opBits = check.bits;
            storage.insertDerivedBefore(operands, check.firstCmpRef, MicroInstrOpcode::LoadRegReg, copyOps);

            MicroInstrOperand subOps[4];
            subOps[0].reg     = offset;
            subOps[1].opBits  = check.bits;
            subOps[2].microOp = MicroOp::Subtract;
            subOps[3].setImmediateValue(ApInt(check.low, getNumBits(check.bits)));
            storage.insertDerivedBefore(operands, check.firstCmpRef, MicroInstrOpcode::OpBinaryRegImm, subOps);

            MicroInstrOperand* lastCmpOps = storage.ptr(check.lastCmpRef)->ops(operands);
            lastCmpOps[0].reg             = offset;
            lastCmpOps[2].setImmediateValue(ApInt(check.range, getNumBits(check.bits)));
            storage.ptr(check.lastJumpRef)->ops(operands)[0].cpuCond = MicroCond::Above;

            storage.erase(check.firstCmpRef);
            storage.erase(check.firstJumpRef);
        }

        context.builder->invalidateControlFlowGraph();
        return true;
    }

    // A short-circuit `and`/`or` whose result is kept as a value:
    //
    //     cmp    X1                      cmp    X1
    //     setcc1 A                       setcc1 A
    //     B = A                          B = A
    //     j(~cc1) .L        ; and        cmp    X2
    //     cmp    X2                ->    setcc2 D
    //     setcc2 D                       [zext D]
    //     [zext D]                       B &= D            ; B |= D for `or`
    //     B = D                        .L:
    //   .L:
    //
    // On the skipping edge B holds A, which the branch pins to 0 for `and` (1
    // for `or`), so B is A op D on both paths once the second compare runs
    // unconditionally - the `and i1` LLVM makes of two branches to a common
    // destination. The second compare is a register compare: it cannot fault.
    // The flags leave through the join changed, so they must be dead there,
    // and D may not be read anywhere else.
    // `x >= LO and x <= HI` kept as a value: both sides bound the same value,
    // so the right side becomes the whole test - x - LO compared unsigned
    // against HI - LO (foldRangeChecks' fold) - and B simply takes it. The left
    // side stays for the dead-code pass: B's first byte is overwritten.
    struct RangeMerge
    {
        MicroInstrRef leftCmpRef  = MicroInstrRef::invalid();
        MicroInstrRef rightCmpRef = MicroInstrRef::invalid();
        MicroInstrRef rightSetRef = MicroInstrRef::invalid();
        MicroCond     leftCond    = MicroCond::Unconditional;
    };

    bool tryFoldRangeMerge(MicroStorage& storage, MicroOperandStorage& operands, const RangeMerge& merge, uint32_t& nextVirtualIntRegIndex)
    {
        const MicroInstr* leftCmp  = merge.leftCmpRef.isValid() ? storage.ptr(merge.leftCmpRef) : nullptr;
        const MicroInstr* rightCmp = storage.ptr(merge.rightCmpRef);
        const MicroInstr* rightSet = storage.ptr(merge.rightSetRef);
        if (!leftCmp || leftCmp->op != MicroInstrOpcode::CmpRegImm || rightCmp->op != MicroInstrOpcode::CmpRegImm)
            return false;

        const MicroInstrOperand* leftOps  = leftCmp->ops(operands);
        MicroInstrOperand*       rightOps = rightCmp->ops(operands);
        const MicroReg           value    = leftOps[0].reg;
        const MicroOpBits        bits     = leftOps[1].opBits;
        if (!value.isVirtualInt() || rightOps[0].reg != value || rightOps[1].opBits != bits)
            return false;
        if (leftOps[2].hasWideImmediateValue() || rightOps[2].hasWideImmediateValue())
            return false;

        const uint64_t  mask      = getBitsMask(bits);
        uint64_t        low       = leftOps[2].valueU64 & mask;
        uint64_t        high      = rightOps[2].valueU64 & mask;
        const MicroCond rightCond = rightSet->ops(operands)[1].cpuCond;
        bool            isSigned  = false;
        if (merge.leftCond == MicroCond::AboveOrEqual && rightCond == MicroCond::BelowOrEqual)
            isSigned = false;
        else if (merge.leftCond == MicroCond::GreaterOrEqual && rightCond == MicroCond::LessOrEqual)
            isSigned = true;
        else if (merge.leftCond == MicroCond::BelowOrEqual && rightCond == MicroCond::AboveOrEqual)
            std::swap(low, high);
        else if (merge.leftCond == MicroCond::LessOrEqual && rightCond == MicroCond::GreaterOrEqual)
        {
            isSigned = true;
            std::swap(low, high);
        }
        else
            return false;

        if (isSigned)
        {
            const uint32_t numBits = getNumBits(bits);
            const int64_t  lowS    = static_cast<int64_t>(low << (64 - numBits)) >> (64 - numBits);
            const int64_t  highS   = static_cast<int64_t>(high << (64 - numBits)) >> (64 - numBits);
            if (lowS > highS)
                return false;
        }
        else if (low > high)
            return false;

        const MicroReg offset = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);

        MicroInstrOperand copyOps[3];
        copyOps[0].reg    = offset;
        copyOps[1].reg    = value;
        copyOps[2].opBits = bits;
        storage.insertDerivedBefore(operands, merge.rightCmpRef, MicroInstrOpcode::LoadRegReg, copyOps);

        MicroInstrOperand subOps[4];
        subOps[0].reg     = offset;
        subOps[1].opBits  = bits;
        subOps[2].microOp = MicroOp::Subtract;
        subOps[3].setImmediateValue(ApInt(low, getNumBits(bits)));
        storage.insertDerivedBefore(operands, merge.rightCmpRef, MicroInstrOpcode::OpBinaryRegImm, subOps);

        rightOps          = storage.ptr(merge.rightCmpRef)->ops(operands);
        rightOps[0].reg   = offset;
        rightOps[2].setImmediateValue(ApInt((high - low) & mask, getNumBits(bits)));
        storage.ptr(merge.rightSetRef)->ops(operands)[1].cpuCond = MicroCond::BelowOrEqual;
        return true;
    }

    // A short-circuit RHS may compare a cell that the LHS already read. Keep
    // that first value in a register so the RHS becomes a pure comparison and
    // the regular boolean combiner can safely remove the branch:
    //
    //     cmp [address], X            value = [address]
    //     setcc A                     cmp value, X
    //     B = A                       setcc A
    //     jcc .Ljoin          ->      B = A
    //     cmp [address], K            cmp value, K
    //     setcc C                     setcc C
    //     B = C                       B = C
    //
    // The first comparison already performs the load on every path. No write
    // or call may separate it from the repeated comparison.
    bool forwardRepeatedMemoryCompareInShortCircuit(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        std::unordered_set<uint32_t> relocated;
        if (context.builder)
        {
            for (const MicroRelocation& reloc : context.builder->codeRelocations())
            {
                if (reloc.instructionRef.isValid())
                    relocated.insert(reloc.instructionRef.get());
            }
        }

        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            if (it->op != MicroInstrOpcode::JumpCond || relocated.contains(it.current.get()))
                continue;

            const MicroInstrRef copyRef = storage.findPreviousInstructionRef(it.current);
            const MicroInstr*   copy    = storage.ptr(copyRef);
            if (!copy || copy->op != MicroInstrOpcode::LoadRegReg)
                continue;
            const MicroInstrRef setRef = storage.findPreviousInstructionRef(copyRef);
            const MicroInstr*   set    = storage.ptr(setRef);
            if (!set || set->op != MicroInstrOpcode::SetCondReg)
                continue;
            const MicroInstrRef leftCmpRef = storage.findPreviousInstructionRef(setRef);
            const MicroInstr*   leftCmp    = storage.ptr(leftCmpRef);
            if (!leftCmp || (leftCmp->op != MicroInstrOpcode::CmpAmcReg && leftCmp->op != MicroInstrOpcode::CmpAmcImm) ||
                relocated.contains(leftCmpRef.get()))
                continue;

            const MicroInstrRef rightCmpRef = storage.findNextInstructionRef(it.current);
            const MicroInstr*   rightCmp    = storage.ptr(rightCmpRef);
            if (!rightCmp || rightCmp->op != MicroInstrOpcode::CmpAmcImm || relocated.contains(rightCmpRef.get()))
                continue;

            const MicroInstrOperand* leftOps  = leftCmp->ops(operands);
            const MicroInstrOperand* rightOps = rightCmp->ops(operands);
            if (!leftOps || !rightOps)
                continue;
            const uint32_t leftBitsIndex = leftCmp->op == MicroInstrOpcode::CmpAmcReg ? 4 : 2;
            const uint32_t leftMulIndex  = leftCmp->op == MicroInstrOpcode::CmpAmcReg ? 5 : 4;
            const uint32_t leftAddIndex  = leftCmp->op == MicroInstrOpcode::CmpAmcReg ? 6 : 5;
            if (leftOps[0].reg != rightOps[0].reg || leftOps[1].reg != rightOps[1].reg ||
                leftOps[leftBitsIndex].opBits != rightOps[2].opBits || leftOps[3].opBits != rightOps[3].opBits ||
                leftOps[leftMulIndex].valueU64 != rightOps[4].valueU64 || leftOps[leftAddIndex].valueU64 != rightOps[5].valueU64)
                continue;

            bool safe = true;
            for (MicroInstrRef ref = storage.findNextInstructionRef(leftCmpRef); ref.isValid() && ref != rightCmpRef; ref = storage.findNextInstructionRef(ref))
            {
                const MicroInstr*      between = storage.ptr(ref);
                const MicroInstrDef&   info    = MicroInstr::info(between->op);
                const MicroInstrUseDef useDef  = between->collectUseDef(operands, context.encoder);
                if (info.flags.has(MicroInstrFlagsE::WritesMemory) || useDef.isCall ||
                    std::ranges::find(useDef.defs, leftOps[0].reg) != useDef.defs.end() ||
                    std::ranges::find(useDef.defs, leftOps[1].reg) != useDef.defs.end())
                {
                    safe = false;
                    break;
                }
            }
            if (!safe)
                continue;

            const bool     leftHasRegister = leftCmp->op == MicroInstrOpcode::CmpAmcReg;
            MicroInstrRef  sourceLoadRef   = MicroInstrRef::invalid();
            const MicroInstrOperand* sourceLoadOps = nullptr;
            MicroCond swappedSetCond  = MicroCond::Unconditional;
            MicroCond swappedJumpCond = MicroCond::Unconditional;
            if (leftHasRegister)
            {
                sourceLoadRef = storage.findPreviousInstructionRef(leftCmpRef);
                const MicroInstr* sourceLoad = storage.ptr(sourceLoadRef);
                sourceLoadOps = sourceLoad && sourceLoad->op == MicroInstrOpcode::LoadAmcRegMem ? sourceLoad->ops(operands) : nullptr;
                if (!sourceLoadOps || relocated.contains(sourceLoadRef.get()) || sourceLoadOps[0].reg != leftOps[2].reg ||
                    sourceLoadOps[3].opBits != leftOps[leftBitsIndex].opBits)
                    continue;

                uint32_t sourceMentions = 0;
                SmallVector<MicroInstrRegOperandRef> regOperands;
                for (MicroInstr& inst : storage.view())
                {
                    regOperands.clear();
                    inst.collectRegOperands(operands, regOperands, context.encoder);
                    for (const MicroInstrRegOperandRef& regOperand : regOperands)
                    {
                        if (regOperand.reg && *regOperand.reg == sourceLoadOps[0].reg)
                            ++sourceMentions;
                    }
                }
                const auto swapCondition = [](MicroCond& out, const MicroCond in) {
                    switch (in)
                    {
                        case MicroCond::Equal: out = MicroCond::Equal; return true;
                        case MicroCond::NotEqual: out = MicroCond::NotEqual; return true;
                        case MicroCond::Zero: out = MicroCond::Zero; return true;
                        case MicroCond::NotZero: out = MicroCond::NotZero; return true;
                        case MicroCond::Above: out = MicroCond::Below; return true;
                        case MicroCond::AboveOrEqual: out = MicroCond::BelowOrEqual; return true;
                        case MicroCond::Below: out = MicroCond::Above; return true;
                        case MicroCond::BelowOrEqual: out = MicroCond::AboveOrEqual; return true;
                        case MicroCond::Greater: out = MicroCond::Less; return true;
                        case MicroCond::GreaterOrEqual: out = MicroCond::LessOrEqual; return true;
                        case MicroCond::Less: out = MicroCond::Greater; return true;
                        case MicroCond::LessOrEqual: out = MicroCond::GreaterOrEqual; return true;
                        default: return false;
                    }
                };
                const MicroInstrOperand* setOps  = set->ops(operands);
                const MicroInstrOperand* jumpOps = it->ops(operands);
                if (sourceMentions != 2 || !setOps || !jumpOps ||
                    !swapCondition(swappedSetCond, setOps[1].cpuCond) ||
                    !swapCondition(swappedJumpCond, jumpOps[0].cpuCond))
                    continue;
            }

            const MicroReg value           = MicroReg::virtualIntReg(MicroPassHelpers::computeNextVirtualIntRegIndex(context));
            MicroInstrOperand loadOps[7];
            loadOps[0].reg = value;
            loadOps[1]     = leftOps[0];
            loadOps[2]     = leftOps[1];
            loadOps[3]     = leftOps[leftBitsIndex];
            loadOps[4]     = leftOps[3];
            loadOps[5]     = leftOps[leftMulIndex];
            loadOps[6]     = leftOps[leftAddIndex];

            MicroInstrOperand leftRegOps[7];
            leftRegOps[0].reg = value;
            if (leftHasRegister)
            {
                leftRegOps[0]     = sourceLoadOps[1];
                leftRegOps[1]     = sourceLoadOps[2];
                leftRegOps[2].reg = value;
                leftRegOps[3]     = sourceLoadOps[4];
                leftRegOps[4]     = sourceLoadOps[3];
                leftRegOps[5]     = sourceLoadOps[5];
                leftRegOps[6]     = sourceLoadOps[6];
            }
            else
            {
                leftRegOps[1] = leftOps[leftBitsIndex];
                leftRegOps[2] = leftOps[6];
            }

            MicroInstrOperand rightRegOps[3];
            rightRegOps[0].reg = value;
            rightRegOps[1]     = rightOps[2];
            rightRegOps[2]     = rightOps[6];

            if (leftHasRegister)
            {
                set->ops(operands)[1].cpuCond = swappedSetCond;
                it->ops(operands)[0].cpuCond  = swappedJumpCond;
            }
            storage.insertDerivedBefore(operands, leftHasRegister ? sourceLoadRef : leftCmpRef, MicroInstrOpcode::LoadAmcRegMem, loadOps);
            storage.insertDerivedBefore(operands, leftCmpRef, leftHasRegister ? MicroInstrOpcode::CmpAmcReg : MicroInstrOpcode::CmpRegImm,
                                        std::span<const MicroInstrOperand>(leftRegOps, leftHasRegister ? 7 : 3));
            storage.insertDerivedBefore(operands, rightCmpRef, MicroInstrOpcode::CmpRegImm, rightRegOps);
            if (leftHasRegister)
                storage.erase(sourceLoadRef);
            storage.erase(leftCmpRef);
            storage.erase(rightCmpRef);
            return true;
        }

        return false;
    }

    bool convertShortCircuitBooleans(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        if (!context.builder)
            return false;

        struct Candidate
        {
            MicroInstrRef jumpRef   = MicroInstrRef::invalid();
            MicroInstrRef mergeRef  = MicroInstrRef::invalid();
            MicroReg      result;
            MicroReg      rhs;
            MicroOp       op       = MicroOp::And;
            uint32_t      mentions = 2;
            MicroInstrRef leftCmpRef  = MicroInstrRef::invalid();
            MicroInstrRef rightCmpRef = MicroInstrRef::invalid();
            MicroInstrRef rightSetRef = MicroInstrRef::invalid();
            MicroCond     leftCond    = MicroCond::Unconditional;
            MicroReg      skippedDecrement;
            MicroReg      skippedMask;
        };

        SmallVector<Candidate> candidates;
        for (const MicroInstr& inst : storage.view())
        {
            if (inst.op == MicroInstrOpcode::JumpReg)
                return false;
        }

        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            if (it->op != MicroInstrOpcode::JumpCond)
                continue;
            const MicroInstrRef      jumpRef = it.current;
            const MicroInstrOperand* jumpOps = it->ops(operands);
            uint32_t                 joinId  = 0;
            if (!jumpOps || jumpOps[0].cpuCond == MicroCond::Unconditional || !tryGetJumpTargetLabelId(joinId, *it, jumpOps))
                continue;

            // Before the jump: the copy of A into B, then the setcc of the
            // flags the jump reads.
            const MicroInstrRef copyRef = storage.findPreviousInstructionRef(jumpRef);
            const MicroInstr*   copy    = copyRef.isValid() ? storage.ptr(copyRef) : nullptr;
            if (!copy || copy->op != MicroInstrOpcode::LoadRegReg)
                continue;
            const MicroInstrOperand* copyOps = copy->ops(operands);
            if (copyOps[2].opBits != MicroOpBits::B8 || !copyOps[0].reg.isVirtualInt())
                continue;
            const MicroInstrRef setRef = storage.findPreviousInstructionRef(copyRef);
            const MicroInstr*   set    = setRef.isValid() ? storage.ptr(setRef) : nullptr;
            if (!set || set->op != MicroInstrOpcode::SetCondReg || set->ops(operands)[0].reg != copyOps[1].reg)
                continue;

            const MicroCond leftCond = set->ops(operands)[1].cpuCond;
            MicroCond       inverted = MicroCond::Unconditional;
            if (!MicroPassHelpers::invertCondition(inverted, leftCond))
                continue;
            Candidate candidate;
            if (jumpOps[0].cpuCond == inverted)
                candidate.op = MicroOp::And;
            else if (jumpOps[0].cpuCond == leftCond)
                candidate.op = MicroOp::Or;
            else
                continue;
            candidate.jumpRef    = jumpRef;
            candidate.result     = copyOps[0].reg;
            candidate.leftCond   = leftCond;
            candidate.leftCmpRef = storage.findPreviousInstructionRef(setRef);

            // The skipped part: a register compare, its setcc, an optional
            // widening of that byte, the copy into B, then the join.
            MicroInstrRef     ref  = storage.findNextInstructionRef(jumpRef);
            const MicroInstr* inst = ref.isValid() ? storage.ptr(ref) : nullptr;
            if (inst && inst->op != MicroInstrOpcode::CmpRegReg && inst->op != MicroInstrOpcode::CmpRegImm)
            {
                // The one profitable pure RHS currently admitted here is the
                // canonical clear-lowest-bit test. Its two temporaries are
                // checked for outside mentions below before speculation.
                if (inst->op != MicroInstrOpcode::LoadRegReg)
                    continue;
                const MicroInstrOperand* decrementCopy = inst->ops(operands);
                if (!decrementCopy || (decrementCopy[2].opBits != MicroOpBits::B32 && decrementCopy[2].opBits != MicroOpBits::B64))
                    continue;
                const MicroOpBits bits   = decrementCopy[2].opBits;
                const MicroReg    source = decrementCopy[1].reg;
                candidate.skippedDecrement = decrementCopy[0].reg;

                ref  = storage.findNextInstructionRef(ref);
                inst = ref.isValid() ? storage.ptr(ref) : nullptr;
                const MicroInstrOperand* decrement = inst && inst->op == MicroInstrOpcode::OpBinaryRegImm ? inst->ops(operands) : nullptr;
                if (!decrement || decrement[0].reg != candidate.skippedDecrement || decrement[1].opBits != bits ||
                    decrement[2].microOp != MicroOp::Subtract || decrement[3].hasWideImmediateValue() || decrement[3].valueU64 != 1)
                    continue;

                ref  = storage.findNextInstructionRef(ref);
                inst = ref.isValid() ? storage.ptr(ref) : nullptr;
                const MicroInstrOperand* maskCopy = inst && inst->op == MicroInstrOpcode::LoadRegReg ? inst->ops(operands) : nullptr;
                if (!maskCopy || maskCopy[1].reg != source || maskCopy[2].opBits != bits)
                    continue;
                candidate.skippedMask = maskCopy[0].reg;

                ref  = storage.findNextInstructionRef(ref);
                inst = ref.isValid() ? storage.ptr(ref) : nullptr;
                const MicroInstrOperand* mask = inst && inst->op == MicroInstrOpcode::OpBinaryRegReg ? inst->ops(operands) : nullptr;
                if (!mask || mask[0].reg != candidate.skippedMask || mask[1].reg != candidate.skippedDecrement ||
                    mask[2].opBits != bits || mask[3].microOp != MicroOp::And)
                    continue;

                ref  = storage.findNextInstructionRef(ref);
                inst = ref.isValid() ? storage.ptr(ref) : nullptr;
                const MicroInstrOperand* compare = inst && inst->op == MicroInstrOpcode::CmpRegImm ? inst->ops(operands) : nullptr;
                if (!compare || compare[0].reg != candidate.skippedMask || compare[1].opBits != bits ||
                    compare[2].hasWideImmediateValue() || compare[2].valueU64 != 0)
                    continue;
            }
            if (!inst || (inst->op != MicroInstrOpcode::CmpRegReg && inst->op != MicroInstrOpcode::CmpRegImm))
                continue;
            const MicroInstrOperand* cmpOps = inst->ops(operands);
            if (cmpOps[0].reg == candidate.result || (inst->op == MicroInstrOpcode::CmpRegReg && cmpOps[1].reg == candidate.result))
                continue;
            candidate.rightCmpRef = ref;

            ref  = storage.findNextInstructionRef(ref);
            inst = ref.isValid() ? storage.ptr(ref) : nullptr;
            if (!inst || inst->op != MicroInstrOpcode::SetCondReg)
                continue;
            candidate.rhs         = inst->ops(operands)[0].reg;
            candidate.rightSetRef = ref;
            if (!candidate.rhs.isVirtualInt() || candidate.rhs == candidate.result)
                continue;

            ref  = storage.findNextInstructionRef(ref);
            inst = ref.isValid() ? storage.ptr(ref) : nullptr;
            if (inst && inst->op == MicroInstrOpcode::LoadZeroExtRegReg)
            {
                const MicroInstrOperand* extOps = inst->ops(operands);
                if (extOps[0].reg != candidate.rhs || extOps[1].reg != candidate.rhs)
                    continue;
                candidate.mentions += 2;
                ref  = storage.findNextInstructionRef(ref);
                inst = ref.isValid() ? storage.ptr(ref) : nullptr;
            }

            if (!inst || inst->op != MicroInstrOpcode::LoadRegReg)
                continue;
            const MicroInstrOperand* mergeOps = inst->ops(operands);
            if (mergeOps[0].reg != candidate.result || mergeOps[1].reg != candidate.rhs || mergeOps[2].opBits != MicroOpBits::B8)
                continue;
            candidate.mergeRef = ref;

            const MicroInstrRef labelRef = storage.findNextInstructionRef(ref);
            const MicroInstr*   label    = labelRef.isValid() ? storage.ptr(labelRef) : nullptr;
            uint32_t            labelId  = 0;
            if (!label || !tryGetLabelId(labelId, *label, label->ops(operands)) || labelId != joinId)
                continue;
            if (!MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*context.builder, candidate.mergeRef))
                continue;

            candidates.push_back(candidate);
        }

        if (candidates.empty())
            return false;

        // D is a byte the skipped part made for B alone: nothing else may read
        // it, or running that part on the other path would be observable.
        std::unordered_map<uint32_t, uint32_t> rhsMentions;
        std::unordered_map<uint32_t, uint32_t> skippedMentions;
        for (const Candidate& candidate : candidates)
        {
            rhsMentions[candidate.rhs.index()] = 0;
            if (candidate.skippedDecrement.isValid())
            {
                skippedMentions[candidate.skippedDecrement.index()] = 0;
                skippedMentions[candidate.skippedMask.index()]      = 0;
            }
        }
        SmallVector<MicroInstrRegOperandRef> regOperands;
        for (const MicroInstr& inst : storage.view())
        {
            regOperands.clear();
            inst.collectRegOperands(operands, regOperands, context.encoder);
            for (const MicroInstrRegOperandRef& regOperand : regOperands)
            {
                if (!regOperand.reg || !regOperand.reg->isVirtualInt())
                    continue;
                const auto found = rhsMentions.find(regOperand.reg->index());
                if (found != rhsMentions.end())
                    ++found->second;
                const auto skipped = skippedMentions.find(regOperand.reg->index());
                if (skipped != skippedMentions.end())
                    ++skipped->second;
            }
        }

        bool     changed                = false;
        uint32_t nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        for (const Candidate& candidate : candidates)
        {
            // The setcc, the optional self-widening and the merge only.
            if (rhsMentions[candidate.rhs.index()] != candidate.mentions)
                continue;
            if (candidate.skippedDecrement.isValid() &&
                (skippedMentions[candidate.skippedDecrement.index()] != 3 || skippedMentions[candidate.skippedMask.index()] != 3))
                continue;

            const RangeMerge range{.leftCmpRef = candidate.leftCmpRef, .rightCmpRef = candidate.rightCmpRef, .rightSetRef = candidate.rightSetRef, .leftCond = candidate.leftCond};
            if (candidate.op == MicroOp::And && tryFoldRangeMerge(storage, operands, range, nextVirtualIntRegIndex))
            {
                storage.erase(candidate.jumpRef);
                changed = true;
                continue;
            }

            MicroInstrOperand mergeOps[4];
            mergeOps[0].reg     = candidate.result;
            mergeOps[1].reg     = candidate.rhs;
            mergeOps[2].opBits  = MicroOpBits::B8;
            mergeOps[3].microOp = candidate.op;
            storage.insertDerivedBefore(operands, candidate.mergeRef, MicroInstrOpcode::OpBinaryRegReg, mergeOps);
            storage.erase(candidate.mergeRef);
            storage.erase(candidate.jumpRef);
            changed = true;
        }

        if (changed)
            context.builder->invalidateControlFlowGraph();
        return changed;
    }

    // The same range test once the short-circuit is already a byte AND: the
    // bounds were not yet immediates when the branch went away, so the fold
    // happens on the straight-line form.
    //
    //     cmp    X, LO                   cmp    X, LO           ; left for DCE
    //     setge  A                       setge  A
    //     B = A                          B = A
    //     cmp    X, HI             ->    T = X; T -= LO
    //     setle  D                       cmp    T, HI - LO
    //     [zext  D]                      setbe  D
    //     B &= D                         [zext D]
    //                                    B = D
    bool foldRangeAnds(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        if (!context.builder)
            return false;

        struct Candidate
        {
            MicroInstrRef andRef = MicroInstrRef::invalid();
            MicroReg      rhs;
            uint32_t      mentions = 2;
            RangeMerge    range;
        };

        const auto previous = [&storage](const MicroInstrRef ref) -> const MicroInstr* {
            return ref.isValid() ? storage.ptr(ref) : nullptr;
        };

        SmallVector<Candidate> candidates;
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            if (it->op != MicroInstrOpcode::OpBinaryRegReg)
                continue;
            const MicroInstrOperand* andOps = it->ops(operands);
            if (!andOps || andOps[3].microOp != MicroOp::And || andOps[2].opBits != MicroOpBits::B8)
                continue;

            Candidate candidate;
            candidate.andRef = it.current;
            candidate.rhs    = andOps[1].reg;
            const MicroReg result = andOps[0].reg;
            if (!candidate.rhs.isVirtualInt() || !result.isVirtualInt() || candidate.rhs == result)
                continue;

            MicroInstrRef     ref  = storage.findPreviousInstructionRef(it.current);
            const MicroInstr* inst = previous(ref);
            if (inst && inst->op == MicroInstrOpcode::LoadZeroExtRegReg)
            {
                const MicroInstrOperand* extOps = inst->ops(operands);
                if (extOps[0].reg != candidate.rhs || extOps[1].reg != candidate.rhs)
                    continue;
                candidate.mentions += 2;
                ref  = storage.findPreviousInstructionRef(ref);
                inst = previous(ref);
            }
            if (!inst || inst->op != MicroInstrOpcode::SetCondReg || inst->ops(operands)[0].reg != candidate.rhs)
                continue;
            candidate.range.rightSetRef = ref;

            ref  = storage.findPreviousInstructionRef(ref);
            inst = previous(ref);
            if (!inst || inst->op != MicroInstrOpcode::CmpRegImm)
                continue;
            candidate.range.rightCmpRef = ref;

            ref  = storage.findPreviousInstructionRef(ref);
            inst = previous(ref);
            if (!inst || inst->op != MicroInstrOpcode::LoadRegReg)
                continue;
            const MicroInstrOperand* copyOps = inst->ops(operands);
            if (copyOps[0].reg != result || copyOps[2].opBits != MicroOpBits::B8)
                continue;

            ref  = storage.findPreviousInstructionRef(ref);
            inst = previous(ref);
            if (!inst || inst->op != MicroInstrOpcode::SetCondReg || inst->ops(operands)[0].reg != copyOps[1].reg)
                continue;
            candidate.range.leftCond   = inst->ops(operands)[1].cpuCond;
            candidate.range.leftCmpRef = storage.findPreviousInstructionRef(ref);

            if (!MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*context.builder, candidate.andRef))
                continue;
            candidates.push_back(candidate);
        }

        if (candidates.empty())
            return false;

        std::unordered_map<uint32_t, uint32_t> rhsMentions;
        for (const Candidate& candidate : candidates)
            rhsMentions[candidate.rhs.index()] = 0;
        SmallVector<MicroInstrRegOperandRef> regOperands;
        for (const MicroInstr& inst : storage.view())
        {
            regOperands.clear();
            inst.collectRegOperands(operands, regOperands, context.encoder);
            for (const MicroInstrRegOperandRef& regOperand : regOperands)
            {
                if (!regOperand.reg || !regOperand.reg->isVirtualInt())
                    continue;
                const auto found = rhsMentions.find(regOperand.reg->index());
                if (found != rhsMentions.end())
                    ++found->second;
            }
        }

        bool     changed                = false;
        uint32_t nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        for (const Candidate& candidate : candidates)
        {
            if (rhsMentions[candidate.rhs.index()] != candidate.mentions)
                continue;
            if (!tryFoldRangeMerge(storage, operands, candidate.range, nextVirtualIntRegIndex))
                continue;

            MicroInstrOperand* andOps = storage.ptr(candidate.andRef)->ops(operands);
            MicroInstrOperand  copyOps[3];
            copyOps[0].reg    = andOps[0].reg;
            copyOps[1].reg    = candidate.rhs;
            copyOps[2].opBits = MicroOpBits::B8;
            storage.insertDerivedBefore(operands, candidate.andRef, MicroInstrOpcode::LoadRegReg, copyOps);
            storage.erase(candidate.andRef);
            changed = true;
        }

        if (changed)
            context.builder->invalidateControlFlowGraph();
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
            {
                const MicroInstrOperand* ops = inst.ops(operands);
                if (!ops || inst.numOperands < 2)
                    return false;
                for (uint8_t operandIndex = 1; operandIndex < inst.numOperands; ++operandIndex)
                    referencedLabels.insert(ops[operandIndex].valueU64);
                continue;
            }
            if (inst.op == MicroInstrOpcode::Label)
            {
                if (!relocInstrRefs.contains(it.current.get()))
                    labelRefs.push_back(it.current);
                continue;
            }
            if (inst.op == MicroInstrOpcode::LoadLabelAddress)
            {
                const MicroInstrOperand* ops = inst.ops(operands);
                if (!ops || inst.numOperands < 2)
                    return false;
                referencedLabels.insert(ops[1].valueU64);
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

    bool redirectJumpChains(MicroStorage& storage, MicroOperandStorage& operands, const ProgramLayout& layout)
    {
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

    bool eraseJumpsToImmediateLabels(MicroStorage& storage, MicroOperandStorage& operands, const ProgramLayout& layout)
    {
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
    bool invertJumpOverAdjacentJump(MicroStorage& storage, MicroOperandStorage& operands, const ProgramLayout& layout)
    {
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
            if (!MicroPassHelpers::invertCondition(inverted, condOps[0].cpuCond))
                continue;

            ++it;
            condOps[0].cpuCond  = inverted;
            condOps[2].valueU64 = jumpTarget;
            changed |= storage.erase(jumpRef);
        }

        return changed;
    }

    // Conditions the cmov encoder can express. Every condition
    // MicroPassHelpers::invertCondition can produce is encodable; this only fences off
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
        bool                    needsScratch = false;

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
            if (!MicroPassHelpers::invertCondition(inverted, jumpOps[0].cpuCond) || !conditionSupportsConditionalMove(inverted))
                continue;

            conversions.push_back({.jumpRef = it.current, .bodyRef = bodyRef, .labelRef = labelRef, .cond = inverted, .fromImm = fromImm});
            needsScratch = needsScratch || fromImm;
        }

        if (conversions.empty())
            return false;

        // Copies keep their existing registers. Mixed plans still reserve names
        // from the original instruction stream, before any conversion mutates it.
        uint32_t nextVirtualIntRegIndex = needsScratch ? MicroPassHelpers::computeNextVirtualIntRegIndex(context) : 0;

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
        MicroBuilder*                         builder  = nullptr;
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
            if (MicroPassHelpers::instructionActuallyDefinesCpuFlags(*inst, ops))
            {
                arm.definesFlags  = true;
                definedFlagsSoFar |= MicroPassHelpers::instructionOverwritesCpuFlags(*inst, ops);
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
        return MicroPassHelpers::areCpuFlagsDeadAfter(*scan.storage, *scan.operands, diamond.joinLabelRef, scan.builder);
    }

    // The label reference counts and the relocated instructions every
    // if-conversion consults. False when a computed jump makes the counts
    // meaningless.
    bool prepareDiamondScan(DiamondScan& scan, MicroStorage& storage, MicroOperandStorage& operands, const MicroPassContext& context)
    {
        scan.storage  = &storage;
        scan.operands = &operands;
        scan.builder  = context.builder;

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

        return true;
    }

    // The compared value is already available in a register before the
    // branch, so an arm that reloads the exact same cell can reuse it. This
    // exposes an ordinary two-copy diamond to the generic if-converter:
    //
    //     left  = [left address]          left  = [left address]
    //     right = [right address]         right = [right address]
    //     cmp left, right                 cmp left, right
    //     jcc .Lright                     jcc .Lright
    //     result = left                   result = left
    //     jmp .Ljoin                      jmp .Ljoin
    //   .Lright:                        .Lright:
    //     result = [right address]   ->    result = right
    //   .Ljoin:                         .Ljoin:
    //
    // The source load must immediately feed the comparison, and no write or
    // call may occur before the reload. Keeping these constraints local makes
    // the memory equivalence independent of alias analysis.
    bool forwardComparedLoadIntoDiamondArm(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        DiamondScan scan;
        if (!prepareDiamondScan(scan, storage, operands, context))
            return false;

        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstrRef cmpRef = it.current;
            const MicroInstr&   cmp    = *it;
            if (cmp.op != MicroInstrOpcode::CmpRegReg || scan.relocated.contains(cmpRef.get()))
                continue;
            const MicroInstrOperand* cmpOps = cmp.ops(operands);
            if (!cmpOps || (cmpOps[2].opBits != MicroOpBits::B32 && cmpOps[2].opBits != MicroOpBits::B64) ||
                !cmpOps[0].reg.isVirtualInt() || !cmpOps[1].reg.isVirtualInt())
                continue;

            const MicroInstrRef sourceLoadRef = storage.findPreviousInstructionRef(cmpRef);
            const MicroInstr*   sourceLoad    = storage.ptr(sourceLoadRef);
            const auto*         sourceLoadOps = sourceLoad ? sourceLoad->ops(operands) : nullptr;
            if (!sourceLoad || sourceLoad->op != MicroInstrOpcode::LoadAmcRegMem || !sourceLoadOps ||
                scan.relocated.contains(sourceLoadRef.get()) || sourceLoadOps[0].reg != cmpOps[1].reg ||
                sourceLoadOps[3].opBits != cmpOps[2].opBits)
                continue;

            const MicroInstrRef jumpRef = storage.findNextInstructionRef(cmpRef);
            const MicroInstr*   jump    = storage.ptr(jumpRef);
            const auto*         jumpOps = jump ? jump->ops(operands) : nullptr;
            if (!jump || jump->op != MicroInstrOpcode::JumpCond || !jumpOps ||
                jumpOps[0].cpuCond == MicroCond::Unconditional || !conditionSupportsConditionalMove(jumpOps[0].cpuCond) ||
                scan.relocated.contains(jumpRef.get()))
                continue;

            const MicroInstrRef fallthroughRef = storage.findNextInstructionRef(jumpRef);
            const MicroInstr*   fallthrough    = storage.ptr(fallthroughRef);
            const auto*         fallthroughOps = fallthrough ? fallthrough->ops(operands) : nullptr;
            if (!fallthrough || fallthrough->op != MicroInstrOpcode::LoadRegReg || !fallthroughOps ||
                fallthroughOps[1].reg != cmpOps[0].reg || fallthroughOps[2].opBits != cmpOps[2].opBits ||
                scan.relocated.contains(fallthroughRef.get()))
                continue;

            const MicroInstrRef joinJumpRef = storage.findNextInstructionRef(fallthroughRef);
            const MicroInstr*   joinJump    = storage.ptr(joinJumpRef);
            const auto*         joinJumpOps = joinJump ? joinJump->ops(operands) : nullptr;
            if (!joinJump || joinJump->op != MicroInstrOpcode::JumpCond || !joinJumpOps ||
                joinJumpOps[0].cpuCond != MicroCond::Unconditional || scan.relocated.contains(joinJumpRef.get()))
                continue;

            uint32_t armLabelId  = 0;
            uint32_t joinLabelId = 0;
            if (!tryGetJumpTargetLabelId(armLabelId, *jump, jumpOps) ||
                !tryGetJumpTargetLabelId(joinLabelId, *joinJump, joinJumpOps) || armLabelId == joinLabelId)
                continue;
            const auto armReferences = scan.labelReferences.find(armLabelId);
            if (armReferences == scan.labelReferences.end() || armReferences->second != 1)
                continue;

            const MicroInstrRef armLabelRef = storage.findNextInstructionRef(joinJumpRef);
            const MicroInstr*   armLabel    = storage.ptr(armLabelRef);
            uint32_t            foundLabelId = 0;
            if (!armLabel || scan.relocated.contains(armLabelRef.get()) ||
                !tryGetLabelId(foundLabelId, *armLabel, armLabel->ops(operands)) || foundLabelId != armLabelId)
                continue;

            const MicroInstrRef reloadRef = storage.findNextInstructionRef(armLabelRef);
            const MicroInstr*   reload    = storage.ptr(reloadRef);
            const auto*         reloadOps = reload ? reload->ops(operands) : nullptr;
            if (!reload || reload->op != MicroInstrOpcode::LoadAmcRegMem || !reloadOps ||
                scan.relocated.contains(reloadRef.get()) || reloadOps[0].reg != fallthroughOps[0].reg ||
                reloadOps[1].reg != sourceLoadOps[1].reg || reloadOps[2].reg != sourceLoadOps[2].reg ||
                reloadOps[3].opBits != sourceLoadOps[3].opBits || reloadOps[4].opBits != sourceLoadOps[4].opBits ||
                reloadOps[5].valueU64 != sourceLoadOps[5].valueU64 || reloadOps[6].valueU64 != sourceLoadOps[6].valueU64)
                continue;

            const MicroInstrRef joinLabelRef = storage.findNextInstructionRef(reloadRef);
            const MicroInstr*   joinLabel    = storage.ptr(joinLabelRef);
            if (!joinLabel || !tryGetLabelId(foundLabelId, *joinLabel, joinLabel->ops(operands)) || foundLabelId != joinLabelId)
                continue;

            bool safe = true;
            for (MicroInstrRef ref = storage.findNextInstructionRef(sourceLoadRef); ref.isValid() && ref != reloadRef; ref = storage.findNextInstructionRef(ref))
            {
                const MicroInstr*        between = storage.ptr(ref);
                const MicroInstrDef&     info    = MicroInstr::info(between->op);
                const MicroInstrUseDef   useDef  = between->collectUseDef(operands, context.encoder);
                if (info.flags.has(MicroInstrFlagsE::WritesMemory) || useDef.isCall ||
                    std::ranges::find(useDef.defs, sourceLoadOps[1].reg) != useDef.defs.end() ||
                    std::ranges::find(useDef.defs, sourceLoadOps[2].reg) != useDef.defs.end())
                {
                    safe = false;
                    break;
                }
            }
            if (!safe)
                continue;

            MicroInstrOperand copyOps[3] = {};
            copyOps[0]                   = reloadOps[0];
            copyOps[1].reg               = cmpOps[1].reg;
            copyOps[2]                   = reloadOps[3];
            storage.insertDerivedBefore(operands, reloadRef, MicroInstrOpcode::LoadRegReg, copyOps);
            storage.erase(reloadRef);
            return true;
        }

        return false;
    }

    // Both subtraction arms of an absolute difference reload the values that
    // fed the comparison. Compute both register differences in straight-line
    // code, with the forward subtraction last so its flags also select the
    // result:
    //
    //     cmp left, right                  reverse = right
    //     jbe .Lreverse                    reverse -= left
    //     result = left - [right]   ->     result = left
    //     jmp .Ljoin                       result -= right
    //   .Lreverse:                         cmovbe result, reverse
    //     result = [right] - [left]
    //   .Ljoin:
    bool convertComparedLoadsSubtractDiamond(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        DiamondScan scan;
        if (!prepareDiamondScan(scan, storage, operands, context))
            return false;

        const auto sameAddress = [](const MicroInstrOperand* loadOps, const MicroInstrOperand* memoryOps) {
            return loadOps[1].reg == memoryOps[1].reg && loadOps[2].reg == memoryOps[2].reg &&
                   loadOps[3].opBits == memoryOps[3].opBits && loadOps[4].opBits == memoryOps[4].opBits &&
                   loadOps[5].valueU64 == memoryOps[5].valueU64 && loadOps[6].valueU64 == memoryOps[6].valueU64;
        };

        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstrRef cmpRef = it.current;
            const MicroInstr&   cmp    = *it;
            if (cmp.op != MicroInstrOpcode::CmpRegReg || scan.relocated.contains(cmpRef.get()))
                continue;
            const MicroInstrOperand* cmpOps = cmp.ops(operands);
            if (!cmpOps || (cmpOps[2].opBits != MicroOpBits::B32 && cmpOps[2].opBits != MicroOpBits::B64))
                continue;

            const MicroInstrRef rightSourceRef = storage.findPreviousInstructionRef(cmpRef);
            const MicroInstr*   rightSource    = storage.ptr(rightSourceRef);
            const auto*         rightSourceOps = rightSource ? rightSource->ops(operands) : nullptr;
            const MicroInstrRef leftSourceRef  = storage.findPreviousInstructionRef(rightSourceRef);
            const MicroInstr*   leftSource     = storage.ptr(leftSourceRef);
            const auto*         leftSourceOps  = leftSource ? leftSource->ops(operands) : nullptr;
            if (!rightSource || rightSource->op != MicroInstrOpcode::LoadAmcRegMem || !rightSourceOps ||
                !leftSource || leftSource->op != MicroInstrOpcode::LoadAmcRegMem || !leftSourceOps ||
                rightSourceOps[0].reg != cmpOps[1].reg || leftSourceOps[0].reg != cmpOps[0].reg ||
                rightSourceOps[3].opBits != cmpOps[2].opBits || leftSourceOps[3].opBits != cmpOps[2].opBits ||
                scan.relocated.contains(rightSourceRef.get()) || scan.relocated.contains(leftSourceRef.get()))
                continue;

            const MicroInstrRef jumpRef = storage.findNextInstructionRef(cmpRef);
            const MicroInstr*   jump    = storage.ptr(jumpRef);
            const auto*         jumpOps = jump ? jump->ops(operands) : nullptr;
            if (!jump || jump->op != MicroInstrOpcode::JumpCond || !jumpOps ||
                jumpOps[0].cpuCond == MicroCond::Unconditional || !conditionSupportsConditionalMove(jumpOps[0].cpuCond) ||
                scan.relocated.contains(jumpRef.get()))
                continue;

            const MicroInstrRef forwardCopyRef = storage.findNextInstructionRef(jumpRef);
            const MicroInstr*   forwardCopy    = storage.ptr(forwardCopyRef);
            const auto*         forwardCopyOps = forwardCopy ? forwardCopy->ops(operands) : nullptr;
            const MicroInstrRef forwardSubRef  = storage.findNextInstructionRef(forwardCopyRef);
            const MicroInstr*   forwardSub     = storage.ptr(forwardSubRef);
            const auto*         forwardSubOps  = forwardSub ? forwardSub->ops(operands) : nullptr;
            const MicroInstrRef forwardResultRef = storage.findNextInstructionRef(forwardSubRef);
            const MicroInstr*   forwardResult    = storage.ptr(forwardResultRef);
            const auto*         forwardResultOps = forwardResult ? forwardResult->ops(operands) : nullptr;
            if (!forwardCopy || forwardCopy->op != MicroInstrOpcode::LoadRegReg || !forwardCopyOps ||
                forwardCopyOps[1].reg != cmpOps[0].reg || forwardCopyOps[2].opBits != cmpOps[2].opBits ||
                !forwardSub || forwardSub->op != MicroInstrOpcode::OpBinaryRegAmcMem || !forwardSubOps ||
                forwardSubOps[0].reg != forwardCopyOps[0].reg || forwardSubOps[7].microOp != MicroOp::Subtract ||
                !sameAddress(rightSourceOps, forwardSubOps) ||
                !forwardResult || forwardResult->op != MicroInstrOpcode::LoadRegReg || !forwardResultOps ||
                forwardResultOps[1].reg != forwardCopyOps[0].reg || forwardResultOps[2].opBits != cmpOps[2].opBits)
                continue;

            const MicroInstrRef joinJumpRef = storage.findNextInstructionRef(forwardResultRef);
            const MicroInstr*   joinJump    = storage.ptr(joinJumpRef);
            const auto*         joinJumpOps = joinJump ? joinJump->ops(operands) : nullptr;
            if (!joinJump || joinJump->op != MicroInstrOpcode::JumpCond || !joinJumpOps ||
                joinJumpOps[0].cpuCond != MicroCond::Unconditional || scan.relocated.contains(joinJumpRef.get()))
                continue;

            uint32_t armLabelId  = 0;
            uint32_t joinLabelId = 0;
            if (!tryGetJumpTargetLabelId(armLabelId, *jump, jumpOps) ||
                !tryGetJumpTargetLabelId(joinLabelId, *joinJump, joinJumpOps) || armLabelId == joinLabelId)
                continue;
            const auto armReferences = scan.labelReferences.find(armLabelId);
            if (armReferences == scan.labelReferences.end() || armReferences->second != 1)
                continue;

            const MicroInstrRef armLabelRef = storage.findNextInstructionRef(joinJumpRef);
            const MicroInstr*   armLabel    = storage.ptr(armLabelRef);
            uint32_t            foundLabelId = 0;
            if (!armLabel || !tryGetLabelId(foundLabelId, *armLabel, armLabel->ops(operands)) || foundLabelId != armLabelId)
                continue;

            const MicroInstrRef reverseLoadRef = storage.findNextInstructionRef(armLabelRef);
            const MicroInstr*   reverseLoad    = storage.ptr(reverseLoadRef);
            const auto*         reverseLoadOps = reverseLoad ? reverseLoad->ops(operands) : nullptr;
            const MicroInstrRef reverseSubRef  = storage.findNextInstructionRef(reverseLoadRef);
            const MicroInstr*   reverseSub     = storage.ptr(reverseSubRef);
            const auto*         reverseSubOps  = reverseSub ? reverseSub->ops(operands) : nullptr;
            const MicroInstrRef reverseResultRef = storage.findNextInstructionRef(reverseSubRef);
            const MicroInstr*   reverseResult    = storage.ptr(reverseResultRef);
            const auto*         reverseResultOps = reverseResult ? reverseResult->ops(operands) : nullptr;
            if (!reverseLoad || reverseLoad->op != MicroInstrOpcode::LoadAmcRegMem || !reverseLoadOps ||
                !sameAddress(rightSourceOps, reverseLoadOps) ||
                !reverseSub || reverseSub->op != MicroInstrOpcode::OpBinaryRegAmcMem || !reverseSubOps ||
                reverseSubOps[0].reg != reverseLoadOps[0].reg || reverseSubOps[7].microOp != MicroOp::Subtract ||
                !sameAddress(leftSourceOps, reverseSubOps) ||
                !reverseResult || reverseResult->op != MicroInstrOpcode::LoadRegReg || !reverseResultOps ||
                reverseResultOps[0].reg != forwardResultOps[0].reg || reverseResultOps[1].reg != reverseLoadOps[0].reg ||
                reverseResultOps[2].opBits != cmpOps[2].opBits)
                continue;

            const MicroInstrRef joinLabelRef = storage.findNextInstructionRef(reverseResultRef);
            const MicroInstr*   joinLabel    = storage.ptr(joinLabelRef);
            if (!joinLabel || !tryGetLabelId(foundLabelId, *joinLabel, joinLabel->ops(operands)) || foundLabelId != joinLabelId)
                continue;

            MicroInstrOperand reverseCopyOps[3];
            reverseCopyOps[0]       = reverseLoadOps[0];
            reverseCopyOps[1].reg   = cmpOps[1].reg;
            reverseCopyOps[2]       = cmpOps[2];
            MicroInstrOperand reverseRegOps[4];
            reverseRegOps[0]         = reverseSubOps[0];
            reverseRegOps[1].reg     = cmpOps[0].reg;
            reverseRegOps[2]         = cmpOps[2];
            reverseRegOps[3].microOp = MicroOp::Subtract;
            MicroInstrOperand resultCopyOps[3];
            resultCopyOps[0]       = forwardResultOps[0];
            resultCopyOps[1].reg   = cmpOps[0].reg;
            resultCopyOps[2]       = cmpOps[2];
            MicroInstrOperand resultSubOps[4];
            resultSubOps[0]         = forwardResultOps[0];
            resultSubOps[1].reg     = cmpOps[1].reg;
            resultSubOps[2]         = cmpOps[2];
            resultSubOps[3].microOp = MicroOp::Subtract;
            MicroInstrOperand selectOps[4];
            selectOps[0]         = forwardResultOps[0];
            selectOps[1]         = reverseLoadOps[0];
            selectOps[2]         = jumpOps[0];
            selectOps[3]         = cmpOps[2];

            storage.insertDerivedBefore(operands, cmpRef, MicroInstrOpcode::LoadRegReg, reverseCopyOps);
            storage.insertDerivedBefore(operands, cmpRef, MicroInstrOpcode::OpBinaryRegReg, reverseRegOps);
            storage.insertDerivedBefore(operands, cmpRef, MicroInstrOpcode::LoadRegReg, resultCopyOps);
            storage.insertDerivedBefore(operands, cmpRef, MicroInstrOpcode::OpBinaryRegReg, resultSubOps);
            storage.insertDerivedBefore(operands, cmpRef, MicroInstrOpcode::LoadCondRegReg, selectOps);
            storage.erase(cmpRef);
            storage.erase(jumpRef);
            storage.erase(forwardCopyRef);
            storage.erase(forwardSubRef);
            storage.erase(forwardResultRef);
            storage.erase(joinJumpRef);
            storage.erase(armLabelRef);
            storage.erase(reverseLoadRef);
            storage.erase(reverseSubRef);
            storage.erase(reverseResultRef);
            return true;
        }

        return false;
    }

    // A comparison already reads this exact cell on every path, so reusing a
    // register load for the arm cannot introduce a fault:
    //
    //     cmp [base+index*scale], imm      result = [base+index*scale]
    //     jcc .Lload                 ->    cmp result, imm
    //     result = fallback                cmov!cc result, fallback
    //     jmp .Ljoin
    //   .Lload:
    //     result = [base+index*scale]
    //   .Ljoin:
    //
    // This is the common `cell == 0 ? fallback : cell` shape. General diamond
    // conversion deliberately cannot speculate loads, while this one is safe
    // because the preceding memory compare performed the same access.
    bool convertComparedLoadDiamond(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        DiamondScan scan;
        if (!prepareDiamondScan(scan, storage, operands, context))
            return false;

        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstrRef cmpRef = it.current;
            const MicroInstr&   cmp    = *it;
            if (cmp.op != MicroInstrOpcode::CmpAmcImm || scan.relocated.contains(cmpRef.get()))
                continue;
            const MicroInstrOperand* cmpOps = cmp.ops(operands);
            if (!cmpOps)
                continue;

            const MicroInstrRef jumpRef = storage.findNextInstructionRef(cmpRef);
            const MicroInstr*   jump    = storage.ptr(jumpRef);
            const auto*         jumpOps = jump ? jump->ops(operands) : nullptr;
            if (!jump || jump->op != MicroInstrOpcode::JumpCond || !jumpOps ||
                jumpOps[0].cpuCond == MicroCond::Unconditional || !conditionSupportsConditionalMove(jumpOps[0].cpuCond) ||
                scan.relocated.contains(jumpRef.get()))
                continue;

            const MicroInstrRef fallthroughRef = storage.findNextInstructionRef(jumpRef);
            const MicroInstr*   fallthrough    = storage.ptr(fallthroughRef);
            const auto*         fallthroughOps = fallthrough ? fallthrough->ops(operands) : nullptr;
            const bool hasFallbackCopy = fallthrough && fallthrough->op == MicroInstrOpcode::LoadRegReg &&
                                         fallthroughOps && !scan.relocated.contains(fallthroughRef.get());
            const bool hasFallbackImmediate = fallthrough && fallthrough->op == MicroInstrOpcode::LoadRegImm &&
                                              fallthroughOps && !scan.relocated.contains(fallthroughRef.get());
            if (!hasFallbackCopy && !hasFallbackImmediate)
                continue;
            const MicroInstrRef joinJumpRef = storage.findNextInstructionRef(fallthroughRef);
            const MicroInstr*   joinJump    = storage.ptr(joinJumpRef);
            const auto*         joinJumpOps = joinJump ? joinJump->ops(operands) : nullptr;
            if (!joinJump || joinJump->op != MicroInstrOpcode::JumpCond || !joinJumpOps ||
                joinJumpOps[0].cpuCond != MicroCond::Unconditional || scan.relocated.contains(joinJumpRef.get()))
                continue;

            uint32_t armLabelId  = 0;
            uint32_t joinLabelId = 0;
            if (!tryGetJumpTargetLabelId(armLabelId, *jump, jumpOps) ||
                !tryGetJumpTargetLabelId(joinLabelId, *joinJump, joinJumpOps) || armLabelId == joinLabelId)
                continue;
            const auto armReferences = scan.labelReferences.find(armLabelId);
            if (armReferences == scan.labelReferences.end() || armReferences->second != 1)
                continue;

            const MicroInstrRef armLabelRef = storage.findNextInstructionRef(joinJumpRef);
            const MicroInstr*   armLabel    = storage.ptr(armLabelRef);
            uint32_t            foundLabelId = 0;
            if (!armLabel || scan.relocated.contains(armLabelRef.get()) ||
                !tryGetLabelId(foundLabelId, *armLabel, armLabel->ops(operands)) || foundLabelId != armLabelId)
                continue;

            const MicroInstrRef loadRef = storage.findNextInstructionRef(armLabelRef);
            const MicroInstr*   load    = storage.ptr(loadRef);
            const auto*         loadOps = load ? load->ops(operands) : nullptr;
            if (!load || load->op != MicroInstrOpcode::LoadAmcRegMem || !loadOps || scan.relocated.contains(loadRef.get()) ||
                loadOps[1].reg != cmpOps[0].reg || loadOps[2].reg != cmpOps[1].reg ||
                loadOps[3].opBits != cmpOps[2].opBits || loadOps[4].opBits != cmpOps[3].opBits ||
                loadOps[5].valueU64 != cmpOps[4].valueU64 || loadOps[6].valueU64 != cmpOps[5].valueU64)
                continue;
            const MicroOpBits fallbackBits = hasFallbackCopy ? fallthroughOps[2].opBits : fallthroughOps[1].opBits;
            if (fallthroughOps[0].reg != loadOps[0].reg || fallbackBits != loadOps[3].opBits)
                continue;

            const MicroInstrRef joinLabelRef = storage.findNextInstructionRef(loadRef);
            const MicroInstr*   joinLabel    = storage.ptr(joinLabelRef);
            if (!joinLabel || !tryGetLabelId(foundLabelId, *joinLabel, joinLabel->ops(operands)) || foundLabelId != joinLabelId)
                continue;

            MicroCond fallbackCond;
            if (!MicroPassHelpers::invertCondition(fallbackCond, jumpOps[0].cpuCond) || !conditionSupportsConditionalMove(fallbackCond))
                continue;

            const MicroReg result = loadOps[0].reg;
            const MicroReg loaded = result;
            const MicroReg fallback = hasFallbackCopy ? fallthroughOps[1].reg :
                                                       MicroReg::virtualIntReg(MicroPassHelpers::computeNextVirtualIntRegIndex(context));

            MicroInstrOperand loadBefore[7];
            loadBefore[0].reg = loaded;
            for (uint32_t i = 1; i < 7; ++i)
                loadBefore[i] = loadOps[i];

            MicroInstrOperand regCmp[3];
            regCmp[0].reg      = loaded;
            regCmp[1]          = cmpOps[2];
            regCmp[2]          = cmpOps[6];

            MicroInstrOperand immediateOps[3];
            if (hasFallbackImmediate)
            {
                immediateOps[0].reg = fallback;
                immediateOps[1]     = fallthroughOps[1];
                immediateOps[2]     = fallthroughOps[2];
            }

            MicroInstrOperand selectOps[4];
            selectOps[0].reg     = result;
            selectOps[1].reg     = fallback;
            selectOps[2].cpuCond = fallbackCond;
            selectOps[3].opBits  = loadOps[3].opBits;

            storage.insertDerivedBefore(operands, cmpRef, MicroInstrOpcode::LoadAmcRegMem, loadBefore);
            storage.insertDerivedBefore(operands, cmpRef, MicroInstrOpcode::CmpRegImm, regCmp);
            if (hasFallbackImmediate)
                storage.insertDerivedBefore(operands, joinLabelRef, MicroInstrOpcode::LoadRegImm, immediateOps);
            storage.insertDerivedBefore(operands, joinLabelRef, MicroInstrOpcode::LoadCondRegReg, selectOps);

            storage.erase(cmpRef);
            storage.erase(jumpRef);
            storage.erase(fallthroughRef);
            storage.erase(joinJumpRef);
            storage.erase(armLabelRef);
            storage.erase(loadRef);
            return true;
        }
        return false;
    }

    // Select one of two adjacent cells through an index, so exactly the chosen
    // address is read without retaining the diamond's two loads and jumps.
    bool convertAdjacentLoadDiamond(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        DiamondScan scan;
        if (!prepareDiamondScan(scan, storage, operands, context))
            return false;

        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstr& jumpInst = *it;
            if (jumpInst.op != MicroInstrOpcode::JumpCond || scan.relocated.contains(it.current.get()))
                continue;
            const MicroInstrOperand* jumpOps = jumpInst.ops(operands);
            if (!jumpOps || jumpOps[0].cpuCond == MicroCond::Unconditional)
                continue;

            const MicroInstrRef flagsRef = storage.findPreviousInstructionRef(it.current);
            const MicroInstr*   flags    = flagsRef.isValid() ? storage.ptr(flagsRef) : nullptr;
            if (!flags || scan.relocated.contains(flagsRef.get()) || !MicroPassHelpers::instructionActuallyDefinesCpuFlags(*flags, flags->ops(operands)))
                continue;

            const MicroInstrRef firstLoadRef = storage.findNextInstructionRef(it.current);
            const MicroInstr*   firstLoad    = storage.ptr(firstLoadRef);
            if (!firstLoad || (firstLoad->op != MicroInstrOpcode::LoadRegMem && firstLoad->op != MicroInstrOpcode::LoadAmcRegMem) || scan.relocated.contains(firstLoadRef.get()))
                continue;
            const MicroInstrOperand* firstOps = firstLoad->ops(operands);

            const MicroInstrRef joinJumpRef = storage.findNextInstructionRef(firstLoadRef);
            const MicroInstr*   joinJump    = storage.ptr(joinJumpRef);
            const auto*         joinJumpOps = joinJump ? joinJump->ops(operands) : nullptr;
            if (!joinJump || joinJump->op != MicroInstrOpcode::JumpCond || !joinJumpOps || joinJumpOps[0].cpuCond != MicroCond::Unconditional || scan.relocated.contains(joinJumpRef.get()))
                continue;

            uint32_t armLabelId = 0;
            uint32_t joinLabelId = 0;
            if (!tryGetJumpTargetLabelId(armLabelId, jumpInst, jumpOps) || !tryGetJumpTargetLabelId(joinLabelId, *joinJump, joinJumpOps) || armLabelId == joinLabelId)
                continue;
            const auto armReferences = scan.labelReferences.find(armLabelId);
            if (armReferences == scan.labelReferences.end() || armReferences->second != 1)
                continue;

            const MicroInstrRef armLabelRef = storage.findNextInstructionRef(joinJumpRef);
            const MicroInstr*   armLabel    = storage.ptr(armLabelRef);
            uint32_t            foundLabelId = 0;
            if (!armLabel || scan.relocated.contains(armLabelRef.get()) || !tryGetLabelId(foundLabelId, *armLabel, armLabel->ops(operands)) || foundLabelId != armLabelId)
                continue;

            const MicroInstrRef secondLoadRef = storage.findNextInstructionRef(armLabelRef);
            const MicroInstr*   secondLoad    = storage.ptr(secondLoadRef);
            if (!secondLoad || secondLoad->op != firstLoad->op || scan.relocated.contains(secondLoadRef.get()))
                continue;
            const MicroInstrOperand* secondOps = secondLoad->ops(operands);

            const MicroInstrRef joinLabelRef = storage.findNextInstructionRef(secondLoadRef);
            const MicroInstr*   joinLabel    = storage.ptr(joinLabelRef);
            if (!joinLabel || !tryGetLabelId(foundLabelId, *joinLabel, joinLabel->ops(operands)) || foundLabelId != joinLabelId)
                continue;

            uint32_t selectedOperand = UINT32_MAX;
            if (firstOps && secondOps && firstOps[0].reg == secondOps[0].reg)
            {
                if (firstLoad->op == MicroInstrOpcode::LoadRegMem && firstOps[2].opBits == secondOps[2].opBits &&
                    firstOps[3].valueU64 == secondOps[3].valueU64 && firstOps[1].reg != secondOps[1].reg &&
                    firstOps[1].reg.isVirtualInt() && secondOps[1].reg.isVirtualInt())
                    selectedOperand = 1;
                else if (firstLoad->op == MicroInstrOpcode::LoadAmcRegMem && firstOps[1].reg == secondOps[1].reg &&
                         firstOps[3].opBits == secondOps[3].opBits && firstOps[4].opBits == secondOps[4].opBits &&
                         firstOps[5].valueU64 == secondOps[5].valueU64 && firstOps[6].valueU64 == secondOps[6].valueU64 &&
                         firstOps[2].reg != secondOps[2].reg && firstOps[2].reg.isVirtualInt() && secondOps[2].reg.isVirtualInt())
                    selectedOperand = 2;
            }

            if (selectedOperand != UINT32_MAX)
            {
                const MicroInstrOpcode loadOp      = firstLoad->op;
                const uint32_t         numOperands = firstLoad->numOperands;
                const MicroReg         firstSource  = firstOps[selectedOperand].reg;
                const MicroReg         secondSource = secondOps[selectedOperand].reg;
                MicroInstrOperand      selectedLoad[8];
                std::copy_n(firstOps, numOperands, selectedLoad);
                const MicroReg selected = MicroReg::virtualIntReg(MicroPassHelpers::computeNextVirtualIntRegIndex(context));

                MicroInstrOperand copyOps[3];
                copyOps[0].reg    = selected;
                copyOps[1].reg    = firstSource;
                copyOps[2].opBits = MicroOpBits::B64;
                storage.insertDerivedBefore(operands, flagsRef, MicroInstrOpcode::LoadRegReg, copyOps);

                MicroInstrOperand selectOps[4];
                selectOps[0].reg     = selected;
                selectOps[1].reg     = secondSource;
                selectOps[2].cpuCond = jumpOps[0].cpuCond;
                selectOps[3].opBits  = MicroOpBits::B64;
                storage.insertDerivedBefore(operands, it.current, MicroInstrOpcode::LoadCondRegReg, selectOps);

                selectedLoad[selectedOperand].reg = selected;
                storage.insertDerivedBefore(operands, firstLoadRef, loadOp, std::span<const MicroInstrOperand>(selectedLoad, numOperands));

                storage.erase(it.current);
                storage.erase(firstLoadRef);
                storage.erase(joinJumpRef);
                storage.erase(armLabelRef);
                storage.erase(secondLoadRef);
                return true;
            }

            if (firstLoad->op != MicroInstrOpcode::LoadRegMem)
                continue;

            if (!firstOps || !secondOps || firstOps[0].reg != secondOps[0].reg || firstOps[1].reg != secondOps[1].reg || firstOps[2].opBits != secondOps[2].opBits)
                continue;
            const MicroReg    resultReg  = firstOps[0].reg;
            const MicroReg    baseReg    = firstOps[1].reg;
            const MicroOpBits loadBits   = firstOps[2].opBits;
            const uint32_t    cellBits   = getNumBits(firstOps[2].opBits);
            const uint64_t    cellBytes  = cellBits / 8;
            if (!cellBytes || cellBytes > 8 || cellBits % 8)
                continue;
            const uint64_t firstOffset  = firstOps[3].valueU64;
            const uint64_t secondOffset = secondOps[3].valueU64;
            const uint64_t lowOffset    = std::min(firstOffset, secondOffset);
            const uint64_t highOffset   = std::max(firstOffset, secondOffset);
            if (highOffset - lowOffset != cellBytes)
                continue;

            MicroCond indexCond = jumpOps[0].cpuCond;
            if (secondOffset != highOffset)
            {
                MicroCond inverted;
                if (!MicroPassHelpers::invertCondition(inverted, indexCond))
                    continue;
                indexCond = inverted;
            }

            const MicroReg indexReg = MicroReg::virtualIntReg(MicroPassHelpers::computeNextVirtualIntRegIndex(context));
            MicroInstrOperand setOps[2];
            setOps[0].reg     = indexReg;
            setOps[1].cpuCond = indexCond;
            storage.insertDerivedBefore(operands, it.current, MicroInstrOpcode::SetCondReg, setOps);

            MicroInstrOperand extendOps[4];
            extendOps[0].reg    = indexReg;
            extendOps[1].reg    = indexReg;
            extendOps[2].opBits = MicroOpBits::B64;
            extendOps[3].opBits = MicroOpBits::B8;
            storage.insertDerivedBefore(operands, firstLoadRef, MicroInstrOpcode::LoadZeroExtRegReg, extendOps);

            MicroInstrOperand loadOps[8];
            loadOps[0].reg      = resultReg;
            loadOps[1].reg      = baseReg;
            loadOps[2].reg      = indexReg;
            loadOps[3].opBits   = loadBits;
            loadOps[4].opBits   = MicroOpBits::B64;
            loadOps[5].valueU64 = cellBytes;
            loadOps[6].valueU64 = lowOffset;
            storage.insertDerivedBefore(operands, firstLoadRef, MicroInstrOpcode::LoadAmcRegMem, loadOps);

            storage.erase(it.current);
            storage.erase(firstLoadRef);
            storage.erase(joinJumpRef);
            storage.erase(armLabelRef);
            storage.erase(secondLoadRef);
            return true;
        }
        return false;
    }

    bool convertDiamondsToConditionalMoves(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context, MicroSsaState& localSsaState)
    {
        DiamondScan scan;
        if (!prepareDiamondScan(scan, storage, operands, context))
            return false;

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

    // Speculative if-conversion of a triangle whose arm is more than one move:
    //
    //     cmp   X, Y                    cmp   X, Y
    //     jcc   CC, .Ljoin              D' = D
    //     A...  (defines D)       ->    A'...               ; every D in A renamed D'
    //   .Ljoin:                         [cmp X, Y]          ; re-issued when A wrote the flags
    //                                   cmov(~CC) D, D'
    //                                 .Ljoin:
    //
    // `if a[i] > k do c += 1` lowers to this shape. LLVM speculates such a
    // block into a select (SimplifyCFG's SpeculativelyExecuteBB) and then
    // lowers the select without a branch; the arm rules are the diamond's:
    // pure, short, nothing leaving but D. The copy in front keeps D's
    // entry value visible to the renamed arm, so an arm that reads D before
    // writing it, or writes only part of it, still computes what it did, and
    // the full-width move then carries exactly the value the arm left.
    struct Triangle
    {
        MicroInstrRef flagsRef     = MicroInstrRef::invalid();
        MicroInstrRef jumpRef      = MicroInstrRef::invalid();
        MicroInstrRef joinLabelRef = MicroInstrRef::invalid();
        DiamondArm    arm;
        MicroCond     moveCond    = MicroCond::Unconditional;
        MicroReg      result      = MicroReg::invalid();
        bool          sinkCompare = false;
    };

    bool tryMatchTriangleShape(Triangle& out, const DiamondScan& scan, MicroInstrRef jumpRef, const MicroInstr& jumpInst, const MicroInstrOperand* jumpOps)
    {
        uint32_t joinLabelId = 0;
        if (!tryGetJumpTargetLabelId(joinLabelId, jumpInst, jumpOps))
            return false;
        if (!MicroPassHelpers::invertCondition(out.moveCond, jumpOps[0].cpuCond) || !conditionSupportsConditionalMove(out.moveCond))
            return false;

        MicroInstrRef stopRef;
        if (!collectDiamondArm(out.arm, stopRef, scan, jumpRef) || out.arm.refs.empty() || !stopRef.isValid())
            return false;

        // A lone move is convertBranchesToConditionalMoves' shape.
        if (out.arm.refs.size() == 1)
        {
            const MicroInstrOpcode op = scan.storage->ptr(out.arm.refs.front())->op;
            if (op == MicroInstrOpcode::LoadRegReg || op == MicroInstrOpcode::LoadRegImm)
                return false;
        }

        const MicroInstr* labelInst = scan.storage->ptr(stopRef);
        uint32_t          labelId   = 0;
        if (!labelInst || !tryGetLabelId(labelId, *labelInst, labelInst->ops(*scan.operands)) || labelId != joinLabelId)
            return false;

        out.jumpRef      = jumpRef;
        out.joinLabelRef = stopRef;
        return true;
    }

    bool qualifyTriangle(Triangle& triangle, const DiamondScan& scan)
    {
        if (!analyzeDiamondArm(triangle.arm, triangle.result, scan))
            return false;

        // The skipping path carries D's entry value to the join; the move
        // needs that value to exist.
        if (!scan.ssa->reachingDef(triangle.result, triangle.jumpRef).valid())
            return false;

        triangle.sinkCompare = triangle.arm.definesFlags;
        if (!triangle.sinkCompare)
            return true;
        if (triangle.arm.readsEntryFlags)
            return false;

        triangle.flagsRef = scan.storage->findPreviousInstructionRef(triangle.jumpRef);
        if (!triangle.flagsRef.isValid() || scan.relocated.contains(triangle.flagsRef.get()))
            return false;
        const MicroInstr* flagsInst = scan.storage->ptr(triangle.flagsRef);
        if (flagsInst->op != MicroInstrOpcode::CmpRegReg && flagsInst->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const MicroInstrUseDef* flagsUseDef = scan.ssa->instrUseDef(triangle.flagsRef);
        if (!flagsUseDef)
            return false;
        // The renamed arm no longer writes D, so the compare may read it; any
        // other register the arm writes would reach the re-issued compare changed.
        for (const MicroReg use : flagsUseDef->uses)
        {
            if (use != triangle.result && std::ranges::find(triangle.arm.defs, use) != triangle.arm.defs.end())
                return false;
        }

        // The arm's flags no longer reach the join.
        return MicroPassHelpers::areCpuFlagsDeadAfter(*scan.storage, *scan.operands, triangle.joinLabelRef, scan.builder);
    }

    bool convertTrianglesToConditionalMoves(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context, MicroSsaState& localSsaState)
    {
        DiamondScan scan;
        if (!prepareDiamondScan(scan, storage, operands, context))
            return false;

        std::vector<Triangle> triangles;
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstr& jumpInst = *it;
            if (jumpInst.op != MicroInstrOpcode::JumpCond)
                continue;
            const MicroInstrOperand* jumpOps = jumpInst.ops(operands);
            if (!jumpOps || jumpOps[0].cpuCond == MicroCond::Unconditional)
                continue;

            Triangle triangle;
            if (tryMatchTriangleShape(triangle, scan, it.current, jumpInst, jumpOps))
                triangles.push_back(std::move(triangle));
        }

        if (triangles.empty())
            return false;

        scan.ssa = MicroSsaState::ensureFor(context, localSsaState);
        if (!scan.ssa || !scan.ssa->isValid())
            return false;

        std::erase_if(triangles, [&scan](Triangle& triangle) { return !qualifyTriangle(triangle, scan); });

        // Two triangles never share an arm instruction: each arm ends at its
        // own join label, and an arm holds no jump.
        if (triangles.empty())
            return false;

        uint32_t nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        for (const Triangle& triangle : triangles)
        {
            const MicroReg renamedResult = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);

            SmallVector<MicroInstrRegOperandRef> regOperands;
            for (const MicroInstrRef ref : triangle.arm.refs)
            {
                regOperands.clear();
                storage.ptr(ref)->collectRegOperands(operands, regOperands, context.encoder);
                for (const MicroInstrRegOperandRef& regOperand : regOperands)
                {
                    if (*regOperand.reg == triangle.result)
                        *regOperand.reg = renamedResult;
                }
            }

            MicroInstrOperand copyOps[3];
            copyOps[0].reg    = renamedResult;
            copyOps[1].reg    = triangle.result;
            copyOps[2].opBits = MicroOpBits::B64;
            storage.insertDerivedBefore(operands, triangle.arm.refs.front(), MicroInstrOpcode::LoadRegReg, copyOps);

            if (triangle.sinkCompare)
            {
                const MicroInstr*        flagsInst = storage.ptr(triangle.flagsRef);
                const MicroInstrOperand* flagsOps  = flagsInst->ops(operands);
                MicroInstrOperand        sunkOps[3];
                SWC_ASSERT(flagsInst->numOperands <= 3);
                for (uint32_t i = 0; i < flagsInst->numOperands; ++i)
                    sunkOps[i] = flagsOps[i];
                storage.insertDerivedBefore(operands, triangle.joinLabelRef, flagsInst->op, std::span<const MicroInstrOperand>(sunkOps, flagsInst->numOperands));
                storage.erase(triangle.flagsRef);
            }

            MicroInstrOperand movOps[4];
            movOps[0].reg     = triangle.result;
            movOps[1].reg     = renamedResult;
            movOps[2].cpuCond = triangle.moveCond;
            movOps[3].opBits  = MicroOpBits::B64;
            storage.insertDerivedBefore(operands, triangle.joinLabelRef, MicroInstrOpcode::LoadCondRegReg, movOps);

            storage.erase(triangle.jumpRef);
        }

        return true;
    }

    // Speculative if-conversion of an early return:
    //
    //     cmp   X, Y                    cmp   X, Y
    //     jcc   CC, .Lrest              A'...               ; every def of A renamed
    //     A...                          Ta = <A's value>
    //     RET = <A's value>       ->    B...
    //     ret                           Tb = <B's value>
    //   .Lrest:                         [cmp X, Y]          ; re-issued when a path wrote the flags
    //     B...                          cmov(!CC) Tb, Ta
    //     RET = <B's value>             RET = Tb
    //     ret                           ret
    //
    // The `if v < lo do return lo` chain of a clamp or an absolute value written
    // as statements lowers to this shape: each statement is a triangle whose
    // body leaves the function, so the diamond conversion above never sees a
    // join. Folding the innermost pair leaves one straight-line return for the
    // statement above it, and the fixed point folds the chain from the bottom.
    // Both paths run and the condition picks the value, under the diamond's
    // rules - pure, short, nothing leaving a path but its result - with the
    // result the instruction that writes the ABI's integer return register
    // right before the epilogue.
    struct ReturnPath
    {
        SmallVector<MicroInstrRef, 8> refs;
        MicroInstrRef                 valueRef        = MicroInstrRef::invalid();
        MicroInstrRef                 epilogueRef     = MicroInstrRef::invalid();
        MicroInstrRef                 retRef          = MicroInstrRef::invalid();
        MicroOpBits                   valueBits       = MicroOpBits::Zero;
        bool                          definesFlags    = false;
        bool                          readsEntryFlags = false;
    };

    struct EarlyReturn
    {
        MicroInstrRef flagsRef = MicroInstrRef::invalid();
        MicroInstrRef jumpRef  = MicroInstrRef::invalid();
        MicroInstrRef labelRef = MicroInstrRef::invalid();
        ReturnPath    arm;
        ReturnPath    tail;
        MicroCond     moveCond    = MicroCond::Unconditional;
        MicroOpBits   moveBits    = MicroOpBits::B64;
        bool          sinkCompare = false;
    };

    bool isStackRestore(const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg stackPointer)
    {
        return inst.op == MicroInstrOpcode::OpBinaryRegImm && ops && ops[0].reg == stackPointer && ops[2].microOp == MicroOp::Add;
    }

    // The straight line from `fromRef` to a `ret`: speculatable instructions
    // writing virtual registers, the one that materializes the result in the
    // return register, and at most the epilogue's stack restore after it.
    bool collectReturnPath(ReturnPath& out, const DiamondScan& scan, const CallConv& conv, const MicroInstrRef fromRef)
    {
        bool definedFlagsSoFar = false;
        for (MicroInstrRef cur = scan.storage->findNextInstructionRef(fromRef); cur.isValid(); cur = scan.storage->findNextInstructionRef(cur))
        {
            if (scan.relocated.contains(cur.get()))
                return false;

            const MicroInstr*        inst = scan.storage->ptr(cur);
            const MicroInstrOperand* ops  = inst ? inst->ops(*scan.operands) : nullptr;
            if (!inst)
                return false;

            if (inst->op == MicroInstrOpcode::Ret)
            {
                out.retRef = cur;
                return out.valueRef.isValid();
            }

            if (out.valueRef.isValid())
            {
                if (out.epilogueRef.isValid() || !isStackRestore(*inst, ops, conv.stackPointer))
                    return false;
                out.epilogueRef = cur;
                continue;
            }

            if (!isSpeculatableArmInstruction(*inst, ops))
                return false;

            const MicroInstrDef& info = MicroInstr::info(inst->op);
            if (info.flags.has(MicroInstrFlagsE::UsesCpuFlags) && !definedFlagsSoFar)
                out.readsEntryFlags = true;
            if (MicroPassHelpers::instructionActuallyDefinesCpuFlags(*inst, ops))
            {
                out.definesFlags  = true;
                definedFlagsSoFar |= MicroPassHelpers::instructionOverwritesCpuFlags(*inst, ops);
            }

            const MicroOpBits writeBits = armInstructionWriteBits(*inst, ops);
            if (writeBits != MicroOpBits::Zero && ops[0].reg == conv.intReturn)
            {
                out.valueRef  = cur;
                out.valueBits = writeBits;
                continue;
            }

            const MicroInstrUseDef useDef = inst->collectUseDef(*scan.operands, nullptr);
            for (const MicroReg def : useDef.defs)
            {
                if (!def.isVirtualInt())
                    return false;
            }
            if (out.refs.size() >= K_MAX_IF_CONVERT_ARM_INSTR)
                return false;
            out.refs.push_back(cur);
        }

        return false;
    }

    bool tryMatchEarlyReturn(EarlyReturn& out, const DiamondScan& scan, const CallConv& conv, const MicroInstrRef jumpRef, const MicroInstr& jumpInst, const MicroInstrOperand* jumpOps)
    {
        uint32_t labelId = 0;
        if (!tryGetJumpTargetLabelId(labelId, jumpInst, jumpOps))
            return false;
        if (!MicroPassHelpers::invertCondition(out.moveCond, jumpOps[0].cpuCond) || !conditionSupportsConditionalMove(out.moveCond))
            return false;

        out.jumpRef = jumpRef;
        if (!collectReturnPath(out.arm, scan, conv, jumpRef))
            return false;

        // The rest starts at the jump's label, right after the early return,
        // and nothing else lands there.
        out.labelRef = scan.storage->findNextInstructionRef(out.arm.retRef);
        if (!out.labelRef.isValid() || scan.relocated.contains(out.labelRef.get()))
            return false;
        const MicroInstr* labelInst    = scan.storage->ptr(out.labelRef);
        uint32_t          foundLabelId = 0;
        if (!tryGetLabelId(foundLabelId, *labelInst, labelInst->ops(*scan.operands)) || foundLabelId != labelId)
            return false;
        const auto referenceIt = scan.labelReferences.find(labelId);
        if (referenceIt == scan.labelReferences.end() || referenceIt->second != 1)
            return false;

        if (!collectReturnPath(out.tail, scan, conv, out.labelRef))
            return false;

        // One epilogue serves both: they restore the same frame or none.
        if (out.arm.epilogueRef.isValid() != out.tail.epilogueRef.isValid())
            return false;
        if (out.arm.epilogueRef.isValid())
        {
            const MicroInstrOperand* armOps  = scan.storage->ptr(out.arm.epilogueRef)->ops(*scan.operands);
            const MicroInstrOperand* tailOps = scan.storage->ptr(out.tail.epilogueRef)->ops(*scan.operands);
            if (armOps[1].opBits != tailOps[1].opBits || armOps[3].valueU64 != tailOps[3].valueU64)
                return false;
        }

        // cmov exists for 32/64-bit registers only, and a 32-bit write
        // zero-extends, so the wider of the two results is the move's width.
        const uint32_t armBits  = getNumBits(out.arm.valueBits);
        const uint32_t tailBits = getNumBits(out.tail.valueBits);
        if (armBits < 32 || tailBits < 32)
            return false;
        out.moveBits = armBits == 64 || tailBits == 64 ? MicroOpBits::B64 : MicroOpBits::B32;

        // The rest used to run straight after the compare. When either path
        // writes the flags, the compare is re-issued before the move, which
        // needs it pure and its inputs untouched by the rest; the early path
        // cannot touch them, every register it writes is renamed.
        out.sinkCompare = out.arm.definesFlags || out.tail.definesFlags;
        if (!out.sinkCompare)
            return true;
        if (out.arm.readsEntryFlags || out.tail.readsEntryFlags)
            return false;

        out.flagsRef = scan.storage->findPreviousInstructionRef(jumpRef);
        if (!out.flagsRef.isValid() || scan.relocated.contains(out.flagsRef.get()))
            return false;
        const MicroInstr* flagsInst = scan.storage->ptr(out.flagsRef);
        if (flagsInst->op != MicroInstrOpcode::CmpRegReg && flagsInst->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const MicroInstrUseDef flagsUseDef = flagsInst->collectUseDef(*scan.operands, nullptr);
        for (const MicroInstrRef ref : out.tail.refs)
        {
            const MicroInstrUseDef useDef = scan.storage->ptr(ref)->collectUseDef(*scan.operands, nullptr);
            for (const MicroReg use : flagsUseDef.uses)
            {
                if (std::ranges::find(useDef.defs, use) != useDef.defs.end())
                    return false;
            }
        }

        return true;
    }

    // Rename every virtual register the early path writes, so the rest of
    // the function - which used to run instead of it - still reads what it
    // read before, and route the path's result into `valueReg`. False when a
    // read-modify-write touches a register the path never wrote first: its
    // read needs the old value and its write the new name.
    bool renameEarlyPath(const ReturnPath& path, MicroStorage& storage, MicroOperandStorage& operands, const Encoder* encoder, const MicroReg returnReg, const MicroReg valueReg, uint32_t& nextVirtualIntRegIndex)
    {
        std::unordered_map<MicroReg, MicroReg> renamed;
        SmallVector<MicroInstrRegOperandRef>   regOperands;
        SmallVector<MicroInstrRef, 8>          refs = path.refs;
        refs.push_back(path.valueRef);

        for (const MicroInstrRef ref : refs)
        {
            regOperands.clear();
            storage.ptr(ref)->collectRegOperands(operands, regOperands, encoder);
            for (const MicroInstrRegOperandRef& regOperand : regOperands)
            {
                MicroReg& reg = *regOperand.reg;
                if (regOperand.def && ref == path.valueRef && reg == returnReg)
                {
                    reg = valueReg;
                    continue;
                }

                const auto it = renamed.find(reg);
                if (it != renamed.end())
                {
                    reg = it->second;
                    continue;
                }
                if (!regOperand.def || !reg.isVirtualInt())
                    continue;
                if (regOperand.use)
                    return false;

                const MicroReg fresh = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
                renamed.emplace(reg, fresh);
                reg = fresh;
            }
        }

        return true;
    }

    bool convertEarlyReturnsToSelects(MicroStorage& storage, MicroOperandStorage& operands, MicroPassContext& context)
    {
        DiamondScan scan;
        if (!prepareDiamondScan(scan, storage, operands, context))
            return false;

        const CallConv& conv = CallConv::get(context.callConvKind);
        if (!conv.intReturn.isValid())
            return false;

        std::vector<EarlyReturn> candidates;
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstr& jumpInst = *it;
            if (jumpInst.op != MicroInstrOpcode::JumpCond)
                continue;
            const MicroInstrOperand* jumpOps = jumpInst.ops(operands);
            if (!jumpOps || jumpOps[0].cpuCond == MicroCond::Unconditional)
                continue;

            EarlyReturn candidate;
            if (tryMatchEarlyReturn(candidate, scan, conv, it.current, jumpInst, jumpOps))
                candidates.push_back(std::move(candidate));
        }

        if (candidates.empty())
            return false;

        bool     changed                = false;
        uint32_t nextVirtualIntRegIndex = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        for (const EarlyReturn& earlyReturn : candidates)
        {
            const MicroReg armValue  = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
            const MicroReg tailValue = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
            if (!renameEarlyPath(earlyReturn.arm, storage, operands, context.encoder, conv.intReturn, armValue, nextVirtualIntRegIndex))
                continue;

            MicroInstrOperand* tailValueOps = storage.ptr(earlyReturn.tail.valueRef)->ops(operands);
            tailValueOps[0].reg             = tailValue;

            const MicroInstrRef insertBefore = earlyReturn.tail.epilogueRef.isValid() ? earlyReturn.tail.epilogueRef : earlyReturn.tail.retRef;
            if (earlyReturn.sinkCompare)
            {
                const MicroInstr*        flagsInst = storage.ptr(earlyReturn.flagsRef);
                const MicroInstrOperand* flagsOps  = flagsInst->ops(operands);
                MicroInstrOperand        sunkOps[3];
                SWC_ASSERT(flagsInst->numOperands <= 3);
                for (uint32_t i = 0; i < flagsInst->numOperands; ++i)
                    sunkOps[i] = flagsOps[i];
                storage.insertDerivedBefore(operands, insertBefore, flagsInst->op, std::span<const MicroInstrOperand>(sunkOps, flagsInst->numOperands));
                storage.erase(earlyReturn.flagsRef);
            }

            MicroInstrOperand movOps[4];
            movOps[0].reg     = tailValue;
            movOps[1].reg     = armValue;
            movOps[2].cpuCond = earlyReturn.moveCond;
            movOps[3].opBits  = earlyReturn.moveBits;
            storage.insertDerivedBefore(operands, insertBefore, MicroInstrOpcode::LoadCondRegReg, movOps);

            MicroInstrOperand retOps[3];
            retOps[0].reg    = conv.intReturn;
            retOps[1].reg    = tailValue;
            retOps[2].opBits = earlyReturn.moveBits;
            storage.insertDerivedBefore(operands, insertBefore, MicroInstrOpcode::LoadRegReg, retOps);

            storage.erase(earlyReturn.jumpRef);
            if (earlyReturn.arm.epilogueRef.isValid())
                storage.erase(earlyReturn.arm.epilogueRef);
            storage.erase(earlyReturn.arm.retRef);
            storage.erase(earlyReturn.labelRef);
            changed = true;
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

    bool eraseCfgUnreachable(MicroBuilder& builder, MicroStorage& storage, const MicroOperandStorage& operands)
    {
        const MicroControlFlowGraph& cfg = builder.controlFlowGraph();
        if (!cfg.instructionCount() || cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
            return false;

        std::vector<uint8_t>  reachable(cfg.instructionCount(), 0);
        std::vector<uint32_t> stack;
        stack.push_back(0);
        reachable[0] = 1;

        std::unordered_map<uint64_t, uint32_t> labelInstructionIndices;
        SmallVector<uint64_t>                  addressTakenLabels;
        const auto                             instructionRefs = cfg.instructionRefs();
        for (uint32_t instructionIndex = 0; instructionIndex < instructionRefs.size(); ++instructionIndex)
        {
            const MicroInstr* inst = storage.ptr(instructionRefs[instructionIndex]);
            if (!inst)
                continue;

            const MicroInstrOperand* ops = inst->ops(operands);
            if (!ops)
                continue;
            if (inst->op == MicroInstrOpcode::Label && inst->numOperands >= 1)
                labelInstructionIndices[ops[0].valueU64] = instructionIndex;
            else if (inst->op == MicroInstrOpcode::LoadLabelAddress && inst->numOperands >= 2)
                addressTakenLabels.push_back(ops[1].valueU64);
        }

        for (const uint64_t labelId : addressTakenLabels)
        {
            const auto it = labelInstructionIndices.find(labelId);
            if (it == labelInstructionIndices.end() || reachable[it->second])
                continue;
            reachable[it->second] = 1;
            stack.push_back(it->second);
        }

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

        bool changed = false;
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

    if (changed && context.builder)
        context.builder->invalidateControlFlowGraph();
    // Threading one exit of an `and` chain exposes the next join to the
    // fuse, and the fused test to the next threading: a chain settles in
    // one run instead of one link per optimization sweep.
    constexpr uint32_t K_MAX_THREAD_ROUNDS = 4096;
    for (uint32_t round = 0; round < K_MAX_THREAD_ROUNDS; ++round)
    {
        bool roundChanged = fuseMaterializedBoolBranches(storage, operands, context.builder);
        roundChanged |= coalesceShortCircuitResults(storage, operands, context);
        roundChanged |= threadShortCircuitExits(storage, operands, context.builder);
        roundChanged |= eraseUnreferencedLabels(storage, operands, context);
        if (!roundChanged)
            break;
        changed = true;
        if (context.builder)
            context.builder->invalidateControlFlowGraph();
    }
    if (changed && context.builder)
        context.builder->invalidateControlFlowGraph();
    changed |= convertEqualityChainsToBitTests(storage, operands, context);
    changed |= convertSwitchesToPackedTables(storage, operands, context);
    changed |= foldRangeChecks(storage, operands, context);
    if (changed && context.builder)
        context.builder->invalidateControlFlowGraph();
    // A whole `or` chain goes at once, before the two-link form takes its tail.
    changed |= convertOrChainsToBranchless(storage, operands, context);
    changed |= convertThreeWaySignDiamonds(storage, operands, context);
    changed |= forwardRepeatedMemoryCompareInShortCircuit(storage, operands, context);
    changed |= convertShortCircuitBooleans(storage, operands, context);
    if (changed && context.builder)
        context.builder->invalidateControlFlowGraph();
    changed |= foldRangeAnds(storage, operands, context);

    if (changed && context.builder)
        context.builder->invalidateControlFlowGraph();

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

        {
            ProgramLayout layout;
            buildProgramLayout(layout, storage, operands);
            structuralChanged |= redirectJumpChains(storage, operands, layout);
            const bool erasedImmediateJumps = eraseJumpsToImmediateLabels(storage, operands, layout);
            structuralChanged |= erasedImmediateJumps;
            // Retargeting preserves layout; erasing jumps leaves holes that the
            // adjacent-label query deliberately rejects, so rebuild only then.
            if (erasedImmediateJumps)
                buildProgramLayout(layout, storage, operands);
            structuralChanged |= invertJumpOverAdjacentJump(storage, operands, layout);
        }
        structuralChanged |= eraseDeadInstructionsAfterTerminators(storage, operands);

        if (structuralChanged && context.builder)
            context.builder->invalidateControlFlowGraph();

        if (context.builder)
        {
            const bool erasedUnreachable = eraseCfgUnreachable(*context.builder, storage, operands);
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
    if (convertComparedLoadDiamond(storage, operands, context))
    {
        changed = true;
        if (context.ssaState)
            context.ssaState->invalidate();
        localSsaState.invalidate();
        if (context.builder)
            context.builder->invalidateControlFlowGraph();
    }
    if (convertAdjacentLoadDiamond(storage, operands, context))
    {
        changed = true;
        if (context.ssaState)
            context.ssaState->invalidate();
        localSsaState.invalidate();
        if (context.builder)
            context.builder->invalidateControlFlowGraph();
    }
    if (forwardComparedLoadIntoDiamondArm(storage, operands, context))
    {
        changed = true;
        if (context.ssaState)
            context.ssaState->invalidate();
        localSsaState.invalidate();
        if (context.builder)
            context.builder->invalidateControlFlowGraph();
    }
    if (convertComparedLoadsSubtractDiamond(storage, operands, context))
    {
        changed = true;
        if (context.ssaState)
            context.ssaState->invalidate();
        localSsaState.invalidate();
        if (context.builder)
            context.builder->invalidateControlFlowGraph();
    }
    if (convertDiamondsToConditionalMoves(storage, operands, context, localSsaState))
    {
        changed = true;
        if (context.builder)
            context.builder->invalidateControlFlowGraph();
    }

    if (!changed && convertTrianglesToConditionalMoves(storage, operands, context, localSsaState))
    {
        changed = true;
        if (context.builder)
            context.builder->invalidateControlFlowGraph();
    }

    if (convertEarlyReturnsToSelects(storage, operands, context))
    {
        changed = true;
        if (context.builder)
            context.builder->invalidateControlFlowGraph();
    }

    if (changed)
    {
        if (context.builder)
            context.builder->invalidateControlFlowGraph();
        context.passChanged = true;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
