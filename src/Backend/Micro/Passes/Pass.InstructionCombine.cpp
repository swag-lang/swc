#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA instruction combiner on virtual registers.
//
// Tier-1 patterns (run inside the optimization fixed-point loop, so multi-step
// chains converge across iterations):
//
//   Identity removal (current value preserved, kill the op):
//     v op 0     for op in {Add, Sub, Or, Xor, Shl, Shr, Sar, Rol, Ror}
//     v and ~0   (mask for current opBits)
//
//   Absorbing element:
//     v and 0    -> ClearReg v
//     v or  ~0   -> LoadRegImm v, ~0
//
//   Same-op constant reassociation across a single-use SSA chain:
//     v op c1 ; v op c2  -> v op fold(op, c1, c2)
//   for op in {Add(+Sub), Sub(+Add), Mul, And, Or, Xor, Shl, Shr, Sar}.
//
//   Idempotent reg-reg patterns:
//     v op v   for op in {And, Or}                 -> remove (v unchanged)
//     v op v   for op in {Sub, Xor}                -> ClearReg v
//
// Tier-2 memory-op fusion (load/modify/store collapse):
//
//     LoadRegMem  vt, [base + off]
//     OpBinaryRegImm vt, op, imm
//     LoadMemReg  [base + off], vt
//   ->
//     OpBinaryMemImm [base + off], op, imm
//
// Requires the three instructions to be consecutive (no aliasing window),
// matching base reg / offset / opBits, and 'vt' to be single-use across both
// SSA value-IDs (the load's def used only by the op, the op's def used only by
// the store). The middle instruction is rewritten in place — that needs a new
// operand block since OpBinaryMemImm has 5 operands vs. OpBinaryRegImm's 4 —
// and the bracketing load/store are erased. Net win: 2 instructions removed
// plus 1 fewer virtual register live range, which is the dominant lever for
// reducing 'count.micro.raDelta'.
//
// SSA staleness: the pass collects rewrite plans during a forward scan over
// the live IR, then applies them. Each plan touches at most two instructions
// (current + one reaching def), and we never queue a rewrite whose source has
// already been claimed by another plan. After mutation the pass manager
// invalidates the SSA state and the next loop iteration rebuilds it.

SWC_BEGIN_NAMESPACE();

namespace
{
    // Mask of the low 'opBits' bits, sign-extended to 64 (so we can compare
    // immediates against -1 regardless of the operand width).
    uint64_t allOnesMask(MicroOpBits opBits)
    {
        return getBitsMask(opBits);
    }

    bool isSameOpBitsInt(MicroOpBits a, MicroOpBits b)
    {
        return a == b && a != MicroOpBits::Zero && a != MicroOpBits::B128;
    }

    // True if 'imm' is the additive / bitwise zero for 'op' applied as 'v op imm'.
    bool isRightIdentity(MicroOp op, MicroOpBits opBits, uint64_t imm)
    {
        const uint64_t mask = allOnesMask(opBits);
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::Subtract:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
            case MicroOp::ShiftArithmeticLeft:
            case MicroOp::RotateLeft:
            case MicroOp::RotateRight:
                return (imm & mask) == 0;

            case MicroOp::And:
                return (imm & mask) == mask;

            default:
                return false;
        }
    }

    // True if 'v op imm' is constant regardless of v.
    bool isRightAbsorbing(MicroOp op, MicroOpBits opBits, uint64_t imm, uint64_t& outResult)
    {
        const uint64_t mask = allOnesMask(opBits);
        switch (op)
        {
            case MicroOp::And:
                if ((imm & mask) == 0)
                {
                    outResult = 0;
                    return true;
                }
                break;

            case MicroOp::Or:
                if ((imm & mask) == mask)
                {
                    outResult = mask;
                    return true;
                }
                break;

            default:
                break;
        }

        return false;
    }

    // Returns true when 'first' followed by 'second' on the same destination can
    // be reassociated into a single op. 'outOp' is the resulting op kind, and
    // 'outImm' is the combined immediate. A few patterns mix Add/Sub.
    bool tryReassociate(MicroOp     firstOp,
                        uint64_t    firstImm,
                        MicroOp     secondOp,
                        uint64_t    secondImm,
                        MicroOpBits opBits,
                        MicroOp&    outOp,
                        uint64_t&   outImm)
    {
        const uint64_t mask = allOnesMask(opBits);

        const auto fold = [&](MicroOp op, uint64_t lhs, uint64_t rhs) -> std::optional<uint64_t> {
            uint64_t   value  = 0;
            const auto status = MicroPassHelpers::foldBinaryImmediate(value, lhs, rhs, op, opBits);
            if (status != Math::FoldStatus::Ok)
                return std::nullopt;
            return value & mask;
        };

        // Add/Sub family. Compute the net signed contribution then pick the
        // shorter encoding (Add or Sub of the smaller magnitude under 'mask').
        if ((firstOp == MicroOp::Add || firstOp == MicroOp::Subtract) &&
            (secondOp == MicroOp::Add || secondOp == MicroOp::Subtract))
        {
            const uint64_t a           = firstImm & mask;
            const uint64_t b           = secondImm & mask;
            const bool     firstIsSub  = firstOp == MicroOp::Subtract;
            const bool     secondIsSub = secondOp == MicroOp::Subtract;

            uint64_t addImm = 0;  // immediate when encoded as Add.
            if (firstIsSub == secondIsSub)
                addImm = firstIsSub ? ((0u - (a + b)) & mask) : ((a + b) & mask);
            else if (firstIsSub)  // -a + b == b - a
                addImm = (b - a) & mask;
            else                  // +a - b == a - b
                addImm = (a - b) & mask;

            const uint64_t subImm = (0u - addImm) & mask;
            if (addImm <= subImm)
            {
                outOp  = MicroOp::Add;
                outImm = addImm;
            }
            else
            {
                outOp  = MicroOp::Subtract;
                outImm = subImm;
            }
            return true;
        }

        // Bitwise / multiply families: same-op only.
        if (firstOp != secondOp)
            return false;

        switch (firstOp)
        {
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
            {
                const auto v = fold(firstOp, firstImm, secondImm);
                if (!v)
                    return false;
                outOp  = firstOp;
                outImm = *v;
                return true;
            }

            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
            {
                const uint64_t sum = firstImm + secondImm;
                if (sum >= getNumBits(opBits))
                    return false;
                outOp  = firstOp;
                outImm = sum;
                return true;
            }

            default:
                return false;
        }
    }

    struct CombinePlan
    {
        enum class Kind : uint8_t
        {
            EraseCurrent,             // remove 'current' (identity op).
            RewriteCurrentToClear,    // 'current' becomes ClearReg.
            RewriteCurrentToLoadImm,  // 'current' becomes LoadRegImm with 'newImm'.
            ReassociateChain,         // erase 'current', rewrite 'previous' op+imm.
            MemoryFold,               // erase 'previous' (load) + 'current' (store),
                                      // rewrite 'middle' to OpBinaryMemImm.
        };

        Kind          kind     = Kind::EraseCurrent;
        MicroInstrRef current  = MicroInstrRef::invalid();
        MicroInstrRef previous = MicroInstrRef::invalid();
        MicroInstrRef middle   = MicroInstrRef::invalid();
        MicroOp       newOp    = MicroOp::Add;
        uint64_t      newImm   = 0;
        uint64_t      memOff   = 0;
        MicroReg      memBase  = MicroReg::invalid();
        MicroReg      rhsReg   = MicroReg::invalid();
        MicroOpBits   opBits   = MicroOpBits::B64;
        bool          midIsRegReg = false;
    };

    // Look up the SSA reaching-def of 'reg' just before 'instRef' and decide
    // whether it is a single-use, same-shape OpBinaryRegImm we can reassociate.
    bool tryPlanReassociate(CombinePlan&         plan,
                            const MicroSsaState& ssa,
                            const MicroStorage&  storage,
                            const MicroOperandStorage& operands,
                            MicroInstrRef        currentRef,
                            const MicroInstrOperand* curOps)
    {
        const MicroReg dst    = curOps[0].reg;
        const MicroOp  curOp  = curOps[2].microOp;
        const auto     opBits = curOps[1].opBits;
        const uint64_t curImm = curOps[3].valueU64;

        const auto reaching = ssa.reachingDef(dst, currentRef);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst)
            return false;
        if (reaching.inst->op != MicroInstrOpcode::OpBinaryRegImm)
            return false;

        const auto* prevOps = reaching.inst->ops(operands);
        if (!prevOps || reaching.inst->numOperands < 4)
            return false;
        if (prevOps[0].reg != dst)
            return false;
        if (!isSameOpBitsInt(prevOps[1].opBits, opBits))
            return false;

        // Single-use: only the current instruction reads the previous def.
        const auto* valueInfo = ssa.valueInfo(reaching.valueId);
        if (!valueInfo || valueInfo->uses.size() != 1)
            return false;

        MicroOp  combinedOp  = MicroOp::Add;
        uint64_t combinedImm = 0;
        if (!tryReassociate(prevOps[2].microOp, prevOps[3].valueU64, curOp, curImm, opBits, combinedOp, combinedImm))
            return false;

        plan.kind     = CombinePlan::Kind::ReassociateChain;
        plan.current  = currentRef;
        plan.previous = reaching.instRef;
        plan.newOp    = combinedOp;
        plan.newImm   = combinedImm;
        plan.opBits   = opBits;
        SWC_UNUSED(storage);
        return true;
    }

    bool tryPlanRegImm(CombinePlan&             plan,
                       const MicroSsaState*     ssa,
                       const MicroStorage&      storage,
                       const MicroOperandStorage& operands,
                       MicroInstrRef            instRef,
                       const MicroInstr&        inst,
                       const MicroInstrOperand* ops)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegImm || inst.numOperands < 4 || !ops)
            return false;
        if (!ops[0].reg.isVirtualInt())
            return false;

        const MicroOp     op     = ops[2].microOp;
        const MicroOpBits opBits = ops[1].opBits;
        const uint64_t    imm    = ops[3].valueU64;

        // Identity: erase iff the register isn't observed afterwards. (Mirrors
        // StrengthReduction's add-zero handling — cheaper than asserting flag
        // liveness, which the post-RA peephole revisits anyway.)
        if (isRightIdentity(op, opBits, imm))
        {
            if (ssa && !ssa->isRegUsedAfter(ops[0].reg, instRef))
            {
                plan.kind    = CombinePlan::Kind::EraseCurrent;
                plan.current = instRef;
                return true;
            }
        }

        // Absorbing element: rewrite to a constant materialization.
        uint64_t absorbed = 0;
        if (isRightAbsorbing(op, opBits, imm, absorbed))
        {
            if (absorbed == 0)
            {
                plan.kind    = CombinePlan::Kind::RewriteCurrentToClear;
                plan.current = instRef;
                plan.opBits  = opBits;
            }
            else
            {
                plan.kind    = CombinePlan::Kind::RewriteCurrentToLoadImm;
                plan.current = instRef;
                plan.newImm  = absorbed;
                plan.opBits  = opBits;
            }
            return true;
        }

        if (ssa && tryPlanReassociate(plan, *ssa, storage, operands, instRef, ops))
            return true;

        return false;
    }

    bool tryPlanRegReg(CombinePlan&             plan,
                       MicroInstrRef            instRef,
                       const MicroInstr&        inst,
                       const MicroInstrOperand* ops,
                       const MicroSsaState*     ssa)
    {
        if (inst.op != MicroInstrOpcode::OpBinaryRegReg || inst.numOperands < 4 || !ops)
            return false;
        if (ops[0].reg != ops[1].reg)
            return false;
        if (!ops[0].reg.isVirtualInt())
            return false;

        const MicroOp op     = ops[3].microOp;
        const auto    opBits = ops[2].opBits;
        switch (op)
        {
            case MicroOp::And:
            case MicroOp::Or:
                // v op v == v: erase if dead, otherwise leave (rewriting to a
                // self-copy gains nothing pre-RA).
                if (ssa && !ssa->isRegUsedAfter(ops[0].reg, instRef))
                {
                    plan.kind    = CombinePlan::Kind::EraseCurrent;
                    plan.current = instRef;
                    return true;
                }
                return false;

            case MicroOp::Subtract:
            case MicroOp::Xor:
                plan.kind    = CombinePlan::Kind::RewriteCurrentToClear;
                plan.current = instRef;
                plan.opBits  = opBits;
                return true;

            default:
                return false;
        }
    }

    // op kind allowed inside a memory-fold (must have an OpBinaryMemImm form
    // with the same arithmetic).
    bool isMemFoldableOp(MicroOp op)
    {
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::Subtract:
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
                return true;
            default:
                return false;
        }
    }

    bool isControlOrCall(const MicroInstr& inst)
    {
        const auto& info = MicroInstr::info(inst.op);
        return info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
               info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
               info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
               inst.op == MicroInstrOpcode::Label;
    }

    bool writesMemory(const MicroInstr& inst)
    {
        return MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::WritesMemory);
    }

    // Returns true and fills 'plan' when a load/modify/store triple bracketing
    // 'vt' can be collapsed to OpBinaryMemImm (middle = OpBinaryRegImm) or
    // OpBinaryMemReg (middle = OpBinaryRegReg). The triple need not be strictly
    // consecutive — intervening instructions are allowed as long as they do
    // not write memory (potential alias of [base+off]), do not redefine 'vt' or
    // 'base', and (between op and store) do not use 'vt'.
    bool tryPlanMemoryFold(CombinePlan&         plan,
                           const MicroSsaState* ssa,
                           const MicroOperandStorage& operands,
                           MicroInstrRef        loadRef,
                           const MicroInstr&    loadInst,
                           MicroInstrRef        opRef,
                           const MicroInstr&    opInst,
                           MicroInstrRef        storeRef,
                           const MicroInstr&    storeInst)
    {
        if (!ssa)
            return false;
        if (loadInst.op != MicroInstrOpcode::LoadRegMem || storeInst.op != MicroInstrOpcode::LoadMemReg)
            return false;

        const bool middleIsRegImm = opInst.op == MicroInstrOpcode::OpBinaryRegImm;
        const bool middleIsRegReg = opInst.op == MicroInstrOpcode::OpBinaryRegReg;
        if (!middleIsRegImm && !middleIsRegReg)
            return false;
        if (loadInst.numOperands < 4 || opInst.numOperands < 4 || storeInst.numOperands < 4)
            return false;

        const auto* loadOps  = loadInst.ops(operands);
        const auto* opOps    = opInst.ops(operands);
        const auto* storeOps = storeInst.ops(operands);
        if (!loadOps || !opOps || !storeOps)
            return false;

        // Layout reminders:
        //   LoadRegMem    : [dst, base, opBits, off]
        //   OpBinaryRegImm: [reg, opBits, microOp, imm]
        //   OpBinaryRegReg: [dst, src, opBits, microOp]
        //   LoadMemReg    : [base, src, opBits, off]
        const MicroReg    vt        = loadOps[0].reg;
        const MicroReg    loadBase  = loadOps[1].reg;
        const MicroOpBits loadBits  = loadOps[2].opBits;
        const uint64_t    loadOff   = loadOps[3].valueU64;

        const MicroReg    opReg     = opOps[0].reg;
        const MicroOpBits opBits    = middleIsRegImm ? opOps[1].opBits : opOps[2].opBits;
        const MicroOp     microOp   = middleIsRegImm ? opOps[2].microOp : opOps[3].microOp;
        const uint64_t    opImm     = middleIsRegImm ? opOps[3].valueU64 : 0;
        const MicroReg    rhsReg    = middleIsRegReg ? opOps[1].reg : MicroReg::invalid();

        const MicroReg    storeBase = storeOps[0].reg;
        const MicroReg    storeSrc  = storeOps[1].reg;
        const MicroOpBits storeBits = storeOps[2].opBits;
        const uint64_t    storeOff  = storeOps[3].valueU64;

        if (vt != opReg || vt != storeSrc)
            return false;
        if (!vt.isVirtualInt())
            return false;
        if (loadBase != storeBase)
            return false;
        if (loadOff != storeOff)
            return false;
        if (loadBits != opBits || opBits != storeBits)
            return false;
        if (!isMemFoldableOp(microOp))
            return false;
        // For the reg/reg form, the rhs must not alias the destination address
        // base — same reg would change semantics under destructive in-place ops.
        if (middleIsRegReg && (rhsReg == loadBase || rhsReg == vt))
            return false;

        // SSA single-use checks: the load's def feeds only the op; the op's
        // def feeds only the store. Anything else means another reader exists
        // and we cannot drop the bracketing load/store.
        uint32_t loadValueId = 0;
        if (!ssa->defValue(vt, loadRef, loadValueId))
            return false;
        const auto* loadValue = ssa->valueInfo(loadValueId);
        if (!loadValue || loadValue->uses.size() != 1)
            return false;

        uint32_t opValueId = 0;
        if (!ssa->defValue(vt, opRef, opValueId))
            return false;
        const auto* opValue = ssa->valueInfo(opValueId);
        if (!opValue || opValue->uses.size() != 1)
            return false;

        plan.kind     = CombinePlan::Kind::MemoryFold;
        plan.previous = loadRef;
        plan.middle   = opRef;
        plan.current  = storeRef;
        plan.newOp    = microOp;
        plan.newImm   = opImm;
        plan.memOff   = loadOff;
        plan.memBase  = loadBase;
        plan.opBits   = opBits;
        // Encode rhs reg into 'newOp' parameter via piggybacking is ugly;
        // instead reuse memBase carrier and discriminate at apply time on the
        // middle instruction's original opcode. Keep the rhs in a separate
        // field in the plan.
        plan.midIsRegReg = middleIsRegReg;
        plan.rhsReg      = rhsReg;
        return true;
    }

    void applyPlan(MicroStorage& storage, MicroOperandStorage& operands, const CombinePlan& plan)
    {
        switch (plan.kind)
        {
            case CombinePlan::Kind::EraseCurrent:
                storage.erase(plan.current);
                return;

            case CombinePlan::Kind::RewriteCurrentToClear:
            {
                MicroInstr* inst = storage.ptr(plan.current);
                SWC_ASSERT(inst);
                MicroInstrOperand* ops = inst->ops(operands);
                SWC_ASSERT(ops && inst->numOperands >= 1);
                // ClearReg layout: [reg, opBits].
                if (inst->numOperands < 2)
                    return;
                inst->op         = MicroInstrOpcode::ClearReg;
                ops[1].opBits    = plan.opBits;
                inst->numOperands = 2;
                return;
            }

            case CombinePlan::Kind::RewriteCurrentToLoadImm:
            {
                MicroInstr* inst = storage.ptr(plan.current);
                SWC_ASSERT(inst);
                MicroInstrOperand* ops = inst->ops(operands);
                SWC_ASSERT(ops && inst->numOperands >= 3);
                // LoadRegImm layout: [reg, opBits, imm].
                inst->op          = MicroInstrOpcode::LoadRegImm;
                ops[1].opBits     = plan.opBits;
                ops[2].valueU64   = plan.newImm;
                inst->numOperands = 3;
                return;
            }

            case CombinePlan::Kind::ReassociateChain:
            {
                MicroInstr* prev = storage.ptr(plan.previous);
                SWC_ASSERT(prev && prev->op == MicroInstrOpcode::OpBinaryRegImm);
                MicroInstrOperand* prevOps = prev->ops(operands);
                SWC_ASSERT(prevOps && prev->numOperands >= 4);
                prevOps[2].microOp  = plan.newOp;
                prevOps[3].valueU64 = plan.newImm;
                storage.erase(plan.current);
                return;
            }

            case CombinePlan::Kind::MemoryFold:
            {
                // Rewrite the middle in place with a fresh operand block
                // (OpBinaryMemImm/MemReg both need 5 ops, more than the
                // original 4-op middle had allocated).
                MicroInstr* mid = storage.ptr(plan.middle);
                SWC_ASSERT(mid);

                const auto [newRef, newOps] = operands.emplaceUninitArray(5);
                if (plan.midIsRegReg)
                {
                    // OpBinaryMemReg layout: [memReg, reg, opBits, microOp, memOffset].
                    newOps[0].reg      = plan.memBase;
                    newOps[1].reg      = plan.rhsReg;
                    newOps[2].opBits   = plan.opBits;
                    newOps[3].microOp  = plan.newOp;
                    newOps[4].valueU64 = plan.memOff;
                    mid->op            = MicroInstrOpcode::OpBinaryMemReg;
                }
                else
                {
                    // OpBinaryMemImm layout: [memReg, opBits, microOp, memOffset, imm].
                    newOps[0].reg      = plan.memBase;
                    newOps[1].opBits   = plan.opBits;
                    newOps[2].microOp  = plan.newOp;
                    newOps[3].valueU64 = plan.memOff;
                    newOps[4].valueU64 = plan.newImm;
                    mid->op            = MicroInstrOpcode::OpBinaryMemImm;
                }
                mid->opsRef      = newRef;
                mid->numOperands = 5;

                storage.erase(plan.previous);
                storage.erase(plan.current);
                return;
            }
        }
    }
}

Result MicroInstructionCombinePass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/InstCombine");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;
    MicroSsaState        localSsaState;
    const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);

    // Collect plans during a single forward scan over the live IR. SSA queries
    // run against the un-mutated state; plans are applied afterwards. We claim
    // each "previous" instruction at most once so chains with multiple folds
    // converge across loop iterations rather than fighting within one.
    SmallVector<CombinePlan, 16> plans;
    std::unordered_set<uint32_t> claimedSources;
    std::unordered_set<uint32_t> claimedInstrs;  // any instruction already in a plan.

    const auto view  = storage.view();
    const auto endIt = view.end();

    // Maximum number of instructions we'll search forward from a LoadRegMem
    // anchor. Bounded to keep the pass linear in IR size while still catching
    // the codegen patterns where the rhs materialization sits between the
    // load and the op.
    constexpr uint32_t K_MAX_FOLD_WINDOW = 16;

    for (auto it = view.begin(); it != endIt; ++it)
    {
        const MicroInstrRef instRef = it.current;
        const MicroInstr&   inst    = *it;
        const auto*         ops     = inst.ops(operands);

        CombinePlan plan;
        bool        planned = false;

        // Memory-fold scan: anchored on each LoadRegMem.
        if (inst.op == MicroInstrOpcode::LoadRegMem && inst.numOperands >= 4 && ops)
        {
            const MicroReg     vt       = ops[0].reg;
            const MicroReg     base     = ops[1].reg;
            const MicroOpBits  loadBits = ops[2].opBits;
            const uint64_t     loadOff  = ops[3].valueU64;

            if (vt.isVirtualInt() && claimedInstrs.find(instRef.get()) == claimedInstrs.end())
            {
                MicroInstrRef     midRef    = MicroInstrRef::invalid();
                const MicroInstr* midInst   = nullptr;
                bool              foundMid  = false;
                bool              aborted   = false;

                auto walker = it;
                ++walker;
                for (uint32_t step = 0; step < K_MAX_FOLD_WINDOW && walker != endIt && !aborted; ++step, ++walker)
                {
                    const MicroInstr& w = *walker;

                    // Match the store FIRST (it writes memory itself, so the
                    // generic writesMemory abort would otherwise reject it).
                    if (foundMid && w.op == MicroInstrOpcode::LoadMemReg && w.numOperands >= 4)
                    {
                        const auto* sOps = w.ops(operands);
                        if (sOps && sOps[0].reg == base && sOps[1].reg == vt &&
                            sOps[2].opBits == loadBits && sOps[3].valueU64 == loadOff)
                        {
                            if (tryPlanMemoryFold(plan, ssaState, operands,
                                                  instRef, inst,
                                                  midRef, *midInst,
                                                  walker.current, w))
                            {
                                const uint32_t a = instRef.get();
                                const uint32_t b = midRef.get();
                                const uint32_t c = walker.current.get();
                                if (claimedInstrs.find(a) == claimedInstrs.end() &&
                                    claimedInstrs.find(b) == claimedInstrs.end() &&
                                    claimedInstrs.find(c) == claimedInstrs.end())
                                {
                                    claimedInstrs.insert(a);
                                    claimedInstrs.insert(b);
                                    claimedInstrs.insert(c);
                                    plans.push_back(plan);
                                    planned = true;
                                }
                            }
                            break;
                        }
                        // A write to a different address aborts (potential alias).
                        aborted = true;
                        break;
                    }

                    if (isControlOrCall(w) || writesMemory(w))
                    {
                        aborted = true;
                        break;
                    }

                    const auto* useDef = ssaState ? ssaState->instrUseDef(walker.current) : nullptr;
                    const bool  defsVt   = useDef && microRegSpanContains(useDef->defs, vt);
                    const bool  defsBase = useDef && microRegSpanContains(useDef->defs, base);
                    const bool  usesVt   = useDef && microRegSpanContains(useDef->uses, vt);

                    if (defsBase)
                    {
                        aborted = true;
                        break;
                    }

                    if (!foundMid)
                    {
                        if (usesVt || defsVt)
                        {
                            // Must be exactly the candidate middle.
                            if ((w.op == MicroInstrOpcode::OpBinaryRegImm ||
                                 w.op == MicroInstrOpcode::OpBinaryRegReg) &&
                                w.numOperands >= 4)
                            {
                                const auto* wOps = w.ops(operands);
                                if (wOps && wOps[0].reg == vt)
                                {
                                    midRef   = walker.current;
                                    midInst  = &w;
                                    foundMid = true;
                                    continue;
                                }
                            }
                            aborted = true;
                            break;
                        }
                    }
                    else
                    {
                        // After the middle we must not see another use of vt
                        // (that would bind vt's post-op value, blocking the
                        // collapse) until we hit the matching store.
                        if (usesVt || defsVt)
                        {
                            aborted = true;
                            break;
                        }
                    }
                }
                SWC_UNUSED(foundMid);
            }
        }

        if (!planned)
        {
            if (inst.op == MicroInstrOpcode::OpBinaryRegImm)
                planned = tryPlanRegImm(plan, ssaState, storage, operands, instRef, inst, ops);
            else if (inst.op == MicroInstrOpcode::OpBinaryRegReg)
                planned = tryPlanRegReg(plan, instRef, inst, ops, ssaState);

            if (planned)
            {
                if (plan.kind == CombinePlan::Kind::ReassociateChain)
                {
                    const uint32_t prevSlot = plan.previous.get();
                    if (!claimedSources.insert(prevSlot).second ||
                        claimedInstrs.find(prevSlot) != claimedInstrs.end() ||
                        claimedInstrs.find(plan.current.get()) != claimedInstrs.end())
                    {
                        planned = false;
                    }
                }

                if (planned)
                {
                    claimedInstrs.insert(plan.current.get());
                    if (plan.previous.isValid())
                        claimedInstrs.insert(plan.previous.get());
                    plans.push_back(plan);
                }
            }
        }
    }

    if (plans.empty())
        return Result::Continue;

    for (const CombinePlan& plan : plans)
        applyPlan(storage, operands, plan);

    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
