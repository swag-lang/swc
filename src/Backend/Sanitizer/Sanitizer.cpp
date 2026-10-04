#include "pch.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Sanitizer/SanitizerCheck.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isPlainLoadInstruction(const MicroInstrOpcode op)
    {
        switch (op)
        {
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadVolatileRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadVecRegMem:
                return true;
            default:
                return false;
        }
    }

    uint8_t sanitizerCheckInterests(const MicroInstr& inst, const MicroInstrDef& def)
    {
        uint8_t result = 0;
        if (inst.op == MicroInstrOpcode::OpBinaryRegImm || inst.op == MicroInstrOpcode::OpBinaryRegReg)
            result |= static_cast<uint8_t>(SanitizerCheckInterest::Binary);
        if (def.flags.has(MicroInstrFlagsE::IsCallInstruction) || inst.op == MicroInstrOpcode::SanityRelease)
            result |= static_cast<uint8_t>(SanitizerCheckInterest::Call);
        if (inst.op == MicroInstrOpcode::Ret)
            result |= static_cast<uint8_t>(SanitizerCheckInterest::Return);

        uint8_t baseOperandIndex = 0;
        if (MicroPassHelpers::dereferenceBaseOperandIndex(baseOperandIndex, inst.op, def))
            result |= static_cast<uint8_t>(SanitizerCheckInterest::Dereference);

        if (isPlainLoadInstruction(inst.op))
            result |= static_cast<uint8_t>(SanitizerCheckInterest::PlainLoad);

        return result;
    }
}

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
                localSlots_.push_back({.start = static_cast<int64_t>(symVar->offset()), .size = symVar->codeGenLocalSize(), .sym = symVar});
        }

        for (const SymbolVariable* symVar : context.sanitizerFunction->parameters())
        {
            if (symVar && symVar->debugStackSlotSize())
                localSlots_.push_back({.start = static_cast<int64_t>(symVar->debugStackSlotOffset()), .size = symVar->debugStackSlotSize(), .sym = symVar});
        }

        std::ranges::sort(localSlots_, [](const LocalSlotExtent& a, const LocalSlotExtent& b) { return a.start < b.start; });
    }
}

const Sanitizer::LocalSlotExtent* Sanitizer::findLocalSlot(const int64_t offset) const
{
    auto it = std::ranges::upper_bound(localSlots_, offset, {}, [](const LocalSlotExtent& e) { return e.start; });
    if (it == localSlots_.begin())
        return nullptr;
    --it;
    return offset < it->start + static_cast<int64_t>(it->size) ? &*it : nullptr;
}

bool Sanitizer::findLocalSlotExtents(int64_t offset, int64_t& outStart, uint64_t& outSize) const
{
    const LocalSlotExtent* slot = findLocalSlot(offset);
    if (!slot)
        return false;

    outStart = slot->start;
    outSize  = slot->size;
    return true;
}

void Sanitizer::computeFunctionProperties()
{
    definitionCounts_.clear();
    stackBaseStable_        = true;
    needsReleaseProvenance_ = false;

    const uint32_t n                = cfg_->instructionCount();
    const bool     inspectStackBase = stackBaseReg_.isValid();
    for (uint32_t i = 0; i < n; i++)
    {
        const MicroInstr& inst = *context_.instructions->ptr(cfg_->instructionRefs()[i]);
        needsReleaseProvenance_ |= inst.op == MicroInstrOpcode::SanityRelease;
        const MicroInstrDef&     def = MicroInstr::info(inst.op);
        const MicroInstrOperand* ops = inst.numOperands ? inst.ops(*context_.operands) : nullptr;
        if (!ops)
            continue;

        if (inspectStackBase && stackBaseStable_ &&
            (inst.op == MicroInstrOpcode::OpBinaryRegImm || inst.op == MicroInstrOpcode::OpBinaryRegReg) &&
            ops[0].reg == stackBaseReg_)
            stackBaseStable_ = false;

        const auto modes    = def.resolvedRegModes(ops);
        const auto regCount = std::min(static_cast<size_t>(inst.numOperands), modes.size());
        for (size_t r = 0; r < regCount; r++)
        {
            // Only virtual-register counts are queried by the provenance checks.
            if ((modes[r] == MicroInstrRegMode::Def || modes[r] == MicroInstrRegMode::UseDef) && ops[r].reg.isVirtual())
            {
                auto [it, inserted] = definitionCounts_.try_emplace(ops[r].reg.packed, 1);
                if (!inserted && it->second < 2)
                    ++it->second;
            }
        }
    }
}

bool Sanitizer::hasSingleDefinition(const MicroReg reg) const
{
    const auto it = definitionCounts_.find(reg.packed);
    return it != definitionCounts_.end() && it->second == 1;
}

bool Sanitizer::frameObjectReachable(const SanitizerState& state, const int64_t slot) const
{
    // A compiler temporary has no extent to bound, so nothing says which writes land in
    // it: only the storage of a declared variable can be proven out of reach.
    const LocalSlotExtent* extent = findLocalSlot(slot);
    return !extent || (state.escapedFrameObjects && state.escapedFrameObjects->contains(extent->start));
}

void Sanitizer::markFrameObjectEscaped(SanitizerState& state, const SanitizerValue& value) const
{
    if (!value.isStackAddr())
        return;

    // An address inside a compiler temporary marks nothing: a temporary never overlaps a
    // declared variable, so a write staying inside the object it was formed from cannot
    // reach one.
    const int64_t          offset = value.hasStackOrigin() ? value.stackOrigin : value.stackOffset;
    const LocalSlotExtent* extent = findLocalSlot(offset);
    if (extent)
    {
        if (!state.escapedFrameObjects)
            state.escapedFrameObjects.emplace();
        state.escapedFrameObjects->insert(extent->start);
    }
}

void Sanitizer::markEscapesFromValueOperands(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) const
{
    if (!ops)
        return;

    uint8_t    baseIndex = 0;
    const bool hasBase   = MicroPassHelpers::dereferenceBaseOperandIndex(baseIndex, inst.op, def);
    const auto modes     = def.resolvedRegModes(ops);
    const auto regCount  = std::min(static_cast<size_t>(inst.numOperands), modes.size());

    for (size_t r = 0; r < regCount; r++)
    {
        // Reading an address to access what it points at leaves it where it was; every
        // other read hands it to something the engine stops following.
        if (modes[r] == MicroInstrRegMode::None || (hasBase && r == baseIndex))
            continue;
        markFrameObjectEscaped(state, getReg(state, ops[r].reg));
        markFrameObjectEscaped(state, getUpperReg(state, ops[r].reg));
    }
}

void Sanitizer::markEscapesFromCallArguments(SmallVector<int64_t>& outReceived, SanitizerState& state, const CallConvKind callConvKind) const
{
    // A call's arguments are set up in registers the instruction does not name, so an
    // address reaches a callee through one of the convention's argument registers or
    // through a stack argument - and a stack argument is a store, already accounted for.
    // Scanning only those keeps the addresses the codegen materializes to reach a local,
    // and drops the moment they are used, out of the escape set.
    const CallConv& callConv = CallConv::get(callConvKind);
    for (const MicroReg reg : callConv.intArgRegs)
    {
        const SanitizerValue value = getReg(state, reg);
        if (!value.isStackAddr())
            continue;
        const int64_t          offset = value.hasStackOrigin() ? value.stackOrigin : value.stackOffset;
        const LocalSlotExtent* extent = findLocalSlot(offset);
        if (extent)
            outReceived.push_back(extent->start);
        markFrameObjectEscaped(state, value);
    }
}

bool Sanitizer::run(std::span<SanitizerCheck* const> checks)
{
    const MicroControlFlowGraph& cfg = context_.builder->controlFlowGraph();
    const uint32_t               n   = cfg.instructionCount();
    if (n == 0 || n > K_MAX_INSTRUCTIONS || checks.empty())
        return reported_;

    SmallVector<EnabledCheck> enabledChecks;
    for (SanitizerCheck* check : checks)
        enabledChecks.push_back({.check = check, .interests = check->interests()});

    cfg_ = &cfg;
    reached_.assign(n, 0);
    inWorklist_.assign(n, 0);

    // In-place mutations of the stack-base register (call-area frame shapes fold a
    // local's offset into it) invalidate the absolute extents used by the bound check.
    // Compute that property alongside the definition counts instead of scanning the
    // complete instruction stream a second time.
    computeFunctionProperties();

    // Resolve call targets up front: checks identify what a call invokes, and the
    // fixpoint needs to know which calls never return.
    callTargets_.reset();
    for (const MicroRelocation& rel : context_.builder->codeRelocations())
    {
        if (rel.targetSymbol &&
            (rel.kind == MicroRelocation::Kind::LocalFunctionAddress || rel.kind == MicroRelocation::Kind::ForeignFunctionAddress))
        {
            if (!callTargets_)
                callTargets_.emplace();
            (*callTargets_)[rel.instructionRef.get()] = rel.targetSymbol;
        }
    }

    // Chain heads are the only points where states are stored and joined: the entry,
    // any merge point (several predecessors), and any target of a branching
    // predecessor. Everything between two heads is a straight-line chain whose states
    // are recomputed on the fly — storing a state per instruction (and copying it on
    // every worklist iteration) made big loopy functions take minutes.
    headStateIndex_.assign(n, K_NO_STATE);
    headStateIndex_[0] = 0;
    uint32_t numStates = 1;
    for (uint32_t i = 1; i < n; i++)
    {
        const MicroControlFlowGraph::EdgeList& preds = cfg.predecessors(i);
        if (preds.size() >= 2)
        {
            headStateIndex_[i] = numStates++;
            continue;
        }
        if (preds.size() == 1)
        {
            const MicroInstr&    predInst = *context_.instructions->ptr(cfg.instructionRefs()[preds[0]]);
            const MicroInstrDef& predDef  = MicroInstr::info(predInst.op);
            if (cfg.successors(preds[0]).size() != 1 || predDef.flags.has(MicroInstrFlagsE::ConditionalJump))
                headStateIndex_[i] = numStates++;
        }
    }

    // Empty hash maps also allocate buckets and sentinel nodes, so only chain heads
    // get a stored state. Intermediate instructions need only the invalid index.
    inState_.clear();
    inState_.resize(numStates);
    computeChainLiveness();

    if (const SymbolFunction* function = context_.sanitizerFunction; function && needsReleaseProvenance_)
    {
        const auto& parameters = function->parameters();
        for (size_t i = 0; i < parameters.size(); ++i)
        {
            if (!parameters[i])
                continue;
            const TypeRef typeRef = ctx().typeMgr().unwrapAliasEnum(ctx(), parameters[i]->typeRef());
            if (!typeRef.isValid())
                continue;
            const TypeInfo& type = ctx().typeMgr().get(typeRef);
            MicroReg        reg;
            if (type.isAnyPointer() && !type.isNullable() && callParameterRegister(reg, *function, context_.callConvKind, i))
                setRegValue(inState_[0], reg, SanitizerValue::makeNonZero());
        }
    }

    reached_[0]    = 1;
    inWorklist_[0] = 1;
    // Small CFGs settle without allocating the heap that a vector of one element needs.
    SmallVector<uint32_t, 32> worklist{0};

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

        walkChain(head, inState_[headStateIndex_[head]], {}, &worklist, steps);
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
        if (headStateIndex_[i] != K_NO_STATE && reached_[i])
            walkChain(i, std::move(inState_[headStateIndex_[i]]), enabledChecks.span(), nullptr, checkSteps);
    }

    return reported_;
}

void Sanitizer::computeChainLiveness()
{
    const MicroControlFlowGraph& cfg       = *cfg_;
    const uint32_t               n         = cfg.instructionCount();
    const size_t                 numStates = inState_.size();

    liveRegIndex_.clear();
    liveWords_ = 0;

    // One pass over every chain, in the shape 'walkChain' follows: the virtual registers
    // a chain reads before writing them, the ones it writes, and the heads it reaches.
    // Where 'walkChain' stops early (a call that never returns), the chain here goes on;
    // that only keeps more registers live.
    struct ChainFacts
    {
        std::vector<uint32_t> uses;
        std::vector<uint32_t> defs;
        std::vector<uint32_t> succStates;
    };

    std::vector<ChainFacts> chains(numStates);
    std::vector<uint32_t>   defStamp;
    MicroInstrUseDef        useDef;
    for (uint32_t head = 0; head < n; head++)
    {
        const uint32_t stateIndex = headStateIndex_[head];
        if (stateIndex == K_NO_STATE)
            continue;

        ChainFacts& chain = chains[stateIndex];
        const auto  stamp = stateIndex + 1;
        uint32_t    index = head;
        for (;;)
        {
            const MicroInstr&    inst = *context_.instructions->ptr(cfg.instructionRefs()[index]);
            const MicroInstrDef& def  = MicroInstr::info(inst.op);
            inst.collectUseDef(useDef, *context_.operands, context_.encoder);
            for (const MicroReg reg : useDef.uses)
            {
                if (!reg.isVirtual())
                    continue;
                const uint32_t dense = liveRegIndex_.ensure(reg);
                if (dense >= defStamp.size())
                    defStamp.resize(dense + 1, 0);
                if (defStamp[dense] != stamp)
                    chain.uses.push_back(dense);
            }

            for (const MicroReg reg : useDef.defs)
            {
                if (!reg.isVirtual())
                    continue;
                const uint32_t dense = liveRegIndex_.ensure(reg);
                if (dense >= defStamp.size())
                    defStamp.resize(dense + 1, 0);
                if (defStamp[dense] != stamp)
                {
                    defStamp[dense] = stamp;
                    chain.defs.push_back(dense);
                }
            }

            const MicroControlFlowGraph::EdgeList& succs = cfg.successors(index);
            if (def.flags.has(MicroInstrFlagsE::TerminatorInstruction) && !def.flags.has(MicroInstrFlagsE::JumpInstruction))
                break;
            if (isModelledSingleEdge(def, succs) && headStateIndex_[succs[0]] == K_NO_STATE)
            {
                index = succs[0];
                continue;
            }

            for (const uint32_t succ : succs)
            {
                if (headStateIndex_[succ] != K_NO_STATE)
                    chain.succStates.push_back(headStateIndex_[succ]);
            }
            break;
        }
    }

    liveWords_ = static_cast<uint32_t>(liveRegIndex_.wordCount());
    if (!liveWords_)
        return;

    const size_t          words = static_cast<size_t>(numStates) * liveWords_;
    std::vector<uint64_t> useBits(words, 0);
    std::vector<uint64_t> defBits(words, 0);
    for (size_t s = 0; s < numStates; s++)
    {
        uint64_t* use = useBits.data() + s * liveWords_;
        uint64_t* def = defBits.data() + s * liveWords_;
        for (const uint32_t dense : chains[s].uses)
            use[dense / 64] |= 1ull << (dense % 64);
        for (const uint32_t dense : chains[s].defs)
            def[dense / 64] |= 1ull << (dense % 64);
    }

    // Backward fixpoint over the chains. State indices were handed out in instruction
    // order, so walking them in reverse visits most successors first.
    chainLiveIn_.assign(words, 0);
    chainLiveOut_.assign(words, 0);
    bool changed = true;
    while (changed)
    {
        changed = false;
        for (size_t s = numStates; s-- > 0;)
        {
            uint64_t*       in  = chainLiveIn_.data() + s * liveWords_;
            uint64_t*       out = chainLiveOut_.data() + s * liveWords_;
            const uint64_t* use = useBits.data() + s * liveWords_;
            const uint64_t* def = defBits.data() + s * liveWords_;
            for (const uint32_t succ : chains[s].succStates)
            {
                const uint64_t* succIn = chainLiveIn_.data() + static_cast<size_t>(succ) * liveWords_;
                for (uint32_t w = 0; w < liveWords_; w++)
                    out[w] |= succIn[w];
            }

            for (uint32_t w = 0; w < liveWords_; w++)
            {
                const uint64_t newIn = use[w] | (out[w] & ~def[w]);
                if (newIn != in[w])
                {
                    in[w]   = newIn;
                    changed = true;
                }
            }
        }
    }
}

void Sanitizer::pruneDeadRegs(SanitizerState& state, const uint64_t* live) const
{
    if (!live)
        return;

    const auto isDead = [&](const uint32_t packed) {
        const MicroReg reg = MicroReg::fromPacked(packed);
        if (!reg.isVirtual() || reg == state.flagsSubject || reg == stackBaseReg_)
            return false;
        const uint32_t dense = liveRegIndex_.find(reg);
        return dense == MicroDenseRegIndex::K_INVALID_INDEX || !(live[dense / 64] & (1ull << (dense % 64)));
    };

    std::erase_if(state.regs, [&](const auto& entry) { return isDead(entry.first); });
    state.upperRegValues.eraseIf([&](const auto& entry) { return isDead(entry.first); });
}

void Sanitizer::walkChain(uint32_t head, SanitizerState cur, const std::span<const EnabledCheck> checks, SmallVector<uint32_t, 32>* worklist, uint64_t& steps)
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
        if (def.flags.has(MicroInstrFlagsE::IsCallInstruction) && callTargets_)
        {
            const auto itTarget = callTargets_->find(instRef.get());
            if (itTarget != callTargets_->end())
                transferCallTarget_ = itTarget->second;
        }
        currentCallTarget_ = transferCallTarget_;

        if (!checks.empty())
        {
            const uint8_t interests = sanitizerCheckInterests(inst, def);
            for (const EnabledCheck& enabled : checks)
                if (interests & enabled.interests)
                    enabled.check->run(*this, cur, inst, def, ops);
        }

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
            if (calleeName == "Swag.safetyPanic" || calleeName == "Swag.panic")
                return;
        }

        if (def.flags.has(MicroInstrFlagsE::ConditionalJump) && succs.size() == 2 && ops)
        {
            if (worklist)
            {
                pruneDeadRegs(cur, chainLiveOut(headStateIndex_[head]));
                propagateConditionalBranch(std::move(cur), ops, succs, *worklist);
            }
            return;
        }

        if (isModelledSingleEdge(def, succs))
        {
            const uint32_t s = succs[0];
            if (headStateIndex_[s] == K_NO_STATE)
            {
                index = s; // straight-line: keep walking with the same state
                continue;
            }
            if (worklist)
                propagate(std::move(cur), s, *worklist);
            return;
        }

        if (!worklist || succs.empty())
            return;

        SanitizerState edge = std::move(cur);
        pruneDeadRegs(edge, chainLiveOut(headStateIndex_[head]));
        dropZeros(edge);
        edge.flagsSubject = MicroReg::invalid();
        for (size_t i = 0; i + 1 < succs.size(); ++i)
            propagate(edge, succs[i], *worklist);
        propagate(std::move(edge), succs.back(), *worklist);
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
    if (!reg.isValid())
        return;

    if (reg.isAnyFloat())
        state.upperRegValues.erase(reg.packed);

    // Missing entries already mean Unknown; keep provenance even without a known value.
    if (info == SanitizerRegInfo{})
        state.regs.erase(reg.packed);
    else
        state.regs.insert_or_assign(reg.packed, info);
}

SanitizerValue Sanitizer::getUpperReg(const SanitizerState& state, MicroReg reg)
{
    if (!reg.isAnyFloat())
        return {};
    const auto it = state.upperRegValues.find(reg.packed);
    return it == state.upperRegValues.end() ? SanitizerValue{} : it->second;
}

void Sanitizer::setUpperReg(SanitizerState& state, MicroReg reg, const SanitizerValue& value)
{
    if (value.kind == SanitizerValueKind::Unknown)
        state.upperRegValues.erase(reg.packed);
    else
        state.upperRegValues.insertOrAssign(reg.packed, value);
}

SanitizerValue Sanitizer::getStackLane(const SanitizerState& state, int64_t slot)
{
    const auto it = state.stack.find(slot);
    if (it == state.stack.end() || it->second.storedBytes != 8)
        return {};
    SanitizerValue value = it->second;
    value.storedBytes    = 0;
    return value;
}

void Sanitizer::setStackValue(SanitizerState& state, int64_t slot, SanitizerValue value, uint8_t size)
{
    SWC_ASSERT(size && size <= 8);
    if (size < 8)
    {
        if (value.isConstant())
            value.constant &= (1ULL << (size * 8)) - 1;
        else
            value = {};
    }
    if (value.kind == SanitizerValueKind::Unknown)
        state.stack.erase(slot);
    else
    {
        value.storedBytes = size;
        state.stack.insert_or_assign(slot, value);
    }
}

// Reads the pointer provenance of a register before its destination is rewritten. Writing a
// value replaces the whole entry, so the fact has to be taken first and put back after.
Sanitizer::PointerOrigin Sanitizer::takePointerOrigin(const SanitizerState& state, MicroReg reg)
{
    const SanitizerRegInfo* info = findReg(state, reg);
    if (!info || (!info->hasPointerOriginSlot && !info->releasedPointer))
        return {};
    return {.valid = true, .slot = info->hasPointerOriginSlot ? info->pointerOriginSlot : 0, .hasSlot = info->hasPointerOriginSlot, .released = info->releasedPointer, .releasedOrigin = info->releasedOrigin};
}

void Sanitizer::applyPointerOrigin(SanitizerState& state, MicroReg reg, const PointerOrigin& origin)
{
    if (!origin.valid || !reg.isValid())
        return;

    // A carried origin always contributes a fact, so the entry cannot become empty.
    SWC_ASSERT(origin.hasSlot || origin.released);
    if (reg.isAnyFloat())
        state.upperRegValues.erase(reg.packed);

    SanitizerRegInfo& info = state.regs[reg.packed];
    if (origin.hasSlot)
    {
        info.hasPointerOriginSlot = true;
        info.pointerOriginSlot    = origin.slot;
    }
    if (origin.released)
    {
        info.releasedPointer = true;
        info.releasedOrigin  = origin.releasedOrigin;
    }
}

void Sanitizer::setRegValue(SanitizerState& state, MicroReg reg, const SanitizerValue& value)
{
    setReg(state, reg, SanitizerRegInfo{value});
}

bool Sanitizer::resolveStackSlot(const SanitizerState& state, MicroReg base, uint64_t offset, int64_t& outSlot) const
{
    const SanitizerValue baseValue = getReg(state, base);
    if (!baseValue.isStackAddr())
        return false;
    outSlot = baseValue.stackOffset + static_cast<int64_t>(offset);
    return true;
}

bool Sanitizer::resolveAccessLocation(SanitizerLocation& outLocation, const SanitizerState& state, const MicroReg base, const int64_t offset) const
{
    outLocation        = {};
    outLocation.offset = offset;

    // The object is whatever pointer the base holds, and what names it across the reloads
    // the codegen makes is where that pointer LIVES: a frame slot, or a register nothing
    // redefines. A base that is neither names nothing that survives the next access.
    const SanitizerRegInfo* baseInfo = findReg(state, base);

    // An address already formed from an object keeps naming it, offset and all.
    if (baseInfo && baseInfo->hasAddressLocation)
    {
        outLocation = baseInfo->addressLocation;
        outLocation.offset += offset;
        return true;
    }

    if (baseInfo && baseInfo->hasOriginSlot)
    {
        outLocation.fromSlot = true;
        outLocation.slot     = baseInfo->originSlot;
        return true;
    }

    if (base.isVirtual() && hasSingleDefinition(base))
    {
        outLocation.basePacked = base.packed;
        return true;
    }

    return false;
}

bool Sanitizer::resolveAccessStackSlot(int64_t& outSlot, const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) const
{
    if (!ops)
        return false;

    MicroPassHelpers::AmcLayout layout;
    if (MicroPassHelpers::amcLayoutFor(layout, inst.op))
    {
        const SanitizerValue index = getReg(state, ops[layout.indexIdx].reg);
        if (!index.isConstant())
            return false;
        return resolveStackSlot(state, ops[layout.baseIdx].reg, index.constant * ops[layout.mulIdx].valueU64 + ops[layout.addIdx].valueU64, outSlot);
    }

    if (!def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
        return false;
    return resolveStackSlot(state, ops[def.memBaseOperandIndex].reg, ops[def.memOffsetOperandIndex].valueU64, outSlot);
}

bool Sanitizer::callParameterRegister(MicroReg& outReg, const SymbolFunction& fn, CallConvKind callConvKind, size_t paramIndex) const
{
    const auto& params = fn.parameters();
    if (paramIndex >= params.size() || !params[paramIndex])
        return false;

    const CallConv& callConv = CallConv::get(callConvKind);
    size_t          abiIndex = paramIndex;

    const ABITypeNormalize::NormalizedType returnType = ABITypeNormalize::normalize(ctx(), callConv, fn.returnTypeRef(), ABITypeNormalize::Usage::Return);
    if (returnType.isIndirect)
        ++abiIndex;
    if (fn.isClosure())
        ++abiIndex;
    if (fn.hasInterfaceMethodSlot())
        ++abiIndex;

    SmallVector<ABICall::ArgLayout> argLayouts;
    argLayouts.resize(params.size() + abiIndex - paramIndex);
    for (size_t i = 0; i < params.size(); ++i)
    {
        if (!params[i])
            return false;
        const ABITypeNormalize::NormalizedType type = ABITypeNormalize::normalize(ctx(), callConv, params[i]->typeRef(), ABITypeNormalize::Usage::Argument);
        argLayouts[i + abiIndex - paramIndex]       = {.numBits = static_cast<uint8_t>(type.numBits ? type.numBits : 64), .isFloat = type.isFloat};
    }

    if (argLayouts[abiIndex].isFloat)
        return false;

    const uint32_t regIndex = ABICall::argumentRegisterIndex(callConv, argLayouts, static_cast<uint32_t>(abiIndex));
    if (regIndex == UINT32_MAX)
        return false;
    outReg = callConv.intArgRegs[regIndex];
    return true;
}

bool Sanitizer::locationOwnerPassed(const SanitizerState& state, const SanitizerLocation& location, CallConvKind callConvKind) const
{
    const CallConv& callConv = CallConv::get(callConvKind);
    for (const MicroReg reg : callConv.intArgRegs)
    {
        const auto* handed = findReg(state, reg);
        if (!handed)
            continue;
        if (handed->hasAddressLocation && handed->addressLocation == location)
            return true;
        if (location.fromSlot && handed->hasOriginSlot && handed->originSlot == location.slot)
            return true;
        if (!location.fromSlot && handed->hasOriginReg && handed->originReg.packed == location.basePacked)
            return true;
    }
    return false;
}

void Sanitizer::propagate(const SanitizerState& edge, uint32_t index, SmallVector<uint32_t, 32>& worklist)
{
    const uint32_t stateIndex = headStateIndex_[index];
    SWC_ASSERT(stateIndex != K_NO_STATE);

    bool changed;
    if (!reached_[index])
    {
        reached_[index]      = 1;
        inState_[stateIndex] = edge;
        pruneDeadRegs(inState_[stateIndex], chainLiveIn(stateIndex));
        changed = true;
    }
    else
    {
        changed = joinInto(inState_[stateIndex], edge);
    }

    if (changed && !inWorklist_[index])
    {
        inWorklist_[index] = 1;
        worklist.push_back(index);
        std::ranges::push_heap(worklist, std::greater());
    }
}

void Sanitizer::propagate(SanitizerState&& edge, uint32_t index, SmallVector<uint32_t, 32>& worklist)
{
    const uint32_t stateIndex = headStateIndex_[index];
    SWC_ASSERT(stateIndex != K_NO_STATE);

    if (reached_[index])
    {
        propagate(static_cast<const SanitizerState&>(edge), index, worklist);
        return;
    }

    reached_[index]      = 1;
    inState_[stateIndex] = std::move(edge);
    pruneDeadRegs(inState_[stateIndex], chainLiveIn(stateIndex));
    if (!inWorklist_[index])
    {
        inWorklist_[index] = 1;
        worklist.push_back(index);
        std::ranges::push_heap(worklist, std::greater());
    }
}

bool Sanitizer::joinInto(SanitizerState& into, const SanitizerState& from)
{
    bool changed = false;

    for (auto it = into.upperRegValues.begin(); it != into.upperRegValues.end();)
    {
        const auto other = from.upperRegValues.find(it->first);
        if (other == from.upperRegValues.end() || other->second != it->second)
        {
            it      = into.upperRegValues.erase(it);
            changed = true;
        }
        else
            ++it;
    }

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
        if (f == from.movedFrom.end() || f->second.size != it->second.size)
        {
            it      = into.movedFrom.erase(it);
            changed = true;
        }
        else
        {
            const SourceCodeRef& intoOrigin = it->second.origin;
            const SourceCodeRef& fromOrigin = f->second.origin;
            if (intoOrigin.isValid() && (intoOrigin.srcViewRef != fromOrigin.srcViewRef || intoOrigin.tokRef != fromOrigin.tokRef))
            {
                it->second.origin = {};
                changed           = true;
            }
            ++it;
        }
    }

    // The one MAY fact of the state: an address that escaped on either incoming path has
    // escaped here, so this set grows where every other one shrinks.
    if (from.escapedFrameObjects && !from.escapedFrameObjects->empty())
    {
        if (!into.escapedFrameObjects)
            into.escapedFrameObjects.emplace();
        for (const int64_t object : *from.escapedFrameObjects)
        {
            if (into.escapedFrameObjects->insert(object).second)
                changed = true;
        }
    }

    for (auto it = into.aliasPtrSlots.begin(); it != into.aliasPtrSlots.end();)
    {
        const auto fromIt = from.aliasPtrSlots.find(it->first);
        if (fromIt == from.aliasPtrSlots.end() || fromIt->second != it->second)
        {
            it      = into.aliasPtrSlots.erase(it);
            changed = true;
        }
        else
            ++it;
    }

    if (into.freedPtrLocations && !from.freedPtrLocations)
    {
        changed |= !into.freedPtrLocations->empty();
        into.freedPtrLocations.reset();
    }
    else if (into.freedPtrLocations && from.freedPtrLocations)
    {
        for (auto it = into.freedPtrLocations->begin(); it != into.freedPtrLocations->end();)
        {
            const auto fromIt = from.freedPtrLocations->find(it->first);
            if (fromIt == from.freedPtrLocations->end())
            {
                it      = into.freedPtrLocations->erase(it);
                changed = true;
            }
            else
            {
                if (it->second.isValid() && (it->second.srcViewRef != fromIt->second.srcViewRef || it->second.tokRef != fromIt->second.tokRef))
                {
                    it->second = {};
                    changed    = true;
                }
                ++it;
            }
        }
    }

    for (auto it = into.freedPtrSlots.begin(); it != into.freedPtrSlots.end();)
    {
        const auto fromIt = from.freedPtrSlots.find(it->first);
        if (fromIt == from.freedPtrSlots.end())
        {
            it      = into.freedPtrSlots.erase(it);
            changed = true;
        }
        else
        {
            if (it->second.isValid() && (it->second.srcViewRef != fromIt->second.srcViewRef || it->second.tokRef != fromIt->second.tokRef))
            {
                it->second = {};
                changed    = true;
            }
            ++it;
        }
    }

    for (auto it = into.aliasPtrRegs.begin(); it != into.aliasPtrRegs.end();)
    {
        const auto fromIt = from.aliasPtrRegs.find(it->first);
        if (fromIt == from.aliasPtrRegs.end() || it->second != fromIt->second)
        {
            it      = into.aliasPtrRegs.erase(it);
            changed = true;
        }
        else
            ++it;
    }

    for (auto it = into.aliasPtrLocations.begin(); it != into.aliasPtrLocations.end();)
    {
        const auto fromIt = from.aliasPtrLocations.find(it->first);
        if (fromIt == from.aliasPtrLocations.end() || it->second != fromIt->second)
        {
            it      = into.aliasPtrLocations.erase(it);
            changed = true;
        }
        else
            ++it;
    }
    if (into.pendingReleaseLocation && into.pendingReleaseLocation != from.pendingReleaseLocation)
    {
        into.pendingReleaseLocation.reset();
        into.pendingReleaseOrigin = {};
        changed                   = true;
    }

    if (into.flagsSubject.isValid() && (into.flagsSubject != from.flagsSubject || into.flagsBits != from.flagsBits))
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

    uint64_t memoryWriteSize(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::StoreVecMemReg:
                return getNumBits(ops[2].opBits) / 8;
            case MicroInstrOpcode::LoadMemImm:
                return getNumBits(ops[1].opBits) / 8;
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
                return getNumBits(ops[4].opBits) / 8;
            default:
                return K_ASSUMED_STORE_SIZE;
        }
    }

    void clearMovedFromOverlaps(SanitizerState& state, const int64_t slot)
    {
        for (auto it = state.movedFrom.begin(); it != state.movedFrom.end();)
        {
            const int64_t rangeStart = it->first;
            const int64_t rangeEnd   = rangeStart + static_cast<int64_t>(it->second.size);
            if (slot + static_cast<int64_t>(K_ASSUMED_STORE_SIZE) > rangeStart && slot < rangeEnd)
                it = state.movedFrom.erase(it);
            else
                ++it;
        }
    }

    // A pointer-wide fact at 'slot' is invalidated by a store at 'written'.
    bool storeOverlapsPointer(const int64_t slot, const int64_t written)
    {
        return written + static_cast<int64_t>(K_ASSUMED_STORE_SIZE) > slot && written < slot + static_cast<int64_t>(sizeof(void*));
    }

}

void Sanitizer::forgetWrittenLifecycleFacts(SanitizerState& state, const int64_t slot) const
{
    state.freedPtrSlots.eraseIf([slot](const auto& entry) { return storeOverlapsPointer(entry.first, slot); });

    // An object is named by where its pointer lives: rewriting that pointer makes the
    // name mean another object, so nothing said about the old one may survive it.
    if (state.freedPtrLocations)
        std::erase_if(*state.freedPtrLocations, [slot](const auto& entry) { return entry.first.fromSlot && storeOverlapsPointer(entry.first.slot, slot); });

    // Overwriting either end of a proven copy ends the equality: the copy holds a value
    // the other slot no longer has, and releasing that other slot says nothing about it.
    state.aliasPtrSlots.eraseIf([slot](const auto& entry) { return storeOverlapsPointer(entry.first, slot) || storeOverlapsPointer(entry.second, slot); });
    state.aliasPtrRegs.eraseIf([slot](const auto& entry) { return storeOverlapsPointer(entry.first, slot); });
    state.aliasPtrLocations.eraseIf([slot](const auto& entry) { return storeOverlapsPointer(entry.first, slot) || (entry.second.fromSlot && storeOverlapsPointer(entry.second.slot, slot)); });
}

void Sanitizer::forgetReachableLifecycleFacts(SanitizerState& state) const
{
    state.freedPtrSlots.eraseIf([&](const auto& entry) { return frameObjectReachable(state, entry.first); });
    state.aliasPtrSlots.eraseIf([&](const auto& entry) { return frameObjectReachable(state, entry.first) || frameObjectReachable(state, entry.second); });
    state.aliasPtrRegs.eraseIf([&](const auto& entry) { return frameObjectReachable(state, entry.first); });
    state.aliasPtrLocations.eraseIf([&](const auto& entry) { return frameObjectReachable(state, entry.first); });
}

bool Sanitizer::writeMayReachFrame(const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) const
{
    uint8_t baseIndex = 0;
    if (!ops || !MicroPassHelpers::dereferenceBaseOperandIndex(baseIndex, inst.op, def))
        return true;
    return getReg(state, ops[baseIndex].reg).isStackAddr();
}

void Sanitizer::recordSlotCopy(SanitizerState& state, const int64_t slot, const MicroReg valueReg, const MicroOpBits opBits) const
{
    // Only a whole pointer proves the two slots hold the same address; a narrower store
    // keeps part of the value and answers nothing about what it points at.
    if (opBits != MicroOpBits::B64 || frameObjectReachable(state, slot))
        return;

    const SanitizerRegInfo* source = findReg(state, valueReg);
    if (needsReleaseProvenance_)
    {
        if (source && source->hasOriginReg)
            state.aliasPtrRegs.insertOrAssign(slot, source->originReg);
        else if (valueReg.isVirtual() && hasSingleDefinition(valueReg))
            state.aliasPtrRegs.insertOrAssign(slot, valueReg);
        if (source && source->releasedPointer)
            state.freedPtrSlots.insertOrAssign(slot, source->releasedOrigin);
        if (source && source->hasOriginLocation)
            state.aliasPtrLocations.insertOrAssign(slot, source->originLocation);
        else if (source && source->hasOriginSlot)
        {
            const auto origin = state.aliasPtrLocations.find(source->originSlot);
            if (origin != state.aliasPtrLocations.end())
                state.aliasPtrLocations.insertOrAssign(slot, origin->second);
        }
    }
    if (!source || !source->hasOriginSlot || source->originSlot == slot || frameObjectReachable(state, source->originSlot))
        return;

    // Copies chain to one representative, so a release names the whole class whichever
    // member it was written through.
    int64_t    root      = source->originSlot;
    const auto rootEntry = state.aliasPtrSlots.find(root);
    if (rootEntry != state.aliasPtrSlots.end())
        root = rootEntry->second;
    if (root == slot)
        return;

    state.aliasPtrSlots.insertOrAssign(slot, root);

    // Copying a pointer that is already released carries the release with it.
    const auto released = state.freedPtrSlots.find(root);
    if (released == state.freedPtrSlots.end())
        return;
    const SourceCodeRef origin = released->second;
    state.freedPtrSlots.insertOrAssign(slot, origin);
}

void Sanitizer::appendAliasClass(SmallVector<int64_t>& out, const SanitizerState& state, const int64_t slot)
{
    out.push_back(slot);

    int64_t    root  = slot;
    const auto entry = state.aliasPtrSlots.find(slot);
    if (entry != state.aliasPtrSlots.end())
    {
        root = entry->second;
        out.push_back(root);
    }

    for (const auto& [copy, of] : state.aliasPtrSlots)
    {
        if (of == root && copy != slot)
            out.push_back(copy);
    }
}

void Sanitizer::applyValueEffects(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) const
{
    if (!state.stack.empty() && def.flags.has(MicroInstrFlagsE::WritesMemory) && !def.flags.has(MicroInstrFlagsE::IsCallInstruction))
    {
        int64_t slot = 0;
        if (resolveAccessStackSlot(slot, state, inst, def, ops))
        {
            const uint64_t size     = memoryWriteSize(inst, ops);
            const auto     overlaps = [slot, size](const auto& entry) {
                const uint64_t storedSize = entry.second.storedBytes ? entry.second.storedBytes : 8;
                if (entry.first <= slot)
                    return static_cast<uint64_t>(slot) - static_cast<uint64_t>(entry.first) < storedSize;
                return static_cast<uint64_t>(entry.first) - static_cast<uint64_t>(slot) < size;
            };
            // A fact covers at most eight bytes. Large frames need only a bounded
            // number of hash probes, not a scan of every local on every store.
            if (state.stack.size() <= size + 7)
                std::erase_if(state.stack, overlaps);
            else
            {
                for (uint64_t offset = 0; offset < size + 7; ++offset)
                {
                    const int64_t candidate = std::bit_cast<int64_t>(static_cast<uint64_t>(slot) - 7 + offset);
                    const auto    it        = state.stack.find(candidate);
                    if (it != state.stack.end() && overlaps(*it))
                        state.stack.erase(it);
                }
            }
        }
        else
        {
            uint8_t baseIndex = 0;
            if (!MicroPassHelpers::dereferenceBaseOperandIndex(baseIndex, inst.op, def) ||
                getReg(state, ops[baseIndex].reg).kind != SanitizerValueKind::GlobalAddr)
                state.stack.clear();
        }
    }

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

    // Lifecycle facts - a released pointer, and the slot copies that share it - follow
    // one aliasing discipline: any write that could reassign a slot revalidates it. Calls
    // are handled below, after the freeing call has marked its own arguments.
    const bool hasLifecycleFacts = !state.freedPtrSlots.empty() || !state.aliasPtrSlots.empty() || !state.aliasPtrRegs.empty() || !state.aliasPtrLocations.empty() ||
                                   (state.freedPtrLocations && !state.freedPtrLocations->empty());
    if (hasLifecycleFacts && !def.flags.has(MicroInstrFlagsE::IsCallInstruction) && def.flags.has(MicroInstrFlagsE::WritesMemory))
    {
        if (!state.aliasPtrLocations.empty())
        {
            SanitizerLocation written;
            if (def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) && resolveAccessLocation(written, state, ops[def.memBaseOperandIndex].reg, static_cast<int64_t>(ops[def.memOffsetOperandIndex].valueU64)))
                state.aliasPtrLocations.eraseIf([&](const auto& entry) { return entry.second == written; });
            else
            {
                int64_t stackSlot = 0;
                if (!resolveAccessStackSlot(stackSlot, state, inst, def, ops))
                    state.aliasPtrLocations.clear();
            }
        }
        // A pointer a heap object owns is named by base and offset, so writing that
        // exact place revalidates it and any other write the analysis cannot pin drops
        // every such fact.
        if (state.freedPtrLocations && !state.freedPtrLocations->empty())
        {
            uint8_t           baseIndex = 0;
            SanitizerLocation written;
            if (def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) &&
                MicroPassHelpers::dereferenceBaseOperandIndex(baseIndex, inst.op, def) &&
                resolveAccessLocation(written, state, ops[baseIndex].reg, static_cast<int64_t>(ops[def.memOffsetOperandIndex].valueU64)))
                state.freedPtrLocations->erase(written);
            else
                state.freedPtrLocations.reset();
        }

        int64_t slot = 0;
        if (resolveAccessStackSlot(slot, state, inst, def, ops))
            forgetWrittenLifecycleFacts(state, slot);
        else if (writeMayReachFrame(state, inst, def, ops))
        {
            // A frame write the analysis cannot pin to one slot: it lands anywhere in the
            // object it indexes, so every fact about the frame goes.
            state.freedPtrSlots.clear();
            state.aliasPtrSlots.clear();
            state.aliasPtrRegs.clear();
            state.aliasPtrLocations.clear();
        }
        else
            forgetReachableLifecycleFacts(state);
    }

    switch (inst.op)
    {
        case MicroInstrOpcode::SanityRelease:
        {
            int64_t slot = 0;
            if (resolveStackSlot(state, ops[0].reg, ops[1].valueU64, slot))
            {
                const auto value = state.stack.find(slot);
                if (value != state.stack.end() && value->second.isZero())
                    return;
                SmallVector<int64_t> released;
                appendAliasClass(released, state, slot);
                const auto location = state.aliasPtrLocations.find(slot);
                if (location != state.aliasPtrLocations.end())
                {
                    state.pendingReleaseLocation = location->second;
                    state.pendingReleaseOrigin   = inst.debugSourceInfo.sourceCodeRef;
                }
                for (const int64_t alias : released)
                {
                    state.freedPtrSlots.insertOrAssign(alias, inst.debugSourceInfo.sourceCodeRef);
                    const auto reg = state.aliasPtrRegs.find(alias);
                    if (reg != state.aliasPtrRegs.end())
                    {
                        SanitizerRegInfo info;
                        if (const auto* previous = findReg(state, reg->second))
                            info = *previous;
                        info.releasedPointer = true;
                        info.releasedOrigin  = inst.debugSourceInfo.sourceCodeRef;
                        setReg(state, reg->second, info);
                    }
                }
            }
            return;
        }
        case MicroInstrOpcode::SanityInvalidate:
        {
            int64_t slot = 0;
            if (resolveStackSlot(state, ops[0].reg, 0, slot) && ops[1].valueU64 > 0)
                state.movedFrom.insertOrAssign(slot, {.size = ops[1].valueU64, .origin = inst.debugSourceInfo.sourceCodeRef});
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
            if (ops[1].opBits == MicroOpBits::B128)
                setUpperReg(state, ops[0].reg, SanitizerValue::makeConstant(0));
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
            // (and its origin slot) is zero. The stack-base register has a special value
            // outside the map.
            SanitizerRegInfo info;
            if (const SanitizerRegInfo* src = findReg(state, ops[1].reg))
                info = *src;
            if (stackBaseReg_.isValid() && ops[1].reg == stackBaseReg_)
                info.value = SanitizerValue::makeStackAddr(0);

            const uint8_t sourceBits = static_cast<uint8_t>(getNumBits(ops[inst.op == MicroInstrOpcode::LoadRegReg ? 2 : 3].opBits));
            if (sourceBits < 64)
            {
                if (info.value.isConstant())
                {
                    info.value.constant &= (1ULL << sourceBits) - 1;
                    if (inst.op == MicroInstrOpcode::LoadSignedExtRegReg && (info.value.constant & (1ULL << (sourceBits - 1))))
                        info.value.constant |= ~((1ULL << sourceBits) - 1);
                }
                else
                    info.value = {};
                info.originSlotBits = std::min(info.originSlotBits, sourceBits);
            }

            // Keep the FIRST virtual register of the copy chain: a value moved into an
            // argument register has to be nameable again after the call clobbers that
            // register, and what the code reads afterwards is another copy of that first
            // one rather than of the argument.
            if (ops[1].reg.isVirtual() && hasSingleDefinition(ops[1].reg) && !info.hasOriginReg)
            {
                info.hasOriginReg = true;
                info.originReg    = ops[1].reg;
            }

            const bool           wide  = inst.op == MicroInstrOpcode::LoadRegReg && ops[2].opBits == MicroOpBits::B128;
            const SanitizerValue upper = wide ? getUpperReg(state, ops[1].reg) : SanitizerValue{};
            setReg(state, ops[0].reg, info);
            if (wide)
                setUpperReg(state, ops[0].reg, upper);
            return;
        }

        case MicroInstrOpcode::LoadAddrRegMem:
        {
            // An address formed from a pointer still addresses the same object, so the
            // pointer provenance travels with it even though the value origin does not: the
            // result no longer holds what the slot holds. It is carried after the value is
            // written, because writing a value replaces the whole entry.
            const PointerOrigin carried = takePointerOrigin(state, ops[1].reg);

            const SanitizerValue baseValue = getReg(state, ops[1].reg);
            if (baseValue.isStackAddr())
            {
                const int64_t slot = baseValue.stackOffset + static_cast<int64_t>(ops[3].valueU64);
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
            applyPointerOrigin(state, ops[0].reg, carried);

            // Forming a field's address keeps which object it belongs to, so the read
            // that follows names the same place the release did.
            SanitizerLocation formed;
            if (resolveAccessLocation(formed, state, ops[1].reg, static_cast<int64_t>(ops[3].valueU64)))
            {
                SanitizerRegInfo formedInfo;
                if (const SanitizerRegInfo* existing = findReg(state, ops[0].reg))
                    formedInfo = *existing;
                formedInfo.hasAddressLocation = true;
                formedInfo.addressLocation    = formed;
                setReg(state, ops[0].reg, formedInfo);
            }
            return;
        }

        case MicroInstrOpcode::LoadAddrAmcRegMem:
        {
            const PointerOrigin carried = takePointerOrigin(state, ops[1].reg);

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
            else if (baseValue.kind == SanitizerValueKind::GlobalAddr)
            {
                // Global storage does not move, so an element of it is still global
                // storage - which is what says it never came from an allocator.
                setRegValue(state, ops[0].reg, SanitizerValue::makeGlobalAddr());
            }
            else
            {
                // A dynamic index leaves an address the engine can no longer name a slot
                // for: what it addresses is out of reach from here on.
                markFrameObjectEscaped(state, baseValue);
                // The new register can still address a captured object field. Forget
                // that copy before a later store mistakes the new base for a disjoint one.
                state.aliasPtrLocations.clear();
                setRegValue(state, ops[0].reg, baseValue.isKnownNonZero() ? SanitizerValue::makeNonZero() : SanitizerValue{});
            }
            applyPointerOrigin(state, ops[0].reg, carried);
            return;
        }

        case MicroInstrOpcode::LoadRegMem:
        case MicroInstrOpcode::LoadVecRegMem:
        case MicroInstrOpcode::LoadSignedExtRegMem:
        case MicroInstrOpcode::LoadZeroExtRegMem:
        case MicroInstrOpcode::LoadAmcRegMem:
        case MicroInstrOpcode::LoadSignedExtAmcRegMem:
        case MicroInstrOpcode::LoadZeroExtAmcRegMem:
        {
            // A known indexed address names the same slot as a plain address. Both
            // forms retain its value, pointer provenance and wide-copy lanes.
            const bool indexed         = inst.op == MicroInstrOpcode::LoadAmcRegMem || inst.op == MicroInstrOpcode::LoadSignedExtAmcRegMem || inst.op == MicroInstrOpcode::LoadZeroExtAmcRegMem;
            const bool signedExtension = inst.op == MicroInstrOpcode::LoadSignedExtRegMem || inst.op == MicroInstrOpcode::LoadSignedExtAmcRegMem;
            const bool extension       = signedExtension || inst.op == MicroInstrOpcode::LoadZeroExtRegMem || inst.op == MicroInstrOpcode::LoadZeroExtAmcRegMem;
            int64_t    slot            = 0;
            if (resolveAccessStackSlot(slot, state, inst, def, ops))
            {
                const uint8_t    loadBits = static_cast<uint8_t>(getNumBits(ops[indexed ? (extension ? 4 : 3) : (extension ? 3 : 2)].opBits));
                const bool       wide     = loadBits == 128;
                SanitizerRegInfo info;
                if (wide)
                    info.value = getStackLane(state, slot);
                else
                {
                    const auto it = state.stack.find(slot);
                    info.value    = it != state.stack.end() ? it->second : SanitizerValue{};
                    if (info.value.storedBytes && info.value.storedBytes * 8 < loadBits)
                        info.value = {};
                    else if (loadBits < 64)
                    {
                        if (info.value.isConstant())
                            info.value.constant &= (1ULL << loadBits) - 1;
                        else
                            info.value = {};
                    }
                    info.value.storedBytes = 0;
                }
                info.hasOriginSlot        = true;
                info.originSlot           = slot;
                info.originSlotBits       = loadBits;
                info.hasPointerOriginSlot = true;
                info.pointerOriginSlot    = slot;

                // A full load of a non-null pointer keeps its declared contract through
                // an inline binding whose parameter type is nullable. Keep concrete
                // values (including an unsafe zero) ahead of that type information.
                if (needsReleaseProvenance_ && loadBits == 64 && info.value.kind == SanitizerValueKind::Unknown)
                {
                    const LocalSlotExtent* extent = findLocalSlot(slot);
                    if (extent && extent->start == slot && extent->sym)
                    {
                        const TypeRef typeRef = ctx().typeMgr().unwrapAliasEnum(ctx(), extent->sym->typeRef());
                        if (typeRef.isValid())
                        {
                            const TypeInfo& type = ctx().typeMgr().get(typeRef);
                            if (type.isAnyPointer() && !type.isNullable())
                                info.value = SanitizerValue::makeNonZero();
                        }
                    }
                }

                if (info.value.isConstant() && extension)
                {
                    const uint32_t srcBits = getNumBits(ops[indexed ? 4 : 3].opBits);
                    if (srcBits && srcBits < 64)
                    {
                        const uint64_t mask = (1ULL << srcBits) - 1;
                        uint64_t       v    = info.value.constant & mask;
                        if (signedExtension && (v >> (srcBits - 1)) & 1)
                            v |= ~mask;
                        info.value = SanitizerValue::makeConstant(v);
                    }
                }

                const SanitizerValue upper = wide ? getStackLane(state, slot + 8) : SanitizerValue{};
                setReg(state, ops[0].reg, info);
                if (wide)
                    setUpperReg(state, ops[0].reg, upper);
                return;
            }

            if (indexed)
            {
                setRegValue(state, ops[0].reg, {});
                return;
            }

            // Not the frame: the access still names one place, once the OBJECT is named
            // by where its pointer lives rather than by the register that happens to hold
            // it - the codegen reloads that pointer for every access.
            SanitizerRegInfo  locationInfo;
            SanitizerLocation location;
            if (resolveAccessLocation(location, state, ops[def.memBaseOperandIndex].reg, static_cast<int64_t>(ops[def.memOffsetOperandIndex].valueU64)))
            {
                locationInfo.hasOriginLocation = true;
                locationInfo.originLocation    = location;
                if (const auto* released = state.findFreedPtrLocation(location))
                {
                    locationInfo.releasedPointer = true;
                    locationInfo.releasedOrigin  = *released;
                }
            }

            setReg(state, ops[0].reg, locationInfo);
            return;
        }

        case MicroInstrOpcode::LoadAmcMemReg:
        {
            const SanitizerValue value = getReg(state, ops[2].reg);
            const bool           wide  = ops[4].opBits == MicroOpBits::B128;
            const SanitizerValue upper = wide ? getUpperReg(state, ops[2].reg) : SanitizerValue{};
            markFrameObjectEscaped(state, value);
            markFrameObjectEscaped(state, upper);

            int64_t slot = 0;
            if (resolveAccessStackSlot(slot, state, inst, def, ops))
            {
                setStackValue(state, slot, value, wide ? 8 : static_cast<uint8_t>(getNumBits(ops[4].opBits) / 8));
                if (wide)
                    setStackValue(state, slot + 8, upper, 8);
                recordSlotCopy(state, slot, ops[2].reg, ops[4].opBits);
            }
            return;
        }

        case MicroInstrOpcode::LoadMemReg:
        case MicroInstrOpcode::StoreVecMemReg:
        {
            // Whatever the destination is, an address written to memory can be read back
            // anywhere, so the object it names stops being out of reach.
            const SanitizerValue value = getReg(state, ops[1].reg);
            const bool           wide  = ops[2].opBits == MicroOpBits::B128;
            const SanitizerValue upper = wide ? getUpperReg(state, ops[1].reg) : SanitizerValue{};
            markFrameObjectEscaped(state, value);
            markFrameObjectEscaped(state, upper);

            int64_t slot = 0;
            if (resolveStackSlot(state, ops[0].reg, ops[3].valueU64, slot))
            {
                setStackValue(state, slot, value, wide ? 8 : static_cast<uint8_t>(getNumBits(ops[2].opBits) / 8));
                if (wide)
                    setStackValue(state, slot + 8, upper, 8);
                recordSlotCopy(state, slot, ops[1].reg, ops[2].opBits);
            }
            return;
        }

        case MicroInstrOpcode::LoadMemImm:
        {
            int64_t slot = 0;
            if (resolveStackSlot(state, ops[0].reg, ops[2].valueU64, slot))
                setStackValue(state, slot, SanitizerValue::makeConstant(ops[3].valueU64), static_cast<uint8_t>(getNumBits(ops[1].opBits) / 8));
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
            else if (isAddSub && cur.kind == SanitizerValueKind::GlobalAddr)
                setRegValue(state, reg, SanitizerValue::makeGlobalAddr());
            else
            {
                markFrameObjectEscaped(state, cur);
                setRegValue(state, reg, {});
            }
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

            markFrameObjectEscaped(state, getReg(state, ops[0].reg));
            markFrameObjectEscaped(state, getReg(state, ops[1].reg));
            setRegValue(state, ops[0].reg, {});
            return;
        }

        case MicroInstrOpcode::CmpRegImm:
            state.flagsSubject = ops[2].valueU64 == 0 ? ops[0].reg : MicroReg::invalid();
            state.flagsBits    = static_cast<uint8_t>(getNumBits(ops[1].opBits));
            return;

        case MicroInstrOpcode::CmpRegReg:
            state.flagsBits = static_cast<uint8_t>(getNumBits(ops[2].opBits));
            if (getReg(state, ops[1].reg).isZero())
                state.flagsSubject = ops[0].reg;
            else if (getReg(state, ops[0].reg).isZero())
                state.flagsSubject = ops[1].reg;
            else
                state.flagsSubject = MicroReg::invalid();
            return;

        case MicroInstrOpcode::SetCondReg:
        {
            SanitizerRegInfo        info;
            const SanitizerRegInfo* subject       = state.flagsSubject.isValid() ? findReg(state, state.flagsSubject) : nullptr;
            bool                    trueIfZero    = false;
            bool                    subjectIsZero = false;
            if (subject && condIsZeroTest(ops[1].cpuCond, trueIfZero) && subject->value.tryZeroTest(subjectIsZero, state.flagsBits))
            {
                info.value = SanitizerValue::makeConstant(trueIfZero == subjectIsZero);
                setReg(state, ops[0].reg, info);
                return;
            }
            GuardSlot guard;
            if (subject && condIsZeroTest(ops[1].cpuCond, trueIfZero) && resolveGuardSlot(guard, *subject, state.flagsBits))
            {
                info.hasZeroTest        = true;
                info.zeroTestSlot       = guard.offset;
                info.zeroTestSlotBits   = guard.bits;
                info.zeroTestTrueIfZero = trueIfZero == guard.zeroIfSubjectZero;
            }
            setReg(state, ops[0].reg, info);
            return;
        }

        default:
            break;
    }

    if (def.flags.has(MicroInstrFlagsE::IsCallInstruction))
    {
        const auto pendingRelease = state.pendingReleaseLocation;
        const auto pendingOrigin  = state.pendingReleaseOrigin;
        state.pendingReleaseLocation.reset();
        state.pendingReleaseOrigin    = {};
        const auto callConvKind       = ops ? ops[def.callConvIndex].callConv : CallConvKind::Swag;
        const bool keepPendingRelease = pendingRelease && !locationOwnerPassed(state, *pendingRelease, callConvKind);
        state.aliasPtrLocations.eraseIf([&](const auto& entry) { return locationOwnerPassed(state, entry.second, callConvKind); });
        // A callee with a FREES summary invalidates what its marked arguments point
        // to: remember the slots those pointers were loaded from, BEFORE the clobber
        // wipe erases the argument registers.
        SmallVector<int64_t>           newlyFreed;
        SmallVector<MicroReg>          newlyFreedRegs;
        SmallVector<SanitizerLocation> newlyFreedLocations;
        const auto*                    calleeFn  = transferCallTarget_ ? transferCallTarget_->safeCast<SymbolFunction>() : nullptr;
        const uint64_t                 freesMask = calleeFn ? calleeFn->freesParamsMask() : 0;
        if (freesMask && ops)
        {
            for (uint64_t remaining = freesMask; remaining; remaining &= remaining - 1)
            {
                const size_t i = std::countr_zero(remaining);
                MicroReg     argReg;
                if (!callParameterRegister(argReg, *calleeFn, ops[0].callConv, i))
                    continue;
                const SanitizerRegInfo* argInfo = findReg(state, argReg);
                if (!argInfo)
                    continue;
                if (argInfo->hasOriginSlot)
                    appendAliasClass(newlyFreed, state, argInfo->originSlot);

                // A pointer with no frame slot of its own - a parameter, above all - is
                // named by the register holding it, which the allocator keeps live across
                // the call. The mark goes on the virtual source, not on the argument
                // register the call is about to clobber.
                if (argInfo->hasOriginReg)
                    newlyFreedRegs.push_back(argInfo->originReg);
                else if (argReg.isVirtual())
                    newlyFreedRegs.push_back(argReg);

                // A pointer this call releases that lived in an object rather than in the
                // frame. A callee handed that object as well can put a live pointer back
                // where this one was, so the release says nothing then.
                if (!argInfo->hasOriginLocation)
                    continue;

                if (!locationOwnerPassed(state, argInfo->originLocation, callConvKind))
                    newlyFreedLocations.push_back(argInfo->originLocation);
            }
        }

        // Calls clobber caller-saved registers and may mutate escaped locals. A callee
        // reaches a frame slot only through a pointer to it, so what it cannot address it
        // cannot reassign: a release proven before an ordinary call still holds after it,
        // which is the shape almost every real use-after-free has.
        SmallVector<int64_t> addressedByCallee;
        markEscapesFromCallArguments(addressedByCallee, state, ops ? ops[def.callConvIndex].callConv : CallConvKind::Swag);

        // A virtual register is a value the allocator keeps live across the call, and an
        // address formed from the frame is a function of a frame pointer the call
        // preserves. The codegen caches those address registers and reuses them after the
        // call, so dropping them would leave every local but the one at frame offset zero
        // unnameable from there on - which is exactly where a release and its use are
        // separated by an ordinary call. Everything else goes: a physical register is
        // clobbered, and what a register said about the CONTENT of a slot no longer holds
        // once the callee may have written it.
        std::erase_if(state.regs, [](const auto& entry) { return !MicroReg::fromPacked(entry.first).isVirtual() || (!entry.second.value.isStackAddr() && !entry.second.releasedPointer); });
        state.upperRegValues.eraseIf([](const auto& entry) { return !MicroReg::fromPacked(entry.first).isVirtual() || !entry.second.isStackAddr(); });
        for (auto& [reg, info] : state.regs)
            info = SanitizerRegInfo{.value = info.value, .releasedPointer = info.releasedPointer, .releasedOrigin = info.releasedOrigin};

        for (const MicroReg reg : newlyFreedRegs)
        {
            SanitizerRegInfo info;
            if (const SanitizerRegInfo* existing = findReg(state, reg))
                info = *existing;
            info.releasedPointer = true;
            info.releasedOrigin  = inst.debugSourceInfo.sourceCodeRef;
            setReg(state, reg, info);
        }
        state.stack.clear();
        forgetReachableLifecycleFacts(state);
        state.flagsSubject = MicroReg::invalid();

        // A callee can write through any pointer it is handed, so nothing said about an
        // object survives a call - the release below re-states what this one just did.
        state.freedPtrLocations.reset();
        if (!newlyFreedLocations.empty())
        {
            state.freedPtrLocations.emplace();
            for (const auto& location : newlyFreedLocations)
                (*state.freedPtrLocations)[location] = inst.debugSourceInfo.sourceCodeRef;
        }
        if (keepPendingRelease)
        {
            if (!state.freedPtrLocations)
                state.freedPtrLocations.emplace();
            (*state.freedPtrLocations)[*pendingRelease] = pendingOrigin;
        }

        // A callee handed both a pointer to release and the storage that holds it can put
        // a live address back where the released one was: what it can reassign, it did
        // not leave released.
        for (const int64_t slot : newlyFreed)
        {
            const LocalSlotExtent* extent = findLocalSlot(slot);
            if (extent && std::ranges::find(addressedByCallee, extent->start) != addressedByCallee.end())
                continue;
            state.freedPtrSlots.insertOrAssign(slot, inst.debugSourceInfo.sourceCodeRef);
        }
        return;
    }

    // Everything the switch above does not model: an address it reads is an address the
    // engine stops following.
    markEscapesFromValueOperands(state, inst, def, ops);

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
void Sanitizer::propagateConditionalBranch(SanitizerState state, const MicroInstrOperand* ops, const MicroControlFlowGraph::EdgeList& succs, SmallVector<uint32_t, 32>& worklist)
{
    const bool              hasSubject   = state.flagsSubject.isValid();
    const SanitizerRegInfo* subject      = hasSubject ? findReg(state, state.flagsSubject) : nullptr;
    const SanitizerValue    subjectValue = stackBaseReg_.isValid() && state.flagsSubject == stackBaseReg_
                                               ? SanitizerValue::makeStackAddr(0)
                                           : subject ? subject->value
                                                     : SanitizerValue{};

    bool       condTrueIfSubjectZero = false;
    const bool isZeroTest            = hasSubject && condIsZeroTest(ops[0].cpuCond, condTrueIfSubjectZero);
    if (isZeroTest)
    {
        // A zero-test whose subject value the state already proves decides the branch:
        // only the feasible edge is explored. Inlining a constant null folds the guard
        // to a constant but leaves the guarded dereference as a not-yet-swept dead
        // block, and walking it would report code that can never execute. The compare
        // width matters: a non-null pointer can still have a zero low byte.
        bool provenZero = false;
        if (subjectValue.tryZeroTest(provenZero, state.flagsBits))
        {
            // successors = [taken (cond true), fallthrough (cond false)].
            const bool condIsTrue = condTrueIfSubjectZero == provenZero;
            state.flagsSubject    = MicroReg::invalid();
            propagate(std::move(state), succs[condIsTrue ? 0 : 1], worklist);
            return;
        }
    }

    GuardSlot guard;
    if (subject && isZeroTest && resolveGuardSlot(guard, *subject, state.flagsBits))
    {
        // successors = [taken (cond true), fallthrough (cond false)].
        queueRefined(state, succs[0], guard, condTrueIfSubjectZero == guard.zeroIfSubjectZero, worklist);
        queueRefined(std::move(state), succs[1], guard, (!condTrueIfSubjectZero) == guard.zeroIfSubjectZero, worklist);
        return;
    }

    // Unmodellable branch: keep exploring, but drop provable zeros only if the branch
    // actually tested a value against zero (the flags encode a zero-comparison), so
    // nothing is reported past a zero-guard we could not attribute to a slot (e.g.
    // `assume`). A comparison against a non-zero constant — such as the INT_MIN/-1
    // overflow checks the front end wraps every integer division in — does not constrain
    // zero-ness, so provable zeros must survive it (else no division-by-zero is caught).
    //
    // A subject the state already values exactly refines nothing either: the front end's
    // bound check compares a constant index against a constant count, and dropping every
    // zero across it took the index `table[0]` is written with along with it - which is
    // what made the first element of a local table, and only the first, unnameable.
    const bool dropAcrossEdge = hasSubject && !subjectValue.isConstant();
    if (dropAcrossEdge)
        dropZeros(state);
    state.flagsSubject = MicroReg::invalid();
    propagate(state, succs[0], worklist);
    propagate(std::move(state), succs[1], worklist);
}

bool Sanitizer::resolveGuardSlot(GuardSlot& out, const SanitizerRegInfo& subject, uint8_t bits)
{
    if (subject.hasZeroTest)
    {
        // subject is a bool == (slot is zero) when zeroTestTrueIfZero.
        // subject == 0 (false) ⇒ slot is zero iff !zeroTestTrueIfZero.
        out = {.offset = subject.zeroTestSlot, .bits = subject.zeroTestSlotBits, .zeroIfSubjectZero = !subject.zeroTestTrueIfZero};
        return true;
    }
    if (subject.hasOriginSlot && subject.originSlotBits && bits)
    {
        out = {.offset = subject.originSlot, .bits = std::min(bits, subject.originSlotBits), .zeroIfSubjectZero = true};
        return true;
    }
    return false;
}

void Sanitizer::queueRefined(SanitizerState state, uint32_t index, const GuardSlot& guard, bool slotIsZero, SmallVector<uint32_t, 32>& worklist)
{
    const auto           it      = state.stack.find(guard.offset);
    const SanitizerValue current = it != state.stack.end() ? it->second : SanitizerValue{};

    bool currentIsZero = false;
    if ((!current.storedBytes || current.storedBytes * 8 >= guard.bits) && current.tryZeroTest(currentIsZero, guard.bits) && slotIsZero != currentIsZero)
        return; // infeasible

    // A guard narrows an unknown value, but must retain any value already known,
    // including its storage width: later reloads and wide copies need the same fact.
    if (current.kind == SanitizerValueKind::Unknown)
    {
        auto refined        = slotIsZero ? SanitizerValue::makeConstant(0) : SanitizerValue::makeNonZero();
        refined.storedBytes = guard.bits / 8;
        state.stack.insert_or_assign(guard.offset, refined);
    }
    state.flagsSubject = MicroReg::invalid();
    propagate(std::move(state), index, worklist);
}

void Sanitizer::dropZeros(SanitizerState& state)
{
    for (auto it = state.regs.begin(); it != state.regs.end();)
    {
        if (it->second.value.isZero())
            it->second.value = {};
        if (it->second == SanitizerRegInfo{})
            it = state.regs.erase(it);
        else
            ++it;
    }
    std::erase_if(state.stack, [](const auto& entry) { return entry.second.isZero(); });
    state.upperRegValues.eraseIf([](const auto& entry) { return entry.second.isZero(); });
}

bool Sanitizer::resolvePlainLoadStackSlot(int64_t& outSlot, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops, const SanitizerState& state) const
{
    if (!ops)
        return false;

    if (!isPlainLoadInstruction(inst.op))
        return false;

    return resolveStackSlot(state, ops[def.memBaseOperandIndex].reg, ops[def.memOffsetOperandIndex].valueU64, outSlot);
}

void Sanitizer::reportLoadFromMovedRange(const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops, const SanitizerState& state, const DiagnosticId id)
{
    if (state.movedFrom.empty())
        return;

    int64_t slot = 0;
    if (!resolvePlainLoadStackSlot(slot, inst, def, ops, state))
        return;

    for (const auto& [rangeStart, range] : state.movedFrom)
    {
        if (slot < rangeStart || slot >= rangeStart + static_cast<int64_t>(range.size))
            continue;

        std::array<ReportNote, 2> notes;
        size_t                    noteCount = 0;

        const SanitizerRegInfo* baseInfo  = findReg(state, ops[def.memBaseOperandIndex].reg);
        const LocalSlotExtent*  movedSlot = findLocalSlot(rangeStart);
        const LocalSlotExtent*  viewSlot  = baseInfo && baseInfo->hasOriginSlot ? findLocalSlot(baseInfo->originSlot) : nullptr;
        if (viewSlot && movedSlot && viewSlot->sym && movedSlot->sym && viewSlot->sym != movedSlot->sym)
            notes[noteCount++] = {.source = viewSlot->sym->codeRef(), .id = DiagnosticId::sema_note_borrow_taken_here, .sym = viewSlot->sym};
        if (range.origin.isValid() && movedSlot && movedSlot->sym)
            notes[noteCount++] = {.source = range.origin, .id = DiagnosticId::sanity_note_move_origin, .sym = movedSlot->sym};

        report(inst, id, {}, std::span{notes.data(), noteCount});
        return;
    }
}

void Sanitizer::report(const MicroInstr& inst, DiagnosticId id)
{
    report(inst, id, {}, std::span<const ReportNote>{});
}

void Sanitizer::report(const MicroInstr& inst, DiagnosticId id, const SourceCodeRef& noteSource, DiagnosticId noteId)
{
    if (noteId == DiagnosticId::None || !noteSource.isValid())
    {
        report(inst, id);
        return;
    }

    const ReportNote note{.source = noteSource, .id = noteId};
    report(inst, id, {}, std::span{&note, 1});
}

void Sanitizer::report(const MicroInstr& inst, const DiagnosticId id, const std::string_view sym, const std::string_view what)
{
    report(inst, id, {.sym = sym, .what = what}, std::span<const ReportNote>{});
}

void Sanitizer::report(const MicroInstr& inst, DiagnosticId id, const ReportArguments& arguments, const std::span<const ReportNote> notes)
{
    const SourceCodeRef& codeRef = inst.debugSourceInfo.sourceCodeRef;

    // The same source location can be reached by several paths and can lower to several
    // instructions; report each (location, diagnostic) pair at most once.
    const uint64_t key = (static_cast<uint64_t>(codeRef.srcViewRef.get()) << 40) ^ (static_cast<uint64_t>(codeRef.tokRef.get()) << 8) ^ static_cast<uint64_t>(id);
    reported_          = true;
    if (!reportedLocations_)
        reportedLocations_.emplace();
    if (!reportedLocations_->insert(key).second)
        return;

    ResolvedDebugSourceInfo resolved;
    if (!tryResolveDebugSourceInfo(*context_.taskContext, resolved, inst.debugSourceInfo))
        return;

    const FileRef fileRef = resolved.sourceFile ? resolved.sourceFile->ref() : FileRef::invalid();
    Diagnostic    diag    = Diagnostic::get(id, fileRef);
    if (!arguments.sym.empty())
        diag.last().addArgument(Diagnostic::ARG_SYM, arguments.sym);
    if (!arguments.what.empty())
        diag.last().addArgument(Diagnostic::ARG_WHAT, arguments.what);
    diag.last().addSpan(resolved.codeRange, "", DiagnosticSeverity::Error);
    for (const ReportNote& note : notes)
    {
        ResolvedDebugSourceInfo resolvedNote;
        DebugSourceInfo         noteSourceInfo;
        noteSourceInfo.sourceCodeRef = note.source;
        if (tryResolveDebugSourceInfo(*context_.taskContext, resolvedNote, noteSourceInfo))
        {
            diag.addNote(note.id);
            if (note.sym)
                diag.last().addArgument(Diagnostic::ARG_SYM, note.sym->name(ctx()));
            diag.last().addSpan(resolvedNote.codeRange);
        }
    }
    diag.report(*context_.taskContext);
}

SWC_END_NAMESPACE();
