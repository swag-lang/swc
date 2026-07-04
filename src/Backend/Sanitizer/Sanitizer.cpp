#include "pch.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Sanitizer/SanitizerCheck.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Sanitizer::Sanitizer(MicroPassContext& context) :
    context_(context),
    stackBaseReg_(context.debugStackBaseVirtualReg)
{
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
        {
            for (const uint32_t s : succs)
            {
                SanitizerState edge = cur;
                dropZeros(edge);
                edge.flagsSubject = MicroReg::invalid();
                propagate(edge, s, worklist);
            }
        }
    }

    // Resolve call targets so checks can identify what a call instruction invokes.
    std::unordered_map<uint32_t, const Symbol*> callTargets;
    for (const MicroRelocation& rel : context_.builder->codeRelocations())
    {
        if (rel.targetSymbol &&
            (rel.kind == MicroRelocation::Kind::LocalFunctionAddress || rel.kind == MicroRelocation::Kind::ForeignFunctionAddress))
            callTargets[rel.instructionRef.get()] = rel.targetSymbol;
    }

    // Apply the checks only on the converged states.
    for (uint32_t i = 0; i < n; i++)
    {
        if (!reached_[i])
            continue;
        const MicroInstrRef      instRef = cfg.instructionRefs()[i];
        const MicroInstr&        inst    = *context_.instructions->ptr(instRef);
        const MicroInstrDef&     def     = MicroInstr::info(inst.op);
        const MicroInstrOperand* ops     = inst.numOperands ? inst.ops(*context_.operands) : nullptr;

        currentCallTarget_ = nullptr;
        if (def.flags.has(MicroInstrFlagsE::IsCallInstruction))
        {
            const auto it = callTargets.find(instRef.get());
            if (it != callTargets.end())
                currentCallTarget_ = it->second;
        }

        for (SanitizerCheck* check : checks)
            check->run(*this, inState_[i], inst, def, ops);
    }

    return reported_;
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

    if (into.flagsSubject.isValid() && into.flagsSubject != from.flagsSubject)
    {
        into.flagsSubject = MicroReg::invalid();
        changed           = true;
    }

    return changed;
}

void Sanitizer::applyValueEffects(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) const
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
            // A move/extension propagates the whole tracked info (value + origin + zero-
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
            else if (baseValue.isZero())
                setRegValue(state, ops[0].reg, SanitizerValue::makeConstant(0)); // zero-derived
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
            if (isAddSub && cur.isZero())
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

void Sanitizer::invalidateDefs(SanitizerState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
{
    const uint32_t regCount = std::min<uint32_t>(inst.numOperands, def.regModes.size());
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
