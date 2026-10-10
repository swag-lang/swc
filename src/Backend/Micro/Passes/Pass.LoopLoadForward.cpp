#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoopLoadForward.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroLabelHelpers.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/PointerSet.h"
#include "Support/Report/Assert.h"

// See the header for the transformation. The proofs are local to one loop
// body: positions are indices into the body, the index register has exactly
// one definition in the body (its step), and every access the rule reasons
// about runs before that step, so all of them see the same index value within
// one trip and that value plus the step on the next trip.

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID      = std::numeric_limits<uint32_t>::max();
    constexpr uint32_t K_MAX_BODY     = 256;
    constexpr uint32_t K_MAX_ROOT_HOP = 16;

    struct RegDefs
    {
        uint32_t      count = 0;
        MicroInstrRef ref   = MicroInstrRef::invalid();
        uint32_t      pos   = 0;
    };

    // One memory access through `[base + index * scale + disp]`.
    struct Access
    {
        uint32_t    pos     = 0;
        bool        isStore = false;
        MicroReg    base;
        MicroReg    index;
        uint64_t    scale = 0;
        uint64_t    disp  = 0;
        uint32_t    width = 0;
        MicroOpBits bits  = MicroOpBits::Zero;
        // The loaded register, or the stored one.
        MicroReg value;
    };

    struct FunctionInfo
    {
        MicroPassContext*                      context  = nullptr;
        MicroStorage*                          storage  = nullptr;
        MicroOperandStorage*                   operands = nullptr;
        // Keyed by packed register, by label id and by instruction slot; only looked up.
        FlatKeyMap<RegDefs>  defs;
        FlatKeyMap<uint32_t> labelReferences;
        FlatKeySet           relocated;
        // Instructions before the first label or control transfer run once.
        uint32_t entryEnd = 0;
    };

    // A base register as a constant offset from a root that holds one value
    // for the whole call: the stack pointer, or a register defined once in the
    // entry block. Each hop is a single definition: a full-width copy or an
    // address with a constant displacement.
    bool resolveRoot(const FunctionInfo& fn, MicroReg& outRoot, uint64_t& outOffset, MicroReg reg)
    {
        uint64_t offset = 0;
        for (uint32_t hop = 0; hop < K_MAX_ROOT_HOP; ++hop)
        {
            if (reg == fn.context->encoder->stackPointerReg())
            {
                // Distinct snapshots of a moving stack pointer are not one root.
                const RegDefs* stackDef = fn.defs.find(reg.packed);
                if (stackDef && stackDef->count)
                    return false;
                outRoot   = reg;
                outOffset = offset;
                return true;
            }

            const RegDefs* it = fn.defs.find(reg.packed);
            if (!reg.isVirtual() || !it || it->count != 1)
                return false;
            const MicroInstr*        inst = fn.storage->ptr(it->ref);
            const MicroInstrOperand* ops  = inst ? inst->ops(*fn.operands) : nullptr;
            if (!ops)
                return false;
            if (inst->op == MicroInstrOpcode::LoadAddrRegMem && ops[2].opBits == MicroOpBits::B64 && !ops[1].reg.isInstructionPointer())
            {
                offset += ops[3].valueU64;
                reg = ops[1].reg;
                continue;
            }
            if (inst->op == MicroInstrOpcode::LoadRegReg && ops[2].opBits == MicroOpBits::B64 && ops[1].reg.isInt() && ops[1].reg.isVirtual())
            {
                reg = ops[1].reg;
                continue;
            }

            // The register is the root: it must hold one value for the call.
            if (it->pos >= fn.entryEnd)
                return false;
            outRoot   = reg;
            outOffset = offset;
            return true;
        }
        return false;
    }

    struct Loop
    {
        MicroInstrRef                         labelRef = MicroInstrRef::invalid();
        MicroInstrRef                         latchRef = MicroInstrRef::invalid();
        std::vector<MicroInstrRef>            refs;
        std::vector<const MicroInstr*>        insts;
        std::vector<const MicroInstrOperand*> ops;
        std::vector<MicroInstrUseDef>         useDefs;
    };

    // Describes the access an instruction of the body makes, when it is one
    // the rule understands. `addrDefs` maps a register to the body position of
    // its single in-body address definition.
    bool describeAccess(Access& out, const Loop& loop, uint32_t pos, const std::unordered_map<uint32_t, uint32_t>& addrDefs)
    {
        out                           = {};
        out.pos                       = pos;
        const MicroInstr&        inst = *loop.insts[pos];
        const MicroInstrOperand* ops  = loop.ops[pos];
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadAmcRegMem:
                // [0] dst, [1] base, [2] index, [3] dst bits, [4] memory bits, [5] scale, [6] disp
                if (ops[3].opBits != ops[4].opBits)
                    return false;
                out.base  = ops[1].reg;
                out.index = ops[2].reg;
                out.scale = ops[5].valueU64;
                out.disp  = ops[6].valueU64;
                out.bits  = ops[4].opBits;
                out.value = ops[0].reg;
                break;
            case MicroInstrOpcode::LoadAmcMemReg:
                // [0] base, [1] index, [2] src, [3] address bits, [4] value bits, [5] scale, [6] disp
                if (ops[3].opBits != MicroOpBits::B64)
                    return false;
                out.isStore = true;
                out.base    = ops[0].reg;
                out.index   = ops[1].reg;
                out.scale   = ops[5].valueU64;
                out.disp    = ops[6].valueU64;
                out.bits    = ops[4].opBits;
                out.value   = ops[2].reg;
                break;
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadMemReg:
            {
                const bool     isStore = inst.op == MicroInstrOpcode::LoadMemReg;
                const MicroReg addr    = isStore ? ops[0].reg : ops[1].reg;
                const auto     it      = addrDefs.find(addr.packed);
                if (it == addrDefs.end() || it->second >= pos)
                    return false;
                const MicroInstrOperand* addrOps = loop.ops[it->second];
                SWC_ASSERT(loop.insts[it->second]->op == MicroInstrOpcode::LoadAddrAmcRegMem);
                // [0] dst, [1] base, [2] index, [3] dst bits, [4] value bits, [5] scale, [6] disp
                if (addrOps[3].opBits != MicroOpBits::B64 || addrOps[4].opBits != MicroOpBits::B64)
                    return false;
                out.isStore = isStore;
                out.base    = addrOps[1].reg;
                out.index   = addrOps[2].reg;
                out.scale   = addrOps[5].valueU64;
                out.disp    = addrOps[6].valueU64 + ops[3].valueU64;
                out.bits    = ops[2].opBits;
                out.value   = isStore ? ops[1].reg : ops[0].reg;
                break;
            }
            default:
                return false;
        }

        if (out.bits != MicroOpBits::B8 && out.bits != MicroOpBits::B16 && out.bits != MicroOpBits::B32 && out.bits != MicroOpBits::B64)
            return false;
        out.width = getNumBytes(out.bits);
        return (out.scale == 1 || out.scale == 2 || out.scale == 4 || out.scale == 8) && out.base.isValid() && out.index.isValid() && !out.base.isInstructionPointer();
    }

    bool rangesDisjoint(uint64_t startA, uint32_t widthA, uint64_t startB, uint32_t widthB)
    {
        // Address arithmetic wraps. Neither start may fall inside the other
        // byte range, including a range that crosses the end of the address space.
        return startB - startA >= widthA && startA - startB >= widthB;
    }

    struct Forward
    {
        uint32_t consumer = K_INVALID;
        uint32_t producer = K_INVALID;
    };

    // Finds loads whose value the previous trip already read or stored.
    void findForwards(std::vector<Forward>& out, FunctionInfo& fn, const Loop& loop)
    {
        out.clear();
        const auto n = static_cast<uint32_t>(loop.refs.size());

        // Registers the body defines, and where; the index candidates are
        // those defined once, by an immediate step.
        FlatKeyMap<uint32_t>                   defCount;
        FlatKeyMap<uint32_t>                   lastDef;
        std::unordered_map<uint32_t, uint32_t> addrDefs;
        for (uint32_t i = 0; i < n; ++i)
        {
            for (const MicroReg def : loop.useDefs[i].defs)
            {
                defCount.getOrInsert(def.packed)++;
                lastDef.getOrInsert(def.packed) = i;
            }
        }
        const auto definitionCount = [&](const MicroReg reg) {
            const uint32_t* count = defCount.find(reg.packed);
            return count ? *count : 0;
        };
        for (uint32_t i = 0; i < n; ++i)
        {
            if (loop.insts[i]->op != MicroInstrOpcode::LoadAddrAmcRegMem)
                continue;
            const MicroReg dst = loop.ops[i][0].reg;
            if (definitionCount(dst) == 1)
                addrDefs[dst.packed] = i;
        }

        std::vector<Access> accesses;
        for (uint32_t i = 0; i < n; ++i)
        {
            const MicroInstr&    inst = *loop.insts[i];
            const MicroInstrDef& info = MicroInstr::info(inst.op);
            Access               access;
            const bool           known = describeAccess(access, loop, i, addrDefs);
            // Any write the rule cannot place may hit the carried element.
            if (info.flags.has(MicroInstrFlagsE::WritesMemory) && (!known || !access.isStore))
                return;
            if (known)
                accesses.push_back(access);
        }

        for (const Access& consumer : accesses)
        {
            if (consumer.isStore || fn.relocated.contains(loop.refs[consumer.pos].get()))
                continue;

            // The index: one definition in the body, `index += step`, after
            // every access through it; the base: no definition in the body.
            if (definitionCount(consumer.base) != 0 || definitionCount(consumer.index) != 1)
                continue;
            const uint32_t           stepPos  = *lastDef.find(consumer.index.packed);
            const MicroInstr&        stepInst = *loop.insts[stepPos];
            const MicroInstrOperand* stepOps  = loop.ops[stepPos];
            if (stepInst.op != MicroInstrOpcode::OpBinaryRegImm || stepOps[1].opBits != MicroOpBits::B64 ||
                (stepOps[2].microOp != MicroOp::Add && stepOps[2].microOp != MicroOp::Subtract) || stepOps[3].hasWideImmediateValue())
                continue;
            const uint64_t stepImm = stepOps[3].valueU64;
            const uint64_t step    = stepOps[2].microOp == MicroOp::Add ? stepImm : 0 - stepImm;
            const uint64_t stride  = step * consumer.scale;
            if (!rangesDisjoint(stride, consumer.width, 0, consumer.width))
                continue;

            bool indexAfterAll = true;
            for (const Access& access : accesses)
            {
                if (access.index == consumer.index && access.pos > stepPos)
                    indexAfterAll = false;
            }
            for (const auto& [reg, pos] : addrDefs)
            {
                if (loop.ops[pos][2].reg == consumer.index && pos > stepPos)
                    indexAfterAll = false;
            }
            if (!indexAfterAll)
                continue;

            // The producer: a later access of the previous trip to the same
            // element, through the same base and index.
            const Access* producer = nullptr;
            for (const Access& candidate : accesses)
            {
                if (candidate.pos <= consumer.pos || candidate.base != consumer.base || candidate.index != consumer.index ||
                    candidate.scale != consumer.scale || candidate.bits != consumer.bits || candidate.disp != consumer.disp + stride)
                    continue;
                if (candidate.value.isAnyFloat() != consumer.value.isAnyFloat())
                    continue;
                producer = &candidate;
                break;
            }
            if (!producer)
                continue;

            // Every other store of the body runs between the producer of the
            // previous trip and the consumer of this one, at one of the two
            // index values. Each must miss the carried element on both.
            MicroReg   consumerRoot;
            uint64_t   consumerOffset = 0;
            const bool consumerRooted = resolveRoot(fn, consumerRoot, consumerOffset, consumer.base);
            bool       disjoint       = true;
            for (const Access& store : accesses)
            {
                if (!store.isStore || &store == producer)
                    continue;
                if (store.index != consumer.index || store.scale != consumer.scale)
                {
                    disjoint = false;
                    break;
                }
                uint64_t baseDelta = 0;
                if (store.base != consumer.base)
                {
                    MicroReg storeRoot;
                    uint64_t storeOffset = 0;
                    if (!consumerRooted || !resolveRoot(fn, storeRoot, storeOffset, store.base) || storeRoot != consumerRoot)
                    {
                        disjoint = false;
                        break;
                    }
                    baseDelta = storeOffset - consumerOffset;
                }

                // Relative to the carried element at this trip's index.
                const uint64_t sameTrip     = baseDelta + store.disp - consumer.disp;
                const uint64_t previousTrip = sameTrip - stride;
                if (!rangesDisjoint(sameTrip, store.width, 0, consumer.width) || !rangesDisjoint(previousTrip, store.width, 0, consumer.width))
                {
                    disjoint = false;
                    break;
                }
            }
            if (!disjoint)
                continue;

            out.push_back({.consumer = consumer.pos, .producer = producer->pos});
        }
    }

    struct ForwardPlan
    {
        MicroInstrOperand preload[8]  = {};
        MicroInstrRef     producerRef = MicroInstrRef::invalid();
        MicroInstrRef     consumerRef = MicroInstrRef::invalid();
        MicroReg          producerValue;
        MicroReg          consumerDst;
        MicroOpBits       bits = MicroOpBits::Zero;
    };

    struct LoopPlan
    {
        MicroInstrRef            labelRef;
        std::vector<ForwardPlan> forwards;
    };

    bool planLoop(LoopPlan& out, FunctionInfo& fn, const Loop& loop)
    {
        std::vector<Forward> forwards;
        findForwards(forwards, fn, loop);
        if (forwards.empty())
            return false;

        // Everything is read from the body before the first insertion, which
        // may grow the instruction and operand storage.
        out.labelRef = loop.labelRef;
        auto& plans  = out.forwards;
        for (const Forward& forward : forwards)
        {
            const MicroInstr&        consumerInst = *loop.insts[forward.consumer];
            const MicroInstrOperand* consumerOps  = loop.ops[forward.consumer];
            const MicroInstr&        producerInst = *loop.insts[forward.producer];
            const MicroInstrOperand* producerOps  = loop.ops[forward.producer];

            ForwardPlan& plan = plans.emplace_back();
            plan.consumerRef  = loop.refs[forward.consumer];
            plan.producerRef  = loop.refs[forward.producer];
            plan.consumerDst  = consumerOps[0].reg;
            if (consumerInst.op == MicroInstrOpcode::LoadAmcRegMem)
            {
                for (uint32_t k = 0; k < std::min<uint32_t>(consumerInst.numOperands, 8); ++k)
                    plan.preload[k] = consumerOps[k];
                plan.bits = consumerOps[4].opBits;
            }
            else
            {
                // `dst = [addr + disp]` with `addr = &[base + index * scale + add]`.
                const MicroReg addr    = consumerOps[1].reg;
                uint32_t       addrPos = K_INVALID;
                for (uint32_t i = 0; i < forward.consumer; ++i)
                {
                    if (loop.insts[i]->op == MicroInstrOpcode::LoadAddrAmcRegMem && loop.ops[i][0].reg == addr)
                        addrPos = i;
                }
                SWC_ASSERT(addrPos != K_INVALID);
                const MicroInstrOperand* addrOps = loop.ops[addrPos];
                plan.bits                        = consumerOps[2].opBits;
                plan.preload[1].reg              = addrOps[1].reg;
                plan.preload[2].reg              = addrOps[2].reg;
                plan.preload[5].valueU64         = addrOps[5].valueU64;
                plan.preload[6].valueU64         = addrOps[6].valueU64 + consumerOps[3].valueU64;
            }
            plan.preload[3].opBits = plan.bits;
            plan.preload[4].opBits = plan.bits;

            if (producerInst.op == MicroInstrOpcode::LoadAmcMemReg)
                plan.producerValue = producerOps[2].reg;
            else if (producerInst.op == MicroInstrOpcode::LoadMemReg)
                plan.producerValue = producerOps[1].reg;
            else
                plan.producerValue = producerOps[0].reg;
        }
        return !plans.empty();
    }

    void applyLoopPlan(MicroPassContext& context, const LoopPlan& plan, uint32_t& nextInt, uint32_t& nextFloat)
    {
        auto& storage  = *context.instructions;
        auto& operands = *context.operands;
        // A load can also supply an earlier load's next-trip value. Keep every
        // producer reference alive until all copies have been inserted.
        for (const ForwardPlan& forward : plan.forwards)
        {
            SWC_ASSERT(nextInt < MicroReg::K_MAX_INDEX && nextFloat < MicroReg::K_MAX_INDEX);
            const MicroReg carried = forward.consumerDst.isAnyFloat() ? MicroReg::virtualFloatReg(nextFloat++) : MicroReg::virtualIntReg(nextInt++);
            auto           preload = std::to_array(forward.preload);
            preload[0].reg         = carried;
            storage.insertDerivedBefore(operands, plan.labelRef, MicroInstrOpcode::LoadAmcRegMem, preload);
            MicroInstrOperand copy[3];
            copy[0].reg    = carried;
            copy[1].reg    = forward.producerValue;
            copy[2].opBits = forward.bits;
            storage.insertDerivedBefore(operands, storage.findNextInstructionRef(forward.producerRef), MicroInstrOpcode::LoadRegReg, copy);
            copy[0].reg = forward.consumerDst;
            copy[1].reg = carried;
            storage.insertDerivedBefore(operands, forward.consumerRef, MicroInstrOpcode::LoadRegReg, copy);
        }
        for (const ForwardPlan& forward : plan.forwards)
            storage.erase(forward.consumerRef);
    }

    bool forwardRound(MicroPassContext& context)
    {
        FunctionInfo fn;
        fn.context  = &context;
        fn.storage  = context.instructions;
        fn.operands = context.operands;

        for (const MicroRelocation& relocation : context.builder->codeRelocations())
        {
            if (relocation.instructionRef.isValid())
                fn.relocated.insert(relocation.instructionRef.get());
        }

        uint32_t position   = 0;
        bool     inEntry    = true;
        bool     hasJumpTab = false;
        for (auto it = fn.storage->view().begin(), end = fn.storage->view().end(); it != end; ++it, ++position)
        {
            const MicroInstr&        inst = *it;
            const MicroInstrOperand* ops  = inst.ops(*fn.operands);
            const MicroInstrDef&     info = MicroInstr::info(inst.op);
            if (inst.op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::JumpInstruction) || info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
            {
                if (inEntry)
                    fn.entryEnd = position;
                inEntry = false;
            }
            if (inst.op == MicroInstrOpcode::JumpTableData || inst.op == MicroInstrOpcode::LoadLabelAddress)
                hasJumpTab = true;

            uint32_t target = 0;
            if (MicroLabelHelpers::tryGetJumpTargetLabelId(target, inst, ops))
                fn.labelReferences.getOrInsert(target)++;

            const MicroInstrUseDef useDef = inst.collectUseDef(*fn.operands, context.encoder);
            for (const MicroReg def : useDef.defs)
            {
                RegDefs& defs = fn.defs.getOrInsert(def.packed);
                defs.count++;
                defs.ref = it.current;
                defs.pos = position;
            }
        }
        if (inEntry)
            fn.entryEnd = position;
        // A jump table names labels the scan does not count as references.
        if (hasJumpTab)
            return false;

        std::vector<LoopPlan> plans;

        // Rotated single-block loops: `label L; body; jcc L`, entered only by
        // falling into the label.
        MicroInstrRef previousRef = MicroInstrRef::invalid();
        for (auto it = fn.storage->view().begin(), end = fn.storage->view().end(); it != end;)
        {
            const MicroInstrRef labelRef = it.current;
            uint32_t            labelId  = 0;
            if (!MicroLabelHelpers::tryGetLabelId(labelId, *it, it->ops(*fn.operands)))
            {
                previousRef = it.current;
                ++it;
                continue;
            }

            // A conditional jump falls through; any other transfer does not.
            const MicroInstr* previous = previousRef.isValid() ? fn.storage->ptr(previousRef) : nullptr;
            bool              fallsIn  = previous != nullptr;
            if (previous && previous->op == MicroInstrOpcode::JumpCond)
                fallsIn = previous->ops(*fn.operands)[0].cpuCond != MicroCond::Unconditional;
            else if (previous && MicroInstr::info(previous->op).flags.has(MicroInstrFlagsE::TerminatorInstruction))
                fallsIn = false;

            Loop loop;
            loop.labelRef = labelRef;
            previousRef   = it.current;
            ++it;
            bool closed = false;
            while (it != end && loop.refs.size() < K_MAX_BODY)
            {
                const MicroInstr&        inst = *it;
                const MicroInstrOperand* ops  = inst.ops(*fn.operands);
                const MicroInstrDef&     info = MicroInstr::info(inst.op);
                if (inst.op == MicroInstrOpcode::Label)
                    break;
                if (info.flags.has(MicroInstrFlagsE::JumpInstruction) || info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                {
                    uint32_t target = 0;
                    closed          = MicroLabelHelpers::tryGetJumpTargetLabelId(target, inst, ops) && target == labelId && ops[0].cpuCond != MicroCond::Unconditional;
                    if (closed)
                        loop.latchRef = it.current;
                    break;
                }
                MicroInstrUseDef useDef = inst.collectUseDef(*fn.operands, context.encoder);
                if (useDef.isCall || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                    std::ranges::find(useDef.defs, context.encoder->stackPointerReg()) != useDef.defs.end())
                    break;
                loop.refs.push_back(it.current);
                loop.insts.push_back(&inst);
                loop.ops.push_back(ops);
                loop.useDefs.push_back(std::move(useDef));
                previousRef = it.current;
                ++it;
            }

            const uint32_t* labelReferenceCount = fn.labelReferences.find(labelId);
            if (!closed || !fallsIn || !labelReferenceCount || *labelReferenceCount != 1 || loop.refs.empty())
                continue;

            LoopPlan plan;
            if (planLoop(plan, fn, loop))
                plans.push_back(std::move(plan));
        }

        if (plans.empty())
            return false;
        uint32_t nextInt   = 0;
        uint32_t nextFloat = 0;
        MicroPassHelpers::computeNextVirtualRegIndices(context, nextInt, nextFloat);
        for (const LoopPlan& plan : plans)
            applyLoopPlan(context, plan, nextInt, nextFloat);
        return true;
    }
}

Result MicroLoopLoadForwardPass::run(MicroPassContext& context)
{
    if (!context.builder || !context.instructions || !context.operands || !context.encoder)
        return Result::Continue;
    if (!context.builder->controlFlowGraph().hasLoop())
        return Result::Continue;

    if (forwardRound(context))
    {
        if (context.ssaState)
            context.ssaState->invalidate();
        context.builder->invalidateControlFlowGraph();
        context.passChanged = true;
    }
    return Result::Continue;
}

SWC_END_NAMESPACE();
