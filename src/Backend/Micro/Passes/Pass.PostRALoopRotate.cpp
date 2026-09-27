#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRALoopRotate.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroLabelHelpers.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroStorage.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

// Post-RA loop layout. See the header for why it runs here.
//
//   H:                            H:
//     cmp  A, B                     cmp  A, B          ; now entry only
//     jcc  EXIT               ->    jcc  EXIT
//     ...body...                  H2:
//     jmp  H                        ...body...
//   EXIT:                           cmp  A, B
//                                   jcc(~cc) H2
//                                 EXIT:
//
// The header test stays where it is and a fresh label opens behind it; only the
// back edge moves, from the top of the test to the top of the body. What each
// iteration executes is unchanged - [cmp][body][jmp][cmp] becomes
// [cmp][body][cmp] - so a test reading memory the body writes still reads it at
// the same point, and the flags each jump consumes are still defined
// immediately above it. A `continue` aimed at H keeps working too: it re-runs
// the test and falls into H2, exactly as before.
//
// The allocator may leave register moves and frame traffic between the label
// and the jump: split connectors before the compare, exit-edge connectors
// between the compare and the jump. They are part of the test. The whole run
// from the label to the jump is what gets copied to the back edge, so each
// iteration still executes it once, at the same point.

SWC_BEGIN_NAMESPACE();

namespace
{
    using MicroLabelHelpers::tryGetJumpTargetLabelId;
    using MicroLabelHelpers::tryGetLabelId;

    // Compare and test instructions define only flags. Copying an arithmetic
    // instruction would also copy its value definition.
    bool isDuplicableTest(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::CmpRegReg:
            case MicroInstrOpcode::CmpRegImm:
            case MicroInstrOpcode::CmpMemImm:
            case MicroInstrOpcode::CmpMemReg:
            case MicroInstrOpcode::CmpAmcImm:
            case MicroInstrOpcode::CmpAmcReg:
            case MicroInstrOpcode::TestRegReg:
            case MicroInstrOpcode::TestRegImm:
            case MicroInstrOpcode::TestMemReg:
            case MicroInstrOpcode::TestMemImm:
                return true;
            default:
                return false;
        }
    }

    bool invertCondition(const MicroCond cond, MicroCond& outInverted)
    {
        switch (cond)
        {
            case MicroCond::Equal: outInverted = MicroCond::NotEqual; return true;
            case MicroCond::NotEqual: outInverted = MicroCond::Equal; return true;
            case MicroCond::Zero: outInverted = MicroCond::NotZero; return true;
            case MicroCond::NotZero: outInverted = MicroCond::Zero; return true;
            case MicroCond::Below: outInverted = MicroCond::AboveOrEqual; return true;
            case MicroCond::AboveOrEqual: outInverted = MicroCond::Below; return true;
            case MicroCond::BelowOrEqual: outInverted = MicroCond::Above; return true;
            case MicroCond::Above: outInverted = MicroCond::BelowOrEqual; return true;
            case MicroCond::Less: outInverted = MicroCond::GreaterOrEqual; return true;
            case MicroCond::GreaterOrEqual: outInverted = MicroCond::Less; return true;
            case MicroCond::LessOrEqual: outInverted = MicroCond::Greater; return true;
            case MicroCond::Greater: outInverted = MicroCond::LessOrEqual; return true;
            default: return false;
        }
    }

    // A connector the allocator places around the test: a register move or
    // frame traffic, flag-neutral, so the compare still feeds the jump.
    bool isDuplicableConnector(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadMemReg:
                return true;
            default:
                return false;
        }
    }

    // A header carrying more than this around its compare is not worth
    // duplicating for the one jump the rotation removes.
    constexpr uint32_t K_MAX_TEST_RUN = 8;

    // Thread a repeated indexed zero test when the two returns of an inlined
    // search already establish its result. A path through a read-only call is
    // admissible, but a write to the cell or either address register is not.
    bool threadRepeatedIndexedZeroTest(MicroPassContext& context, const std::vector<MicroInstrRef>& order)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;
        bool                 hasShape = false;
        for (uint32_t at = 2; at + 3 < order.size(); ++at)
        {
            const MicroInstr* first  = storage.ptr(order[at - 2]);
            const MicroInstr* second = storage.ptr(order[at - 1]);
            const MicroInstr* cmp    = storage.ptr(order[at]);
            const MicroInstr* jump   = storage.ptr(order[at + 1]);
            if (first && first->op == MicroInstrOpcode::Label && second && second->op == MicroInstrOpcode::Label &&
                cmp && cmp->op == MicroInstrOpcode::CmpAmcImm && jump && jump->op == MicroInstrOpcode::JumpCond)
            {
                hasShape = true;
                break;
            }
        }
        if (!hasShape)
            return false;
        const auto&          cfg      = context.builder->controlFlowGraph();
        if (cfg.hasUnsupportedControlFlowForCfgLiveness() || cfg.instructionCount() != order.size())
            return false;

        const auto isZeroCellCompare = [&](const MicroInstr* inst) {
            if (!inst || inst->op != MicroInstrOpcode::CmpAmcImm)
                return false;
            const auto* ops = inst->ops(operands);
            return ops && ops[2].opBits == MicroOpBits::B8 && ops[3].opBits == MicroOpBits::B64 &&
                   !ops[6].hasWideImmediateValue() && ops[6].valueU64 == 0 &&
                   ops[0].reg.isInt() && ops[1].reg.isInt();
        };
        const auto sameCell = [&](const MicroInstr* left, const MicroInstr* right) {
            if (!isZeroCellCompare(left) || !isZeroCellCompare(right))
                return false;
            const auto* a = left->ops(operands);
            const auto* b = right->ops(operands);
            return a[0].reg == b[0].reg && a[1].reg == b[1].reg &&
                   a[4].valueU64 == b[4].valueU64 && a[5].valueU64 == b[5].valueU64;
        };

        std::unordered_map<uint32_t, const Symbol*> callTargets;
        for (const MicroRelocation& relocation : context.builder->codeRelocations())
        {
            if (relocation.instructionRef.isValid() && relocation.targetSymbol)
                callTargets[relocation.instructionRef.get()] = relocation.targetSymbol;
        }
        const auto isReadOnlyCall = [&](const MicroInstrRef ref, const MicroInstr& inst) {
            if (inst.op != MicroInstrOpcode::CallLocal && inst.op != MicroInstrOpcode::CallExtern)
                return false;
            const auto it = callTargets.find(ref.get());
            return it != callTargets.end() && it->second->isFunction() &&
                   it->second->cast<SymbolFunction>().attributes().hasRtFlag(RtAttributeFlagsE::ReadOnly);
        };

        for (uint32_t at = 2; at + 3 < order.size(); ++at)
        {
            const MicroInstr* emptyLabel = storage.ptr(order[at - 2]);
            const MicroInstr* matchLabel = storage.ptr(order[at - 1]);
            const MicroInstr* compare    = storage.ptr(order[at]);
            const MicroInstr* branch     = storage.ptr(order[at + 1]);
            uint32_t          emptyId    = 0;
            uint32_t          matchId    = 0;
            if (!emptyLabel || !matchLabel || !tryGetLabelId(emptyId, *emptyLabel, emptyLabel->ops(operands)) ||
                !tryGetLabelId(matchId, *matchLabel, matchLabel->ops(operands)) ||
                !isZeroCellCompare(compare) || !branch || branch->op != MicroInstrOpcode::JumpCond)
                continue;
            const auto* branchOps = branch->ops(operands);
            if (!branchOps || (branchOps[0].cpuCond != MicroCond::Equal && branchOps[0].cpuCond != MicroCond::NotEqual) ||
                !MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*context.builder, order[at + 1]))
                continue;
            uint32_t branchTarget = 0;
            if (!tryGetJumpTargetLabelId(branchTarget, *branch, branchOps) ||
                branchTarget == emptyId || branchTarget == matchId)
                continue;
            const auto addressTaken = cfg.addressTakenLabelIndices();
            if (std::ranges::find(addressTaken, at - 2) != addressTaken.end() ||
                std::ranges::find(addressTaken, at - 1) != addressTaken.end())
                continue;

            const auto* cellOps = compare->ops(operands);
            uint32_t    visits  = 0;
            std::unordered_set<uint64_t> visiting;
            const auto provesEdge = [&](auto&& self, const uint32_t predecessor, const uint32_t successor, const bool wantZero) -> bool {
                if (++visits > 512 || predecessor >= order.size() || successor >= order.size())
                    return false;
                const uint64_t edge = (static_cast<uint64_t>(predecessor) << 32) | successor;
                if (!visiting.insert(edge).second)
                    return false;
                const MicroInstrRef ref  = order[predecessor];
                const MicroInstr*   inst = storage.ptr(ref);
                if (!inst)
                    return false;
                if (inst->op == MicroInstrOpcode::JumpCond && predecessor != 0)
                {
                    const MicroInstr* guard = storage.ptr(order[predecessor - 1]);
                    if (sameCell(guard, compare))
                    {
                        const auto* jumpOps = inst->ops(operands);
                        uint32_t    target  = 0;
                        if (jumpOps && tryGetJumpTargetLabelId(target, *inst, jumpOps) &&
                            (jumpOps[0].cpuCond == MicroCond::Equal || jumpOps[0].cpuCond == MicroCond::NotEqual))
                        {
                            const bool taken = cfg.indexOfLabel(target) == successor;
                            if (taken != (successor == predecessor + 1))
                            {
                                const bool zero = taken == (jumpOps[0].cpuCond == MicroCond::Equal);
                                visiting.erase(edge);
                                return zero == wantZero;
                            }
                        }
                    }
                }

                const auto flags = MicroInstr::info(inst->op).flags;
                if (flags.has(MicroInstrFlagsE::WritesMemory) ||
                    (flags.has(MicroInstrFlagsE::IsCallInstruction) && !isReadOnlyCall(ref, *inst)))
                    return false;
                const MicroInstrUseDef useDef = inst->collectUseDef(operands, context.encoder);
                for (const MicroReg def : useDef.defs)
                {
                    if (def == cellOps[0].reg || def == cellOps[1].reg)
                        return false;
                }
                const auto& incoming = cfg.predecessors(predecessor);
                if (incoming.empty())
                    return false;
                for (const uint32_t prior : incoming)
                {
                    if (!self(self, prior, predecessor, wantZero))
                        return false;
                }
                visiting.erase(edge);
                return true;
            };

            bool safe = !cfg.predecessors(at - 2).empty() && !cfg.predecessors(at - 1).empty();
            for (const uint32_t predecessor : cfg.predecessors(at - 2))
            {
                visits = 0;
                visiting.clear();
                safe &= provesEdge(provesEdge, predecessor, at - 2, true);
            }
            bool hasMatchJump = false;
            for (const uint32_t predecessor : cfg.predecessors(at - 1))
            {
                if (predecessor == at - 2)
                    continue; // the empty fallthrough is removed by this rewrite
                hasMatchJump = true;
                visits       = 0;
                visiting.clear();
                safe &= provesEdge(provesEdge, predecessor, at - 1, false);
            }
            if (!safe || !hasMatchJump)
                continue;

            const MicroInstr* afterBranch = storage.ptr(order[at + 2]);
            uint32_t          fallthrough = 0;
            const bool        needsLabel  = !tryGetLabelId(fallthrough, *afterBranch, afterBranch->ops(operands));
            if (needsLabel)
                fallthrough = context.builder->createLabel().get();
            const uint32_t zeroTarget    = branchOps[0].cpuCond == MicroCond::Equal ? branchTarget : fallthrough;
            const uint32_t nonzeroTarget = branchOps[0].cpuCond == MicroCond::Equal ? fallthrough : branchTarget;
            const MicroInstrOperand branchSize = branchOps[1];

            // Every incoming jump was proved above. The empty edge that falls
            // out of the probe's last comparison still arrives at emptyLabel.
            for (const MicroInstrRef ref : order)
            {
                MicroInstr* inst = storage.ptr(ref);
                if (!inst || inst->op != MicroInstrOpcode::JumpCond)
                    continue;
                MicroInstrOperand* ops = inst->ops(operands);
                uint32_t target = 0;
                if (!tryGetJumpTargetLabelId(target, *inst, ops))
                    continue;
                if (target == emptyId)
                    ops[2].valueU64 = zeroTarget;
                else if (target == matchId)
                    ops[2].valueU64 = nonzeroTarget;
            }
            if (needsLabel)
            {
                MicroInstrOperand labelOps[1];
                labelOps[0].valueU64 = fallthrough;
                storage.insertDerivedBefore(operands, order[at + 2], MicroInstrOpcode::Label, labelOps);
            }
            if (zeroTarget != fallthrough)
            {
                MicroInstrOperand jumpOps[3] = {};
                jumpOps[0].cpuCond  = MicroCond::Unconditional;
                jumpOps[1]          = branchSize;
                jumpOps[2].valueU64 = zeroTarget;
                storage.insertDerivedBefore(operands, order[at - 1], MicroInstrOpcode::JumpCond, jumpOps);
            }
            storage.erase(order[at - 1]);
            storage.erase(order[at]);
            storage.erase(order[at + 1]);
            context.builder->invalidateControlFlowGraph();
            context.passChanged = true;
            return true;
        }
        return false;
    }

    // Move flag-neutral preparations behind the latch's taken back edge. An
    // entry jump skips them on the first iteration; later iterations execute
    // them at the same point as before, then fall into the body. The exit path
    // still skips them, even when their results are live beyond the loop.
    bool rotateLatchConnectors(MicroPassContext& context, const std::vector<MicroInstrRef>& order)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;

        std::unordered_map<uint32_t, uint32_t> labels;
        bool                                   labelsReady = false;

        for (uint32_t i = 0; i + 3 < order.size(); ++i)
        {
            const MicroInstr* cmp = storage.ptr(order[i]);
            const MicroInstr* jcc = storage.ptr(order[i + 1]);
            if (!cmp || !jcc || cmp->op != MicroInstrOpcode::CmpRegImm || jcc->op != MicroInstrOpcode::JumpCond)
                continue;
            const auto* jccOps = jcc->ops(operands);
            if (!jccOps || jcc->numOperands < 3 || jccOps[0].cpuCond == MicroCond::Unconditional)
                continue;
            MicroCond inverted = MicroCond::Unconditional;
            if (!invertCondition(jccOps[0].cpuCond, inverted))
                continue;

            uint32_t exitId = 0;
            if (!tryGetJumpTargetLabelId(exitId, *jcc, jccOps))
                continue;

            if (!labelsReady)
            {
                for (uint32_t labelOrdinal = 0; labelOrdinal < order.size(); ++labelOrdinal)
                {
                    const MicroInstr* inst = storage.ptr(order[labelOrdinal]);
                    uint32_t          id   = 0;
                    if (inst && tryGetLabelId(id, *inst, inst->ops(operands)))
                        labels[id] = labelOrdinal;
                }
                labelsReady = true;
            }

            const auto exitIt = labels.find(exitId);
            if (exitIt == labels.end() || exitIt->second <= i + 2)
                continue;
            const uint32_t backIndex = exitIt->second - 1;
            const MicroInstr* back   = storage.ptr(order[backIndex]);
            if (!back || back->op != MicroInstrOpcode::JumpCond || back->numOperands < 3)
                continue;
            const auto* backOps = back->ops(operands);
            if (!backOps || backOps[0].cpuCond != MicroCond::Unconditional ||
                backOps[2].valueU64 > std::numeric_limits<uint32_t>::max())
                continue;
            const auto bodyIt = labels.find(static_cast<uint32_t>(backOps[2].valueU64));
            if (bodyIt == labels.end() || bodyIt->second >= i)
                continue;

            bool safe = true;
            for (uint32_t connectorIndex = i + 2; connectorIndex < backIndex; ++connectorIndex)
            {
                const MicroInstr* connector = storage.ptr(order[connectorIndex]);
                if (!connector || !isDuplicableConnector(*connector))
                {
                    safe = false;
                    break;
                }
            }
            if (!safe)
                continue;

            const MicroInstrRef bodyRef = order[bodyIt->second];
            const uint64_t prepId = context.builder->createLabel().get();
            MicroInstrOperand entryOps[3] = {backOps[0], backOps[1], backOps[2]};
            MicroInstrOperand prepOps[1];
            prepOps[0].valueU64 = prepId;
            storage.insertDerivedBefore(operands, bodyRef, MicroInstrOpcode::JumpCond, entryOps);
            storage.insertDerivedBefore(operands, bodyRef, MicroInstrOpcode::Label, prepOps);
            for (uint32_t connectorIndex = i + 2; connectorIndex < backIndex; ++connectorIndex)
            {
                const MicroInstrRef oldRef = order[connectorIndex];
                const MicroInstr*  oldInst = storage.ptr(oldRef);
                SmallVector<MicroInstrOperand, 8> copy;
                for (uint32_t op = 0; op < oldInst->numOperands; ++op)
                    copy.push_back(oldInst->ops(operands)[op]);
                const MicroInstrRef newRef = storage.insertDerivedBefore(operands, bodyRef, oldInst->op, {copy.data(), copy.size()});
                for (auto& relocation : context.builder->codeRelocations())
                {
                    if (relocation.instructionRef == oldRef)
                        relocation.instructionRef = newRef;
                }
                storage.erase(oldRef);
            }
            MicroInstrOperand* rewrittenOps = storage.ptr(order[i + 1])->ops(operands);
            rewrittenOps[0].cpuCond         = inverted;
            rewrittenOps[2].valueU64       = prepId;
            storage.erase(order[backIndex]);
            context.builder->invalidateControlFlowGraph();
            context.passChanged = true;
            return true;
        }
        return false;
    }

    struct Rotation
    {
        // Ordinals into the listing: [testBegin, testEnd) is the test run,
        // the compare and its connectors, copied to the back edge.
        uint32_t      testBegin    = 0;
        uint32_t      testEnd      = 0;
        MicroInstrRef jccRef       = MicroInstrRef::invalid();
        MicroInstrRef bodyFirstRef = MicroInstrRef::invalid();
        MicroInstrRef backRef      = MicroInstrRef::invalid();
        MicroCond     inverted     = MicroCond::Unconditional;
    };

    // Put a short loop step on the fall-through path of a two-way comparison:
    //
    //   je T; ja P; jmp S; T: ...; P: inc i; jmp H; S:
    //       ->
    //   je T; jbe S; P: inc i; jmp H; T: ...; jmp P; S:
    //
    // The unequal advancing path saves one executed jump. Moving the existing
    // step, rather than cloning it, keeps code size and incoming edges stable.
    // This is post-RA so block layout cannot change register assignment.
    bool placeShortLoopStep(MicroPassContext& context, const std::vector<MicroInstrRef>& order)
    {
        MicroStorage&        storage   = *context.instructions;
        MicroOperandStorage& operands  = *context.operands;
        const auto           findLabel = [&](const uint64_t id, const uint32_t endOrdinal) {
            for (uint32_t index = 0; index < endOrdinal; ++index)
            {
                const MicroInstr* inst = storage.ptr(order[index]);
                if (inst && inst->op == MicroInstrOpcode::Label && inst->ops(operands)[0].valueU64 == id)
                    return index;
            }
            return static_cast<uint32_t>(order.size());
        };

        for (uint32_t ordinal = 0; ordinal + 4 < order.size(); ++ordinal)
        {
            const MicroInstrRef firstRef  = order[ordinal];
            const MicroInstrRef secondRef = order[ordinal + 1];
            const MicroInstrRef skipRef   = order[ordinal + 2];
            const MicroInstrRef tieRef    = order[ordinal + 3];
            const MicroInstr*   first     = storage.ptr(firstRef);
            const MicroInstr*   second    = storage.ptr(secondRef);
            const MicroInstr*   skip      = storage.ptr(skipRef);
            const MicroInstr*   tie       = storage.ptr(tieRef);
            if (!first || !second || !skip || !tie ||
                first->op != MicroInstrOpcode::JumpCond || second->op != MicroInstrOpcode::JumpCond ||
                skip->op != MicroInstrOpcode::JumpCond || tie->op != MicroInstrOpcode::Label ||
                first->numOperands < 3 || second->numOperands < 3 || skip->numOperands < 3)
                continue;
            const auto* firstOps  = first->ops(operands);
            const auto* secondOps = second->ops(operands);
            const auto* skipOps   = skip->ops(operands);
            const auto* tieOps    = tie->ops(operands);
            if (!firstOps || !secondOps || !skipOps || !tieOps ||
                firstOps[0].cpuCond == MicroCond::Unconditional ||
                secondOps[0].cpuCond == MicroCond::Unconditional ||
                skipOps[0].cpuCond != MicroCond::Unconditional ||
                firstOps[2].valueU64 != tieOps[0].valueU64)
                continue;
            MicroCond inverted = MicroCond::Unconditional;
            if (!invertCondition(secondOps[0].cpuCond, inverted))
                continue;

            const uint32_t stepSearchEnd = static_cast<uint32_t>(std::min<size_t>(order.size(), static_cast<size_t>(ordinal) + 81));
            const uint32_t stepOrdinal   = findLabel(secondOps[2].valueU64, stepSearchEnd);
            if (stepOrdinal <= ordinal + 4 ||
                stepOrdinal - ordinal > 80 || stepOrdinal + 3 >= order.size())
                continue;
            const MicroInstrRef stepLabelRef = order[stepOrdinal];
            const MicroInstrRef updateRef    = order[stepOrdinal + 1];
            const MicroInstrRef backRef      = order[stepOrdinal + 2];
            const MicroInstr*   update       = storage.ptr(updateRef);
            const MicroInstr*   back         = storage.ptr(backRef);
            const MicroInstr*   stop         = storage.ptr(order[stepOrdinal + 3]);
            if (!update || !back || !stop ||
                update->op != MicroInstrOpcode::OpBinaryRegImm || back->op != MicroInstrOpcode::JumpCond ||
                stop->op != MicroInstrOpcode::Label || update->numOperands < 4 || back->numOperands < 3)
                continue;
            const auto*       updateOps  = update->ops(operands);
            const auto*       backOps    = back->ops(operands);
            const auto*       stopOps    = stop->ops(operands);
            const MicroInstr* beforeStep = storage.ptr(order[stepOrdinal - 1]);
            if (!updateOps || !backOps || !stopOps || !beforeStep ||
                (updateOps[2].microOp != MicroOp::Add && updateOps[2].microOp != MicroOp::Subtract) ||
                updateOps[1].opBits != MicroOpBits::B64 || updateOps[3].valueU64 != 1 ||
                backOps[0].cpuCond != MicroCond::Unconditional ||
                skipOps[2].valueU64 != stopOps[0].valueU64 ||
                beforeStep->op == MicroInstrOpcode::Ret ||
                (beforeStep->op == MicroInstrOpcode::JumpCond &&
                 beforeStep->ops(operands)[0].cpuCond == MicroCond::Unconditional))
                continue;
            if (findLabel(backOps[2].valueU64, ordinal) >= ordinal)
                continue;

            // Capture operands before insertions can grow their storage.
            std::array<MicroInstrOperand, 3> rewritten     = {secondOps[0], secondOps[1], secondOps[2]};
            rewritten[0].cpuCond                           = inverted;
            rewritten[2].valueU64                          = skipOps[2].valueU64;
            std::array<MicroInstrOperand, 3> jumpToStep    = {backOps[0], backOps[1], backOps[2]};
            jumpToStep[2].valueU64                         = secondOps[2].valueU64;
            std::array<MicroInstrOperand, 4> updateCopy    = {updateOps[0], updateOps[1], updateOps[2], updateOps[3]};
            const MicroInstrOperand          stepLabelCopy = storage.ptr(stepLabelRef)->ops(operands)[0];
            std::array<MicroInstrOperand, 3> backCopy      = {backOps[0], backOps[1], backOps[2]};
            const MicroInstrOpcode           updateOpcode  = update->op;
            const MicroInstrOpcode           backOpcode    = back->op;

            storage.insertDerivedBefore(operands, tieRef, MicroInstrOpcode::Label, std::span(&stepLabelCopy, 1));
            storage.insertDerivedBefore(operands, tieRef, updateOpcode, updateCopy);
            storage.insertDerivedBefore(operands, tieRef, backOpcode, backCopy);
            storage.insertDerivedBefore(operands, order[stepOrdinal + 3], MicroInstrOpcode::JumpCond, jumpToStep);
            MicroInstr*        rewrittenSecond = storage.ptr(secondRef);
            MicroInstrOperand* rewrittenOps    = rewrittenSecond->ops(operands);
            for (uint32_t i = 0; i < 3; ++i)
                rewrittenOps[i] = rewritten[i];
            storage.erase(skipRef);
            storage.erase(stepLabelRef);
            storage.erase(updateRef);
            storage.erase(backRef);
            context.builder->invalidateControlFlowGraph();
            context.passChanged = true;
            return true;
        }
        return false;
    }

    // A two-way count comparison can place its advancing step before the
    // header. Mismatches then branch backward to the step and fall through
    // the next comparison, instead of paying an unconditional back edge on
    // every advance. The one-time entry jumps over that step.
    bool placeMismatchStepBeforeHeader(MicroPassContext& context, const std::vector<MicroInstrRef>& order)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;
        for (uint32_t header = 0; header + 9 < order.size(); ++header)
        {
            const MicroInstr*        headerInst = storage.ptr(order[header]);
            const MicroInstrOperand* headerOps  = headerInst ? headerInst->ops(operands) : nullptr;
            if (!headerInst || headerInst->op != MicroInstrOpcode::Label || !headerOps)
                continue;

            for (uint32_t loads = 1; loads <= 2; ++loads)
            {
                const uint32_t compare = header + 1 + loads;
                if (compare + 6 >= order.size())
                    break;
                bool indexedLoads = true;
                for (uint32_t i = header + 1; i < compare; ++i)
                    indexedLoads &= storage.ptr(order[i])->op == MicroInstrOpcode::LoadAmcRegMem;
                if (!indexedLoads)
                    continue;

                const MicroInstr* cmp         = storage.ptr(order[compare]);
                const MicroInstr* equal       = storage.ptr(order[compare + 1]);
                const MicroInstr* lessOrEqual = storage.ptr(order[compare + 2]);
                const MicroInstr* stepLabel   = storage.ptr(order[compare + 3]);
                const MicroInstr* update      = storage.ptr(order[compare + 4]);
                const MicroInstr* back        = storage.ptr(order[compare + 5]);
                const MicroInstr* tieLabel    = storage.ptr(order[compare + 6]);
                if (!cmp || !equal || !lessOrEqual || !stepLabel || !update || !back || !tieLabel ||
                    (cmp->op != MicroInstrOpcode::CmpAmcReg && cmp->op != MicroInstrOpcode::CmpRegReg) ||
                    equal->op != MicroInstrOpcode::JumpCond || lessOrEqual->op != MicroInstrOpcode::JumpCond ||
                    stepLabel->op != MicroInstrOpcode::Label || update->op != MicroInstrOpcode::OpBinaryRegImm ||
                    back->op != MicroInstrOpcode::JumpCond || tieLabel->op != MicroInstrOpcode::Label ||
                    equal->numOperands < 3 || lessOrEqual->numOperands < 3 ||
                    update->numOperands < 4 || back->numOperands < 3)
                    continue;

                const MicroInstrOperand* equalOps  = equal->ops(operands);
                const MicroInstrOperand* lessOps   = lessOrEqual->ops(operands);
                const MicroInstrOperand* stepOps   = stepLabel->ops(operands);
                const MicroInstrOperand* updateOps = update->ops(operands);
                const MicroInstrOperand* backOps   = back->ops(operands);
                const MicroInstrOperand* tieOps    = tieLabel->ops(operands);
                if (!equalOps || !lessOps || !stepOps || !updateOps || !backOps || !tieOps ||
                    equalOps[0].cpuCond != MicroCond::Equal || lessOps[0].cpuCond != MicroCond::BelowOrEqual ||
                    equalOps[2].valueU64 != tieOps[0].valueU64 ||
                    backOps[0].cpuCond != MicroCond::Unconditional || backOps[2].valueU64 != headerOps[0].valueU64 ||
                    (updateOps[2].microOp != MicroOp::Add && updateOps[2].microOp != MicroOp::Subtract) ||
                    updateOps[1].opBits != MicroOpBits::B64 || updateOps[3].valueU64 != 1)
                    continue;

                const uint64_t    mismatchLabelId = context.builder->createLabel().get();
                MicroInstrOperand entryJump[3]    = {backOps[0], backOps[1], backOps[2]};
                MicroInstrOperand mismatchLabelOps[1];
                mismatchLabelOps[0].valueU64      = mismatchLabelId;
                MicroInstrOperand exitJump[3]     = {lessOps[0], lessOps[1], lessOps[2]};
                MicroInstrOperand stepLabelOps[1] = {stepOps[0]};
                MicroInstrOperand updateCopy[4]   = {updateOps[0], updateOps[1], updateOps[2], updateOps[3]};

                storage.insertDerivedBefore(operands, order[header], MicroInstrOpcode::JumpCond, entryJump);
                storage.insertDerivedBefore(operands, order[header], MicroInstrOpcode::Label, mismatchLabelOps);
                storage.insertDerivedBefore(operands, order[header], MicroInstrOpcode::JumpCond, exitJump);
                storage.insertDerivedBefore(operands, order[header], MicroInstrOpcode::Label, stepLabelOps);
                storage.insertDerivedBefore(operands, order[header], MicroInstrOpcode::OpBinaryRegImm, updateCopy);

                MicroInstr*        rewrittenEqual = storage.ptr(order[compare + 1]);
                MicroInstrOperand* rewrittenOps   = rewrittenEqual->ops(operands);
                rewrittenOps[0].cpuCond           = MicroCond::NotEqual;
                rewrittenOps[2].valueU64          = mismatchLabelId;
                storage.erase(order[compare + 2]);
                storage.erase(order[compare + 3]);
                storage.erase(order[compare + 4]);
                storage.erase(order[compare + 5]);
                context.builder->invalidateControlFlowGraph();
                context.passChanged = true;
                return true;
            }
        }
        return false;
    }
}

Result MicroPostRaLoopRotatePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    if (!context.builder)
        return Result::Continue;

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;
    if (storage.count() < 4)
        return Result::Continue;

    // Recognition does not mutate the listing. Index all incoming jumps once;
    // every header can then check its unique back edge without rescanning the function.
    struct JumpTarget
    {
        uint32_t count   = 0;
        uint32_t ordinal = 0;
    };
    std::unordered_map<uint32_t, JumpTarget> jumpsByTarget;
    std::vector<MicroInstrRef>               order;
    bool                                     hasJumpCond = false;
    order.reserve(storage.count());
    for (auto it = storage.view().begin(), endIt = storage.view().end(); it != endIt; ++it)
    {
        const auto ordinal = static_cast<uint32_t>(order.size());
        order.push_back(it.current);
        if (it->op != MicroInstrOpcode::JumpCond)
            continue;
        hasJumpCond = true;
        uint32_t target = 0;
        if (!tryGetJumpTargetLabelId(target, *it, it->ops(operands)))
            continue;
        auto& incoming = jumpsByTarget[target];
        ++incoming.count;
        incoming.ordinal = ordinal;
    }

    if (!hasJumpCond)
        return Result::Continue;

    if (threadRepeatedIndexedZeroTest(context, order))
        return Result::Continue;
    if (placeShortLoopStep(context, order))
        return Result::Continue;
    if (placeMismatchStepBeforeHeader(context, order))
        return Result::Continue;
    if (rotateLatchConnectors(context, order))
        return Result::Continue;

    // Every rotation needs an incoming jump to its header.
    if (jumpsByTarget.empty())
        return Result::Continue;

    // Copying an instruction that carries a relocation would need the
    // relocation cloned onto both copies; no test shape observed here does, so
    // such a header is left alone rather than handled.
    std::optional<std::unordered_set<uint32_t>> relocatedInstructions;

    SmallVector<Rotation> rotations;

    for (uint32_t ordinal = 0; ordinal + 3 < order.size(); ++ordinal)
    {
        const MicroInstr* labelInst = storage.ptr(order[ordinal]);
        if (!labelInst)
            continue;
        uint32_t labelId = 0;
        if (!tryGetLabelId(labelId, *labelInst, labelInst->ops(operands)))
            continue;

        // A header without one incoming jump cannot rotate, regardless of
        // its test run. The incoming-jump index stays fixed during recognition.
        const auto incoming = jumpsByTarget.find(labelId);
        if (incoming == jumpsByTarget.end() || incoming->second.count != 1)
            continue;

        // The test run: one duplicable compare, possibly surrounded by
        // connectors, closed by the conditional jump.
        const uint32_t testBegin = ordinal + 1;
        uint32_t       testEnd   = testBegin;
        bool           haveTest  = false;
        bool           closed    = false;
        for (; testEnd < order.size() && testEnd - testBegin <= K_MAX_TEST_RUN; ++testEnd)
        {
            const MicroInstr* testInst = storage.ptr(order[testEnd]);
            if (!testInst)
                break;
            if (testInst->op == MicroInstrOpcode::JumpCond)
            {
                closed = haveTest;
                break;
            }
            if (isDuplicableTest(*testInst))
            {
                if (haveTest)
                    break;
                haveTest = true;
            }
            else if (!isDuplicableConnector(*testInst))
            {
                break;
            }
        }
        if (!closed || testEnd + 1 >= order.size())
            continue;

        const MicroInstrRef      jccRef  = order[testEnd];
        const MicroInstr*        jccInst = storage.ptr(jccRef);
        const MicroInstrOperand* jccOps  = jccInst->ops(operands);
        if (!jccOps || jccInst->numOperands < 3)
            continue;
        const MicroCond cond = jccOps[0].cpuCond;
        if (cond == MicroCond::Unconditional)
            continue;
        uint32_t exitLabelId = 0;
        if (!tryGetJumpTargetLabelId(exitLabelId, *jccInst, jccOps) || exitLabelId == labelId)
            continue;

        // The back edge must be the only jump aimed at this label, and
        // unconditional. A second one would keep re-entering above the test
        // this rotation stops re-running.
        const uint32_t backOrdinal = incoming->second.ordinal;
        if (backOrdinal <= testEnd)
            continue;
        const MicroInstrRef      backRef  = order[backOrdinal];
        const MicroInstr*        backInst = storage.ptr(backRef);
        const MicroInstrOperand* backOps  = backInst->ops(operands);
        if (backOps[0].cpuCond != MicroCond::Unconditional)
            continue;

        // Falling out of the rotated back edge must land where the header test
        // used to send control, which it does exactly when the exit label is
        // what physically follows the back edge.
        if (backOrdinal + 1 >= order.size())
            continue;
        const MicroInstr* afterBack = storage.ptr(order[backOrdinal + 1]);
        uint32_t          afterId   = 0;
        if (!afterBack || !tryGetLabelId(afterId, *afterBack, afterBack->ops(operands)) || afterId != exitLabelId)
            continue;

        MicroCond inverted = MicroCond::Unconditional;
        if (!invertCondition(cond, inverted))
            continue;

        // The whole shape is known before a relocation snapshot is needed.
        // A relocated test or connector cannot be duplicated at the back edge.
        if (!relocatedInstructions)
        {
            relocatedInstructions.emplace();
            for (const MicroRelocation& reloc : context.builder->codeRelocations())
            {
                if (reloc.instructionRef.isValid())
                    relocatedInstructions->insert(reloc.instructionRef.get());
            }
        }
        bool hasRelocatedTest = false;
        for (uint32_t testOrdinal = testBegin; testOrdinal < testEnd; ++testOrdinal)
        {
            if (relocatedInstructions->contains(order[testOrdinal].get()))
            {
                hasRelocatedTest = true;
                break;
            }
        }
        if (hasRelocatedTest)
            continue;

        rotations.push_back({.testBegin = testBegin, .testEnd = testEnd, .jccRef = jccRef, .bodyFirstRef = order[testEnd + 1], .backRef = backRef, .inverted = inverted});
    }

    if (rotations.empty())
        return Result::Continue;

    for (const Rotation& rotation : rotations)
    {
        const MicroInstr* jccInst = storage.ptr(rotation.jccRef);
        if (!jccInst)
            continue;
        const MicroInstrOperand* jccOps = jccInst->ops(operands);
        if (!jccOps)
            continue;
        const MicroInstrOperand jccOpBits = jccOps[1];

        const uint64_t bodyLabelId = context.builder->createLabel().get();

        MicroInstrOperand bodyLabelOps[1];
        bodyLabelOps[0].valueU64 = bodyLabelId;
        storage.insertDerivedBefore(operands, rotation.bodyFirstRef, MicroInstrOpcode::Label, bodyLabelOps);

        // The test run is copied in order; each instruction is captured
        // before the insertion that may move the storage under it.
        for (uint32_t ordinal = rotation.testBegin; ordinal < rotation.testEnd; ++ordinal)
        {
            const MicroInstr* testInst = storage.ptr(order[ordinal]);
            SWC_ASSERT(testInst);
            const MicroInstrOperand* testOps = testInst->ops(operands);
            SWC_ASSERT(testOps);
            SmallVector<MicroInstrOperand, 8> testCopy;
            for (uint32_t i = 0; i < testInst->numOperands; ++i)
                testCopy.push_back(testOps[i]);
            const MicroInstrOpcode testOp = testInst->op;
            storage.insertDerivedBefore(operands, rotation.backRef, testOp, {testCopy.data(), testCopy.size()});
        }

        const MicroInstr* backInst = storage.ptr(rotation.backRef);
        if (!backInst || backInst->numOperands < 3)
            continue;
        MicroInstrOperand* backOps = backInst->ops(operands);
        if (!backOps)
            continue;
        backOps[0].cpuCond  = rotation.inverted;
        backOps[1]          = jccOpBits;
        backOps[2].valueU64 = bodyLabelId;
    }

    context.builder->invalidateControlFlowGraph();
    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
