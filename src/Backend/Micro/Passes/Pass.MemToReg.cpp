#include "pch.h"
#include "Backend/Micro/Passes/Pass.MemToReg.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"
#include "Support/Memory/MemoryProfile.h"

// mem2reg: promote non-escaping fixed-width scalar stack slots to virtual
// registers. See the header for rationale and the loop-carried safety rule.
//
// Conservative by construction:
//  - it only fires for slots reached exclusively as the base of a constant-
//    offset scalar load/store, and abandons promotion for the whole function on
//    any use of the frame base (or a frame-derived address) it cannot explain
//    (taking a slot's address exposes the whole object, so partial reasoning is
//    unsound);
//  - it never promotes a slot whose value is live across a loop back-edge,
//    since a loop-carried mutable virtual register breaks downstream register
//    optimizations that assume a single dominating definition.

SWC_BEGIN_NAMESPACE();

namespace
{
    struct SlotAccess
    {
        MicroInstrRef ref     = MicroInstrRef::invalid();
        uint64_t      offset  = 0;
        MicroOpBits   bits    = MicroOpBits::Zero;
        bool          isWrite = false;
    };

    struct SlotInfo
    {
        bool                    hasWrite = false;
        SmallVector<SlotAccess> accesses;
    };

    bool isHandledScalarMemOp(MicroInstrOpcode op)
    {
        return op == MicroInstrOpcode::LoadRegMem ||
               op == MicroInstrOpcode::LoadMemReg ||
               op == MicroInstrOpcode::LoadMemImm;
    }

    bool isPromotableBits(MicroOpBits bits)
    {
        // b32/b64 only. For integers, 64-bit copies are full width and 32-bit
        // writes zero-extend to the full register on x86-64, so a register copy
        // matches the zero-extending memory load (b8/b16 would leave stale upper
        // bits). For floats, b32/b64 are the scalar single/double widths and a
        // float register copy is full-width.
        return bits == MicroOpBits::B32 || bits == MicroOpBits::B64;
    }

    // The local frame base is the stack-pointer-derived register the front-end
    // addresses locals through. It is either a plain copy `mov reg, sp` or a
    // constant lea `lea reg, [sp + C]` (the compiler often biases it past the
    // saved-register / spill area). We pick the candidate that is (a) never
    // redefined or arithmetic-modified after its definition — a register that
    // gets `reg += imm` is a transient address-calculation scratch, not the
    // stable base — and (b) actually used as the base of constant-offset scalar
    // loads/stores, preferring the most-used one. The escape analysis then
    // validates the choice and bails the whole function if it is wrong.
    MicroReg detectFrameBase(MicroStorage& storage, MicroOperandStorage& operands, MicroReg stackPointer, MicroInstrRef& outDefRef)
    {
        struct Cand
        {
            MicroInstrRef defRef   = MicroInstrRef::invalid();
            uint32_t      baseUses = 0;
            bool          stable   = true;
        };
        std::unordered_map<MicroReg, Cand> cands;

        // Pass A: collect sp-derived definitions.
        for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
        {
            const MicroInstr&        inst = *it;
            const MicroInstrOperand* ops  = inst.ops(operands);
            if (!ops)
                continue;
            const bool isMov = inst.op == MicroInstrOpcode::LoadRegReg && ops[1].reg == stackPointer;
            const bool isLea = inst.op == MicroInstrOpcode::LoadAddrRegMem && ops[1].reg == stackPointer;
            if ((isMov || isLea) && ops[0].reg.isVirtualInt())
            {
                Cand& c = cands[ops[0].reg];
                if (c.defRef.isValid())
                    c.stable = false; // defined more than once: not a stable base.
                else
                    c.defRef = it.current;
            }
        }
        if (cands.empty())
            return MicroReg::invalid();

        // Pass B: invalidate candidates redefined/modified elsewhere, and count
        // their uses as a constant-offset memory base.
        for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
        {
            const MicroInstr&        inst = *it;
            const MicroInstrOperand* ops  = inst.ops(operands);
            if (!ops)
                continue;

            SmallVector<MicroInstrRegOperandRef> regRefs;
            inst.collectRegOperands(operands, regRefs, nullptr);
            for (const auto& rref : regRefs)
            {
                if (!rref.reg || !rref.def)
                    continue;
                const auto found = cands.find(*rref.reg);
                if (found != cands.end() && it.current != found->second.defRef)
                    found->second.stable = false;
            }

            // Count uses where the candidate is the addressing base: a direct
            // scalar load/store base, or the base of a `lea` that derives a
            // sub-address (`lea ar, [base + off]`). The latter matters because
            // the front-end frequently materializes each local's address with a
            // lea first, so the frame base may never appear as a direct base.
            MicroReg baseReg = MicroReg::invalid();
            if (inst.op == MicroInstrOpcode::LoadRegMem || inst.op == MicroInstrOpcode::LoadAddrRegMem)
                baseReg = ops[1].reg;
            else if (inst.op == MicroInstrOpcode::LoadMemReg || inst.op == MicroInstrOpcode::LoadMemImm)
                baseReg = ops[0].reg;
            if (baseReg.isValid())
            {
                const auto found = cands.find(baseReg);
                if (found != cands.end())
                    ++found->second.baseUses;
            }
        }

        MicroReg best;
        uint32_t bestUses = 0;
        for (const auto& [reg, c] : cands)
        {
            if (c.stable && c.defRef.isValid() && c.baseUses > bestUses)
            {
                best      = reg;
                bestUses  = c.baseUses;
                outDefRef = c.defRef;
            }
        }
        return best;
    }

    struct Promotion
    {
        uint64_t    offset;
        MicroOpBits bits;
        bool        isFloat;
    };

    //===-- Loop-carried safety analysis ----------------------------------===//
    //
    // A promoted slot is unsafe when its value is live across a loop back-edge.
    // We compute, on the per-instruction CFG, the set of back-edge targets, then
    // run a standard backward liveness for each candidate slot (load = use,
    // full-width store = kill). A slot is loop-carried iff it is live-in at the
    // function entry or at any back-edge target.

    // Iterative DFS over the per-instruction CFG; an edge to a node currently on
    // the DFS stack is a back-edge. Records the targets of those edges.
    void collectBackEdgeTargets(const MicroControlFlowGraph& cfg, std::unordered_set<uint32_t>& outTargets)
    {
        const uint32_t n = cfg.instructionCount();
        if (n == 0)
            return;

        enum Color : uint8_t
        {
            White,
            Gray,
            Black
        };
        std::vector           color(n, White);
        std::vector<uint32_t> nextChild(n, 0);
        std::vector<uint32_t> stack;
        stack.reserve(n);

        for (uint32_t root = 0; root < n; ++root)
        {
            if (color[root] != White)
                continue;
            // Only start DFS from genuine entries (no predecessors) and, as a
            // fallback, from any still-unvisited node so unreachable cycles are
            // still classified conservatively.
            color[root]     = Gray;
            nextChild[root] = 0;
            stack.push_back(root);

            while (!stack.empty())
            {
                const uint32_t u    = stack.back();
                const auto&    succ = cfg.successors(u);
                if (nextChild[u] < succ.size())
                {
                    const uint32_t v = succ[nextChild[u]++];
                    if (v >= n)
                        continue;
                    if (color[v] == White)
                    {
                        color[v]     = Gray;
                        nextChild[v] = 0;
                        stack.push_back(v);
                    }
                    else if (color[v] == Gray)
                    {
                        // u -> v with v on the active stack: back-edge.
                        outTargets.insert(v);
                    }
                }
                else
                {
                    color[u] = Black;
                    stack.pop_back();
                }
            }
        }
    }

    // Backward liveness for a single slot. `use[i]` = instruction i loads the
    // slot, `kill[i]` = instruction i fully overwrites it. Returns true if the
    // slot is live-in at the entry or at any back-edge target (i.e. its value
    // can survive a loop iteration) — meaning it must NOT be promoted.
    bool slotIsLoopCarried(const MicroControlFlowGraph&        cfg,
                           const std::vector<uint8_t>&         use,
                           const std::vector<uint8_t>&         kill,
                           const std::unordered_set<uint32_t>& backEdgeTargets)
    {
        const uint32_t       n = cfg.instructionCount();
        std::vector<uint8_t> liveIn(n, 0);

        const auto succs = cfg.successors();

        bool           changed  = true;
        uint32_t       guard    = 0;
        const uint32_t maxIters = n + 4;
        while (changed && guard++ < maxIters)
        {
            changed = false;
            for (uint32_t idx = n; idx-- > 0;)
            {
                uint8_t liveOut = 0;
                for (const uint32_t s : succs[idx])
                {
                    if (s < n && liveIn[s])
                    {
                        liveOut = 1;
                        break;
                    }
                }
                const uint8_t newIn = use[idx] ? 1 : (kill[idx] ? 0 : liveOut);
                if (newIn != liveIn[idx])
                {
                    liveIn[idx] = newIn;
                    changed     = true;
                }
            }
        }

        // Entry node(s): any node with no predecessors. Live-in there means the
        // slot is read before being written from function start.
        const auto preds = cfg.predecessors();
        for (uint32_t idx = 0; idx < n; ++idx)
        {
            if (preds[idx].empty() && liveIn[idx])
                return true;
        }
        for (const uint32_t t : backEdgeTargets)
        {
            if (t < n && liveIn[t])
                return true;
        }
        return false;
    }
}

Result MicroMemToRegPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/MemToReg");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    if (!context.builder)
        return Result::Continue;

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;

    const CallConv& callConv     = CallConv::get(context.callConvKind);
    const MicroReg  stackPointer = callConv.stackPointer;
    if (!stackPointer.isValid())
        return Result::Continue;

    MicroInstrRef  frameBaseDefRef = MicroInstrRef::invalid();
    const MicroReg frameBase       = detectFrameBase(storage, operands, stackPointer, frameBaseDefRef);
    if (!frameBase.isValid() || !frameBaseDefRef.isValid())
        return Result::Continue;

    // ---- Pass 1: collect address registers `lea ar, [fb + off]`. ----
    std::unordered_map<MicroReg, uint64_t> addrRegOffset;
    std::unordered_set<MicroReg>           badAddrReg;

    for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
    {
        const MicroInstr&        inst = *it;
        const MicroInstrOperand* ops  = inst.ops(operands);
        if (!ops)
            continue;

        if (it.current == frameBaseDefRef)
            continue;

        if (inst.op == MicroInstrOpcode::LoadAddrRegMem && ops[1].reg == frameBase)
        {
            const MicroReg ar = ops[0].reg;
            if (!ar.isVirtualInt() || ar == frameBase)
                badAddrReg.insert(ar);
            else if (addrRegOffset.contains(ar))
                badAddrReg.insert(ar);
            else
                addrRegOffset[ar] = ops[3].valueU64;
        }
    }

    auto isTracked = [&](MicroReg reg) -> bool {
        return reg == frameBase || addrRegOffset.contains(reg);
    };

    // ---- Pass 2: classify accesses; bail the whole function on any escape. ----
    std::unordered_map<uint64_t, SlotInfo> slots;
    bool                                   bail = false;

    for (auto it = storage.view().begin(), end = storage.view().end(); it != end && !bail; ++it)
    {
        const MicroInstrRef      ref  = it.current;
        const MicroInstr&        inst = *it;
        const MicroInstrOperand* ops  = inst.ops(operands);
        if (!ops)
            continue;

        if (ref == frameBaseDefRef)
            continue;
        if (inst.op == MicroInstrOpcode::LoadAddrRegMem && ops[1].reg == frameBase)
            continue;

        MicroReg baseReg   = MicroReg::invalid();
        uint64_t baseSlot  = 0;
        bool     baseValid = false;

        auto resolveBase = [&](MicroReg reg, uint64_t extraOffset) {
            if (reg == frameBase)
            {
                baseReg = reg, baseSlot = extraOffset, baseValid = true;
            }
            else
            {
                const auto found = addrRegOffset.find(reg);
                if (found != addrRegOffset.end() && !badAddrReg.contains(reg))
                    baseReg = reg, baseSlot = found->second + extraOffset, baseValid = true;
            }
        };

        MicroReg   valueReg = MicroReg::invalid();
        SlotAccess pending;
        bool       hasPending = false;
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegMem:
                resolveBase(ops[1].reg, ops[3].valueU64);
                valueReg = ops[0].reg;
                if (baseValid)
                    pending = {ref, baseSlot, ops[2].opBits, false}, hasPending = true;
                break;
            case MicroInstrOpcode::LoadMemReg:
                resolveBase(ops[0].reg, ops[3].valueU64);
                valueReg = ops[1].reg;
                if (baseValid)
                    pending = {ref, baseSlot, ops[2].opBits, true}, hasPending = true;
                break;
            case MicroInstrOpcode::LoadMemImm:
                resolveBase(ops[0].reg, ops[2].valueU64);
                if (baseValid)
                    pending = {ref, baseSlot, ops[1].opBits, true}, hasPending = true;
                break;
            default:
                break;
        }

        // Moving a tracked pointer as a value means the address escapes.
        if (baseValid && valueReg.isValid() && isTracked(valueReg))
        {
            bail = true;
            break;
        }

        // Any tracked register appearing anywhere other than as the base of a
        // recognized scalar access is an escape we cannot reason about.
        SmallVector<MicroInstrRegOperandRef> regRefs;
        inst.collectRegOperands(operands, regRefs, context.encoder);
        for (const auto& rref : regRefs)
        {
            if (!rref.reg || !isTracked(*rref.reg))
                continue;
            const bool isExplainedBase = baseValid && *rref.reg == baseReg && isHandledScalarMemOp(inst.op);
            if (!isExplainedBase)
            {
                bail = true;
                break;
            }
        }
        if (bail)
            break;

        if (hasPending)
        {
            SlotInfo& slot = slots[pending.offset];
            slot.accesses.push_back(pending);
            if (pending.isWrite)
                slot.hasWrite = true;
        }
    }

    if (bail)
        return Result::Continue;

    // ---- Decide candidate offsets: consistent b32/b64 width, a single
    //      register class (all-int or all-float), a write, and no overlap with
    //      any other accessed slot. ----
    SmallVector<Promotion> promotions;

    for (auto& [offset, slot] : slots)
    {
        if (slot.accesses.empty() || !slot.hasWrite)
            continue;

        const MicroOpBits bits       = slot.accesses[0].bits;
        bool              consistent = isPromotableBits(bits);
        for (const SlotAccess& acc : slot.accesses)
        {
            if (acc.bits != bits)
            {
                consistent = false;
                break;
            }
        }
        if (!consistent)
            continue;

        // Determine the slot's register class from its reg-valued accesses; all
        // must agree. Float slots may not carry a LoadMemImm (an integer
        // immediate must not be written into a float register).
        bool ok         = true;
        bool classKnown = false;
        bool isFloat    = false;
        for (const SlotAccess& acc : slot.accesses)
        {
            const MicroInstr*        inst = storage.ptr(acc.ref);
            const MicroInstrOperand* iops = inst ? inst->ops(operands) : nullptr;
            if (!iops)
            {
                ok = false;
                break;
            }
            if (inst->op == MicroInstrOpcode::LoadMemImm)
                continue; // class resolved from reg accesses
            const MicroReg valueReg = (inst->op == MicroInstrOpcode::LoadRegMem) ? iops[0].reg : iops[1].reg;
            const bool     regFloat = valueReg.isAnyFloat();
            if (!regFloat && !valueReg.isAnyInt())
            {
                ok = false;
                break;
            }
            if (!classKnown)
            {
                classKnown = true;
                isFloat    = regFloat;
            }
            else if (isFloat != regFloat)
            {
                ok = false; // mixed int/float view of the same slot
                break;
            }
        }
        if (!ok || !classKnown)
            continue;

        if (isFloat)
        {
            // A float slot initialized via an integer immediate store can't be
            // turned into a float register copy safely — skip it.
            bool hasImm = false;
            for (const SlotAccess& acc : slot.accesses)
            {
                const MicroInstr* inst = storage.ptr(acc.ref);
                if (inst && inst->op == MicroInstrOpcode::LoadMemImm)
                {
                    hasImm = true;
                    break;
                }
            }
            if (hasImm)
                continue;
        }

        promotions.push_back({offset, bits, isFloat});
    }

    if (promotions.empty())
        return Result::Continue;

    SmallVector<Promotion> filtered;
    for (const Promotion& p : promotions)
    {
        const uint64_t pStart  = p.offset;
        const uint64_t pEnd    = p.offset + getNumBytes(p.bits);
        bool           overlap = false;
        for (const auto& [otherOffset, otherSlot] : slots)
        {
            if (otherOffset == p.offset)
                continue;
            for (const SlotAccess& acc : otherSlot.accesses)
            {
                const uint64_t aStart = acc.offset;
                const uint64_t aEnd   = acc.offset + getNumBytes(acc.bits);
                if (!(aEnd <= pStart || pEnd <= aStart))
                {
                    overlap = true;
                    break;
                }
            }
            if (overlap)
                break;
        }
        if (!overlap)
            filtered.push_back(p);
    }
    promotions = std::move(filtered);
    if (promotions.empty())
        return Result::Continue;

    // ---- Loop-carried safety filter: drop any candidate whose value is live
    //      across a loop back-edge (promoting it to a mutable register would
    //      expose it to register optimizations that miscompile loop-carried
    //      multi-def values). ----
    {
        const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
        if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
            return Result::Continue; // can't prove safety: promote nothing.

        const uint32_t n = cfg.instructionCount();
        if (n == 0)
            return Result::Continue;

        // Map instruction ref -> CFG index.
        std::unordered_map<uint32_t, uint32_t> refToIndex;
        refToIndex.reserve(n);
        const auto instrRefs = cfg.instructionRefs();
        for (uint32_t i = 0; i < n; ++i)
            refToIndex[instrRefs[i].get()] = i;

        std::unordered_set<uint32_t> backEdgeTargets;
        collectBackEdgeTargets(cfg, backEdgeTargets);

        SmallVector<Promotion> safe;
        for (const Promotion& p : promotions)
        {
            std::vector<uint8_t> use(n, 0);
            std::vector<uint8_t> kill(n, 0);
            bool                 mappingOk = true;
            for (const SlotAccess& acc : slots[p.offset].accesses)
            {
                const auto found = refToIndex.find(acc.ref.get());
                if (found == refToIndex.end())
                {
                    mappingOk = false;
                    break;
                }
                const uint32_t idx = found->second;
                if (acc.isWrite)
                    kill[idx] = 1;
                else
                    use[idx] = 1;
            }
            if (!mappingOk)
                continue; // an access we can't locate in the CFG: skip to be safe.

            if (!slotIsLoopCarried(cfg, use, kill, backEdgeTargets))
                safe.push_back(p);
        }
        promotions = std::move(safe);
    }
    if (promotions.empty())
        return Result::Continue;

    // ---- Allocate a fresh virtual register per promoted offset (int or float). ----
    uint32_t nextVirtualIntRegIndex   = std::max<uint32_t>(1, context.builder->nextVirtualIntRegIndexHint());
    uint32_t nextVirtualFloatRegIndex = 1;
    for (const MicroInstr& inst : storage.view())
    {
        SmallVector<MicroInstrRegOperandRef> refs;
        inst.collectRegOperands(operands, refs, context.encoder);
        for (const auto& ref : refs)
        {
            if (!ref.reg || ref.reg->index() >= MicroReg::K_MAX_INDEX)
                continue;
            if (ref.reg->isVirtualInt())
                nextVirtualIntRegIndex = std::max(nextVirtualIntRegIndex, ref.reg->index() + 1);
            else if (ref.reg->isVirtualFloat())
                nextVirtualFloatRegIndex = std::max(nextVirtualFloatRegIndex, ref.reg->index() + 1);
        }
    }

    std::unordered_map<uint64_t, MicroReg> slotReg;
    for (const Promotion& p : promotions)
        slotReg[p.offset] = p.isFloat ? MicroReg::virtualFloatReg(nextVirtualFloatRegIndex++)
                                      : MicroReg::virtualIntReg(nextVirtualIntRegIndex++);

    // ---- Rewrite all accesses of the promoted slots to register ops. ----
    for (const Promotion& p : promotions)
    {
        const MicroReg    vreg = slotReg[p.offset];
        const MicroOpBits bits = p.bits;

        for (const SlotAccess& acc : slots[p.offset].accesses)
        {
            MicroInstr* inst = storage.ptr(acc.ref);
            if (!inst)
                continue;
            MicroInstrOperand* ops = inst->ops(operands);
            if (!ops)
                continue;

            if (inst->op == MicroInstrOpcode::LoadRegMem)
            {
                const MicroReg dst = ops[0].reg;
                ops[0].reg         = dst;
                ops[1].reg         = vreg;
                ops[2].opBits      = bits;
                inst->op           = MicroInstrOpcode::LoadRegReg;
                inst->numOperands  = 3;
            }
            else if (inst->op == MicroInstrOpcode::LoadMemReg)
            {
                const MicroReg src = ops[1].reg;
                ops[0].reg         = vreg;
                ops[1].reg         = src;
                ops[2].opBits      = bits;
                inst->op           = MicroInstrOpcode::LoadRegReg;
                inst->numOperands  = 3;
            }
            else if (inst->op == MicroInstrOpcode::LoadMemImm)
            {
                const MicroInstrOperand imm = ops[3];
                ops[0].reg                  = vreg;
                ops[1].opBits               = bits;
                ops[2]                      = imm;
                inst->op                    = MicroInstrOpcode::LoadRegImm;
                inst->numOperands           = 3;
            }
        }
    }

    if (context.ssaState)
        context.ssaState->invalidate();
    context.builder->invalidateControlFlowGraph();
    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
