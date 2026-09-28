#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"
#include "Support/Report/Assert.h"

// Post-RA peephole optimization on physical registers.
//
// Architecture
// ------------
// Mirrors instruction-combine on purpose:
// - rules are small self-contained functions;
// - rules are registered by anchor opcode;
// - scans batch Actions and apply them after the walk finishes.
//
// This keeps the pass cheap today while making it easy to add more post-RA
// cleanup rules later without growing one large if/else cascade.

SWC_BEGIN_NAMESPACE();

namespace
{
    using namespace PostRaPeephole;

    // Put a frame reload on the fallthrough edge of a join when every jump
    // into that join already carries the stored value in the same register.
    // A loop's common branch can then skip a reload needed only after its
    // uncommon branch has reused the register.
    bool sinkFrameReloadToFallthrough(MicroPassContext& context)
    {
        if (!context.builder)
            return false;

        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;
        const auto&          cfg      = context.builder->controlFlowGraph();
        if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
            return false;

        const auto     refs = cfg.instructionRefs();
        const CallConv& conv = CallConv::get(context.callConvKind);
        constexpr uint32_t K_MAX_BACKTRACK = 256;
        for (uint32_t labelIndex = 1; labelIndex + 1 < refs.size(); ++labelIndex)
        {
            const MicroInstr* label = storage.ptr(refs[labelIndex]);
            const MicroInstr* load  = storage.ptr(refs[labelIndex + 1]);
            const auto*       at    = load && load->op == MicroInstrOpcode::LoadRegMem ? load->ops(operands) : nullptr;
            if (!label || label->op != MicroInstrOpcode::Label || !at ||
                !at[0].reg.isInt() || at[1].reg != conv.stackPointer || at[0].reg == at[1].reg ||
                at[2].opBits != MicroOpBits::B64 ||
                std::ranges::find(cfg.addressTakenLabelIndices(), labelIndex) != cfg.addressTakenLabelIndices().end())
                continue;

            const auto& incoming = cfg.predecessors(labelIndex);
            if (incoming.size() < 2 || std::ranges::find(incoming, labelIndex - 1) == incoming.end())
                continue;
            const MicroInstr* fallthrough = storage.ptr(refs[labelIndex - 1]);
            if (!fallthrough || MicroInstr::info(fallthrough->op).flags.has(MicroInstrFlagsE::TerminatorInstruction))
                continue;

            bool valid = true;
            for (const uint32_t jumpIndex : incoming)
            {
                if (jumpIndex == labelIndex - 1)
                    continue;
                const MicroInstr* jump    = storage.ptr(refs[jumpIndex]);
                const auto*       jumpOps = jump && jump->op == MicroInstrOpcode::JumpCond ? jump->ops(operands) : nullptr;
                if (!jumpOps ||
                    std::ranges::find(cfg.successors(jumpIndex), labelIndex) == cfg.successors(jumpIndex).end() ||
                    jumpIndex >= labelIndex)
                {
                    valid = false;
                    break;
                }

                // Every backward path must reach a matching frame store (or
                // reload) before a register change or a memory write. The
                // bounded walk deliberately rejects complicated joins.
                std::vector<uint32_t> pending = {jumpIndex};
                std::unordered_set<uint32_t> visited;
                while (!pending.empty() && valid)
                {
                    const uint32_t index = pending.back();
                    pending.pop_back();
                    if (!visited.insert(index).second)
                    {
                        valid = false;
                        break;
                    }
                    // A back edge may reach a store at the preceding loop
                    // latch. Never use the reload being moved as its own
                    // proof of register/frame equivalence.
                    if (visited.size() > K_MAX_BACKTRACK || index == labelIndex + 1)
                    {
                        valid = false;
                        break;
                    }
                    const MicroInstr* inst = storage.ptr(refs[index]);
                    if (!inst)
                    {
                        valid = false;
                        break;
                    }
                    const auto* ops = inst->ops(operands);
                    if (ops && inst->op == MicroInstrOpcode::LoadMemReg &&
                        ops[0].reg == at[1].reg && ops[1].reg == at[0].reg &&
                        ops[2].opBits == at[2].opBits && ops[3].valueU64 == at[3].valueU64)
                        continue;
                    if (ops && inst->op == MicroInstrOpcode::LoadRegMem &&
                        ops[0].reg == at[0].reg && ops[1].reg == at[1].reg &&
                        ops[2].opBits == at[2].opBits && ops[3].valueU64 == at[3].valueU64)
                        continue;
                    if (MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::WritesMemory) ||
                        MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                    {
                        valid = false;
                        break;
                    }
                    const MicroInstrUseDef useDef = inst->collectUseDef(operands, context.encoder);
                    if (std::ranges::find(useDef.defs, at[0].reg) != useDef.defs.end() ||
                        std::ranges::find(useDef.defs, at[1].reg) != useDef.defs.end() ||
                        cfg.predecessors(index).empty())
                    {
                        valid = false;
                        break;
                    }
                    for (const uint32_t predecessor : cfg.predecessors(index))
                        pending.push_back(predecessor);
                }
                if (!valid)
                    break;
            }
            if (!valid)
                continue;

            MicroInstrOperand movedOps[4];
            std::copy_n(at, 4, movedOps);
            storage.insertDerivedBefore(operands, refs[labelIndex], MicroInstrOpcode::LoadRegMem, movedOps);
            storage.erase(refs[labelIndex + 1]);
            return true;
        }
        return false;
    }

    // A spill store may be delayed until the sole branch that reads its home.
    // Restrict this to allocator-owned slots: program pointers cannot reach
    // them, and every explicit frame access can be checked by its offset.
    bool sinkFrameStoreIntoBranchTarget(MicroPassContext& context)
    {
        if (!context.builder || context.spillAreaLo >= context.spillAreaHi ||
            context.spillAreaHi - context.spillAreaLo < sizeof(uint64_t))
            return false;

        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;
        const auto&          cfg      = context.builder->controlFlowGraph();
        if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
            return false;

        const auto      refs = cfg.instructionRefs();
        const MicroReg  stack = CallConv::get(context.callConvKind).stackPointer;
        for (uint32_t storeIndex = 0; storeIndex + 2 < refs.size(); ++storeIndex)
        {
            const MicroInstr* store = storage.ptr(refs[storeIndex]);
            const auto*       saved = store && store->op == MicroInstrOpcode::LoadMemReg ? store->ops(operands) : nullptr;
            if (!saved || saved[0].reg != stack || !saved[1].reg.isInt() || saved[1].reg == stack ||
                saved[2].opBits != MicroOpBits::B64 || saved[3].valueU64 < context.spillAreaLo ||
                saved[3].valueU64 > context.spillAreaHi - sizeof(uint64_t))
                continue;

            const MicroReg value  = saved[1].reg;
            const uint64_t offset = saved[3].valueU64;
            uint32_t       reloadIndex = MicroControlFlowGraph::K_NO_INDEX;
            bool           slotOpaque  = false;
            std::vector<uint32_t> sameStores;
            for (uint32_t index = 0; index < refs.size(); ++index)
            {
                const MicroInstr* inst = storage.ptr(refs[index]);
                if (!inst)
                {
                    slotOpaque = true;
                    break;
                }
                const auto* ops  = inst->ops(operands);
                const auto& info = MicroInstr::info(inst->op);
                const bool indexedMemory = inst->op == MicroInstrOpcode::LoadAmcRegMem ||
                                           inst->op == MicroInstrOpcode::LoadSignedExtAmcRegMem ||
                                           inst->op == MicroInstrOpcode::LoadZeroExtAmcRegMem ||
                                           inst->op == MicroInstrOpcode::LoadAmcMemReg ||
                                           inst->op == MicroInstrOpcode::LoadAmcMemImm ||
                                           inst->op == MicroInstrOpcode::OpBinaryRegAmcMem ||
                                           inst->op == MicroInstrOpcode::OpUnaryAmcMem ||
                                           inst->op == MicroInstrOpcode::OpBinaryAmcMemReg ||
                                           inst->op == MicroInstrOpcode::OpBinaryAmcMemImm ||
                                           inst->op == MicroInstrOpcode::CmpAmcImm ||
                                           inst->op == MicroInstrOpcode::CmpAmcReg ||
                                           inst->op == MicroInstrOpcode::VecUnaryAmcRegMem ||
                                           inst->op == MicroInstrOpcode::CmpRegAmc;
                if (ops && indexedMemory)
                {
                    for (uint8_t operand = 0; operand < std::min<uint8_t>(inst->numOperands, 3); ++operand)
                        slotOpaque = slotOpaque || ops[operand].reg == stack;
                    if (slotOpaque)
                        break;
                }
                if (!ops || !info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) ||
                    ops[info.memBaseOperandIndex].reg != stack)
                    continue;

                const uint64_t accessOffset = ops[info.memOffsetOperandIndex].valueU64;
                uint64_t accessSize = 64;
                if (inst->op == MicroInstrOpcode::LoadRegMem || inst->op == MicroInstrOpcode::LoadMemReg)
                    accessSize = getNumBytes(ops[2].opBits);
                else if (inst->op == MicroInstrOpcode::LoadMemImm)
                    accessSize = getNumBytes(ops[1].opBits);
                if (accessOffset > offset + 7 || (accessOffset < offset && offset - accessOffset >= accessSize))
                    continue;
                if (inst->op == MicroInstrOpcode::LoadMemReg && accessOffset == offset &&
                    ops[1].reg == value && ops[2].opBits == MicroOpBits::B64)
                {
                    sameStores.push_back(index);
                    continue;
                }
                if (inst->op == MicroInstrOpcode::LoadRegMem && accessOffset == offset &&
                    ops[2].opBits == MicroOpBits::B64 && reloadIndex == MicroControlFlowGraph::K_NO_INDEX)
                {
                    reloadIndex = index;
                    continue;
                }
                slotOpaque = true;
                break;
            }
            if (slotOpaque || reloadIndex == MicroControlFlowGraph::K_NO_INDEX || reloadIndex <= storeIndex)
                continue;

            for (uint32_t labelIndex = storeIndex + 1; labelIndex < reloadIndex; ++labelIndex)
            {
                const MicroInstr* label = storage.ptr(refs[labelIndex]);
                const MicroInstr* targetFirst = labelIndex + 1 < refs.size() ? storage.ptr(refs[labelIndex + 1]) : nullptr;
                if (!label || label->op != MicroInstrOpcode::Label || cfg.predecessors(labelIndex).size() != 1 ||
                    std::ranges::find(cfg.addressTakenLabelIndices(), labelIndex) != cfg.addressTakenLabelIndices().end() ||
                    !targetFirst || targetFirst->op == MicroInstrOpcode::Label)
                    continue;
                const uint32_t branchIndex = cfg.predecessors(labelIndex)[0];
                const MicroInstr* branch = storage.ptr(refs[branchIndex]);
                if (!branch || branch->op != MicroInstrOpcode::JumpCond || branchIndex <= storeIndex ||
                    branchIndex >= labelIndex)
                    continue;

                // The target must dominate its only reader, even through the
                // loop back edge. Otherwise delaying the write leaves a path
                // that can observe an older slot value.
                std::vector<uint32_t> pending = {0};
                std::vector<uint8_t>  seen(refs.size(), 0);
                bool                  dominates = true;
                while (!pending.empty() && dominates)
                {
                    const uint32_t index = pending.back();
                    pending.pop_back();
                    if (index == labelIndex || seen[index])
                        continue;
                    seen[index] = 1;
                    if (index == reloadIndex)
                    {
                        dominates = false;
                        break;
                    }
                    for (const uint32_t successor : cfg.successors(index))
                        pending.push_back(successor);
                }
                if (!dominates)
                    continue;

                // A matching offset names the same slot only when the stack
                // pointer has the same value at the moved store and the read.
                // Track balanced outgoing-call adjustments on every route.
                std::vector<uint8_t> reachesRead(refs.size(), 0);
                pending.assign(1, reloadIndex);
                while (!pending.empty())
                {
                    const uint32_t index = pending.back();
                    pending.pop_back();
                    if (reachesRead[index])
                        continue;
                    reachesRead[index] = 1;
                    for (const uint32_t predecessor : cfg.predecessors(index))
                        pending.push_back(predecessor);
                }
                std::vector<int64_t> stackDelta(refs.size(), INT64_MIN);
                pending.assign(1, labelIndex);
                stackDelta[labelIndex] = 0;
                bool stableStack = true;
                while (!pending.empty() && stableStack)
                {
                    const uint32_t index = pending.back();
                    pending.pop_back();
                    if (!reachesRead[index])
                        continue;
                    const MicroInstr* inst = storage.ptr(refs[index]);
                    if (!inst)
                    {
                        stableStack = false;
                        break;
                    }
                    const MicroInstrUseDef useDef = inst->collectUseDef(operands, context.encoder);
                    int64_t                nextDelta = stackDelta[index];
                    if (std::ranges::find(useDef.defs, stack) != useDef.defs.end())
                    {
                        const auto* ops = inst->ops(operands);
                        if (inst->op == MicroInstrOpcode::OpBinaryRegImm && ops && ops[0].reg == stack &&
                            ops[1].opBits == MicroOpBits::B64 && ops[3].valueU64 <= 0x100000 &&
                            (ops[2].microOp == MicroOp::Add || ops[2].microOp == MicroOp::Subtract))
                            nextDelta += ops[2].microOp == MicroOp::Add ? static_cast<int64_t>(ops[3].valueU64) :
                                                                      -static_cast<int64_t>(ops[3].valueU64);
                        else if (inst->op == MicroInstrOpcode::Push)
                            nextDelta -= 8;
                        else if (inst->op == MicroInstrOpcode::Pop)
                            nextDelta += 8;
                        else
                        {
                            stableStack = false;
                            break;
                        }
                    }
                    if (nextDelta > 0 || (index == reloadIndex && nextDelta != 0))
                    {
                        stableStack = false;
                        break;
                    }
                    if (index != reloadIndex)
                    {
                        for (const uint32_t successor : cfg.successors(index))
                        {
                            if (!reachesRead[successor])
                                continue;
                            if (stackDelta[successor] == INT64_MIN)
                            {
                                stackDelta[successor] = nextDelta;
                                pending.push_back(successor);
                            }
                            else if (stackDelta[successor] != nextDelta)
                            {
                                stableStack = false;
                                break;
                            }
                        }
                    }
                }
                if (!stableStack)
                    continue;

                // On every incoming path, the register must still equal the
                // slot's last value. A later loop-latch store is also a valid
                // source; the store we move is the source on the first trip.
                pending.assign(1, branchIndex);
                std::unordered_set<uint32_t> visited;
                bool valid = true;
                while (!pending.empty() && valid)
                {
                    const uint32_t index = pending.back();
                    pending.pop_back();
                    if (!visited.insert(index).second || visited.size() > 256)
                    {
                        valid = false;
                        break;
                    }
                    const MicroInstr* inst = storage.ptr(refs[index]);
                    if (!inst)
                    {
                        valid = false;
                        break;
                    }
                    const auto* ops = inst->ops(operands);
                    if (ops && inst->op == MicroInstrOpcode::LoadMemReg &&
                        ops[0].reg == stack && ops[1].reg == value &&
                        ops[2].opBits == MicroOpBits::B64 && ops[3].valueU64 == offset)
                        continue;
                    if (index == reloadIndex ||
                        MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::WritesMemory) ||
                        MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                    {
                        valid = false;
                        break;
                    }
                    const MicroInstrUseDef useDef = inst->collectUseDef(operands, context.encoder);
                    if (std::ranges::find(useDef.defs, value) != useDef.defs.end() ||
                        std::ranges::find(useDef.defs, stack) != useDef.defs.end() ||
                        cfg.predecessors(index).empty())
                    {
                        valid = false;
                        break;
                    }
                    for (const uint32_t predecessor : cfg.predecessors(index))
                        pending.push_back(predecessor);
                }
                if (!valid)
                    continue;

                // A later write to this private slot is dead when every route
                // from that write to the sole read crosses the new cold-entry
                // store. This removes the loop-latch write on the hot path.
                std::vector<MicroInstrRef> deadStores;
                for (const uint32_t otherStore : sameStores)
                {
                    if (otherStore == storeIndex)
                        continue;
                    pending.clear();
                    for (const uint32_t successor : cfg.successors(otherStore))
                        pending.push_back(successor);
                    std::fill(seen.begin(), seen.end(), 0);
                    bool readBeforeCold = false;
                    while (!pending.empty() && !readBeforeCold)
                    {
                        const uint32_t index = pending.back();
                        pending.pop_back();
                        if (index == labelIndex || seen[index])
                            continue;
                        seen[index] = 1;
                        if (index == reloadIndex)
                        {
                            readBeforeCold = true;
                            break;
                        }
                        for (const uint32_t successor : cfg.successors(index))
                            pending.push_back(successor);
                    }
                    if (!readBeforeCold)
                        deadStores.push_back(refs[otherStore]);
                }
                if (deadStores.empty())
                    continue;

                MicroInstrOperand movedOps[4];
                std::copy_n(saved, 4, movedOps);
                storage.insertDerivedBefore(operands, refs[labelIndex + 1], MicroInstrOpcode::LoadMemReg, movedOps);
                storage.erase(refs[storeIndex]);
                for (const MicroInstrRef deadStore : deadStores)
                    storage.erase(deadStore);
                return true;
            }
        }
        return false;
    }

    // A RIP load needed only on one side of a forward branch need not run on
    // the other side. Keep this after allocation: moving it earlier changes
    // physical-register pressure, while moving it into the sole successor
    // leaves allocation and the successful path's instruction count intact.
    bool sinkRipLoadIntoBranchTarget(MicroPassContext& context)
    {
        if (!context.builder)
            return false;

        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;
        const auto&          cfg      = context.builder->controlFlowGraph();
        if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
            return false;

        const auto refs = cfg.instructionRefs();
        thread_local MicroPassHelpers::MicroPhysLiveness liveness;
        bool livenessReady = false;
        for (MicroRelocation& relocation : context.builder->codeRelocations())
        {
            if (relocation.form != MicroRelocation::Form::Relative32 ||
                (relocation.kind != MicroRelocation::Kind::ConstantAddress &&
                relocation.kind != MicroRelocation::Kind::GlobalInitAddress &&
                relocation.kind != MicroRelocation::Kind::GlobalZeroAddress))
                continue;

            const uint32_t loadIndex = cfg.indexOf(relocation.instructionRef);
            if (loadIndex == MicroControlFlowGraph::K_NO_INDEX || loadIndex + 3 >= refs.size())
                continue;
            const MicroInstr* load = storage.ptr(refs[loadIndex]);
            const auto*       ops  = load ? load->ops(operands) : nullptr;
            if (!load || load->op != MicroInstrOpcode::LoadRegMem || !ops ||
                ops[1].reg != MicroReg::instructionPointer())
                continue;

            const MicroReg dst = ops[0].reg;
            if (MicroPassHelpers::MicroPhysLiveness::bitOf(dst) == MicroPassHelpers::MicroPhysLiveness::K_INVALID_BIT)
                continue;

            // Require a straight-line region. No intervening instruction may
            // consume or redefine the loaded register, call, or write memory
            // before the branch.
            const uint32_t limit = static_cast<uint32_t>(refs.size());
            for (uint32_t branchIndex = loadIndex + 1; branchIndex < limit; ++branchIndex)
            {
                const MicroInstr* inst = storage.ptr(refs[branchIndex]);
                if (!inst || cfg.predecessors(branchIndex).size() != 1 ||
                    cfg.predecessors(branchIndex)[0] != branchIndex - 1)
                    break;
                if (inst->op == MicroInstrOpcode::JumpCond)
                {
                    const auto& successors = cfg.successors(branchIndex);
                    if (successors.size() != 2)
                        break;
                    const uint32_t target = successors[0];
                    if (target <= branchIndex + 1 || target + 1 >= refs.size() ||
                        cfg.predecessors(target).size() != 1 || cfg.predecessors(target)[0] != branchIndex ||
                        cfg.predecessors(target + 1).size() != 1 || cfg.predecessors(target + 1)[0] != target)
                        break;
                    const MicroInstr* targetInst = storage.ptr(refs[target]);
                    const MicroInstr* nextInst   = storage.ptr(refs[target + 1]);
                    if (!targetInst || targetInst->op != MicroInstrOpcode::Label ||
                        !nextInst || nextInst->op == MicroInstrOpcode::Label ||
                        std::ranges::find(cfg.addressTakenLabelIndices(), target) != cfg.addressTakenLabelIndices().end())
                        break;

                    if (!livenessReady)
                    {
                        MicroPassHelpers::computePhysicalLiveness(liveness, context);
                        livenessReady = true;
                    }
                    const uint32_t bit = MicroPassHelpers::MicroPhysLiveness::bitOf(dst);
                    if (!liveness.valid || !(liveness.liveIn[target] & (1ull << bit)) ||
                        (liveness.liveIn[branchIndex + 1] & (1ull << bit)))
                        break;

                    MicroInstrOperand movedOps[4];
                    std::copy_n(ops, 4, movedOps);
                    const MicroInstrRef moved = storage.insertDerivedBefore(operands, refs[target + 1], MicroInstrOpcode::LoadRegMem,
                                                                            movedOps);
                    relocation.instructionRef = moved;
                    storage.erase(refs[loadIndex]);
                    return true;
                }

                const MicroInstrUseDef useDef = inst->collectUseDef(operands, context.encoder);
                if (std::ranges::find(useDef.uses, dst) != useDef.uses.end() ||
                    std::ranges::find(useDef.defs, dst) != useDef.defs.end() ||
                    useDef.isCall || MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::WritesMemory) ||
                    MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    break;
            }
        }
        return false;
    }

    PatternRegistry buildRegistry()
    {
        PatternRegistry r;
        r.add(MicroInstrOpcode::Nop, tryEraseTrivial);
        r.add(MicroInstrOpcode::ClearReg, tryEraseScalarReturnConversionClear);
        r.add(MicroInstrOpcode::LoadRegReg, tryEraseTrivial);
        r.add(MicroInstrOpcode::LoadRegReg, tryEraseZeroExtendedSelfCopy);
        r.add(MicroInstrOpcode::LoadZeroExtRegMem, tryEraseByteZeroExtendAfterSubtract);
        r.add(MicroInstrOpcode::LoadZeroExtAmcRegMem, tryEraseByteZeroExtendAfterSubtract);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldByteLoadSubtractExtend);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldFloatReturnSelectDiamond);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldFloatReturnXorCopyChain);
        r.add(MicroInstrOpcode::JumpCond, tryEraseTrivial);
        r.add(MicroInstrOpcode::JumpCond, tryInvertBranchOverJump);
        r.add(MicroInstrOpcode::JumpCond, tryShareReturnEpilogue);
        r.add(MicroInstrOpcode::CmpRegImm, tryFoldConditionalBitwiseNot);
        r.add(MicroInstrOpcode::CmpRegImm, tryFactorCommonConditionalShiftNoCopy);
        r.add(MicroInstrOpcode::CmpRegImm, tryFactorCommonConditionalShiftBare);
        r.add(MicroInstrOpcode::CmpRegImm, tryReuseFlagsForCompare);
        r.add(MicroInstrOpcode::TestMemReg, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::TestMemImm, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::TestRegReg, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::TestRegImm, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::CmpRegReg, tryReuseAddFlagsForUnsignedWrap);
        r.add(MicroInstrOpcode::CmpRegReg, tryFactorCommonConditionalShiftNoCopy);
        r.add(MicroInstrOpcode::CmpRegReg, tryFactorCommonConditionalShiftBare);
        r.add(MicroInstrOpcode::CmpRegReg, tryEraseRepeatedCompare);
        r.add(MicroInstrOpcode::CmpRegReg, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::CmpRegImm, tryEraseDeadCompare);
        for (const MicroInstrOpcode op : {MicroInstrOpcode::CmpRegReg, MicroInstrOpcode::CmpRegImm, MicroInstrOpcode::CmpMemReg,
                                          MicroInstrOpcode::CmpMemImm, MicroInstrOpcode::CmpAmcReg, MicroInstrOpcode::CmpAmcImm,
                                          MicroInstrOpcode::TestRegReg, MicroInstrOpcode::TestRegImm, MicroInstrOpcode::TestMemReg,
                                          MicroInstrOpcode::TestMemImm})
            r.add(op, tryEraseCompareAfterBranch);
        r.add(MicroInstrOpcode::CmpMemReg, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::CmpMemImm, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::OpUnaryReg, tryFoldCarryMask);
        r.add(MicroInstrOpcode::OpUnaryReg, tryFoldZeroComparisonMask);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldZeroBooleanProduct);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldUnsignedAverage);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldCarryArithmetic);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldCarryComparisonSum);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldZeroTestBooleanSum);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryNarrowBitwiseZeroExtensions);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryUseTestForDeadMask);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldBorrowDifference);
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryFoldConditionalAddSubtract);
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryUseTestForDeadMask);
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryFoldCarryOffset);
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryNarrowShiftedBoolean);
        r.add(MicroInstrOpcode::LoadAddrRegMem, tryShortenAddressUnitOffset);
        r.add(MicroInstrOpcode::LoadAddrRegMem, tryFoldCarryOffset);
        r.add(MicroInstrOpcode::LoadAddrAmcRegMem, tryShortenAddressAdd);
        r.add(MicroInstrOpcode::LoadAddrAmcRegMem, tryFoldScaledAdd);
        r.add(MicroInstrOpcode::LoadAddrAmcRegMem, tryFoldDoubledAddressAdd);
        r.add(MicroInstrOpcode::LoadCondRegReg, tryFoldBooleanOrSelect);
        r.add(MicroInstrOpcode::LoadCondRegReg, tryReuseNegationForSignSelect);
        r.add(MicroInstrOpcode::LoadCondRegReg, tryFoldCarrySelectOfConstants);
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryNarrowZeroExtendedShift);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryFoldSubtractBoolean);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryEraseBooleanRecanonicalization);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryFoldZeroExtendedBooleanCompare);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryExtractHighByte);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryNarrowTruncatedRightShift);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryExtractSignBoolean);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryClearBeforeSetCondition);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryHoistNarrowZeroExtendAcrossUnary);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryFoldNarrowUnsignedAverage);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryRetargetNarrowZeroSelect);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryRetargetNarrowAbsoluteDifference);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryRetargetNarrowSelectCascade);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryWidenNarrowSelectGraph);
        r.add(MicroInstrOpcode::LoadRegImm, tryClearZeroBeforeSelect);
        r.add(MicroInstrOpcode::LoadRegImm, tryFoldConstantBooleanSet);
        r.add(MicroInstrOpcode::LoadRegImm, tryForwardLoadRegImm);
        r.add(MicroInstrOpcode::LoadRegImm, tryEraseRepeatedImmediate);
        r.add(MicroInstrOpcode::LoadRegImm, tryCanonicalizeZeroToClear);
        r.add(MicroInstrOpcode::LoadRegMem, tryFoldLoadIntoTest);
        r.add(MicroInstrOpcode::LoadRegMem, tryFoldDeadScalarIncrement);
        r.add(MicroInstrOpcode::LoadRegMem, tryErasePrivateFrameReloadAfterBranch);
        r.add(MicroInstrOpcode::LoadRegMem, tryFoldLoadIntoNarrowExtract);
        r.add(MicroInstrOpcode::LoadRegMem, tryFoldLoadIntoBinary);
        r.add(MicroInstrOpcode::LoadRegMem, tryEraseFloatClearBeforeFullWrite);
        r.add(MicroInstrOpcode::ClearReg, tryEraseFloatClearBeforeFullWrite);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldClearIntoResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryEraseFloatClearBeforeFullWrite);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldIndexedFloatAccumulation);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldIndexedFloatCompare);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldLoadIntoBinary);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldIndexedByteAverage);
        r.add(MicroInstrOpcode::LoadMemReg, tryEraseOverwrittenStore);
        r.add(MicroInstrOpcode::LoadMemReg, tryEraseRedundantStoreReload);
        r.add(MicroInstrOpcode::LoadMemReg, tryMoveSpillReloadBeforeSourceOverwrite);
        r.add(MicroInstrOpcode::LoadMemReg, tryForwardStoredValueToReload);
        r.add(MicroInstrOpcode::OpBinaryRegMem, tryUseSelfOperandForFloatBinary);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCopyIntoFloatBinary);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCopyIntoIntegerMultiply);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldMultiplyShiftResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldMultiplyIntoResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldFloatBinaryIntoResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCopyIntoVecShiftImm);
        r.add(MicroInstrOpcode::LoadRegReg, tryInvertZeroSelect);
        r.add(MicroInstrOpcode::LoadRegReg, tryInvertResultZeroSelect);
        r.add(MicroInstrOpcode::LoadRegReg, tryRetargetUnaryResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCopyRoundTrip);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldIndexedByteSaturatingAdd);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldByteMultiplySelectCopies);
        r.add(MicroInstrOpcode::LoadRegReg, tryFactorNarrowConditionalShift);
        r.add(MicroInstrOpcode::LoadRegReg, tryFactorCommonConditionalShift);
        r.add(MicroInstrOpcode::LoadRegReg, tryFactorCommonConditionalBinary);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldSelectedIntegerAdd);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCopyIntoIntegerAdd);
        r.add(MicroInstrOpcode::LoadRegReg, tryRetargetAddressResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldMaskedIndexIncrement);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCommutativeAddressCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryCommuteBinaryResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryRetargetFloatConversionBeforeCompare);
        r.add(MicroInstrOpcode::LoadRegReg, tryNarrowShiftCountCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldSignedCeilAverage);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldSignedFloorAverage);
        r.add(MicroInstrOpcode::LoadRegReg, tryNarrowCopyOf32BitResult);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldAddMultiplyResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldIntegerAddResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldUnsignedCeilAverage64);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldUnsignedCeilAverage);
        r.add(MicroInstrOpcode::LoadRegReg, tryRetargetSelectedValueCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryRetargetSelectedIntermediate);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldConditionalCascadeResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldConditionalChainResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldConditionalResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryRetargetNegatedConditionalResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryForwardCopySource);
        r.add(MicroInstrOpcode::LoadRegReg, tryCoalesceLocalCopyChain);
        r.add(MicroInstrOpcode::LoadRegReg, tryForwardCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryEraseRedundantCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryNarrowCopyBefore32BitWrite);
        r.add(MicroInstrOpcode::LoadSignedExtRegReg, tryDropSignExtendBeforeNarrowCompare);
        r.add(MicroInstrOpcode::LoadSignedExtRegReg, tryFoldConditionalCascadeResultCopy);
        return r;
    }

    const PatternRegistry& registry()
    {
        static const PatternRegistry R = buildRegistry();
        return R;
    }

    void runPerInstructionPatterns(Context& ctx)
    {
        const PatternRegistry& reg   = registry();
        const auto             view  = ctx.storage->view();
        const auto             endIt = view.end();
        for (auto it = view.begin(); it != endIt; ++it, ++ctx.instructionIndex)
        {
            for (const PatternFn fn : reg.patternsFor(it->op))
            {
                if (fn(ctx, it.current, *it))
                    break;
            }
        }
    }
}

Result MicroPostRaPeepholePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    if (sinkFrameReloadToFallthrough(context) || sinkFrameStoreIntoBranchTarget(context) || sinkRipLoadIntoBranchTarget(context))
    {
        context.passChanged = true;
        return Result::Continue;
    }

    // Reuse the analysis and rewrite storage on this worker. All facts and
    // claims below belong to one pass run and must be reset before its scan.
    thread_local Context ctx;
    ctx.claimed.clear();
    ctx.actions.clear();
    ctx.instructionIndex      = 0;
    ctx.physicalLivenessReady = false;
    ctx.upperHalfReady        = false;
    ctx.upperHalfValid        = false;

    const CallConv& conv = CallConv::get(context.callConvKind);
    ctx.passContext      = &context;
    ctx.storage          = context.instructions;
    ctx.operands         = context.operands;
    ctx.encoder          = context.encoder;
    ctx.builder          = context.builder;
    ctx.stackPointer     = conv.stackPointer;
    ctx.framePointer     = conv.framePointer;
    ctx.localStackBase   = context.debugStackBasePhysReg;
    ctx.floatReturn      = conv.floatReturn;
    ctx.allowForwarding  = context.isFirstOptimizationSweep;

    eraseRedundantUpperHalfClears(ctx);
    forwardPrivateFrameReloads(ctx);
    runPerInstructionPatterns(ctx);

    if (ctx.actions.empty())
        return Result::Continue;

    for (const Action& action : ctx.actions)
        MicroPeephole::applyAction(ctx, action);

    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
