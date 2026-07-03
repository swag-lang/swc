#include "pch.h"
#include "Backend/Micro/Passes/Pass.Sanity.h"
#include "Backend/Encoder/Encoder.h"
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
    // Only a `Constant` value equal to zero is a *provable* null. `StackAddr` and
    // `GlobalAddr` are known non-null (address of a local / of a global). `Unknown`
    // is anything else and is never flagged, so the analysis only reports pointers
    // it can prove are null — no false positives.
    // ---------------------------------------------------------------------------
    enum class SanityKind : uint8_t
    {
        Unknown,
        Constant,
        StackAddr,
        GlobalAddr,
    };

    struct SanityValue
    {
        SanityKind kind        = SanityKind::Unknown;
        uint64_t   constant    = 0; // Constant
        int64_t    stackOffset = 0; // StackAddr

        static SanityValue makeConstant(uint64_t value) { return {SanityKind::Constant, value, 0}; }
        static SanityValue makeStackAddr(int64_t offset) { return {SanityKind::StackAddr, 0, offset}; }
        static SanityValue makeGlobalAddr() { return {SanityKind::GlobalAddr, 0, 0}; }

        bool isProvableNull() const { return kind == SanityKind::Constant && constant == 0; }
        bool isStackAddr() const { return kind == SanityKind::StackAddr; }
    };

    // Basic-block-local abstract interpreter for provable null-pointer dereferences.
    //
    // It walks the instruction stream in order and tracks, within each straight-line
    // region, the value held by every virtual register and by every simulated local
    // stack slot. At any control-flow boundary (label, call, branch, terminator) it
    // conservatively drops all tracked state, so nothing is ever assumed across a
    // merge/branch — this keeps the analysis sound (no false positives) at the cost
    // of only catching nulls that are provable within a single basic block. Path
    // sensitivity across guards (`if p == null { ... }`) is a later phase.
    class SanityInterpreter
    {
    public:
        SanityInterpreter(MicroPassContext& context) :
            context_(context),
            stackBaseReg_(context.debugStackBaseVirtualReg)
        {
        }

        // Returns true if at least one provable null dereference was reported, in
        // which case the caller must abort codegen so the faulty function is never
        // emitted or run.
        bool run()
        {
            for (MicroInstr& inst : context_.instructions->view())
                step(inst);
            return reported_;
        }

    private:
        SanityValue getReg(MicroReg reg) const
        {
            // The local-stack base register addresses locals: treat it as a stack
            // address at offset 0 so `[base + off]` resolves to stack slot `off`.
            if (stackBaseReg_.isValid() && reg == stackBaseReg_)
                return SanityValue::makeStackAddr(0);

            const auto it = regs_.find(reg.packed);
            if (it == regs_.end())
                return {};
            return it->second;
        }

        void setReg(MicroReg reg, const SanityValue& value)
        {
            if (!reg.isValid())
                return;
            regs_[reg.packed] = value;
        }

        // Resolves the effective stack offset addressed by `[base + off]`, if `base`
        // is a known stack address. Returns false otherwise.
        bool resolveStackSlot(MicroReg base, uint64_t offset, int64_t& outSlot) const
        {
            const SanityValue baseValue = getReg(base);
            if (!baseValue.isStackAddr())
                return false;
            outSlot = baseValue.stackOffset + static_cast<int64_t>(offset);
            return true;
        }

        void invalidate()
        {
            regs_.clear();
            stack_.clear();
        }

        void step(MicroInstr& inst)
        {
            const MicroInstrDef&   def = MicroInstr::info(inst.op);
            const MicroInstrOperand* ops = inst.numOperands ? inst.ops(*context_.operands) : nullptr;

            // Check dereferences before applying value effects.
            checkDereference(inst, def, ops);

            switch (inst.op)
            {
                case MicroInstrOpcode::LoadRegImm:
                    // ops: [def, opBits, imm]
                    setReg(ops[0].reg, SanityValue::makeConstant(ops[2].valueU64));
                    return;

                case MicroInstrOpcode::ClearReg:
                    // ops: [def, opBits]
                    setReg(ops[0].reg, SanityValue::makeConstant(0));
                    return;

                case MicroInstrOpcode::LoadRegReg:
                    // ops: [def, src, opBits]
                    setReg(ops[0].reg, getReg(ops[1].reg));
                    return;

                case MicroInstrOpcode::LoadRegPtrImm:
                    // ops: [def, opBits, value]  (absolute pointer immediate)
                    setReg(ops[0].reg, SanityValue::makeConstant(ops[2].valueU64));
                    return;

                case MicroInstrOpcode::LoadRegPtrReloc:
                    // ops: [def, opBits, value]  (address of a global/function — non-null)
                    setReg(ops[0].reg, SanityValue::makeGlobalAddr());
                    return;

                case MicroInstrOpcode::LoadAddrRegMem:
                {
                    // ops: [def, base, opBits, off] — address computation (lea).
                    const SanityValue baseValue = getReg(ops[1].reg);
                    int64_t           slot      = 0;
                    if (resolveStackSlot(ops[1].reg, ops[3].valueU64, slot))
                        setReg(ops[0].reg, SanityValue::makeStackAddr(slot));
                    else if (baseValue.isProvableNull())
                        // `&p.field` on a null `p` was already reported by checkDereference;
                        // drop the null so the eventual store through this address does not
                        // report the same dereference a second time.
                        setReg(ops[0].reg, {});
                    else if (baseValue.kind == SanityKind::GlobalAddr)
                        setReg(ops[0].reg, SanityValue::makeGlobalAddr());
                    else if (baseValue.kind == SanityKind::Constant)
                        setReg(ops[0].reg, SanityValue::makeConstant(baseValue.constant + ops[3].valueU64));
                    else
                        setReg(ops[0].reg, {});
                    return;
                }

                case MicroInstrOpcode::LoadRegMem:
                {
                    // ops: [def, base, opBits, off] — load through a pointer.
                    int64_t slot = 0;
                    if (resolveStackSlot(ops[1].reg, ops[3].valueU64, slot))
                    {
                        const auto it = stack_.find(slot);
                        setReg(ops[0].reg, it != stack_.end() ? it->second : SanityValue{});
                    }
                    else
                        setReg(ops[0].reg, {});
                    return;
                }

                case MicroInstrOpcode::LoadMemReg:
                {
                    // ops: [base, src, opBits, off] — store a register through a pointer.
                    int64_t slot = 0;
                    if (resolveStackSlot(ops[0].reg, ops[3].valueU64, slot))
                        stack_[slot] = getReg(ops[1].reg);
                    return;
                }

                case MicroInstrOpcode::LoadMemImm:
                {
                    // ops: [base, opBits, off, imm] — store an immediate through a pointer.
                    int64_t slot = 0;
                    if (resolveStackSlot(ops[0].reg, ops[2].valueU64, slot))
                        stack_[slot] = SanityValue::makeConstant(ops[3].valueU64);
                    return;
                }

                case MicroInstrOpcode::OpBinaryRegImm:
                {
                    // ops: [reg (use+def), opBits, microOp, imm]. Constant add/subtract is
                    // how the front end forms the address of a local (`stackBase + off`) and
                    // does pointer/offset arithmetic, so it must be tracked to follow values
                    // through stack slots.
                    const MicroReg    reg = ops[0].reg;
                    const SanityValue cur = getReg(reg);
                    const uint64_t    imm = ops[3].valueU64;
                    if (ops[2].microOp == MicroOp::Add)
                    {
                        if (cur.isStackAddr())
                            setReg(reg, SanityValue::makeStackAddr(cur.stackOffset + static_cast<int64_t>(imm)));
                        else if (cur.kind == SanityKind::Constant)
                            setReg(reg, SanityValue::makeConstant(cur.constant + imm));
                        else
                            setReg(reg, {});
                    }
                    else if (ops[2].microOp == MicroOp::Subtract)
                    {
                        if (cur.isStackAddr())
                            setReg(reg, SanityValue::makeStackAddr(cur.stackOffset - static_cast<int64_t>(imm)));
                        else if (cur.kind == SanityKind::Constant)
                            setReg(reg, SanityValue::makeConstant(cur.constant - imm));
                        else
                            setReg(reg, {});
                    }
                    else
                        setReg(reg, {});
                    return;
                }

                default:
                    break;
            }

            // Control-flow boundaries and calls: drop all tracked state so nothing is
            // ever assumed across a branch, merge, or clobbering call.
            if (def.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                def.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                def.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                inst.op == MicroInstrOpcode::Label)
            {
                invalidate();
                return;
            }

            // Any other instruction: conservatively mark its register definitions as
            // Unknown so a stale tracked value is never reused.
            invalidateDefs(inst, def, ops);
        }

        void invalidateDefs(const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
        {
            const uint32_t regCount = std::min<uint32_t>(inst.numOperands, static_cast<uint32_t>(def.regModes.size()));
            for (uint32_t i = 0; i < regCount; i++)
            {
                if (def.regModes[i] == MicroInstrRegMode::Def || def.regModes[i] == MicroInstrRegMode::UseDef)
                    setReg(ops[i].reg, {});
            }
        }

        void checkDereference(const MicroInstr& inst, const MicroInstrDef& def, const MicroInstrOperand* ops)
        {
            if (!def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
                return;
            // Note: a `lea` (LoadAddrRegMem) computes an address without touching memory,
            // but forming the address of a field/element of a null pointer (`&p.field`)
            // still requires `p` to be a valid object, so it is reported like a real
            // dereference.

            const MicroReg    base      = ops[def.memBaseOperandIndex].reg;
            const SanityValue baseValue = getReg(base);
            if (!baseValue.isProvableNull())
                return;

            reportNullDeref(inst);
        }

        void reportNullDeref(const MicroInstr& inst)
        {
            ResolvedDebugSourceInfo resolved;
            if (!tryResolveDebugSourceInfo(*context_.taskContext, resolved, inst.debugSourceInfo))
                return;

            const FileRef fileRef = resolved.sourceFile ? resolved.sourceFile->ref() : FileRef::invalid();
            Diagnostic    diag    = Diagnostic::get(DiagnosticId::safety_err_null_deref, fileRef);
            diag.last().addSpan(resolved.codeRange, "", DiagnosticSeverity::Error);
            diag.report(*context_.taskContext);
            reported_ = true;
        }

        MicroPassContext&                        context_;
        MicroReg                                 stackBaseReg_;
        bool                                     reported_ = false;
        std::unordered_map<uint32_t, SanityValue> regs_;  // key: MicroReg.packed
        std::unordered_map<int64_t, SanityValue>  stack_; // key: stack slot offset
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
    // Read-only analysis: never mutate the IR.
    context.passChanged = false;

    if (!nullSafetyEnabled(context))
        return Result::Continue;
    if (!context.instructions || !context.operands || !context.taskContext)
        return Result::Continue;

    // On a proven null dereference, abort codegen so the faulty function is never
    // emitted or executed. The reported error fails the build (or is matched by a
    // test's expected-error marker); a function that legitimately produced no code
    // because it errored is skipped by the backend's missing-code validation.
    SanityInterpreter interpreter(context);
    if (interpreter.run())
        return Result::Error;
    return Result::Continue;
}

SWC_END_NAMESPACE();
