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
        };

        Kind          kind = Kind::EraseCurrent;
        MicroInstrRef current  = MicroInstrRef::invalid();
        MicroInstrRef previous = MicroInstrRef::invalid();
        MicroOp       newOp    = MicroOp::Add;
        uint64_t      newImm   = 0;
        MicroOpBits   opBits   = MicroOpBits::B64;
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

    const auto view  = storage.view();
    const auto endIt = view.end();
    for (auto it = view.begin(); it != endIt; ++it)
    {
        const MicroInstrRef instRef = it.current;
        const MicroInstr&   inst    = *it;
        const auto*         ops     = inst.ops(operands);

        CombinePlan plan;
        bool        planned = false;

        if (inst.op == MicroInstrOpcode::OpBinaryRegImm)
            planned = tryPlanRegImm(plan, ssaState, storage, operands, instRef, inst, ops);
        else if (inst.op == MicroInstrOpcode::OpBinaryRegReg)
            planned = tryPlanRegReg(plan, instRef, inst, ops, ssaState);

        if (!planned)
            continue;

        if (plan.kind == CombinePlan::Kind::ReassociateChain)
        {
            const uint32_t prevSlot = plan.previous.get();
            if (!claimedSources.insert(prevSlot).second)
                continue;
        }

        plans.push_back(plan);
    }

    if (plans.empty())
        return Result::Continue;

    for (const CombinePlan& plan : plans)
        applyPlan(storage, operands, plan);

    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
