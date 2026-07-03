#include "pch.h"
#include "Backend/Micro/Passes/Pass.Sanity.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Runtime.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // ---------------------------------------------------------------------------
    // Abstract value tracked for a register or a stack slot.
    //
    // `Constant 0` is a provable null. `NonZero`, `StackAddr` and `GlobalAddr` are
    // known non-null. `Unknown` is anything else and is never flagged, so the analysis
    // only ever reports pointers it can prove are null on *every* path — no false
    // positives.
    // ---------------------------------------------------------------------------
    enum class SanityKind : uint8_t
    {
        Unknown,
        Constant,
        NonZero,    // known non-null, exact value unknown (e.g. narrowed by a guard)
        StackAddr,  // address of a local stack slot (non-null)
        GlobalAddr, // address of a global / function (non-null)
    };

    struct SanityValue
    {
        SanityKind kind        = SanityKind::Unknown;
        uint64_t   constant    = 0; // Constant
        int64_t    stackOffset = 0; // StackAddr

        static SanityValue makeConstant(uint64_t value) { return {SanityKind::Constant, value, 0}; }
        static SanityValue makeNonZero() { return {SanityKind::NonZero, 0, 0}; }
        static SanityValue makeStackAddr(int64_t offset) { return {SanityKind::StackAddr, 0, offset}; }
        static SanityValue makeGlobalAddr() { return {SanityKind::GlobalAddr, 0, 0}; }

        bool isProvableNull() const { return kind == SanityKind::Constant && constant == 0; }
        bool isKnownNonZero() const
        {
            return kind == SanityKind::NonZero ||
                   kind == SanityKind::StackAddr ||
                   kind == SanityKind::GlobalAddr ||
                   (kind == SanityKind::Constant && constant != 0);
        }
        bool isStackAddr() const { return kind == SanityKind::StackAddr; }

        bool operator==(const SanityValue& o) const { return kind == o.kind && constant == o.constant && stackOffset == o.stackOffset; }
    };

    // Per-register information carried along the flow.
    struct RegInfo
    {
        SanityValue value;

        // If the register was loaded from a local stack slot, remember which, so a guard
        // testing this register can narrow the slot it came from (in unoptimized IR the
        // guarded block reloads the pointer from the same slot).
        bool    hasOriginSlot = false;
        int64_t originSlot    = 0;

        // If the register is a boolean produced by a null test (`setcc` after `cmp x,0`),
        // remember which slot was tested and whether the bool is true when that slot is
        // null. A branch on the bool then narrows the underlying pointer's slot.
        bool    hasNullTest        = false;
        int64_t nullTestSlot       = 0;
        bool    nullTestTrueIfNull = false;

        bool operator==(const RegInfo& o) const
        {
            return value == o.value && hasOriginSlot == o.hasOriginSlot && originSlot == o.originSlot &&
                   hasNullTest == o.hasNullTest && nullTestSlot == o.nullTestSlot && nullTestTrueIfNull == o.nullTestTrueIfNull;
        }
    };

    // Abstract machine state at one program point.
    struct SanityState
    {
        std::unordered_map<uint32_t, RegInfo>    regs;  // key: MicroReg.packed
        std::unordered_map<int64_t, SanityValue> stack; // key: stack slot offset
        MicroReg                                 flagsSubject = MicroReg::invalid();
    };

    // Path-sensitive "must-be-null" data-flow analysis for null-pointer dereferences.
    //
    // A monotone forward analysis over the control-flow graph: each program point holds
    // the state that is true on *all* paths reaching it (join = keep only values both
    // predecessors agree on; disagreement widens to Unknown). This is cheap (linear,
    // no path explosion) and cannot report a false positive — a slot is only "null" if
    // it is provably null on every path. At a null-test branch each edge narrows the
    // tested pointer/slot (so `if p != null { p.x }` is safe and `if p == null { p.x }`
    // is flagged) and infeasible edges are pruned. Branches it cannot model drop all
    // provable-null values, staying sound.
    class SanityInterpreter
    {
    public:
        explicit SanityInterpreter(MicroPassContext& context) :
            context_(context),
            stackBaseReg_(context.debugStackBaseVirtualReg)
        {
        }

        bool run()
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

                SanityState              cur = inState_[index];
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
                        SanityState edge = cur;
                        dropNulls(edge);
                        edge.flagsSubject = MicroReg::invalid();
                        propagate(edge, s, worklist);
                    }
            }

            // Report only on the converged states: a dereference is flagged only if its
            // incoming state proves the base is null on every path. Checking during the
            // fixpoint would report on a transient pre-join state that a later merge
            // widens back to Unknown.
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

    private:
        static constexpr uint32_t K_MAX_INSTRUCTIONS = 20000;
        static constexpr uint64_t K_ITERATION_CAP    = 400000;

        static bool isModelledSingleEdge(const MicroInstrDef& def, const MicroControlFlowGraph::EdgeList& succs)
        {
            // A plain fall-through or an unconditional direct jump: the state flows
            // unchanged to the single successor.
            return succs.size() == 1 && !def.flags.has(MicroInstrFlagsE::ConditionalJump);
        }

        // -------------------------------------------------------------------
        // Register / slot access
        // -------------------------------------------------------------------
        SanityValue getReg(const SanityState& state, MicroReg reg) const
        {
            if (stackBaseReg_.isValid() && reg == stackBaseReg_)
                return SanityValue::makeStackAddr(0);
            const auto it = state.regs.find(reg.packed);
            return it == state.regs.end() ? SanityValue{} : it->second.value;
        }

        static const RegInfo* findReg(const SanityState& state, MicroReg reg)
        {
            const auto it = state.regs.find(reg.packed);
            return it == state.regs.end() ? nullptr : &it->second;
        }

        void setReg(SanityState& state, MicroReg reg, const RegInfo& info) const
        {
            if (reg.isValid())
                state.regs[reg.packed] = info;
        }

        void setRegValue(SanityState& state, MicroReg reg, const SanityValue& value) const
        {
            if (reg.isValid())
                state.regs[reg.packed] = RegInfo{value};
        }

        bool resolveStackSlot(const SanityState& state, MicroReg base, uint64_t offset, int64_t& outSlot) const
        {
            const SanityValue baseValue = getReg(state, base);
            if (!baseValue.isStackAddr())
                return false;
            outSlot = baseValue.stackOffset + static_cast<int64_t>(offset);
            return true;
        }

        // -------------------------------------------------------------------
        // Join + propagation
        // -------------------------------------------------------------------
        void propagate(const SanityState& edge, uint32_t index, std::vector<uint32_t>& worklist)
        {
            bool changed;
            if (!reached_[index])
            {
                reached_[index]   = 1;
                inState_[index]   = edge;
                changed           = true;
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

        // Meet `from` into `into`, keeping only what both agree on. Returns true if
        // `into` lost information (needs reprocessing).
        static bool joinInto(SanityState& into, const SanityState& from)
        {
            bool changed = false;

            for (auto it = into.stack.begin(); it != into.stack.end();)
            {
                const auto f = from.stack.find(it->first);
                if (f == from.stack.end() || !(f->second == it->second))
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
                if (f == from.regs.end() || !(f->second == it->second))
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

        // -------------------------------------------------------------------
        // Value effects
        // -------------------------------------------------------------------
        void applyValueEffects(SanityState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) const
        {
            switch (inst.op)
            {
                case MicroInstrOpcode::LoadRegImm:
                    setRegValue(state, ops[0].reg, SanityValue::makeConstant(ops[2].valueU64));
                    return;

                case MicroInstrOpcode::LoadRegPtrImm:
                    setRegValue(state, ops[0].reg, SanityValue::makeConstant(ops[2].valueU64));
                    return;

                case MicroInstrOpcode::ClearReg:
                    setRegValue(state, ops[0].reg, SanityValue::makeConstant(0));
                    return;

                case MicroInstrOpcode::LoadRegPtrReloc:
                    setRegValue(state, ops[0].reg, SanityValue::makeGlobalAddr());
                    return;

                case MicroInstrOpcode::LoadRegReg:
                case MicroInstrOpcode::LoadZeroExtRegReg:
                case MicroInstrOpcode::LoadSignedExtRegReg:
                {
                    // A move/extension propagates the whole tracked info (value + origin +
                    // null-test fact). The value goes through getReg so the special stack-
                    // base register is resolved even though it is not stored in the map.
                    RegInfo info;
                    if (const RegInfo* src = findReg(state, ops[1].reg))
                        info = *src;
                    info.value = getReg(state, ops[1].reg);
                    setReg(state, ops[0].reg, info);
                    return;
                }

                case MicroInstrOpcode::LoadAddrRegMem:
                {
                    const SanityValue baseValue = getReg(state, ops[1].reg);
                    int64_t           slot      = 0;
                    if (resolveStackSlot(state, ops[1].reg, ops[3].valueU64, slot))
                        setRegValue(state, ops[0].reg, SanityValue::makeStackAddr(slot));
                    else if (baseValue.isProvableNull())
                        setRegValue(state, ops[0].reg, SanityValue::makeConstant(0)); // null-derived
                    else if (baseValue.kind == SanityKind::GlobalAddr)
                        setRegValue(state, ops[0].reg, SanityValue::makeGlobalAddr());
                    else
                        setRegValue(state, ops[0].reg, {});
                    return;
                }

                case MicroInstrOpcode::LoadRegMem:
                {
                    int64_t slot = 0;
                    if (resolveStackSlot(state, ops[1].reg, ops[3].valueU64, slot))
                    {
                        const auto it = state.stack.find(slot);
                        RegInfo    info;
                        info.value         = it != state.stack.end() ? it->second : SanityValue{};
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
                        state.stack[slot] = SanityValue::makeConstant(ops[3].valueU64);
                    return;
                }

                case MicroInstrOpcode::OpBinaryRegImm:
                {
                    const MicroReg    reg      = ops[0].reg;
                    const SanityValue cur      = getReg(state, reg);
                    const uint64_t    imm      = ops[3].valueU64;
                    const bool        isAddSub = ops[2].microOp == MicroOp::Add || ops[2].microOp == MicroOp::Subtract;
                    if (isAddSub && cur.isProvableNull())
                        setRegValue(state, reg, SanityValue::makeConstant(0));
                    else if (ops[2].microOp == MicroOp::Add && cur.isStackAddr())
                        setRegValue(state, reg, SanityValue::makeStackAddr(cur.stackOffset + static_cast<int64_t>(imm)));
                    else if (ops[2].microOp == MicroOp::Add && cur.kind == SanityKind::Constant)
                        setRegValue(state, reg, SanityValue::makeConstant(cur.constant + imm));
                    else if (ops[2].microOp == MicroOp::Subtract && cur.isStackAddr())
                        setRegValue(state, reg, SanityValue::makeStackAddr(cur.stackOffset - static_cast<int64_t>(imm)));
                    else if (ops[2].microOp == MicroOp::Subtract && cur.kind == SanityKind::Constant)
                        setRegValue(state, reg, SanityValue::makeConstant(cur.constant - imm));
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
                    RegInfo        info; // value stays Unknown (a 0/1 bool, not a pointer)
                    const RegInfo* subject    = state.flagsSubject.isValid() ? findReg(state, state.flagsSubject) : nullptr;
                    bool           trueIfZero = false;
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

        void invalidateDefs(SanityState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops) const
        {
            const uint32_t regCount = std::min<uint32_t>(inst.numOperands, static_cast<uint32_t>(def.regModes.size()));
            for (uint32_t i = 0; i < regCount; i++)
                if (def.regModes[i] == MicroInstrRegMode::Def || def.regModes[i] == MicroInstrRegMode::UseDef)
                    setRegValue(state, ops[i].reg, {});
        }

        static bool condIsZeroTest(MicroCond cond, bool& outTrueIfZero)
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

        // -------------------------------------------------------------------
        // Conditional branch: narrow the tested slot on each edge, prune infeasible
        // edges, and fall back to dropping nulls when it cannot be modelled.
        // -------------------------------------------------------------------
        void propagateConditionalBranch(const SanityState& state, const MicroInstrOperand* ops,
                                        const MicroControlFlowGraph::EdgeList& succs, std::vector<uint32_t>& worklist)
        {
            const RegInfo* subject = state.flagsSubject.isValid() ? findReg(state, state.flagsSubject) : nullptr;

            bool condTrueIfSubjectZero = false;
            int64_t slot               = 0;
            bool    slotNullIfSubjectZero = false;
            if (subject && condIsZeroTest(ops[0].cpuCond, condTrueIfSubjectZero) &&
                resolveGuardSlot(*subject, slot, slotNullIfSubjectZero))
            {
                // successors = [taken (cond true), fallthrough (cond false)].
                queueRefined(state, succs[0], slot, condTrueIfSubjectZero == slotNullIfSubjectZero, worklist);
                queueRefined(state, succs[1], slot, (!condTrueIfSubjectZero) == slotNullIfSubjectZero, worklist);
                return;
            }

            // Unmodellable guard: keep exploring but drop provable nulls so nothing is
            // reported past a guard we did not understand.
            for (const uint32_t s : succs)
            {
                SanityState edge = state;
                dropNulls(edge);
                edge.flagsSubject = MicroReg::invalid();
                propagate(edge, s, worklist);
            }
        }

        static bool resolveGuardSlot(const RegInfo& subject, int64_t& outSlot, bool& outSlotNullIfSubjectZero)
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

        void queueRefined(const SanityState& state, uint32_t index, int64_t slot, bool slotIsNull, std::vector<uint32_t>& worklist)
        {
            const auto        it      = state.stack.find(slot);
            const SanityValue current = it != state.stack.end() ? it->second : SanityValue{};

            if (slotIsNull && current.isKnownNonZero())
                return; // infeasible
            if (!slotIsNull && current.isProvableNull())
                return; // infeasible

            SanityState edge  = state;
            edge.stack[slot]  = slotIsNull ? SanityValue::makeConstant(0) : SanityValue::makeNonZero();
            edge.flagsSubject = MicroReg::invalid();
            propagate(edge, index, worklist);
        }

        static void dropNulls(SanityState& state)
        {
            for (auto& [key, info] : state.regs)
                if (info.value.isProvableNull())
                    info.value = {};
            for (auto& [slot, value] : state.stack)
                if (value.isProvableNull())
                    value = {};
        }

        // -------------------------------------------------------------------
        // Dereference check + reporting
        // -------------------------------------------------------------------
        void checkDereference(const SanityState& state, const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
        {
            if (!def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
                return;
            // A `lea` only computes an address; it never faults. Real code legitimately
            // forms addresses from a null base (e.g. the data pointer of an empty, zero-
            // length slice), so only an actual load/store is a dereference.
            if (inst.op == MicroInstrOpcode::LoadAddrRegMem || inst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
                return;

            if (getReg(state, ops[def.memBaseOperandIndex].reg).isProvableNull())
                reportNullDeref(inst);
        }

        void reportNullDeref(const MicroInstr& inst)
        {
            const SourceCodeRef& codeRef = inst.debugSourceInfo.sourceCodeRef;

            // The same source dereference is reached by several paths / fixpoint passes
            // and can lower to several instructions; report each location at most once.
            const uint64_t key = (static_cast<uint64_t>(codeRef.srcViewRef.get()) << 32) | codeRef.tokRef.get();
            reported_          = true;
            if (!reportedLocations_.insert(key).second)
                return;

            ResolvedDebugSourceInfo resolved;
            if (!tryResolveDebugSourceInfo(*context_.taskContext, resolved, inst.debugSourceInfo))
                return;

            const FileRef fileRef = resolved.sourceFile ? resolved.sourceFile->ref() : FileRef::invalid();
            Diagnostic    diag    = Diagnostic::get(DiagnosticId::safety_err_null_deref, fileRef);
            diag.last().addSpan(resolved.codeRange, "", DiagnosticSeverity::Error);
            diag.report(*context_.taskContext);
        }

        MicroPassContext&            context_;
        MicroReg                     stackBaseReg_;
        const MicroControlFlowGraph* cfg_      = nullptr;
        bool                         reported_ = false;
        std::vector<SanityState>     inState_;
        std::vector<char>            reached_;
        std::vector<char>            inWorklist_;
        std::unordered_set<uint64_t> reportedLocations_;
    };

    // The analysis runs only when the `Null` safety guard is enabled for this build
    // configuration (All in debug/fast-debug, None in release/fast-compile).
    bool nullSafetyEnabled(const MicroPassContext& context)
    {
        if (!context.taskContext)
            return false;

        const Runtime::BuildCfg& buildCfg = context.taskContext->compiler().buildCfg();
        const auto               guards   = static_cast<uint16_t>(buildCfg.safetyGuards);
        const auto               want     = static_cast<uint16_t>(Runtime::SafetyWhat::Null);
        return (guards & want) == want;
    }
}

Result MicroSanityPass::run(MicroPassContext& context)
{
    context.passChanged = false;

    if (!nullSafetyEnabled(context))
        return Result::Continue;
    if (!context.instructions || !context.operands || !context.taskContext || !context.builder)
        return Result::Continue;

    // On a proven null dereference, abort codegen so the faulty function is never
    // emitted or run. The reported error fails the build (or is matched by a test's
    // expected-error marker); a function that legitimately produced no code because it
    // errored is skipped by the backend's missing-code validation.
    SanityInterpreter interpreter(context);
    if (interpreter.run())
        return Result::Error;
    return Result::Continue;
}

SWC_END_NAMESPACE();
