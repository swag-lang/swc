#include "pch.h"
#include "Backend/Sanitizer/NullDerefAnalysis.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroStorage.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

NullDerefAnalysis::NullDerefAnalysis(MicroPassContext& context) :
    context_(context),
    stackBaseReg_(context.debugStackBaseVirtualReg)
{
}

bool NullDerefAnalysis::run()
{
    const MicroControlFlowGraph& cfg = context_.builder->controlFlowGraph();
    const uint32_t               n   = cfg.instructionCount();
    if (n == 0 || n > K_MAX_INSTRUCTIONS)
        return reported_;

    cfg_ = &cfg;
    inState_.assign(n, {});
    reached_.assign(n, 0);
    inWorklist_.assign(n, 0);

    reached_[0]    = 1;
    inWorklist_[0] = 1;
    std::vector<uint32_t> worklist{0};

    uint64_t iterations = 0;
    while (!worklist.empty() && iterations < K_ITERATION_CAP)
    {
        iterations++;
        const uint32_t index = worklist.back();
        worklist.pop_back();
        inWorklist_[index] = 0;

        SanitizerState           cur  = inState_[index];
        const MicroInstr&        inst = *context_.instructions->ptr(cfg.instructionRefs()[index]);
        const MicroInstrDef&     def  = MicroInstr::info(inst.op);
        const MicroInstrOperand* ops  = inst.numOperands ? inst.ops(*context_.operands) : nullptr;

        applyValueEffects(cur, inst, def, ops);

        const MicroControlFlowGraph::EdgeList& succs = cfg.successors(index);
        if (def.flags.has(MicroInstrFlagsE::TerminatorInstruction) && !def.flags.has(MicroInstrFlagsE::JumpInstruction))
            continue; // Ret: no successor

        if (def.flags.has(MicroInstrFlagsE::ConditionalJump) && succs.size() == 2 && ops)
            propagateConditionalBranch(cur, ops, succs, worklist);
        else if (isModelledSingleEdge(def, succs))
            propagate(cur, succs[0], worklist);
        else
            for (const uint32_t s : succs)
            {
                SanitizerState edge = cur;
                dropNulls(edge);
                edge.flagsSubject = MicroReg::invalid();
                propagate(edge, s, worklist);
            }
    }

    // Report only on the converged states: a dereference is flagged only if its incoming
    // state proves the base is null on every path. Checking during the fixpoint would
    // report on a transient pre-join state that a later merge widens back to Unknown.
    for (uint32_t i = 0; i < n; i++)
    {
        if (!reached_[i])
            continue;
        const MicroInstr&        inst = *context_.instructions->ptr(cfg.instructionRefs()[i]);
        const MicroInstrDef&     def  = MicroInstr::info(inst.op);
        const MicroInstrOperand* ops  = inst.numOperands ? inst.ops(*context_.operands) : nullptr;
        checkDereference(inState_[i], inst, def, ops);
    }

    return reported_;
}

bool NullDerefAnalysis::isModelledSingleEdge(const MicroInstrDef& def, const MicroControlFlowGraph::EdgeList& succs)
{
    // A plain fall-through or an unconditional direct jump: the state flows unchanged to
    // the single successor.
    return succs.size() == 1 && !def.flags.has(MicroInstrFlagsE::ConditionalJump);
}

// ---------------------------------------------------------------------------
// Register / slot access
// ---------------------------------------------------------------------------
SanitizerValue NullDerefAnalysis::getReg(const SanitizerState& state, MicroReg reg) const
{
    if (stackBaseReg_.isValid() && reg == stackBaseReg_)
        return SanitizerValue::makeStackAddr(0);
    const auto it = state.regs.find(reg.packed);
    return it == state.regs.end() ? SanitizerValue{} : it->second.value;
}

const SanitizerRegInfo* NullDerefAnalysis::findReg(const SanitizerState& state, MicroReg reg)
{
    const auto it = state.regs.find(reg.packed);
    return it == state.regs.end() ? nullptr : &it->second;
}

void NullDerefAnalysis::setReg(SanitizerState& state, MicroReg reg, const SanitizerRegInfo& info)
{
    if (reg.isValid())
        state.regs[reg.packed] = info;
}

void NullDerefAnalysis::setRegValue(SanitizerState& state, MicroReg reg, const SanitizerValue& value)
{
    if (reg.isValid())
        state.regs[reg.packed] = SanitizerRegInfo{value};
}

bool NullDerefAnalysis::resolveStackSlot(const SanitizerState& state, MicroReg base, uint64_t offset, int64_t& outSlot) const
{
    const SanitizerValue baseValue = getReg(state, base);
    if (!baseValue.isStackAddr())
        return false;
    outSlot = baseValue.stackOffset + static_cast<int64_t>(offset);
    return true;
}

// ---------------------------------------------------------------------------
// Join + propagation
// ---------------------------------------------------------------------------
void NullDerefAnalysis::propagate(const SanitizerState& edge, uint32_t index, std::vector<uint32_t>& worklist)
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
    }
}

bool NullDerefAnalysis::joinInto(SanitizerState& into, const SanitizerState& from)
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

    if (into.flagsSubject.isValid() && into.flagsSubject != from.flagsSubject)
    {
        into.flagsSubject = MicroReg::invalid();
        changed           = true;
    }

    return changed;
}

// ---------------------------------------------------------------------------
// Value effects
// ---------------------------------------------------------------------------
void NullDerefAnalysis::applyValueEffects(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) const
{
    switch (inst.op)
    {
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
            // A move/extension propagates the whole tracked info (value + origin + null-
            // test fact). The value goes through getReg so the special stack-base register
            // is resolved even though it is not stored in the map.
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
                setRegValue(state, ops[0].reg, SanitizerValue::makeStackAddr(slot));
            else if (baseValue.isProvableNull())
                setRegValue(state, ops[0].reg, SanitizerValue::makeConstant(0)); // null-derived
            else if (baseValue.kind == SanitizerValueKind::GlobalAddr)
                setRegValue(state, ops[0].reg, SanitizerValue::makeGlobalAddr());
            else
                setRegValue(state, ops[0].reg, {});
            return;
        }

        case MicroInstrOpcode::LoadRegMem:
        {
            int64_t slot = 0;
            if (resolveStackSlot(state, ops[1].reg, ops[3].valueU64, slot))
            {
                const auto       it = state.stack.find(slot);
                SanitizerRegInfo info;
                info.value         = it != state.stack.end() ? it->second : SanitizerValue{};
                info.hasOriginSlot = true;
                info.originSlot    = slot;
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
            if (isAddSub && cur.isProvableNull())
                setRegValue(state, reg, SanitizerValue::makeConstant(0));
            else if (ops[2].microOp == MicroOp::Add && cur.isStackAddr())
                setRegValue(state, reg, SanitizerValue::makeStackAddr(cur.stackOffset + static_cast<int64_t>(imm)));
            else if (ops[2].microOp == MicroOp::Add && cur.kind == SanitizerValueKind::Constant)
                setRegValue(state, reg, SanitizerValue::makeConstant(cur.constant + imm));
            else if (ops[2].microOp == MicroOp::Subtract && cur.isStackAddr())
                setRegValue(state, reg, SanitizerValue::makeStackAddr(cur.stackOffset - static_cast<int64_t>(imm)));
            else if (ops[2].microOp == MicroOp::Subtract && cur.kind == SanitizerValueKind::Constant)
                setRegValue(state, reg, SanitizerValue::makeConstant(cur.constant - imm));
            else
                setRegValue(state, reg, {});
            return;
        }

        case MicroInstrOpcode::CmpRegImm:
            state.flagsSubject = ops[2].valueU64 == 0 ? ops[0].reg : MicroReg::invalid();
            return;

        case MicroInstrOpcode::CmpRegReg:
            if (getReg(state, ops[1].reg).isProvableNull())
                state.flagsSubject = ops[0].reg;
            else if (getReg(state, ops[0].reg).isProvableNull())
                state.flagsSubject = ops[1].reg;
            else
                state.flagsSubject = MicroReg::invalid();
            return;

        case MicroInstrOpcode::SetCondReg:
        {
            SanitizerRegInfo        info; // value stays Unknown (a 0/1 bool, not a pointer)
            const SanitizerRegInfo* subject    = state.flagsSubject.isValid() ? findReg(state, state.flagsSubject) : nullptr;
            bool                    trueIfZero = false;
            if (subject && subject->hasOriginSlot && condIsZeroTest(ops[1].cpuCond, trueIfZero))
            {
                info.hasNullTest        = true;
                info.nullTestSlot       = subject->originSlot;
                info.nullTestTrueIfNull = trueIfZero;
            }
            setReg(state, ops[0].reg, info);
            return;
        }

        default:
            break;
    }

    if (def.flags.has(MicroInstrFlagsE::IsCallInstruction))
    {
        // Calls clobber caller-saved registers and may mutate escaped locals.
        state.regs.clear();
        state.stack.clear();
        state.flagsSubject = MicroReg::invalid();
        return;
    }

    if (def.flags.has(MicroInstrFlagsE::DefinesCpuFlags))
        state.flagsSubject = MicroReg::invalid();
    invalidateDefs(state, inst, def, ops);
}

void NullDerefAnalysis::invalidateDefs(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    const uint32_t regCount = std::min<uint32_t>(inst.numOperands, def.regModes.size());
    for (uint32_t i = 0; i < regCount; i++)
        if (def.regModes[i] == MicroInstrRegMode::Def || def.regModes[i] == MicroInstrRegMode::UseDef)
            setRegValue(state, ops[i].reg, {});
}

bool NullDerefAnalysis::condIsZeroTest(MicroCond cond, bool& outTrueIfZero)
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

// ---------------------------------------------------------------------------
// Conditional branch: narrow the tested slot on each edge, prune infeasible edges,
// and fall back to dropping nulls when it cannot be modelled.
// ---------------------------------------------------------------------------
void NullDerefAnalysis::propagateConditionalBranch(const SanitizerState& state, const MicroInstrOperand* ops, const MicroControlFlowGraph::EdgeList& succs, std::vector<uint32_t>& worklist)
{
    const SanitizerRegInfo* subject = state.flagsSubject.isValid() ? findReg(state, state.flagsSubject) : nullptr;

    bool    condTrueIfSubjectZero = false;
    int64_t slot                  = 0;
    bool    slotNullIfSubjectZero = false;
    if (subject && condIsZeroTest(ops[0].cpuCond, condTrueIfSubjectZero) &&
        resolveGuardSlot(*subject, slot, slotNullIfSubjectZero))
    {
        // successors = [taken (cond true), fallthrough (cond false)].
        queueRefined(state, succs[0], slot, condTrueIfSubjectZero == slotNullIfSubjectZero, worklist);
        queueRefined(state, succs[1], slot, (!condTrueIfSubjectZero) == slotNullIfSubjectZero, worklist);
        return;
    }

    // Unmodellable guard: keep exploring but drop provable nulls so nothing is reported
    // past a guard we did not understand.
    for (const uint32_t s : succs)
    {
        SanitizerState edge = state;
        dropNulls(edge);
        edge.flagsSubject = MicroReg::invalid();
        propagate(edge, s, worklist);
    }
}

bool NullDerefAnalysis::resolveGuardSlot(const SanitizerRegInfo& subject, int64_t& outSlot, bool& outSlotNullIfSubjectZero)
{
    if (subject.hasNullTest)
    {
        // subject is a bool == (slot is null) when nullTestTrueIfNull.
        // subject == 0 (false) ⇒ slot is null iff !nullTestTrueIfNull.
        outSlot                  = subject.nullTestSlot;
        outSlotNullIfSubjectZero = !subject.nullTestTrueIfNull;
        return true;
    }
    if (subject.hasOriginSlot)
    {
        outSlot                  = subject.originSlot;
        outSlotNullIfSubjectZero = true; // subject IS the pointer: subject==0 ⇒ slot null
        return true;
    }
    return false;
}

void NullDerefAnalysis::queueRefined(const SanitizerState& state, uint32_t index, int64_t slot, bool slotIsNull, std::vector<uint32_t>& worklist)
{
    const auto           it      = state.stack.find(slot);
    const SanitizerValue current = it != state.stack.end() ? it->second : SanitizerValue{};

    if (slotIsNull && current.isKnownNonZero())
        return; // infeasible
    if (!slotIsNull && current.isProvableNull())
        return; // infeasible

    SanitizerState edge = state;
    edge.stack[slot]    = slotIsNull ? SanitizerValue::makeConstant(0) : SanitizerValue::makeNonZero();
    edge.flagsSubject   = MicroReg::invalid();
    propagate(edge, index, worklist);
}

void NullDerefAnalysis::dropNulls(SanitizerState& state)
{
    for (auto& info : state.regs | std::views::values)
        if (info.value.isProvableNull())
            info.value = {};
    for (auto& value : state.stack | std::views::values)
        if (value.isProvableNull())
            value = {};
}

// ---------------------------------------------------------------------------
// Dereference check + reporting
// ---------------------------------------------------------------------------
void NullDerefAnalysis::checkDereference(const SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    if (!def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
        return;
    // A `lea` only computes an address; it never faults. Real code legitimately forms
    // addresses from a null base (e.g. the data pointer of an empty, zero-length slice),
    // so only an actual load/store is a dereference.
    if (inst.op == MicroInstrOpcode::LoadAddrRegMem || inst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
        return;

    if (getReg(state, ops[def.memBaseOperandIndex].reg).isProvableNull())
        reportNullDeref(inst);
}

void NullDerefAnalysis::reportNullDeref(const MicroInstr& inst)
{
    const SourceCodeRef& codeRef = inst.debugSourceInfo.sourceCodeRef;

    // The same source dereference is reached by several paths / fixpoint passes and can
    // lower to several instructions; report each location at most once.
    const uint64_t key = (static_cast<uint64_t>(codeRef.srcViewRef.get()) << 32) | codeRef.tokRef.get();
    reported_          = true;
    if (!reportedLocations_.insert(key).second)
        return;

    ResolvedDebugSourceInfo resolved;
    if (!tryResolveDebugSourceInfo(*context_.taskContext, resolved, inst.debugSourceInfo))
        return;

    const FileRef    fileRef = resolved.sourceFile ? resolved.sourceFile->ref() : FileRef::invalid();
    const Diagnostic diag    = Diagnostic::get(DiagnosticId::safety_err_null_deref, fileRef);
    diag.last().addSpan(resolved.codeRange, "", DiagnosticSeverity::Error);
    diag.report(*context_.taskContext);
}

SWC_END_NAMESPACE();
