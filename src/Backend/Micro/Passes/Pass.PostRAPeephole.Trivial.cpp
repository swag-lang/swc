#include "pch.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroOptimizationLimits.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    // A value stored both in its source local and in a spill home can be read
    // from the local while both locations still hold the same bits. Leave the
    // spill store for readers outside the proven region; dead-store elimination
    // removes it only after every reader has gone.
    bool reuseLocalStoresForSpillReloads(MicroPassContext& context)
    {
        if (!context.builder || context.spillAreaLo >= context.spillAreaHi)
            return false;
        const MicroReg stack = CallConv::get(context.callConvKind).stackPointer;
        const MicroReg local = context.debugStackBasePhysReg;
        if (!local.isValid() || local == stack)
            return false;
        auto&       storage  = *context.instructions;
        auto&       operands = *context.operands;
        const auto& cfg      = context.builder->controlFlowGraph();
        const auto  refs     = cfg.instructionRefs();

        // Capture must be in the entry block, before any path can skip it.
        uint32_t capture = MicroControlFlowGraph::K_NO_INDEX;
        for (uint32_t i = 0; i < refs.size(); ++i)
        {
            const auto& inst = *storage.ptr(refs[i]);
            const auto* ops  = inst.ops(operands);
            const auto& info = MicroInstr::info(inst.op);
            if (inst.op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                break;
            if (inst.op == MicroInstrOpcode::LoadRegReg && ops && ops[0].reg == local && ops[1].reg == stack && ops[2].opBits == MicroOpBits::B64)
            {
                capture = i;
                break;
            }
        }
        if (capture == MicroControlFlowGraph::K_NO_INDEX)
            return false;
        uint32_t stableUntil = static_cast<uint32_t>(refs.size());
        for (uint32_t i = capture + 1; i < refs.size(); ++i)
        {
            if (MicroPassHelpers::regTouch(*storage.ptr(refs[i]), operands, local, context.encoder).def)
            {
                stableUntil = i;
                break;
            }
        }

        std::optional<FlatKeyMap<uint64_t>> stackOffsets;
        bool                                changed = false;
        using MicroOptimizationLimits::PostRAPeepholeCommon::K_SPILL_RELOAD_WINDOW;
        for (uint32_t i = capture + 1; i + 1 < stableUntil; ++i)
        {
            const auto& spill = *storage.ptr(refs[i]);
            const auto& saved = *storage.ptr(refs[i + 1]);
            if (spill.op != MicroInstrOpcode::LoadMemReg || saved.op != MicroInstrOpcode::LoadMemReg)
                continue;
            const auto* spillOps = spill.ops(operands);
            const auto* savedOps = saved.ops(operands);
            if (!spillOps || !savedOps || spillOps[0].reg != stack || savedOps[0].reg != local ||
                spillOps[1].reg != savedOps[1].reg || spillOps[2].opBits != MicroOpBits::B64 || savedOps[2].opBits != MicroOpBits::B64)
                continue;
            const uint64_t spillOffset = spillOps[3].valueU64;
            const uint64_t localOffset = savedOps[3].valueU64;
            if (spillOffset < context.spillAreaLo || spillOffset > context.spillAreaHi ||
                8 > context.spillAreaHi - spillOffset || spillOffset > INT32_MAX || localOffset > INT32_MAX)
                continue;
            if (!stackOffsets)
                stackOffsets = MicroPassHelpers::collectStackPointerOffsets(context, refs[capture], 0);
            const auto* offset = stackOffsets->find(refs[i].get());
            if (!offset)
                continue;
            const auto stackDelta = static_cast<int64_t>(*offset);
            if (stackDelta < INT32_MIN || stackDelta > INT32_MAX)
                continue;
            const auto spillLocation = stackDelta + static_cast<int64_t>(spillOffset);
            const auto localLocation = static_cast<int64_t>(localOffset);
            if (spillLocation < localLocation + 8 && localLocation < spillLocation + 8)
                continue;

            const uint32_t end = i + std::min<uint32_t>(K_SPILL_RELOAD_WINDOW, static_cast<uint32_t>(refs.size()) - i);
            for (uint32_t j = i + 2; j < end; ++j)
            {
                auto&       inst = *storage.ptr(refs[j]);
                auto*       ops  = inst.ops(operands);
                const auto& info = MicroInstr::info(inst.op);
                if (inst.op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                    info.flags.has(MicroInstrFlagsE::TerminatorInstruction) || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                    MicroPassHelpers::regTouch(inst, operands, local, context.encoder, stack).def)
                    break;

                if (info.flags.has(MicroInstrFlagsE::WritesMemory))
                {
                    // Normalize both frame bases to the capture, including the
                    // allocator's spill reserve below it. Every other writer is
                    // an alias barrier, including indexed stores.
                    uint64_t writtenOffset = 0;
                    uint64_t writtenSize   = 0;
                    if (ops && (ops[0].reg == local || ops[0].reg == stack))
                    {
                        if (inst.op == MicroInstrOpcode::LoadMemReg || inst.op == MicroInstrOpcode::StoreVecMemReg)
                        {
                            writtenOffset = ops[3].valueU64;
                            writtenSize   = getNumBytes(ops[2].opBits);
                        }
                        else if (inst.op == MicroInstrOpcode::LoadMemImm)
                        {
                            writtenOffset = ops[2].valueU64;
                            writtenSize   = getNumBytes(ops[1].opBits);
                        }
                    }
                    if (!writtenSize || writtenOffset > INT32_MAX)
                        break;
                    const auto writtenLocation = static_cast<int64_t>(writtenOffset) + (ops[0].reg == stack ? stackDelta : 0);
                    if ((writtenLocation < localLocation + 8 && localLocation < writtenLocation + static_cast<int64_t>(writtenSize)) ||
                        (writtenLocation < spillLocation + 8 && spillLocation < writtenLocation + static_cast<int64_t>(writtenSize)))
                        break;
                }
                if (inst.op == MicroInstrOpcode::LoadRegMem && ops && ops[1].reg == stack &&
                    ops[2].opBits == MicroOpBits::B64 && ops[3].valueU64 == spillOffset)
                {
                    ops[1].reg      = local;
                    ops[3].valueU64 = localOffset;
                    changed         = true;
                }
            }
        }
        return changed;
    }

    namespace
    {
        bool labelsHaveSingleReference(const Context& ctx, const uint64_t firstLabelId, const uint64_t secondLabelId)
        {
            uint32_t firstCount  = 0;
            uint32_t secondCount = 0;
            for (const MicroInstr& candidate : ctx.storage->view())
            {
                if (candidate.op != MicroInstrOpcode::JumpCond && candidate.op != MicroInstrOpcode::JumpCondImm &&
                    candidate.op != MicroInstrOpcode::JumpReg && candidate.op != MicroInstrOpcode::JumpTableData)
                    continue;
                const MicroInstrOperand* ops = candidate.ops(*ctx.operands);
                if (!ops)
                    continue;

                if ((candidate.op == MicroInstrOpcode::JumpCond || candidate.op == MicroInstrOpcode::JumpCondImm) &&
                    candidate.numOperands >= 3)
                {
                    firstCount += ops[2].valueU64 == firstLabelId;
                    secondCount += ops[2].valueU64 == secondLabelId;
                }
                else if (candidate.op == MicroInstrOpcode::JumpReg && candidate.numOperands >= 2)
                {
                    for (uint8_t index = 1; index < candidate.numOperands; ++index)
                    {
                        firstCount += ops[index].valueU64 == firstLabelId;
                        secondCount += ops[index].valueU64 == secondLabelId;
                    }
                }
                else if (candidate.op == MicroInstrOpcode::JumpTableData)
                {
                    for (uint8_t index = 0; index < candidate.numOperands; ++index)
                    {
                        firstCount += ops[index].valueU64 == firstLabelId;
                        secondCount += ops[index].valueU64 == secondLabelId;
                    }
                }
                if (firstCount > 1 || secondCount > 1)
                    return false;
            }
            return firstCount == 1 && secondCount == 1;
        }
    }

    // Keep a pointer already held in a persistent register across the
    // collision paths of a table probe. Every path back to its original load
    // must be free of writes to that register or its private frame slot. A
    // spill store is disjoint when allocator metadata places it outside the
    // source local object. A read-only call may intervene: the ABI preserves
    // the register, and the call cannot change the frame slot.
    bool forwardPrivateFrameReloads(Context& ctx)
    {
        if (!ctx.builder || !ctx.localStackBase.isValid())
            return false;

        const MicroControlFlowGraph& cfg = ctx.builder->controlFlowGraph();
        if (cfg.hasUnsupportedControlFlowForCfgLiveness())
            return false;
        const auto      refs    = cfg.instructionRefs();
        const CallConv& conv    = CallConv::get(ctx.passContext->callConvKind);
        bool            changed = false;

        std::optional<FlatKeySet> readOnlyCallRefs;
        const auto                isReadOnlyCall = [&](const MicroInstrRef ref) {
            if (!readOnlyCallRefs)
                readOnlyCallRefs = MicroPassHelpers::collectReadOnlyCallRefs(*ctx.builder);
            return readOnlyCallRefs->contains(ref.get());
        };

        const auto isSourceObjectSlot = [&](const MicroInstrOperand* source) {
            if (!ctx.passContext->sanitizerFunction || source[1].reg != ctx.localStackBase)
                return false;
            const uint64_t offset = source[3].valueU64;
            for (const MicroFrameObject& object : MicroPassHelpers::frameObjects(*ctx.passContext))
            {
                if (object.size >= 8 && offset >= object.offset && offset - object.offset <= object.size - 8)
                    return true;
            }
            return false;
        };

        using MicroOptimizationLimits::PostRAPeepholeTrivial::K_MAX_SPAN;
        // Only predecessors between source and candidate can be visited.
        std::array<uint8_t, K_MAX_SPAN + 1> visited;
        std::vector<uint32_t>               pending;
        for (uint32_t candidateIndex = 1; candidateIndex + 2 < refs.size(); ++candidateIndex)
        {
            const MicroInstrRef candidateRef = refs[candidateIndex];
            const MicroInstr*   candidate    = ctx.instruction(candidateRef);
            const auto*         load         = candidate && candidate->op == MicroInstrOpcode::LoadRegMem ? candidate->ops(*ctx.operands) : nullptr;
            if (!load || !load[0].reg.isInt() || !ctx.isPrivateFrameBase(load[1].reg) || load[2].opBits != MicroOpBits::B64)
                continue;
            const MicroInstr* compare    = ctx.instruction(refs[candidateIndex + 1]);
            const MicroInstr* jump       = ctx.instruction(refs[candidateIndex + 2]);
            const auto*       compareOps = compare && compare->op == MicroInstrOpcode::CmpAmcImm ? compare->ops(*ctx.operands) : nullptr;
            if (!compareOps || compareOps[0].reg != load[0].reg || !jump || jump->op != MicroInstrOpcode::JumpCond)
                continue;

            const uint32_t first = candidateIndex > K_MAX_SPAN ? candidateIndex - K_MAX_SPAN : 0;
            for (uint32_t sourceIndex = candidateIndex; sourceIndex-- > first;)
            {
                const MicroInstr* source    = ctx.instruction(refs[sourceIndex]);
                const auto*       sourceOps = source && source->op == MicroInstrOpcode::LoadRegMem ? source->ops(*ctx.operands) : nullptr;
                if (!sourceOps || !conv.isIntPersistentReg(sourceOps[0].reg) || sourceOps[0].reg == load[0].reg ||
                    sourceOps[1].reg != load[1].reg || sourceOps[2].opBits != load[2].opBits ||
                    sourceOps[3].valueU64 != load[3].valueU64)
                    continue;

                std::optional<bool> sourceObjectSlot;
                const auto          disjointSpillStore = [&](const MicroInstr& step) {
                    if (ctx.passContext->spillAreaLo >= ctx.passContext->spillAreaHi)
                        return false;
                    if (step.op != MicroInstrOpcode::LoadMemReg && step.op != MicroInstrOpcode::LoadMemImm)
                        return false;
                    const MicroInstrOperand* ops = step.ops(*ctx.operands);
                    if (!ops || ops[0].reg != conv.stackPointer)
                        return false;
                    if (!sourceObjectSlot)
                        sourceObjectSlot = isSourceObjectSlot(sourceOps);
                    if (!*sourceObjectSlot)
                        return false;
                    const uint64_t offset = ops[step.op == MicroInstrOpcode::LoadMemReg ? 3 : 2].valueU64;
                    const uint64_t width  = getNumBytes(ops[step.op == MicroInstrOpcode::LoadMemReg ? 2 : 1].opBits);
                    return width && offset >= ctx.passContext->spillAreaLo &&
                           offset <= ctx.passContext->spillAreaHi && width <= ctx.passContext->spillAreaHi - offset;
                };

                visited.fill(0);
                pending.clear();
                pending.push_back(candidateIndex);
                bool valid = true;
                while (!pending.empty() && valid)
                {
                    const uint32_t index = pending.back();
                    pending.pop_back();
                    for (const uint32_t predecessor : cfg.predecessors(index))
                    {
                        if (predecessor == sourceIndex)
                            continue;
                        if (predecessor <= sourceIndex || predecessor >= candidateIndex || visited[predecessor - sourceIndex])
                        {
                            if (predecessor <= sourceIndex || predecessor >= candidateIndex)
                                valid = false;
                            continue;
                        }
                        visited[predecessor - sourceIndex] = 1;
                        const MicroInstr* step             = ctx.instruction(refs[predecessor]);
                        if (!step)
                        {
                            valid = false;
                            break;
                        }
                        if (MicroInstr::info(step->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                        {
                            if (!conv.isIntPersistentReg(load[1].reg) || !isReadOnlyCall(refs[predecessor]))
                            {
                                valid = false;
                                break;
                            }
                        }
                        else if (MicroInstr::info(step->op).flags.has(MicroInstrFlagsE::WritesMemory) &&
                                 !disjointSpillStore(*step))
                        {
                            valid = false;
                            break;
                        }
                        const MicroInstrUseDef useDef = step->collectUseDef(*ctx.operands, ctx.encoder);
                        if (std::ranges::find(useDef.defs, sourceOps[0].reg) != useDef.defs.end() ||
                            std::ranges::find(useDef.defs, load[1].reg) != useDef.defs.end())
                        {
                            valid = false;
                            break;
                        }
                        pending.push_back(predecessor);
                    }
                }
                if (!valid)
                    continue;

                const MicroInstrRef reloadRef       = candidateIndex + 3 < refs.size() ? refs[candidateIndex + 3] : MicroInstrRef::invalid();
                const MicroInstr*   reloadInst      = ctx.instruction(reloadRef);
                const auto*         reload          = reloadInst && reloadInst->op == MicroInstrOpcode::LoadRegMem ? reloadInst->ops(*ctx.operands) : nullptr;
                const bool          redundantReload = reload && reload[0].reg == load[0].reg && reload[1].reg == load[1].reg && reload[2].opBits == load[2].opBits && reload[3].valueU64 == load[3].valueU64;
                if (!redundantReload && ctx.isRegDeadAfter(load[0].reg, candidateIndex + 2) &&
                    ctx.claimAll({refs[sourceIndex], candidateRef, refs[candidateIndex + 1]}))
                {
                    MicroInstrOperand rewrittenCompare[8] = {};
                    std::copy_n(compareOps, compare->numOperands, rewrittenCompare);
                    rewrittenCompare[0].reg = sourceOps[0].reg;
                    ctx.emitRewrite(refs[candidateIndex + 1], compare->op,
                                    std::span(rewrittenCompare, compare->numOperands));
                    ctx.emitErase(candidateRef);
                    changed = true;
                    break;
                }
                const uint32_t      storeIndex = candidateIndex + (redundantReload ? 4 : 3);
                const MicroInstrRef storeRef   = storeIndex < refs.size() ? refs[storeIndex] : MicroInstrRef::invalid();
                const MicroInstr*   storeInst  = ctx.instruction(storeRef);
                const auto*         store      = storeInst && storeInst->op == MicroInstrOpcode::LoadAmcMemImm ? storeInst->ops(*ctx.operands) : nullptr;
                if (store && store[0].reg == load[0].reg)
                {
                    if (!ctx.physicalLivenessReady)
                    {
                        ctx.physicalLivenessReady = true;
                        MicroPassHelpers::computePhysicalLiveness(ctx.physicalLiveness, *ctx.passContext, MicroPassHelpers::MicroPhysLivenessMode::LiveOutOnly);
                    }
                    const uint32_t bit         = MicroPassHelpers::MicroPhysLiveness::bitOf(load[0].reg);
                    bool           deadOnTaken = ctx.physicalLiveness.valid && bit < 64 && cfg.successors(candidateIndex + 2).size() == 2;
                    for (const uint32_t successor : cfg.successors(candidateIndex + 2))
                    {
                        if (successor == candidateIndex + 3)
                            continue;
                        deadOnTaken &= bit < 64 && successor < ctx.physicalLiveness.liveIn.size() &&
                                       (ctx.physicalLiveness.liveIn[successor] & (1ull << bit)) == 0;
                    }
                    if (deadOnTaken && !ctx.physicalLiveness.isLiveOut(storeIndex, load[0].reg))
                    {
                        const bool claimed = redundantReload ? ctx.claimAll({refs[sourceIndex], candidateRef, refs[candidateIndex + 1], reloadRef, storeRef}) : ctx.claimAll({refs[sourceIndex], candidateRef, refs[candidateIndex + 1], storeRef});
                        if (!claimed)
                            continue;
                        MicroInstrOperand rewrittenCompare[8] = {};
                        MicroInstrOperand rewrittenStore[8]   = {};
                        std::copy_n(compareOps, compare->numOperands, rewrittenCompare);
                        std::copy_n(store, storeInst->numOperands, rewrittenStore);
                        rewrittenCompare[0].reg = sourceOps[0].reg;
                        rewrittenStore[0].reg   = sourceOps[0].reg;
                        ctx.emitRewrite(refs[candidateIndex + 1], compare->op,
                                        std::span(rewrittenCompare, compare->numOperands));
                        ctx.emitRewrite(storeRef, storeInst->op, std::span(rewrittenStore, storeInst->numOperands));
                        ctx.emitErase(candidateRef);
                        if (redundantReload)
                            ctx.emitErase(reloadRef);
                        changed = true;
                        break;
                    }
                }
                if (redundantReload ? !ctx.claimAll({refs[sourceIndex], candidateRef, reloadRef}) : !ctx.claimAll({refs[sourceIndex], candidateRef}))
                    continue;

                MicroInstrOperand copy[3] = {};
                copy[0].reg               = load[0].reg;
                copy[1].reg               = sourceOps[0].reg;
                copy[2].opBits            = MicroOpBits::B64;
                ctx.emitRewrite(candidateRef, MicroInstrOpcode::LoadRegReg, copy);
                if (redundantReload)
                    ctx.emitErase(reloadRef);
                changed = true;
                break;
            }
        }
        return changed;
    }

    bool tryEraseTrivial(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.op == MicroInstrOpcode::Nop ? nullptr : inst.ops(*ctx.operands);
        if (!isTriviallyErasableNoEffect(inst, ops) &&
            !isRedundantFallthroughJumpToNextLabel(ctx, ref, inst, ops))
            return false;

        if (!ctx.claimAll({ref}))
            return false;

        ctx.emitErase(ref);
        return true;
    }

    // Register allocation may leave a load/add/store for a loop-local field
    // that pre-RA combine deliberately kept scalar. Once the assigned result
    // register is dead, an x64 memory increment avoids both the reload and
    // the store without changing register allocation or the add's flags.
    bool tryFoldDeadScalarIncrement(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        const MicroInstrOperand* load = loadInst.ops(*ctx.operands);
        if (!load || !load[0].reg.isInt() || !load[1].reg.isInt() || load[0].reg == load[1].reg)
            return false;

        const MicroInstrRef      addRef  = ctx.nextRef(loadRef);
        const MicroInstr*        addInst = ctx.instruction(addRef);
        const MicroInstrOperand* add     = addInst && addInst->op == MicroInstrOpcode::OpBinaryRegImm ? addInst->ops(*ctx.operands) : nullptr;
        if (!add || add[0].reg != load[0].reg || add[1].opBits != load[2].opBits ||
            add[2].microOp != MicroOp::Add || add[3].hasWideImmediateValue() || add[3].valueU64 != 1)
            return false;

        const MicroInstrRef      storeRef  = ctx.nextRef(addRef);
        const MicroInstr*        storeInst = ctx.instruction(storeRef);
        const MicroInstrOperand* store     = storeInst && storeInst->op == MicroInstrOpcode::LoadMemReg ? storeInst->ops(*ctx.operands) : nullptr;
        if (!store || store[0].reg != load[1].reg || store[1].reg != load[0].reg ||
            store[2].opBits != load[2].opBits || store[3].valueU64 != load[3].valueU64 ||
            !ctx.isRegDeadAfter(load[0].reg, ctx.instructionIndex + 2))
            return false;

        MicroInstrOperand folded[5];
        folded[0].reg      = load[1].reg;
        folded[1].opBits   = load[2].opBits;
        folded[2].microOp  = MicroOp::Add;
        folded[3].valueU64 = load[3].valueU64;
        folded[4].valueU64 = 1;
        MicroInstr probe;
        probe.op          = MicroInstrOpcode::OpBinaryMemImm;
        probe.numOperands = 5;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, probe, folded)) ||
            !ctx.claimAll({loadRef, addRef, storeRef}))
            return false;

        ctx.emitRewrite(addRef, probe.op, folded, true);
        ctx.emitErase(loadRef);
        ctx.emitErase(storeRef);
        return true;
    }

    // A conditional memory test does not change either the pointer just
    // loaded from a private frame slot or that slot's contents. On the branch
    // fallthrough, loading the same pointer into the same register again is
    // redundant even when the taken edge leaves the block.
    bool tryErasePrivateFrameReloadAfterBranch(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        const MicroInstrOperand* load = loadInst.ops(*ctx.operands);
        if (!load || !load[0].reg.isInt() || !ctx.isPrivateFrameBase(load[1].reg) ||
            load[0].reg == load[1].reg || load[2].opBits != MicroOpBits::B64)
            return false;

        const MicroInstrRef      compareRef  = ctx.nextRef(loadRef);
        const MicroInstr*        compareInst = ctx.instruction(compareRef);
        const MicroInstrOperand* compare     = compareInst && compareInst->op == MicroInstrOpcode::CmpAmcImm ? compareInst->ops(*ctx.operands) : nullptr;
        if (!compare || compare[0].reg != load[0].reg)
            return false;

        const MicroInstrRef      jumpRef  = ctx.nextRef(compareRef);
        const MicroInstr*        jumpInst = ctx.instruction(jumpRef);
        const MicroInstrOperand* jump     = jumpInst && jumpInst->op == MicroInstrOpcode::JumpCond ? jumpInst->ops(*ctx.operands) : nullptr;
        if (!jump || jump[0].cpuCond == MicroCond::Unconditional)
            return false;

        const MicroInstrRef      reloadRef  = ctx.nextRef(jumpRef);
        const MicroInstr*        reloadInst = ctx.instruction(reloadRef);
        const MicroInstrOperand* reload     = reloadInst && reloadInst->op == MicroInstrOpcode::LoadRegMem ? reloadInst->ops(*ctx.operands) : nullptr;
        if (!reload || reload[0].reg != load[0].reg || reload[1].reg != load[1].reg ||
            reload[2].opBits != load[2].opBits || reload[3].valueU64 != load[3].valueU64 ||
            !ctx.claimAll({loadRef, compareRef, jumpRef, reloadRef}))
            return false;

        ctx.emitErase(reloadRef);
        return true;
    }

    // A conditional jump over an unconditional one:
    //
    //     jbe .L ; jmp .M ; .L:    ->    ja .M ; .L:
    //
    // Branch simplification does it before allocation; copies that vanish
    // after it can leave the shape behind, as a float clamp's did. Every
    // condition has an exact complement over the flags, unordered floats
    // included.
    // A jump whose target is itself an unconditional jump goes straight to the final target:
    //
    //     jump L1 ... L1: jump L2        ->    jump L2 ... L1: jump L2
    //
    // The branch simplification threads such chains before allocation, but there a join
    // often still starts with the copies that merge its values; once the allocator has
    // coalesced them, the join is a bare jump and the hot path takes two jumps in a row.
    bool tryThreadJumpToJump(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || inst.numOperands < 3 || ctx.isClaimed(ref) || !ctx.builder)
            return false;

        const auto&    cfg   = ctx.builder->controlFlowGraph();
        const auto     refs  = cfg.instructionRefs();
        const uint64_t first = ops[2].valueU64;
        uint32_t       index = cfg.indexOfLabel(first);
        if (index == MicroControlFlowGraph::K_NO_INDEX)
            return false;

        // The first instruction at the target, past any other label placed there.
        const MicroInstr* next = nullptr;
        MicroInstrRef     nextRef;
        for (; index < refs.size(); ++index)
        {
            nextRef = refs[index];
            next    = ctx.instruction(nextRef);
            if (!next || next->op != MicroInstrOpcode::Label)
                break;
        }
        if (!next || next->op != MicroInstrOpcode::JumpCond || nextRef == ref || ctx.isClaimed(nextRef))
            return false;
        const MicroInstrOperand* nextOps = next->ops(*ctx.operands);
        if (!nextOps || next->numOperands < 3 || nextOps[0].cpuCond != MicroCond::Unconditional || nextOps[2].valueU64 == first)
            return false;
        if (!ctx.claimAll({ref}))
            return false;

        MicroInstrOperand branch[3] = {ops[0], ops[1], ops[2]};
        branch[2].valueU64          = nextOps[2].valueU64;
        ctx.emitRewrite(ref, MicroInstrOpcode::JumpCond, branch);
        return true;
    }

    bool tryInvertBranchOverJump(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || ops[0].cpuCond == MicroCond::Unconditional)
            return false;
        MicroCond inverted = MicroCond::Unconditional;
        if (!MicroPassHelpers::invertCondition(inverted, ops[0].cpuCond))
            return false;

        auto scanIt = MicroStorage::Iterator{ctx.storage, ref};
        ++scanIt;
        const MicroInstrRef      skipRef = scanIt.current;
        const MicroInstr*        skip    = skipRef.isValid() ? &*scanIt : nullptr;
        const MicroInstrOperand* skipOps = skip && skip->op == MicroInstrOpcode::JumpCond ? skip->ops(*ctx.operands) : nullptr;
        if (!skipOps || skipOps[0].cpuCond != MicroCond::Unconditional)
            return false;
        ++scanIt;
        const MicroInstrRef      labelRef = scanIt.current;
        const MicroInstr*        label    = labelRef.isValid() ? &*scanIt : nullptr;
        const MicroInstrOperand* labelOps = label && label->op == MicroInstrOpcode::Label ? label->ops(*ctx.operands) : nullptr;
        if (!labelOps || labelOps[0].valueU64 != ops[2].valueU64 || !ctx.claimAll({ref, skipRef}))
            return false;

        MicroInstrOperand branch[3] = {ops[0], ops[1], ops[2]};
        branch[0].cpuCond           = inverted;
        branch[1].opBits            = MicroOpBits::B32;
        branch[2].valueU64          = skipOps[2].valueU64;
        ctx.emitRewrite(ref, MicroInstrOpcode::JumpCond, branch);
        ctx.emitErase(skipRef);
        return true;
    }

    namespace
    {
        using MicroOptimizationLimits::PostRAPeepholeTrivial::K_MAX_RETURN_TAIL;

        bool collectSimpleReturnTail(const Context& ctx, MicroInstrRef ref, std::array<MicroInstrRef, K_MAX_RETURN_TAIL>& refs, uint32_t& count)
        {
            count                    = 0;
            auto              scanIt = MicroStorage::Iterator{ctx.storage, ref};
            const MicroInstr* inst   = scanIt.current.isValid() ? &*scanIt : nullptr;
            if (inst && inst->op == MicroInstrOpcode::LoadRegReg)
            {
                refs[count++] = scanIt.current;
                ++scanIt;
                inst = scanIt.current.isValid() ? &*scanIt : nullptr;
            }
            if (inst && inst->op == MicroInstrOpcode::OpBinaryRegImm)
            {
                const MicroInstrOperand* ops = inst->ops(*ctx.operands);
                if (!ops || ops[0].reg != ctx.stackPointer || ops[1].opBits != MicroOpBits::B64 ||
                    ops[2].microOp != MicroOp::Add)
                    return false;
                refs[count++] = scanIt.current;
                ++scanIt;
                inst = scanIt.current.isValid() ? &*scanIt : nullptr;
            }
            while (inst && inst->op == MicroInstrOpcode::Pop && count + 1 < K_MAX_RETURN_TAIL)
            {
                refs[count++] = scanIt.current;
                ++scanIt;
                inst = scanIt.current.isValid() ? &*scanIt : nullptr;
            }
            if (!inst || inst->op != MicroInstrOpcode::Ret || count >= K_MAX_RETURN_TAIL)
                return false;
            refs[count++] = scanIt.current;
            return true;
        }

        bool sameReturnInstruction(const Context& ctx, const MicroInstrRef lhsRef, const MicroInstrRef rhsRef)
        {
            const MicroInstr* lhs = ctx.instruction(lhsRef);
            const MicroInstr* rhs = ctx.instruction(rhsRef);
            if (!lhs || !rhs || lhs->op != rhs->op || lhs->numOperands != rhs->numOperands)
                return false;
            const MicroInstrOperand* a = lhs->ops(*ctx.operands);
            const MicroInstrOperand* b = rhs->ops(*ctx.operands);
            switch (lhs->op)
            {
                case MicroInstrOpcode::LoadRegReg:
                    return a && b && a[0].reg == b[0].reg && a[1].reg == b[1].reg && a[2].opBits == b[2].opBits;
                case MicroInstrOpcode::OpBinaryRegImm:
                    return a && b && a[0].reg == b[0].reg && a[1].opBits == b[1].opBits &&
                           a[2].microOp == b[2].microOp &&
                           a[3].valueInt.bitWidth() == b[3].valueInt.bitWidth() && a[3].valueInt.eq(b[3].valueInt);
                case MicroInstrOpcode::Pop:
                    return a && b && a[0].reg == b[0].reg;
                case MicroInstrOpcode::Ret:
                    return true;
                default:
                    return false;
            }
        }
    }

    // Two identical return tails can share one epilogue while the branch to
    // the collision path becomes the complementary branch to the later tail.
    // The collision path then becomes the fallthrough, as in a single-exit
    // lookup loop, without adding a jump to either hot path.
    bool tryShareReturnEpilogue(Context& ctx, const MicroInstrRef branchRef, const MicroInstr& branchInst)
    {
        const MicroInstrOperand* branchOps = branchInst.ops(*ctx.operands);
        if (!branchOps || branchOps[0].cpuCond == MicroCond::Unconditional)
            return false;
        MicroCond inverted = MicroCond::Unconditional;
        if (!MicroPassHelpers::invertCondition(inverted, branchOps[0].cpuCond))
            return false;

        std::array<MicroInstrRef, K_MAX_RETURN_TAIL> firstTail;
        uint32_t                                     firstCount = 0;
        if (!collectSimpleReturnTail(ctx, ctx.nextRef(branchRef), firstTail, firstCount))
            return false;
        const MicroInstrRef      collisionRef = ctx.nextRef(firstTail[firstCount - 1]);
        const MicroInstr*        collision    = ctx.instruction(collisionRef);
        const MicroInstrOperand* collisionOps = collision ? collision->ops(*ctx.operands) : nullptr;
        if (!collision || collision->op != MicroInstrOpcode::Label || !collisionOps ||
            collisionOps[0].valueU64 != branchOps[2].valueU64)
            return false;

        MicroInstrRef exitRef = ctx.nextRef(collisionRef);
        for (uint32_t step = 0; step < MicroOptimizationLimits::PostRAPeepholeTrivial::K_MAX_RETURN_EXIT_SCAN; ++step)
        {
            const MicroInstr* inst = ctx.instruction(exitRef);
            if (!inst || inst->op == MicroInstrOpcode::Ret)
                return false;
            if (inst->op == MicroInstrOpcode::Label)
                break;
            exitRef = ctx.nextRef(exitRef);
        }
        const MicroInstr*        exitLabel = ctx.instruction(exitRef);
        const MicroInstrOperand* exitOps   = exitLabel ? exitLabel->ops(*ctx.operands) : nullptr;
        if (!exitLabel || exitLabel->op != MicroInstrOpcode::Label || !exitOps)
            return false;

        std::array<MicroInstrRef, K_MAX_RETURN_TAIL> secondTail;
        uint32_t                                     secondCount = 0;
        if (!collectSimpleReturnTail(ctx, ctx.nextRef(exitRef), secondTail, secondCount) ||
            firstCount != secondCount)
            return false;
        for (uint32_t i = 0; i < firstCount; ++i)
            if (!sameReturnInstruction(ctx, firstTail[i], secondTail[i]))
                return false;

        std::array<MicroInstrRef, K_MAX_RETURN_TAIL + 1> claims;
        claims[0] = branchRef;
        for (uint32_t i = 0; i < firstCount; ++i)
            claims[i + 1] = firstTail[i];
        if (!ctx.claimAll(std::span{claims.data(), firstCount + 1}))
            return false;

        MicroInstrOperand rewritten[3] = {branchOps[0], branchOps[1], branchOps[2]};
        rewritten[0].cpuCond           = inverted;
        rewritten[2].valueU64          = exitOps[0].valueU64;
        ctx.emitRewrite(branchRef, MicroInstrOpcode::JumpCond, rewritten);
        for (uint32_t i = 0; i < firstCount; ++i)
            ctx.emitErase(firstTail[i]);
        return true;
    }

    // `mov eax, eax` clears the upper half of rax, so a dword self-copy is
    // kept as a rule. Where that half is already clear on every path - after
    // any 32-bit write - it changes nothing.
    bool tryEraseZeroExtendedSelfCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || ops[0].reg != ops[1].reg || !ops[0].reg.isInt() ||
            ops[2].opBits != MicroOpBits::B32)
            return false;
        if (!ctx.isUpperHalfZeroBefore(ref, ops[0].reg) || !ctx.claimAll({ref}))
            return false;
        ctx.emitErase(ref);
        return true;
    }

    // A zero-extended byte remains zero above bit seven after an 8-bit
    // subtract: x86 changes only the low byte. A delimiter check may branch
    // away, but its fall-through still comes from the zero-extending load.
    //
    //   movzx r, byte [p]; cmp r, ','; je exit; sub r8, '0'; movzx r, r8
    //       ->
    //   movzx r, byte [p]; cmp r, ','; je exit; sub r8, '0'
    bool tryEraseByteZeroExtendAfterSubtract(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto*    loadOps         = inst.ops(*ctx.operands);
        const uint32_t destBitsIndex   = inst.op == MicroInstrOpcode::LoadZeroExtAmcRegMem ? 3 : 2;
        const uint32_t sourceBitsIndex = inst.op == MicroInstrOpcode::LoadZeroExtAmcRegMem ? 4 : 3;
        if (!loadOps || !loadOps[0].reg.isInt() ||
            (loadOps[destBitsIndex].opBits != MicroOpBits::B32 && loadOps[destBitsIndex].opBits != MicroOpBits::B64) ||
            loadOps[sourceBitsIndex].opBits != MicroOpBits::B8)
            return false;
        const MicroReg reg    = loadOps[0].reg;
        auto           scanIt = MicroStorage::Iterator{ctx.storage, ref};
        ++scanIt;
        if (!scanIt.current.isValid())
            return false;
        const MicroInstrRef cmpRef = scanIt.current;
        const MicroInstr*   cmp    = cmpRef.isValid() ? &*scanIt : nullptr;
        ++scanIt;
        if (!scanIt.current.isValid())
            return false;
        const MicroInstrRef branchRef = scanIt.current;
        const MicroInstr*   branch    = branchRef.isValid() ? &*scanIt : nullptr;
        ++scanIt;
        if (!scanIt.current.isValid())
            return false;
        MicroInstrRef     subRef     = scanIt.current;
        const MicroInstr* beforeSub  = subRef.isValid() ? &*scanIt : nullptr;
        MicroInstrRef     addressRef = MicroInstrRef::invalid();
        // The decimal accumulator may prepare its LEA between the delimiter
        // branch and the byte subtraction. It cannot change this byte value.
        if (beforeSub &&
            (beforeSub->op == MicroInstrOpcode::LoadAddrRegMem ||
             beforeSub->op == MicroInstrOpcode::LoadAddrAmcRegMem))
        {
            const MicroInstrUseDef useDef = beforeSub->collectUseDef(*ctx.operands, ctx.encoder);
            if (std::ranges::find(useDef.uses, reg) != useDef.uses.end() ||
                std::ranges::find(useDef.defs, reg) != useDef.defs.end())
                return false;
            addressRef = subRef;
            ++scanIt;
            if (!scanIt.current.isValid())
                return false;
            subRef    = scanIt.current;
            beforeSub = subRef.isValid() ? &*scanIt : nullptr;
        }
        ++scanIt;
        const MicroInstrRef extRef = scanIt.current;
        const MicroInstr*   sub    = beforeSub;
        const MicroInstr*   ext    = extRef.isValid() ? &*scanIt : nullptr;
        if (!sub || !branch || !cmp || !ext ||
            sub->op != MicroInstrOpcode::OpBinaryRegImm || branch->op != MicroInstrOpcode::JumpCond ||
            cmp->op != MicroInstrOpcode::CmpRegImm ||
            ext->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* subOps    = sub->ops(*ctx.operands);
        const auto* branchOps = branch->ops(*ctx.operands);
        const auto* cmpOps    = cmp->ops(*ctx.operands);
        const auto* extOps    = ext->ops(*ctx.operands);
        if (!subOps || !branchOps || !cmpOps || !extOps ||
            subOps[0].reg != reg || subOps[1].opBits != MicroOpBits::B8 || subOps[2].microOp != MicroOp::Subtract ||
            branchOps[0].cpuCond == MicroCond::Unconditional || cmpOps[0].reg != reg ||
            (cmpOps[1].opBits != MicroOpBits::B32 && cmpOps[1].opBits != MicroOpBits::B64) ||
            extOps[0].reg != reg || extOps[1].reg != reg ||
            extOps[2].opBits != MicroOpBits::B64 || extOps[3].opBits != MicroOpBits::B8)
            return false;
        const bool claimed = addressRef.isValid() ? ctx.claimAll({ref, cmpRef, branchRef, addressRef, subRef, extRef}) : ctx.claimAll({ref, cmpRef, branchRef, subRef, extRef});
        if (!claimed)
            return false;
        ctx.emitErase(extRef);
        return true;
    }

    // Move a byte's zero extension into its memory load when the only work
    // before the original extension is a low-byte subtraction. The subtraction
    // leaves the high bits established by MOVZX intact, so the final MOVZX is
    // redundant even when the byte subtraction wraps.
    bool tryFoldByteLoadSubtractExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* load = inst.ops(*ctx.operands);
        if (!load || inst.numOperands < 7 || load[3].opBits != MicroOpBits::B8 ||
            load[4].opBits != MicroOpBits::B64 || load[1].reg.isInstructionPointer())
            return false;
        const MicroReg reg = load[0].reg;
        if (!reg.isInt())
            return false;
        auto scanIt = MicroStorage::Iterator{ctx.storage, ref};
        ++scanIt;
        if (!scanIt.current.isValid())
            return false;
        const MicroInstrRef subRef = scanIt.current;
        const MicroInstr*   sub    = subRef.isValid() ? &*scanIt : nullptr;
        ++scanIt;
        const MicroInstrRef extRef = scanIt.current;
        const MicroInstr*   ext    = extRef.isValid() ? &*scanIt : nullptr;
        if (!sub || !ext || sub->op != MicroInstrOpcode::OpBinaryRegImm ||
            ext->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* subOps = sub->ops(*ctx.operands);
        const auto* extOps = ext->ops(*ctx.operands);
        if (!subOps || !extOps || subOps[0].reg != reg || subOps[1].opBits != MicroOpBits::B8 ||
            subOps[2].microOp != MicroOp::Subtract || extOps[0].reg != reg || extOps[1].reg != reg ||
            extOps[2].opBits != MicroOpBits::B64 || extOps[3].opBits != MicroOpBits::B8 ||
            !ctx.claimAll({ref, subRef, extRef}))
            return false;

        MicroInstrOperand widened[7] = {load[0], load[1], load[2], load[3], load[4], load[5], load[6]};
        widened[3].opBits            = MicroOpBits::B64;
        widened[4].opBits            = MicroOpBits::B8;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadZeroExtAmcRegMem, widened);
        ctx.emitErase(extRef);
        return true;
    }

    // A 32-bit comparison observes the same low bits before and after a
    // 32-to-64-bit sign extension. Read the original register when the wider
    // value has no later consumer.
    bool tryDropSignExtendBeforeNarrowCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* extend = inst.ops(*ctx.operands);
        if (!extend ||
            extend[2].opBits != MicroOpBits::B64 || extend[3].opBits != MicroOpBits::B32 ||
            !extend[0].reg.isInt() || !extend[1].reg.isInt())
            return false;

        const MicroInstrRef cmpRef = ctx.nextRef(ref);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        const auto*         cmpOps = cmp && cmp->op == MicroInstrOpcode::CmpRegImm ? cmp->ops(*ctx.operands) : nullptr;
        if (!cmpOps || cmpOps[0].reg != extend[0].reg ||
            cmpOps[1].opBits != MicroOpBits::B32)
            return false;

        bool deadAfterCompare = ctx.isRegDeadAfter(extend[0].reg, ctx.instructionIndex + 1);
        if (!deadAfterCompare)
        {
            // A large function may not have usable whole-function liveness.
            // Prove the two immediate branch paths locally when each path
            // overwrites the wider value before reading it.
            const MicroInstrRef branchRef = ctx.nextRef(cmpRef);
            const MicroInstr*   branch    = ctx.instruction(branchRef);
            const auto*         branchOps = branch && branch->op == MicroInstrOpcode::JumpCond ? branch->ops(*ctx.operands) : nullptr;
            if (branchOps && branch->numOperands >= 3 &&
                branchOps[0].cpuCond != MicroCond::Unconditional &&
                regIsDeadAfter(ctx, branchRef, extend[0].reg))
            {
                for (auto it = ctx.storage->view().begin(), endIt = ctx.storage->view().end(); it != endIt; ++it)
                {
                    if (it->op != MicroInstrOpcode::Label)
                        continue;
                    const MicroInstrOperand* labelOps = it->ops(*ctx.operands);
                    if (labelOps && labelOps[0].valueU64 == branchOps[2].valueU64)
                    {
                        deadAfterCompare = regIsDeadAfter(ctx, it.current, extend[0].reg);
                        break;
                    }
                }
            }
        }
        if (!deadAfterCompare || !ctx.claimAll({ref, cmpRef}))
            return false;

        MicroInstrOperand narrowed[3] = {cmpOps[0], cmpOps[1], cmpOps[2]};
        narrowed[0].reg               = extend[1].reg;
        ctx.emitErase(ref);
        ctx.emitRewrite(cmpRef, cmp->op, narrowed);
        return true;
    }

    // A store reads its vector without changing it, so a second full clear
    // immediately after that store has no effect and does not change flags.
    bool tryEraseRepeatedVectorClear(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* clear = inst.ops(*ctx.operands);
        if (!clear || !clear[0].reg.isFloat() || clear[1].opBits != MicroOpBits::B128)
            return false;
        const MicroInstrRef storeRef = ctx.previousRef(ref);
        const MicroInstr*   store    = ctx.instruction(storeRef);
        const auto*         storeOps = store ? store->ops(*ctx.operands) : nullptr;
        if (!store || store->op != MicroInstrOpcode::LoadMemReg || !storeOps || storeOps[1].reg != clear[0].reg)
            return false;
        const MicroInstrRef previousRef = ctx.previousRef(storeRef);
        const MicroInstr*   previous    = ctx.instruction(previousRef);
        const auto*         previousOps = previous ? previous->ops(*ctx.operands) : nullptr;
        if (!previous || previous->op != MicroInstrOpcode::ClearReg || !previousOps ||
            previousOps[0].reg != clear[0].reg || previousOps[1].opBits != MicroOpBits::B128 ||
            !ctx.claimAll({previousRef, storeRef, ref}))
            return false;
        ctx.emitErase(ref);
        return true;
    }

    // A float clear is kept as a rule: it zeroes the lanes a partial write
    // such as cvtsi2ss leaves alone. When the next instruction replaces the
    // whole register instead - another clear, a scalar load from memory, a
    // move from an integer register - the clear does nothing:
    //
    //     xorps xmm0, xmm0 ; movss xmm0, [rip + c]    ->    movss xmm0, [rip + c]
    //
    // A float constant materialized over a conversion kept the clear that
    // conversion needed. The rule anchors on the write, after the folds that
    // consume it along with its clear.
    bool tryEraseFloatClearBeforeFullWrite(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isFloat())
            return false;
        const MicroReg reg = ops[0].reg;

        bool needsUpperProof = false;
        switch (inst.op)
        {
            case MicroInstrOpcode::ClearReg:
                break;
            case MicroInstrOpcode::LoadRegMem:
                if (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64)
                    return false;
                break;
            case MicroInstrOpcode::LoadRegReg:
                if (!ops[1].reg.isInt())
                {
                    if (!ops[1].reg.isFloat() || (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64))
                        return false;
                    needsUpperProof = true;
                }
                break;
            default:
                return false;
        }

        const MicroInstrRef      clearRef = ctx.previousRef(ref);
        const MicroInstr*        clear    = ctx.instruction(clearRef);
        const MicroInstrOperand* clearOps = clear ? clear->ops(*ctx.operands) : nullptr;
        if (!clearOps || clear->op != MicroInstrOpcode::ClearReg || clearOps[0].reg != reg)
            return false;
        if (needsUpperProof && !areFloatUpperLanesDeadAfter(ctx, ref, reg, ops[2].opBits))
            return false;
        if (!ctx.claimAll({clearRef, ref}))
            return false;
        ctx.emitErase(clearRef);

        return true;
    }

    // A scalar float argument that arrives in the ABI return register can be
    // copied to a temporary only to receive a sign-mask XOR and be copied back
    // for return. Retarget the XOR to the ABI register: it still reads the
    // argument's original bits, and the two moves become dead.
    bool tryFoldFloatReturnXorCopyChain(Context& ctx, const MicroInstrRef firstCopyRef, const MicroInstr& firstCopyInst)
    {
        if (ctx.isClaimed(firstCopyRef) || !ctx.passContext || !ctx.passContext->usesFloatReturnRegOnRet)
            return false;

        const auto* firstCopy = firstCopyInst.ops(*ctx.operands);
        if (!firstCopy || !firstCopy[0].reg.isFloat() || firstCopy[1].reg != ctx.floatReturn ||
            (firstCopy[2].opBits != MicroOpBits::B32 && firstCopy[2].opBits != MicroOpBits::B64))
            return false;

        auto scanIt = MicroStorage::Iterator{ctx.storage, firstCopyRef};
        ++scanIt;
        const MicroInstrRef xorRef  = scanIt.current;
        const MicroInstr*   xorInst = xorRef.isValid() ? &*scanIt : nullptr;
        if (!xorInst)
            return false;
        ++scanIt;
        const MicroInstrRef lastCopyRef  = scanIt.current;
        const MicroInstr*   lastCopyInst = lastCopyRef.isValid() ? &*scanIt : nullptr;
        if (!lastCopyInst)
            return false;
        ++scanIt;
        const MicroInstrRef retRef   = scanIt.current;
        const MicroInstr*   retInst  = retRef.isValid() ? &*scanIt : nullptr;
        const auto*         xorOps   = xorInst ? xorInst->ops(*ctx.operands) : nullptr;
        const auto*         lastCopy = lastCopyInst ? lastCopyInst->ops(*ctx.operands) : nullptr;
        if (!xorInst || !lastCopyInst || !retInst || !xorOps || !lastCopy ||
            xorInst->op != MicroInstrOpcode::OpBinaryRegMem || xorOps[0].reg != firstCopy[0].reg ||
            xorOps[1].reg != MicroReg::instructionPointer() || xorOps[2].opBits != firstCopy[2].opBits ||
            xorOps[3].microOp != MicroOp::FloatXor || lastCopyInst->op != MicroInstrOpcode::LoadRegReg ||
            lastCopy[0].reg != ctx.floatReturn || lastCopy[1].reg != firstCopy[0].reg ||
            lastCopy[2].opBits != firstCopy[2].opBits || retInst->op != MicroInstrOpcode::Ret)
            return false;

        std::array<MicroInstrOperand, 5> rewrittenXor = {xorOps[0], xorOps[1], xorOps[2], xorOps[3], xorOps[4]};
        rewrittenXor[0].reg                           = ctx.floatReturn;
        if (!ctx.claimAll({firstCopyRef, xorRef, lastCopyRef}))
            return false;

        ctx.emitErase(firstCopyRef);
        ctx.emitRewrite(xorRef, xorInst->op, rewrittenXor);
        ctx.emitErase(lastCopyRef);
        return true;
    }

    // A scalar float conditional starts with copies for both arms and joins in
    // a third register. When the true value already occupies the ABI return
    // register, branch around one direct false-value copy instead. The same
    // return diamond around a float comparison can become MINSS/MAXSS directly.
    bool tryFoldFloatReturnSelectDiamond(Context& ctx, const MicroInstrRef firstCopyRef, const MicroInstr& firstCopyInst)
    {
        if (ctx.isClaimed(firstCopyRef) || !ctx.passContext || !ctx.passContext->usesFloatReturnRegOnRet)
            return false;

        std::array<MicroInstrRef, 9> refs;
        refs[0] = firstCopyRef;
        for (size_t index = 1; index < refs.size(); ++index)
        {
            refs[index] = ctx.nextRef(refs[index - 1]);
            if (!refs[index].isValid())
                return false;
        }

        constexpr std::array expected = {
            MicroInstrOpcode::LoadRegReg,
            MicroInstrOpcode::LoadRegReg,
            MicroInstrOpcode::Nop,
            MicroInstrOpcode::JumpCond,
            MicroInstrOpcode::JumpCond,
            MicroInstrOpcode::Label,
            MicroInstrOpcode::LoadRegReg,
            MicroInstrOpcode::Label,
            MicroInstrOpcode::LoadRegReg,
        };
        std::array<const MicroInstrOperand*, refs.size()> ops;
        for (size_t index = 0; index < refs.size(); ++index)
        {
            const MicroInstr* candidate = ctx.instruction(refs[index]);
            if (!candidate || ctx.isClaimed(refs[index]) ||
                (index == 2 ? candidate->op != MicroInstrOpcode::CmpRegImm && candidate->op != MicroInstrOpcode::CmpRegReg : candidate->op != expected[index]))
                return false;
            ops[index] = candidate->ops(*ctx.operands);
            if (!ops[index])
                return false;
        }

        const MicroInstrRef retRef = ctx.nextRef(refs.back());
        const MicroInstr*   ret    = ctx.instruction(retRef);
        if (!ret || ret->op != MicroInstrOpcode::Ret)
            return false;

        const MicroOpBits bits      = ops[0][2].opBits;
        const MicroReg    falseTmp  = ops[0][0].reg;
        const MicroReg    falseSrc  = ops[0][1].reg;
        const MicroReg    resultTmp = ops[1][0].reg;
        const MicroReg    trueSrc   = ops[1][1].reg;
        if ((bits != MicroOpBits::B32 && bits != MicroOpBits::B64) ||
            !falseTmp.isFloat() || !falseSrc.isFloat() || !resultTmp.isFloat() ||
            trueSrc != ctx.floatReturn || ops[1][2].opBits != bits ||
            ops[6][0].reg != resultTmp || ops[6][1].reg != falseTmp || ops[6][2].opBits != bits ||
            ops[8][0].reg != ctx.floatReturn || ops[8][1].reg != resultTmp || ops[8][2].opBits != bits)
            return false;

        const uint64_t falseLabelId = ops[5][0].valueU64;
        const uint64_t doneLabelId  = ops[7][0].valueU64;
        if (ops[3][0].cpuCond == MicroCond::Unconditional || ops[3][2].valueU64 != falseLabelId ||
            ops[4][0].cpuCond != MicroCond::Unconditional || ops[4][2].valueU64 != doneLabelId ||
            !labelsHaveSingleReference(ctx, falseLabelId, doneLabelId))
            return false;

        const MicroInstr* compare = ctx.instruction(refs[2]);
        SWC_ASSERT(compare);
        if (compare->op == MicroInstrOpcode::CmpRegReg)
        {
            const bool isMin = ops[2][0].reg == falseTmp && ops[2][1].reg == resultTmp;
            const bool isMax = ops[2][0].reg == resultTmp && ops[2][1].reg == falseTmp;
            if (ops[2][2].opBits != bits || ops[3][0].cpuCond != MicroCond::BelowOrEqual || (!isMin && !isMax))
                return false;

            std::array<MicroInstrOperand, 4> minMax = {};
            minMax[0].reg                           = ctx.floatReturn;
            minMax[1].reg                           = falseSrc;
            minMax[2].opBits                        = bits;
            minMax[3].microOp                       = isMin ? MicroOp::FloatMin : MicroOp::FloatMax;
            if (!ctx.claimAll({refs[0], refs[1], refs[2], refs[3], refs[4], refs[6], refs[8]}))
                return false;
            ctx.emitRewrite(refs[0], MicroInstrOpcode::OpBinaryRegReg, minMax);
            ctx.emitErase(refs[1]);
            ctx.emitErase(refs[2]);
            ctx.emitErase(refs[3]);
            ctx.emitErase(refs[4]);
            ctx.emitErase(refs[6]);
            ctx.emitErase(refs[8]);
            return true;
        }

        MicroCond inverted = MicroCond::Unconditional;
        if (!MicroPassHelpers::invertCondition(inverted, ops[3][0].cpuCond))
            return false;

        std::array<MicroInstrOperand, 3> branch    = {ops[3][0], ops[3][1], ops[3][2]};
        branch[0].cpuCond                          = inverted;
        branch[2].valueU64                         = doneLabelId;
        std::array<MicroInstrOperand, 3> falseCopy = {ops[6][0], ops[6][1], ops[6][2]};
        falseCopy[0].reg                           = ctx.floatReturn;
        falseCopy[1].reg                           = falseSrc;
        falseCopy[2].opBits                        = MicroOpBits::B128;

        if (!ctx.claimAll({refs[0], refs[1], refs[3], refs[4], refs[6], refs[8]}))
            return false;
        ctx.emitErase(refs[0]);
        ctx.emitErase(refs[1]);
        ctx.emitRewrite(refs[3], MicroInstrOpcode::JumpCond, branch);
        ctx.emitErase(refs[4]);
        ctx.emitRewrite(refs[6], MicroInstrOpcode::LoadRegReg, falseCopy);
        ctx.emitErase(refs[8]);
        return true;
    }
}

SWC_END_NAMESPACE();
