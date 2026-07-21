#include "pch.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Sanitizer/SanitizerCheck.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Sanitizer::Sanitizer(MicroPassContext& context) :
    context_(context),
    stackBaseReg_(context.debugStackBaseVirtualReg)
{
    // Extents of the declared variables in the frame, for the bound check. Sorted so
    // lookups can bisect. Locals carry their slot in offset()/codeGenLocalSize()
    // (assignLocalStackSlot); by-value parameters spilled to a debug home use the
    // debugStackSlot pair (only set when debug info is on).
    if (context.sanitizerFunction)
    {
        for (const SymbolVariable* symVar : context.sanitizerFunction->localVariables())
        {
            if (symVar && symVar->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && symVar->codeGenLocalSize())
                localSlots_.push_back({.start = static_cast<int64_t>(symVar->offset()), .size = symVar->codeGenLocalSize()});
        }

        for (const SymbolVariable* symVar : context.sanitizerFunction->parameters())
        {
            if (symVar && symVar->debugStackSlotSize())
                localSlots_.push_back({.start = static_cast<int64_t>(symVar->debugStackSlotOffset()), .size = symVar->debugStackSlotSize()});
        }

        std::ranges::sort(localSlots_, [](const LocalSlotExtent& a, const LocalSlotExtent& b) { return a.start < b.start; });
    }
}

bool Sanitizer::findLocalSlotExtents(int64_t offset, int64_t& outStart, uint64_t& outSize) const
{
    auto it = std::ranges::upper_bound(localSlots_, offset, {}, [](const LocalSlotExtent& e) { return e.start; });
    if (it == localSlots_.begin())
        return false;
    --it;
    if (offset >= it->start + static_cast<int64_t>(it->size))
        return false;

    outStart = it->start;
    outSize  = it->size;
    return true;
}

bool Sanitizer::run(std::span<SanitizerCheck* const> checks)
{
    const MicroControlFlowGraph& cfg = context_.builder->controlFlowGraph();
    const uint32_t               n   = cfg.instructionCount();
    if (n == 0 || n > K_MAX_INSTRUCTIONS || checks.empty())
        return reported_;

    cfg_ = &cfg;
    inState_.assign(n, {});
    reached_.assign(n, 0);
    inWorklist_.assign(n, 0);

    // Detect in-place mutations of the stack-base register (call-area frame shapes
    // fold a local's offset into it): every frame offset the engine computes is then
    // shifted by an unknown amount. Slot-relative facts stay self-consistent, but the
    // bound check compares against absolute extents and must stand down.
    if (stackBaseReg_.isValid())
    {
        for (uint32_t i = 0; i < n; i++)
        {
            const MicroInstr& scanInst = *context_.instructions->ptr(cfg.instructionRefs()[i]);
            if (scanInst.op != MicroInstrOpcode::OpBinaryRegImm && scanInst.op != MicroInstrOpcode::OpBinaryRegReg)
                continue;

            const MicroInstrOperand* scanOps = scanInst.numOperands ? scanInst.ops(*context_.operands) : nullptr;
            if (scanOps && scanOps[0].reg == stackBaseReg_)
            {
                stackBaseStable_ = false;
                break;
            }
        }
    }

    // Resolve call targets up front: checks identify what a call invokes, and the
    // fixpoint needs to know which calls never return.
    callTargets_.clear();
    for (const MicroRelocation& rel : context_.builder->codeRelocations())
    {
        if (rel.targetSymbol &&
            (rel.kind == MicroRelocation::Kind::LocalFunctionAddress || rel.kind == MicroRelocation::Kind::ForeignFunctionAddress))
            callTargets_[rel.instructionRef.get()] = rel.targetSymbol;
    }

    // Chain heads are the only points where states are stored and joined: the entry,
    // any merge point (several predecessors), and any target of a branching
    // predecessor. Everything between two heads is a straight-line chain whose states
    // are recomputed on the fly — storing a state per instruction (and copying it on
    // every worklist iteration) made big loopy functions take minutes.
    isHead_.assign(n, 0);
    isHead_[0] = 1;
    for (uint32_t i = 1; i < n; i++)
    {
        const MicroControlFlowGraph::EdgeList& preds = cfg.predecessors(i);
        if (preds.size() >= 2)
        {
            isHead_[i] = 1;
            continue;
        }
        if (preds.size() == 1)
        {
            const MicroInstr&    predInst = *context_.instructions->ptr(cfg.instructionRefs()[preds[0]]);
            const MicroInstrDef& predDef  = MicroInstr::info(predInst.op);
            if (cfg.successors(preds[0]).size() != 1 || predDef.flags.has(MicroInstrFlagsE::ConditionalJump))
                isHead_[i] = 1;
        }
    }

    reached_[0]    = 1;
    inWorklist_[0] = 1;
    std::vector<uint32_t> worklist{0};

    // The worklist is a min-heap on the instruction index: the linear layout is close
    // to a topological order, so processing lower indices first lets predecessors
    // settle before their successors and cuts re-iteration dramatically.
    uint64_t steps = 0;
    converged_     = true;
    while (!worklist.empty())
    {
        if (steps >= K_ITERATION_CAP)
        {
            converged_ = false;
            break;
        }

        std::ranges::pop_heap(worklist, std::greater());
        const uint32_t head = worklist.back();
        worklist.pop_back();
        inWorklist_[head] = 0;

        walkChain(head, inState_[head], {}, &worklist, steps);
    }

    // Apply the checks only on the converged states, walking each reached chain with
    // the same transfer function. A capped run never reaches this point with checks:
    // its states are transient pre-join snapshots, and reporting on them would flag
    // spurious findings a finished join would have widened away.
    if (!converged_)
        return reported_;

    uint64_t checkSteps = 0;
    for (uint32_t i = 0; i < n; i++)
    {
        if (isHead_[i] && reached_[i])
            walkChain(i, inState_[i], checks, nullptr, checkSteps);
    }

    return reported_;
}

void Sanitizer::walkChain(uint32_t head, SanitizerState cur, std::span<SanitizerCheck* const> checks, std::vector<uint32_t>* worklist, uint64_t& steps)
{
    const MicroControlFlowGraph& cfg   = *cfg_;
    uint32_t                     index = head;

    for (;;)
    {
        steps++;
        const MicroInstrRef      instRef = cfg.instructionRefs()[index];
        const MicroInstr&        inst    = *context_.instructions->ptr(instRef);
        const MicroInstrDef&     def     = MicroInstr::info(inst.op);
        const MicroInstrOperand* ops     = inst.numOperands ? inst.ops(*context_.operands) : nullptr;

        transferCallTarget_ = nullptr;
        if (def.flags.has(MicroInstrFlagsE::IsCallInstruction))
        {
            const auto itTarget = callTargets_.find(instRef.get());
            if (itTarget != callTargets_.end())
                transferCallTarget_ = itTarget->second;
        }
        currentCallTarget_ = transferCallTarget_;

        for (SanitizerCheck* check : checks)
            check->run(*this, cur, inst, def, ops);

        applyValueEffects(cur, inst, def, ops);

        const MicroControlFlowGraph::EdgeList& succs = cfg.successors(index);
        if (def.flags.has(MicroInstrFlagsE::TerminatorInstruction) && !def.flags.has(MicroInstrFlagsE::JumpInstruction))
            return; // Ret: no successor

        // A call that never returns (the runtime panic behind a safety guard) has no
        // fall-through: propagating its cleared state would pollute the join after the
        // guard and erase the very facts the checks front-run the guard with.
        if (transferCallTarget_ && def.flags.has(MicroInstrFlagsE::IsCallInstruction))
        {
            const auto calleeName = transferCallTarget_->name(ctx());
            if (calleeName == "@safetypanic" || calleeName == "@panic")
                return;
        }

        if (def.flags.has(MicroInstrFlagsE::ConditionalJump) && succs.size() == 2 && ops)
        {
            if (worklist)
                propagateConditionalBranch(cur, ops, succs, *worklist);
            return;
        }

        if (isModelledSingleEdge(def, succs))
        {
            const uint32_t s = succs[0];
            if (!isHead_[s])
            {
                index = s; // straight-line: keep walking with the same state
                continue;
            }
            if (worklist)
                propagate(cur, s, *worklist);
            return;
        }

        for (const uint32_t s : succs)
        {
            if (!worklist)
                continue;
            SanitizerState edge = cur;
            dropZeros(edge);
            edge.flagsSubject = MicroReg::invalid();
            propagate(edge, s, *worklist);
        }
        return;
    }
}

TaskContext& Sanitizer::ctx() const
{
    return *context_.taskContext;
}

bool Sanitizer::isModelledSingleEdge(const MicroInstrDef& def, const MicroControlFlowGraph::EdgeList& succs)
{
    // A plain fall-through or an unconditional direct jump: the state flows unchanged to
    // the single successor.
    return succs.size() == 1 && !def.flags.has(MicroInstrFlagsE::ConditionalJump);
}

SanitizerValue Sanitizer::getReg(const SanitizerState& state, MicroReg reg) const
{
    if (stackBaseReg_.isValid() && reg == stackBaseReg_)
        return SanitizerValue::makeStackAddr(0);
    const auto it = state.regs.find(reg.packed);
    return it == state.regs.end() ? SanitizerValue{} : it->second.value;
}

const SanitizerRegInfo* Sanitizer::findReg(const SanitizerState& state, MicroReg reg)
{
    const auto it = state.regs.find(reg.packed);
    return it == state.regs.end() ? nullptr : &it->second;
}

void Sanitizer::setReg(SanitizerState& state, MicroReg reg, const SanitizerRegInfo& info)
{
    if (reg.isValid())
        state.regs[reg.packed] = info;
}

void Sanitizer::setRegValue(SanitizerState& state, MicroReg reg, const SanitizerValue& value)
{
    if (reg.isValid())
        state.regs[reg.packed] = SanitizerRegInfo{value};
}

bool Sanitizer::resolveStackSlot(const SanitizerState& state, MicroReg base, uint64_t offset, int64_t& outSlot) const
{
    const SanitizerValue baseValue = getReg(state, base);
    if (!baseValue.isStackAddr())
        return false;
    outSlot = baseValue.stackOffset + static_cast<int64_t>(offset);
    return true;
}

void Sanitizer::propagate(const SanitizerState& edge, uint32_t index, std::vector<uint32_t>& worklist)
{
    bool changed;
    if (!reached_[index])
    {
        reached_[index] = 1;
        inState_[index] = edge;
        changed         = true;
    }
    else
    {
        changed = joinInto(inState_[index], edge);
    }

    if (changed && !inWorklist_[index])
    {
        inWorklist_[index] = 1;
        worklist.push_back(index);
        std::ranges::push_heap(worklist, std::greater());
    }
}

bool Sanitizer::joinInto(SanitizerState& into, const SanitizerState& from)
{
    bool changed = false;

    for (auto it = into.stack.begin(); it != into.stack.end();)
    {
        const auto f = from.stack.find(it->first);
        if (f == from.stack.end() || f->second != it->second)
        {
            it      = into.stack.erase(it);
            changed = true;
        }
        else
            ++it;
    }

    for (auto it = into.regs.begin(); it != into.regs.end();)
    {
        const auto f = from.regs.find(it->first);
        if (f == from.regs.end() || f->second != it->second)
        {
            it      = into.regs.erase(it);
            changed = true;
        }
        else
            ++it;
    }

    for (auto it = into.movedFrom.begin(); it != into.movedFrom.end();)
    {
        const auto f = from.movedFrom.find(it->first);
        if (f == from.movedFrom.end() || f->second != it->second)
        {
            it      = into.movedFrom.erase(it);
            changed = true;
        }
        else
            ++it;
    }

    for (auto it = into.freedPtrSlots.begin(); it != into.freedPtrSlots.end();)
    {
        if (!from.freedPtrSlots.contains(*it))
        {
            it      = into.freedPtrSlots.erase(it);
            changed = true;
        }
        else
            ++it;
    }

    for (auto it = into.undefinedInit.begin(); it != into.undefinedInit.end();)
    {
        const auto f = from.undefinedInit.find(it->first);
        if (f == from.undefinedInit.end() || f->second != it->second)
        {
            it      = into.undefinedInit.erase(it);
            changed = true;
        }
        else
            ++it;
    }

    if (into.flagsSubject.isValid() && into.flagsSubject != from.flagsSubject)
    {
        into.flagsSubject = MicroReg::invalid();
        changed           = true;
    }

    return changed;
}

namespace
{
    // Moved-from ranges must never survive a write they could alias, or the analysis
    // would report a false positive after a legitimate re-initialization. The store
    // width is not always recoverable from the operands, so overlap is tested against a
    // conservative maximal store size.
    constexpr uint64_t K_ASSUMED_STORE_SIZE = 16;

    void clearMovedFromOverlaps(SanitizerState& state, const int64_t slot)
    {
        for (auto it = state.movedFrom.begin(); it != state.movedFrom.end();)
        {
            const int64_t rangeStart = it->first;
            const int64_t rangeEnd   = rangeStart + static_cast<int64_t>(it->second);
            if (slot + static_cast<int64_t>(K_ASSUMED_STORE_SIZE) > rangeStart && slot < rangeEnd)
                it = state.movedFrom.erase(it);
            else
                ++it;
        }
    }

    void clearUndefinedInitOverlaps(SanitizerState& state, const int64_t slot)
    {
        for (auto it = state.undefinedInit.begin(); it != state.undefinedInit.end();)
        {
            const int64_t rangeStart = it->first;
            const int64_t rangeEnd   = rangeStart + static_cast<int64_t>(it->second);
            if (slot + static_cast<int64_t>(K_ASSUMED_STORE_SIZE) > rangeStart && slot < rangeEnd)
                it = state.undefinedInit.erase(it);
            else
                ++it;
        }
    }
}

void Sanitizer::applyValueEffects(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) const
{
    if (!state.movedFrom.empty() && inst.op != MicroInstrOpcode::SanityInvalidate)
    {
        if (def.flags.has(MicroInstrFlagsE::IsCallInstruction))
        {
            // A call can write through any escaped pointer: forget every moved-from range.
            state.movedFrom.clear();
        }
        else if (def.flags.has(MicroInstrFlagsE::WritesMemory))
        {
            int64_t slot = 0;
            if (def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) &&
                resolveStackSlot(state, ops[def.memBaseOperandIndex].reg, ops[def.memOffsetOperandIndex].valueU64, slot))
                clearMovedFromOverlaps(state, slot);
            else
                state.movedFrom.clear();
        }
    }

    // Undefined-init ranges follow the moved-from discipline exactly: any store that
    // could alias the range initializes it, a call can write through any escaped
    // pointer (out-parameter fills) and forgets everything.
    if (!state.undefinedInit.empty() && inst.op != MicroInstrOpcode::SanityUndefined)
    {
        if (def.flags.has(MicroInstrFlagsE::IsCallInstruction))
        {
            state.undefinedInit.clear();
        }
        else if (def.flags.has(MicroInstrFlagsE::WritesMemory))
        {
            int64_t slot = 0;
            if (def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) &&
                resolveStackSlot(state, ops[def.memBaseOperandIndex].reg, ops[def.memOffsetOperandIndex].valueU64, slot))
                clearUndefinedInitOverlaps(state, slot);
            else
                state.undefinedInit.clear();
        }
    }

    // Freed-pointer slots follow the same aliasing discipline: any write that could
    // reassign the pointer revalidates it. Calls clear the set below (after marking
    // the freeing call's own arguments).
    if (!state.freedPtrSlots.empty() && !def.flags.has(MicroInstrFlagsE::IsCallInstruction) && def.flags.has(MicroInstrFlagsE::WritesMemory))
    {
        int64_t slot = 0;
        if (def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) &&
            resolveStackSlot(state, ops[def.memBaseOperandIndex].reg, ops[def.memOffsetOperandIndex].valueU64, slot))
        {
            for (auto it = state.freedPtrSlots.begin(); it != state.freedPtrSlots.end();)
            {
                if (slot + static_cast<int64_t>(K_ASSUMED_STORE_SIZE) > *it && slot < *it + static_cast<int64_t>(sizeof(void*)))
                    it = state.freedPtrSlots.erase(it);
                else
                    ++it;
            }
        }
        else
            state.freedPtrSlots.clear();
    }

    switch (inst.op)
    {
        case MicroInstrOpcode::SanityInvalidate:
        {
            int64_t slot = 0;
            if (resolveStackSlot(state, ops[0].reg, 0, slot) && ops[1].valueU64 > 0)
                state.movedFrom[slot] = ops[1].valueU64;
            return;
        }
        case MicroInstrOpcode::SanityUndefined:
        {
            int64_t slot = 0;
            if (resolveStackSlot(state, ops[0].reg, 0, slot) && ops[1].valueU64 > 0)
                state.undefinedInit[slot] = ops[1].valueU64;
            return;
        }
        case MicroInstrOpcode::LoadRegImm:
            setRegValue(state, ops[0].reg, SanitizerValue::makeConstant(ops[2].valueU64));
            return;

        case MicroInstrOpcode::LoadRegPtrImm:
            setRegValue(state, ops[0].reg, SanitizerValue::makeConstant(ops[2].valueU64));
            return;

        case MicroInstrOpcode::ClearReg:
            setRegValue(state, ops[0].reg, SanitizerValue::makeConstant(0));
            return;

        case MicroInstrOpcode::LoadRegPtrReloc:
            setRegValue(state, ops[0].reg, SanitizerValue::makeGlobalAddr());
            return;

        case MicroInstrOpcode::LoadRegReg:
        case MicroInstrOpcode::LoadZeroExtRegReg:
        case MicroInstrOpcode::LoadSignedExtRegReg:
        {
            // A move or a widening extension propagates the whole tracked info (value +
            // origin + zero-test fact). Extensions only widen (bool/narrow int -> wider),
            // so zero-ness and the guard facts are preserved: `dst == 0` iff the source
            // (and its origin slot) is zero. The value goes through getReg so the special
            // stack-base register is resolved even though it is not stored in the map.
            SanitizerRegInfo info;
            if (const SanitizerRegInfo* src = findReg(state, ops[1].reg))
                info = *src;
            info.value = getReg(state, ops[1].reg);
            setReg(state, ops[0].reg, info);
            return;
        }

        case MicroInstrOpcode::LoadAddrRegMem:
        {
            const SanitizerValue baseValue = getReg(state, ops[1].reg);
            int64_t              slot      = 0;
            if (resolveStackSlot(state, ops[1].reg, ops[3].valueU64, slot))
            {
                // The formed address starts the object being addressed: that is the
                // origin, unless the base already carries one (derived pointer).
                const int64_t origin = baseValue.hasStackOrigin() ? baseValue.stackOrigin : slot;
                setRegValue(state, ops[0].reg, SanitizerValue::makeStackAddr(slot, origin));
            }
            else if (baseValue.isZero())
                setRegValue(state, ops[0].reg, SanitizerValue::makeConstant(0)); // zero-derived
            else if (baseValue.kind == SanitizerValueKind::GlobalAddr)
                setRegValue(state, ops[0].reg, SanitizerValue::makeGlobalAddr());
            else
                setRegValue(state, ops[0].reg, {});
            return;
        }

        case MicroInstrOpcode::LoadAddrAmcRegMem:
        {
            // ops: [dst, base, mulReg, opBitsDst, opBitsValue, mulValue, addValue].
            // Indexed addressing 'base + index*scale + disp': with a provable constant
            // index the resulting frame offset is exact, and the base keeps the origin.
            const SanitizerValue baseValue = getReg(state, ops[1].reg);
            const SanitizerValue idxValue  = getReg(state, ops[2].reg);
            if (baseValue.isStackAddr() && idxValue.isConstant())
            {
                const int64_t offset = baseValue.stackOffset + static_cast<int64_t>(idxValue.constant * ops[5].valueU64 + ops[6].valueU64);
                const int64_t origin = baseValue.hasStackOrigin() ? baseValue.stackOrigin : baseValue.stackOffset;
                setRegValue(state, ops[0].reg, SanitizerValue::makeStackAddr(offset, origin));
            }
            else if (baseValue.isKnownNonZero())
                setRegValue(state, ops[0].reg, SanitizerValue::makeNonZero());
            else
                setRegValue(state, ops[0].reg, {});
            return;
        }

        case MicroInstrOpcode::LoadRegMem:
        case MicroInstrOpcode::LoadSignedExtRegMem:
        case MicroInstrOpcode::LoadZeroExtRegMem:
        {
            // Widening slot loads keep the tracked value: extensions only widen, so
            // zero-ness, constants and the slot-origin fact are preserved. A tracked
            // constant is extended from the source width so signed values stay exact.
            int64_t slot = 0;
            if (resolveStackSlot(state, ops[def.memBaseOperandIndex].reg, ops[def.memOffsetOperandIndex].valueU64, slot))
            {
                const auto       it = state.stack.find(slot);
                SanitizerRegInfo info;
                info.value         = it != state.stack.end() ? it->second : SanitizerValue{};
                info.hasOriginSlot = true;
                info.originSlot    = slot;

                if (info.value.isConstant() && inst.op != MicroInstrOpcode::LoadRegMem)
                {
                    const uint32_t srcBits = getNumBits(ops[3].opBits);
                    if (srcBits && srcBits < 64)
                    {
                        const uint64_t mask = (1ULL << srcBits) - 1;
                        uint64_t       v    = info.value.constant & mask;
                        if (inst.op == MicroInstrOpcode::LoadSignedExtRegMem && (v >> (srcBits - 1)) & 1)
                            v |= ~mask;
                        info.value = SanitizerValue::makeConstant(v);
                    }
                }

                setReg(state, ops[0].reg, info);
            }
            else
                setRegValue(state, ops[0].reg, {});
            return;
        }

        case MicroInstrOpcode::LoadMemReg:
        {
            int64_t slot = 0;
            if (resolveStackSlot(state, ops[0].reg, ops[3].valueU64, slot))
                state.stack[slot] = getReg(state, ops[1].reg);
            return;
        }

        case MicroInstrOpcode::LoadMemImm:
        {
            int64_t slot = 0;
            if (resolveStackSlot(state, ops[0].reg, ops[2].valueU64, slot))
                state.stack[slot] = SanitizerValue::makeConstant(ops[3].valueU64);
            return;
        }

        case MicroInstrOpcode::OpBinaryRegImm:
        {
            const MicroReg       reg      = ops[0].reg;
            const SanitizerValue cur      = getReg(state, reg);
            const uint64_t       imm      = ops[3].valueU64;
            const bool           isAddSub = ops[2].microOp == MicroOp::Add || ops[2].microOp == MicroOp::Subtract;
            if (isAddSub && cur.isZero())
                setRegValue(state, reg, SanitizerValue::makeConstant(0));
            else if (ops[2].microOp == MicroOp::Add && cur.isStackAddr())
                setRegValue(state, reg, SanitizerValue::makeStackAddr(cur.stackOffset + static_cast<int64_t>(imm), cur.stackOrigin));
            else if (ops[2].microOp == MicroOp::Add && cur.kind == SanitizerValueKind::Constant)
                setRegValue(state, reg, SanitizerValue::makeConstant(cur.constant + imm));
            else if (ops[2].microOp == MicroOp::Subtract && cur.isStackAddr())
                setRegValue(state, reg, SanitizerValue::makeStackAddr(cur.stackOffset - static_cast<int64_t>(imm), cur.stackOrigin));
            else if (ops[2].microOp == MicroOp::Subtract && cur.kind == SanitizerValueKind::Constant)
                setRegValue(state, reg, SanitizerValue::makeConstant(cur.constant - imm));
            else
                setRegValue(state, reg, {});
            return;
        }

        case MicroInstrOpcode::OpBinaryRegReg:
        {
            // ops: [dst (use+def), src, opBits, microOp]. The instruction defines the CPU
            // flags, so the compare-subject tracking is reset like the default path does.
            state.flagsSubject = MicroReg::invalid();

            if (ops[3].microOp == MicroOp::ConvertFloatToFloat)
            {
                // Float width conversion (cvtss2sd / cvtsd2ss); opBits is the SOURCE
                // width. A tracked constant is converted so float constants keep flowing
                // (this is how a float literal reaches its use: LoadRegImm f64 bits, then
                // a convert to the destination width).
                const SanitizerValue src = getReg(state, ops[1].reg);
                if (src.kind == SanitizerValueKind::Constant && ops[2].opBits == MicroOpBits::B64)
                {
                    const auto narrowed = static_cast<float>(std::bit_cast<double>(src.constant));
                    setRegValue(state, ops[0].reg, SanitizerValue::makeConstant(std::bit_cast<uint32_t>(narrowed)));
                }
                else if (src.kind == SanitizerValueKind::Constant && ops[2].opBits == MicroOpBits::B32)
                {
                    const auto widened = static_cast<double>(std::bit_cast<float>(static_cast<uint32_t>(src.constant)));
                    setRegValue(state, ops[0].reg, SanitizerValue::makeConstant(std::bit_cast<uint64_t>(widened)));
                }
                else
                    setRegValue(state, ops[0].reg, {});
                return;
            }

            if (ops[3].microOp == MicroOp::Move)
            {
                setRegValue(state, ops[0].reg, getReg(state, ops[1].reg));
                return;
            }

            setRegValue(state, ops[0].reg, {});
            return;
        }

        case MicroInstrOpcode::CmpRegImm:
            state.flagsSubject = ops[2].valueU64 == 0 ? ops[0].reg : MicroReg::invalid();
            return;

        case MicroInstrOpcode::CmpRegReg:
            if (getReg(state, ops[1].reg).isZero())
                state.flagsSubject = ops[0].reg;
            else if (getReg(state, ops[0].reg).isZero())
                state.flagsSubject = ops[1].reg;
            else
                state.flagsSubject = MicroReg::invalid();
            return;

        case MicroInstrOpcode::SetCondReg:
        {
            SanitizerRegInfo        info; // value stays Unknown (a 0/1 bool)
            const SanitizerRegInfo* subject    = state.flagsSubject.isValid() ? findReg(state, state.flagsSubject) : nullptr;
            bool                    trueIfZero = false;
            if (subject && subject->hasOriginSlot && condIsZeroTest(ops[1].cpuCond, trueIfZero))
            {
                info.hasZeroTest        = true;
                info.zeroTestSlot       = subject->originSlot;
                info.zeroTestTrueIfZero = trueIfZero;
            }
            setReg(state, ops[0].reg, info);
            return;
        }

        default:
            break;
    }

    if (def.flags.has(MicroInstrFlagsE::IsCallInstruction))
    {
        // A callee with a FREES summary invalidates what its marked arguments point
        // to: remember the slots those pointers were loaded from, BEFORE the clobber
        // wipe erases the argument registers.
        SmallVector<int64_t> newlyFreed;
        const auto*          calleeFn  = transferCallTarget_ ? transferCallTarget_->safeCast<SymbolFunction>() : nullptr;
        const uint64_t       freesMask = calleeFn ? calleeFn->freesParamsMask() : 0;
        if (freesMask && ops)
        {
            const CallConv& callConv = CallConv::get(ops[0].callConv);
            for (size_t i = 0; i < callConv.intArgRegs.size() && i < 64; i++)
            {
                if (!((freesMask >> i) & 1))
                    continue;
                const SanitizerRegInfo* argInfo = findReg(state, callConv.intArgRegs[i]);
                if (argInfo && argInfo->hasOriginSlot)
                    newlyFreed.push_back(argInfo->originSlot);
            }
        }

        // Calls clobber caller-saved registers and may mutate escaped locals.
        state.regs.clear();
        state.stack.clear();
        state.freedPtrSlots.clear();
        state.flagsSubject = MicroReg::invalid();
        for (const int64_t slot : newlyFreed)
            state.freedPtrSlots.insert(slot);
        return;
    }

    if (def.flags.has(MicroInstrFlagsE::DefinesCpuFlags))
        state.flagsSubject = MicroReg::invalid();
    invalidateDefs(state, inst, def, ops);
}

void Sanitizer::invalidateDefs(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    const auto regCount = std::min(static_cast<size_t>(inst.numOperands), def.regModes.size());
    for (uint32_t i = 0; i < regCount; i++)
        if (def.regModes[i] == MicroInstrRegMode::Def || def.regModes[i] == MicroInstrRegMode::UseDef)
            setRegValue(state, ops[i].reg, {});
}

bool Sanitizer::condIsZeroTest(MicroCond cond, bool& outTrueIfZero)
{
    switch (cond)
    {
        case MicroCond::Equal:
        case MicroCond::Zero:
            outTrueIfZero = true;
            return true;
        case MicroCond::NotEqual:
        case MicroCond::NotZero:
            outTrueIfZero = false;
            return true;
        default:
            return false;
    }
}

// Conditional branch: narrow the tested slot on each edge, prune infeasible edges,
// and fall back to dropping provable zeros when it cannot be modelled.
void Sanitizer::propagateConditionalBranch(const SanitizerState& state, const MicroInstrOperand* ops, const MicroControlFlowGraph::EdgeList& succs, std::vector<uint32_t>& worklist)
{
    const SanitizerRegInfo* subject = state.flagsSubject.isValid() ? findReg(state, state.flagsSubject) : nullptr;

    bool    condTrueIfSubjectZero = false;
    int64_t slot                  = 0;
    bool    slotZeroIfSubjectZero = false;
    if (subject && condIsZeroTest(ops[0].cpuCond, condTrueIfSubjectZero) &&
        resolveGuardSlot(*subject, slot, slotZeroIfSubjectZero))
    {
        // successors = [taken (cond true), fallthrough (cond false)].
        queueRefined(state, succs[0], slot, condTrueIfSubjectZero == slotZeroIfSubjectZero, worklist);
        queueRefined(state, succs[1], slot, (!condTrueIfSubjectZero) == slotZeroIfSubjectZero, worklist);
        return;
    }

    // Unmodellable branch: keep exploring, but drop provable zeros only if the branch
    // actually tested a value against zero (the flags encode a zero-comparison), so
    // nothing is reported past a zero-guard we could not attribute to a slot (e.g.
    // `assume`). A comparison against a non-zero constant — such as the INT_MIN/-1
    // overflow checks the front end wraps every integer division in — does not constrain
    // zero-ness, so provable zeros must survive it (else no division-by-zero is caught).
    const bool dropAcrossEdge = state.flagsSubject.isValid();
    for (const uint32_t s : succs)
    {
        SanitizerState edge = state;
        if (dropAcrossEdge)
            dropZeros(edge);
        edge.flagsSubject = MicroReg::invalid();
        propagate(edge, s, worklist);
    }
}

bool Sanitizer::resolveGuardSlot(const SanitizerRegInfo& subject, int64_t& outSlot, bool& outSlotZeroIfSubjectZero)
{
    if (subject.hasZeroTest)
    {
        // subject is a bool == (slot is zero) when zeroTestTrueIfZero.
        // subject == 0 (false) ⇒ slot is zero iff !zeroTestTrueIfZero.
        outSlot                  = subject.zeroTestSlot;
        outSlotZeroIfSubjectZero = !subject.zeroTestTrueIfZero;
        return true;
    }
    if (subject.hasOriginSlot)
    {
        outSlot                  = subject.originSlot;
        outSlotZeroIfSubjectZero = true; // subject IS the value: subject==0 ⇒ slot zero
        return true;
    }
    return false;
}

void Sanitizer::queueRefined(const SanitizerState& state, uint32_t index, int64_t slot, bool slotIsZero, std::vector<uint32_t>& worklist)
{
    const auto           it      = state.stack.find(slot);
    const SanitizerValue current = it != state.stack.end() ? it->second : SanitizerValue{};

    if (slotIsZero && current.isKnownNonZero())
        return; // infeasible
    if (!slotIsZero && current.isZero())
        return; // infeasible

    SanitizerState edge = state;
    edge.stack[slot]    = slotIsZero ? SanitizerValue::makeConstant(0) : SanitizerValue::makeNonZero();
    edge.flagsSubject   = MicroReg::invalid();
    propagate(edge, index, worklist);
}

void Sanitizer::dropZeros(SanitizerState& state)
{
    for (auto& info : state.regs | std::views::values)
        if (info.value.isZero())
            info.value = {};
    for (auto& value : state.stack | std::views::values)
        if (value.isZero())
            value = {};
}

void Sanitizer::report(const MicroInstr& inst, DiagnosticId id)
{
    const SourceCodeRef& codeRef = inst.debugSourceInfo.sourceCodeRef;

    // The same source location can be reached by several paths and can lower to several
    // instructions; report each (location, diagnostic) pair at most once.
    const uint64_t key = (static_cast<uint64_t>(codeRef.srcViewRef.get()) << 40) ^ (static_cast<uint64_t>(codeRef.tokRef.get()) << 8) ^ static_cast<uint64_t>(id);
    reported_          = true;
    if (!reportedLocations_.insert(key).second)
        return;

    ResolvedDebugSourceInfo resolved;
    if (!tryResolveDebugSourceInfo(*context_.taskContext, resolved, inst.debugSourceInfo))
        return;

    const FileRef    fileRef = resolved.sourceFile ? resolved.sourceFile->ref() : FileRef::invalid();
    const Diagnostic diag    = Diagnostic::get(id, fileRef);
    diag.last().addSpan(resolved.codeRange, "", DiagnosticSeverity::Error);
    diag.report(*context_.taskContext);
}

SWC_END_NAMESPACE();
