#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA instruction combiner on virtual registers.
//
// Architecture
// ------------
// A small pattern-dispatch framework: every combine rule is a self-contained
// function that receives a CombineCtx and an anchor instruction, decides
// whether it applies, and emits typed Actions describing the rewrite. Patterns
// are registered against the opcode(s) they anchor on, so the scan loop does
// one O(1) table lookup per instruction instead of a cascading if/else.
// SSA queries run on the un-mutated IR throughout the scan; actions are
// applied as a batch at the end, after which the pass manager invalidates
// the shared SSA and the next loop iteration rebuilds it.
//
// Patterns (each in its own try* function):
//
//   Identity / absorb / reassociate on OpBinaryRegImm
//     v op 0, v and ~0                              (drop if v's dead)
//     v and 0     -> ClearReg v
//     v or  ~0    -> LoadRegImm v, mask
//     v op c1 ; v op c2  -> v op fold(op, c1, c2)
//
//   Idempotent reg/reg on OpBinaryRegReg
//     v and v, v or v                               (drop if dead)
//     v - v, v ^ v                                  -> ClearReg v
//
//   Memory-op fusion on LoadRegMem (triple: load + op + store)
//     LoadRegMem vt, [b+o]
//     OpBinaryRegImm/OpBinaryRegReg vt, ...
//     LoadMemReg [b+o], vt
//       -> OpBinaryMemImm / OpBinaryMemReg [b+o], ...
//
//   Addressing-mode fold on LoadMemReg / LoadRegMem
//     reg = base ; reg += imm ; [reg] = src
//       -> [base + imm] = src  (and the symmetric load form)
//
//   Dead zero/sign extends on LoadZeroExtRegReg / LoadSignedExtRegReg
//     If every user of the extended value reads <= srcBits, drop the extend
//     (or narrow it to a plain LoadRegReg at srcBits).
//
//   Store-to-load forwarding (whole-IR cache scan, not anchored)
//     LoadMemReg [b+o], src ; ... ; LoadRegMem dst, [b+o]
//       -> LoadRegMem becomes LoadRegReg dst, src

SWC_BEGIN_NAMESPACE();

namespace
{
    //===------------------------------------------------------------------===//
    //  Math / opcode helpers
    //===------------------------------------------------------------------===//

    bool isSameOpBitsInt(MicroOpBits a, MicroOpBits b)
    {
        return a == b && a != MicroOpBits::Zero && a != MicroOpBits::B128;
    }

    bool isRightIdentity(MicroOp op, MicroOpBits opBits, uint64_t imm)
    {
        const uint64_t mask = getBitsMask(opBits);
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

            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                return (imm & mask) == 1;

            case MicroOp::And:
                return (imm & mask) == mask;

            default:
                return false;
        }
    }

    bool isRightAbsorbing(MicroOp op, MicroOpBits opBits, uint64_t imm, uint64_t& outResult)
    {
        const uint64_t mask = getBitsMask(opBits);
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

            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
                if ((imm & mask) == 0)
                {
                    outResult = 0;
                    return true;
                }
                break;

            default:
                break;
        }

        return false;
    }

    bool tryReassociate(MicroOp     firstOp,
                        uint64_t    firstImm,
                        MicroOp     secondOp,
                        uint64_t    secondImm,
                        MicroOpBits opBits,
                        MicroOp&    outOp,
                        uint64_t&   outImm)
    {
        const uint64_t mask = getBitsMask(opBits);

        const auto fold = [&](MicroOp op, uint64_t lhs, uint64_t rhs) -> std::optional<uint64_t> {
            uint64_t   value  = 0;
            const auto status = MicroPassHelpers::foldBinaryImmediate(value, lhs, rhs, op, opBits);
            if (status != Math::FoldStatus::Ok)
                return std::nullopt;
            return value & mask;
        };

        if ((firstOp == MicroOp::Add || firstOp == MicroOp::Subtract) &&
            (secondOp == MicroOp::Add || secondOp == MicroOp::Subtract))
        {
            const uint64_t a           = firstImm & mask;
            const uint64_t b           = secondImm & mask;
            const bool     firstIsSub  = firstOp == MicroOp::Subtract;
            const bool     secondIsSub = secondOp == MicroOp::Subtract;

            uint64_t addImm = 0;
            if (firstIsSub == secondIsSub)
                addImm = firstIsSub ? ((0u - (a + b)) & mask) : ((a + b) & mask);
            else if (firstIsSub)
                addImm = (b - a) & mask;
            else
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

    // Returns the bit-width at which 'useInst' reads 'reg'. Zero means the
    // caller should treat the use as full-width (safe default).
    MicroOpBits useReadBits(const MicroInstr& useInst, const MicroInstrOperand* useOps, MicroReg reg)
    {
        if (!useOps)
            return MicroOpBits::Zero;

        switch (useInst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::CmpRegReg:
                return useOps[2].opBits;

            case MicroInstrOpcode::CmpRegImm:
            case MicroInstrOpcode::OpBinaryRegImm:
                return useOps[1].opBits;

            case MicroInstrOpcode::OpBinaryRegReg:
                return useOps[2].opBits;

            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
                return useOps[1].reg == reg ? useOps[3].opBits : MicroOpBits::Zero;

            default:
                return MicroOpBits::Zero;
        }
    }

    //===------------------------------------------------------------------===//
    //  Action + Context
    //===------------------------------------------------------------------===//

    // A single rewrite command. Patterns emit actions; the apply phase runs
    // them sequentially once the scan completes.
    struct Action
    {
        static constexpr uint8_t K_MAX_OPS = 5;

        MicroInstrRef     ref            = MicroInstrRef::invalid();
        MicroInstrOpcode  newOp          = MicroInstrOpcode::Nop;
        uint8_t           numOps         = 0;
        MicroInstrOperand ops[K_MAX_OPS] = {};
        bool              erase          = false;
        bool              allocOps       = false; // allocate a new operand block (grow beyond existing).
    };

    struct CombineCtx
    {
        MicroStorage&        storage;
        MicroOperandStorage& operands;
        const MicroSsaState* ssa;

        // Any instruction that a prior pattern already scheduled a rewrite for.
        // Patterns must claim every instruction they plan to touch before
        // emitting actions; if any claim fails the pattern aborts.
        std::unordered_set<uint32_t> claimed;

        SmallVector<Action, 16> actions;

        bool isClaimed(MicroInstrRef r) const { return claimed.contains(r.get()); }

        // Try to claim a batch atomically: succeeds only if none of the refs
        // were previously claimed. Returns false without side-effects on failure.
        bool claimAll(std::initializer_list<MicroInstrRef> refs)
        {
            for (const MicroInstrRef r : refs)
                if (isClaimed(r))
                    return false;
            for (const MicroInstrRef r : refs)
                claimed.insert(r.get());
            return true;
        }

        void emitErase(MicroInstrRef r)
        {
            Action a;
            a.ref   = r;
            a.erase = true;
            actions.push_back(a);
        }

        void emitRewrite(MicroInstrRef                      r,
                         MicroInstrOpcode                   newOp,
                         std::span<const MicroInstrOperand> newOps,
                         bool                               allocNewBlock = false)
        {
            SWC_ASSERT(newOps.size() <= Action::K_MAX_OPS);
            Action a;
            a.ref      = r;
            a.newOp    = newOp;
            a.numOps   = static_cast<uint8_t>(newOps.size());
            a.allocOps = allocNewBlock;
            for (size_t i = 0; i < newOps.size(); ++i)
                a.ops[i] = newOps[i];
            actions.push_back(a);
        }
    };

    void applyAction(const Action& a, const CombineCtx& ctx)
    {
        if (a.erase)
        {
            ctx.storage.erase(a.ref);
            return;
        }

        MicroInstr* inst = ctx.storage.ptr(a.ref);
        SWC_ASSERT(inst);

        if (a.allocOps)
        {
            const auto [newRef, opsBlock] = ctx.operands.emplaceUninitArray(a.numOps);
            for (uint8_t i = 0; i < a.numOps; ++i)
                opsBlock[i] = a.ops[i];
            inst->opsRef = newRef;
        }
        else if (a.numOps > 0)
        {
            MicroInstrOperand* existing = inst->ops(ctx.operands);
            SWC_ASSERT(existing);
            for (uint8_t i = 0; i < a.numOps; ++i)
                existing[i] = a.ops[i];
        }

        inst->op          = a.newOp;
        inst->numOperands = a.numOps;
    }

    //===------------------------------------------------------------------===//
    //  Patterns
    //===------------------------------------------------------------------===//

    // OpBinaryRegImm: identity, absorbing, and reassociation chains.
    bool tryOpBinaryRegImm(CombineCtx& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (inst.numOperands < 4 || ctx.isClaimed(ref))
            return false;

        const MicroInstrOperand* ops = inst.ops(ctx.operands);
        if (!ops || !ops[0].reg.isVirtualInt())
            return false;

        const MicroReg    dst    = ops[0].reg;
        const MicroOpBits opBits = ops[1].opBits;
        const MicroOp     op     = ops[2].microOp;
        const uint64_t    imm    = ops[3].valueU64;

        // Identity: erase when result is unused afterward.
        if (isRightIdentity(op, opBits, imm))
        {
            if (ctx.ssa && !ctx.ssa->isRegUsedAfter(dst, ref))
            {
                if (!ctx.claimAll({ref}))
                    return false;
                ctx.emitErase(ref);
                return true;
            }
        }

        // Absorbing element: rewrite to a constant materializer.
        uint64_t absorbed = 0;
        if (isRightAbsorbing(op, opBits, imm, absorbed))
        {
            if (!ctx.claimAll({ref}))
                return false;

            if (absorbed == 0)
            {
                MicroInstrOperand clearOps[2];
                clearOps[0].reg    = dst;
                clearOps[1].opBits = opBits;
                ctx.emitRewrite(ref, MicroInstrOpcode::ClearReg, clearOps);
            }
            else
            {
                MicroInstrOperand loadOps[3];
                loadOps[0].reg      = dst;
                loadOps[1].opBits   = opBits;
                loadOps[2].valueU64 = absorbed;
                ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegImm, loadOps);
            }
            return true;
        }

        // Reassociate with a preceding single-use OpBinaryRegImm on the same reg.
        if (!ctx.ssa)
            return false;

        const auto reaching = ctx.ssa->reachingDef(dst, ref);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst)
            return false;
        if (reaching.inst->op != MicroInstrOpcode::OpBinaryRegImm || reaching.inst->numOperands < 4)
            return false;

        const MicroInstrOperand* prevOps = reaching.inst->ops(ctx.operands);
        if (!prevOps || prevOps[0].reg != dst || !isSameOpBitsInt(prevOps[1].opBits, opBits))
            return false;

        const auto* valueInfo = ctx.ssa->valueInfo(reaching.valueId);
        if (!valueInfo || valueInfo->uses.size() != 1)
            return false;

        MicroOp  combinedOp  = MicroOp::Add;
        uint64_t combinedImm = 0;
        if (!tryReassociate(prevOps[2].microOp, prevOps[3].valueU64, op, imm, opBits, combinedOp, combinedImm))
            return false;

        if (!ctx.claimAll({ref, reaching.instRef}))
            return false;

        MicroInstrOperand rewritten[4];
        rewritten[0].reg      = dst;
        rewritten[1].opBits   = opBits;
        rewritten[2].microOp  = combinedOp;
        rewritten[3].valueU64 = combinedImm;
        ctx.emitRewrite(reaching.instRef, MicroInstrOpcode::OpBinaryRegImm, rewritten);
        ctx.emitErase(ref);
        return true;
    }

    // OpBinaryRegReg: idempotent self-ops.
    bool tryOpBinaryRegReg(CombineCtx& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (inst.numOperands < 4 || ctx.isClaimed(ref))
            return false;

        const MicroInstrOperand* ops = inst.ops(ctx.operands);
        if (!ops || ops[0].reg != ops[1].reg || !ops[0].reg.isVirtualInt())
            return false;

        const MicroReg    dst    = ops[0].reg;
        const MicroOpBits opBits = ops[2].opBits;
        const MicroOp     op     = ops[3].microOp;

        switch (op)
        {
            case MicroOp::And:
            case MicroOp::Or:
                if (ctx.ssa && !ctx.ssa->isRegUsedAfter(dst, ref))
                {
                    if (!ctx.claimAll({ref}))
                        return false;
                    ctx.emitErase(ref);
                    return true;
                }
                return false;

            case MicroOp::Subtract:
            case MicroOp::Xor:
            {
                if (!ctx.claimAll({ref}))
                    return false;
                MicroInstrOperand clearOps[2];
                clearOps[0].reg    = dst;
                clearOps[1].opBits = opBits;
                ctx.emitRewrite(ref, MicroInstrOpcode::ClearReg, clearOps);
                return true;
            }

            default:
                return false;
        }
    }

    // LoadRegMem: memory-fold triple (load + modify + store).
    bool tryMemoryFoldTriple(CombineCtx& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (loadInst.numOperands < 4 || ctx.isClaimed(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(ctx.operands);
        if (!loadOps)
            return false;

        const MicroReg    vt       = loadOps[0].reg;
        const MicroReg    base     = loadOps[1].reg;
        const MicroOpBits loadBits = loadOps[2].opBits;
        const uint64_t    loadOff  = loadOps[3].valueU64;

        if (!vt.isVirtualInt())
            return false;

        constexpr uint32_t K_MAX_WINDOW = 16;

        // Find the anchor position in the view to walk forward from it.
        const auto view  = ctx.storage.view();
        const auto endIt = view.end();
        auto       walker = view.begin();
        for (; walker != endIt && walker.current != loadRef; ++walker)
        {
        }
        if (walker == endIt)
            return false;
        ++walker;

        MicroInstrRef     midRef   = MicroInstrRef::invalid();
        const MicroInstr* midInst  = nullptr;
        bool              foundMid = false;

        for (uint32_t step = 0; step < K_MAX_WINDOW && walker != endIt; ++step, ++walker)
        {
            const MicroInstr& w = *walker;

            // Match the store first — it writes memory itself, which would
            // otherwise trip the generic aborts below.
            if (foundMid && w.op == MicroInstrOpcode::LoadMemReg && w.numOperands >= 4)
            {
                const MicroInstrOperand* sOps = w.ops(ctx.operands);
                if (!sOps || sOps[0].reg != base || sOps[1].reg != vt ||
                    sOps[2].opBits != loadBits || sOps[3].valueU64 != loadOff)
                    return false;

                const MicroInstrOperand* opOps = midInst->ops(ctx.operands);
                if (!opOps || midInst->numOperands < 4)
                    return false;

                const bool middleIsRegImm = midInst->op == MicroInstrOpcode::OpBinaryRegImm;
                const bool middleIsRegReg = midInst->op == MicroInstrOpcode::OpBinaryRegReg;
                if (!middleIsRegImm && !middleIsRegReg)
                    return false;

                const MicroOpBits opBits  = middleIsRegImm ? opOps[1].opBits : opOps[2].opBits;
                const MicroOp     microOp = middleIsRegImm ? opOps[2].microOp : opOps[3].microOp;
                const uint64_t    opImm   = middleIsRegImm ? opOps[3].valueU64 : 0;
                const MicroReg    rhsReg  = middleIsRegReg ? opOps[1].reg : MicroReg::invalid();

                if (opBits != loadBits || !isMemFoldableOp(microOp))
                    return false;
                if (middleIsRegReg && (rhsReg == base || rhsReg == vt))
                    return false;

                uint32_t loadValueId = 0;
                if (!ctx.ssa->defValue(vt, loadRef, loadValueId))
                    return false;
                const auto* loadValue = ctx.ssa->valueInfo(loadValueId);
                if (!loadValue || loadValue->uses.size() != 1)
                    return false;

                uint32_t opValueId = 0;
                if (!ctx.ssa->defValue(vt, midRef, opValueId))
                    return false;
                const auto* opValue = ctx.ssa->valueInfo(opValueId);
                if (!opValue || opValue->uses.size() != 1)
                    return false;

                const MicroInstrRef storeRef = walker.current;
                if (!ctx.claimAll({loadRef, midRef, storeRef}))
                    return false;

                MicroInstrOperand newOps[5];
                if (middleIsRegReg)
                {
                    // OpBinaryMemReg: [memReg, reg, opBits, microOp, memOffset].
                    newOps[0].reg      = base;
                    newOps[1].reg      = rhsReg;
                    newOps[2].opBits   = opBits;
                    newOps[3].microOp  = microOp;
                    newOps[4].valueU64 = loadOff;
                    ctx.emitRewrite(midRef, MicroInstrOpcode::OpBinaryMemReg, newOps, /*allocNewBlock=*/true);
                }
                else
                {
                    // OpBinaryMemImm: [memReg, opBits, microOp, memOffset, imm].
                    newOps[0].reg      = base;
                    newOps[1].opBits   = opBits;
                    newOps[2].microOp  = microOp;
                    newOps[3].valueU64 = loadOff;
                    newOps[4].valueU64 = opImm;
                    ctx.emitRewrite(midRef, MicroInstrOpcode::OpBinaryMemImm, newOps, /*allocNewBlock=*/true);
                }
                ctx.emitErase(loadRef);
                ctx.emitErase(storeRef);
                return true;
            }

            if (isControlOrCall(w) || writesMemory(w))
                return false;

            const auto* useDef   = ctx.ssa->instrUseDef(walker.current);
            const bool  defsVt   = useDef && microRegSpanContains(useDef->defs, vt);
            const bool  defsBase = useDef && microRegSpanContains(useDef->defs, base);
            const bool  usesVt   = useDef && microRegSpanContains(useDef->uses, vt);

            if (defsBase)
                return false;

            if (!foundMid)
            {
                if (usesVt || defsVt)
                {
                    if ((w.op == MicroInstrOpcode::OpBinaryRegImm ||
                         w.op == MicroInstrOpcode::OpBinaryRegReg) &&
                        w.numOperands >= 4)
                    {
                        const MicroInstrOperand* wOps = w.ops(ctx.operands);
                        if (wOps && wOps[0].reg == vt)
                        {
                            midRef   = walker.current;
                            midInst  = &w;
                            foundMid = true;
                            continue;
                        }
                    }
                    return false;
                }
            }
            else
            {
                if (usesVt || defsVt)
                    return false;
            }
        }

        return false;
    }

    // Zero/sign extend whose upper bits are never read. Collapses to a plain
    // LoadRegReg at srcBits, or an erase when dst == src.
    bool tryNarrowExtend(CombineCtx& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (inst.numOperands < 4 || ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(ctx.operands);
        if (!ops)
            return false;

        const MicroReg    dst     = ops[0].reg;
        const MicroReg    src     = ops[1].reg;
        const MicroOpBits dstBits = ops[2].opBits;
        const MicroOpBits srcBits = ops[3].opBits;

        if (!dst.isVirtual() || dstBits == srcBits || srcBits == MicroOpBits::Zero)
            return false;

        uint32_t valueId = 0;
        if (!ctx.ssa->defValue(dst, ref, valueId))
            return false;

        const auto* valueInfo = ctx.ssa->valueInfo(valueId);
        if (!valueInfo || valueInfo->uses.empty())
            return false;

        const uint32_t srcBitsNum = getNumBits(srcBits);
        for (const auto& useSite : valueInfo->uses)
        {
            if (useSite.kind != MicroSsaState::UseSite::Kind::Instruction)
                return false;
            const MicroInstr* useInst = ctx.storage.ptr(useSite.instRef);
            if (!useInst)
                return false;
            const MicroInstrOperand* useOps  = useInst->ops(ctx.operands);
            const MicroOpBits        useBits = useReadBits(*useInst, useOps, dst);
            if (useBits == MicroOpBits::Zero || getNumBits(useBits) > srcBitsNum)
                return false;
        }

        if (!ctx.claimAll({ref}))
            return false;

        if (dst == src)
        {
            ctx.emitErase(ref);
        }
        else
        {
            MicroInstrOperand moveOps[3];
            moveOps[0].reg    = dst;
            moveOps[1].reg    = src;
            moveOps[2].opBits = srcBits;
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, moveOps);
        }
        return true;
    }

    // Fold a constant-offset computation into a memory operand's offset. Anchor
    // on a store (LoadMemReg) or a load (LoadRegMem) and look backward through
    // SSA for:
    //
    //     base' = OpBinaryRegImm(base', ADD/SUB, imm)              (single-use)
    //     [optionally] base' = LoadRegReg origBase                  (single-use)
    //
    // On success: rewrite the memory instruction's base to origBase (or the
    // add's source if the copy isn't present), adjust its offset by ±imm, and
    // erase the intermediate chain.
    bool tryFoldMemoryAddressing(CombineCtx& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (!ctx.ssa || ctx.isClaimed(ref) || inst.numOperands < 4)
            return false;

        uint8_t baseIdx;
        uint8_t offIdx;
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadMemReg:
                baseIdx = 0;
                offIdx  = 3;
                break;
            case MicroInstrOpcode::LoadRegMem:
                baseIdx = 1;
                offIdx  = 3;
                break;
            default:
                return false;
        }

        const MicroInstrOperand* ops = inst.ops(ctx.operands);
        if (!ops)
            return false;

        const MicroReg baseReg = ops[baseIdx].reg;
        const uint64_t baseOff = ops[offIdx].valueU64;
        if (!baseReg.isVirtual())
            return false;

        const auto reaching = ctx.ssa->reachingDef(baseReg, ref);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst)
            return false;
        if (reaching.inst->op != MicroInstrOpcode::OpBinaryRegImm || reaching.inst->numOperands < 4)
            return false;

        const MicroInstrOperand* addOps = reaching.inst->ops(ctx.operands);
        if (!addOps || addOps[0].reg != baseReg)
            return false;

        const MicroOpBits addBits = addOps[1].opBits;
        const MicroOp     addOp   = addOps[2].microOp;
        const uint64_t    addImm  = addOps[3].valueU64;
        if (addBits != MicroOpBits::B64)
            return false;
        if (addOp != MicroOp::Add && addOp != MicroOp::Subtract)
            return false;

        // Intermediate must feed only this memory op.
        const auto* addValue = ctx.ssa->valueInfo(reaching.valueId);
        if (!addValue || addValue->uses.size() != 1)
            return false;

        // Follow one more step backward: if baseReg's own incoming value is a
        // plain single-use LoadRegReg, we can eliminate the copy too and point
        // the memory op directly at the original base register.
        MicroInstrRef copyRef     = MicroInstrRef::invalid();
        MicroReg      originalReg = baseReg;
        {
            const auto copyReaching = ctx.ssa->reachingDef(baseReg, reaching.instRef);
            if (copyReaching.valid() && !copyReaching.isPhi && copyReaching.inst &&
                copyReaching.inst->op == MicroInstrOpcode::LoadRegReg &&
                copyReaching.inst->numOperands >= 3)
            {
                const MicroInstrOperand* cOps = copyReaching.inst->ops(ctx.operands);
                if (cOps && cOps[0].reg == baseReg)
                {
                    const auto* copyValue = ctx.ssa->valueInfo(copyReaching.valueId);
                    if (copyValue && copyValue->uses.size() == 1)
                    {
                        const MicroReg candidate = cOps[1].reg;
                        // Soundness: the copy's source must still hold the same
                        // SSA value at the memory op — otherwise substituting it
                        // in would read a newer value and change semantics.
                        const auto srcAtCopy = ctx.ssa->reachingDef(candidate, copyReaching.instRef);
                        const auto srcAtMem  = ctx.ssa->reachingDef(candidate, ref);
                        if (srcAtCopy.valid() && srcAtMem.valid() &&
                            srcAtCopy.valueId == srcAtMem.valueId)
                        {
                            copyRef     = copyReaching.instRef;
                            originalReg = candidate;
                        }
                    }
                }
            }
        }

        // 64-bit wrapping arithmetic matches native address behavior.
        const uint64_t newOff = (addOp == MicroOp::Add) ? baseOff + addImm : baseOff - addImm;

        if (!ctx.claimAll({ref, reaching.instRef}))
            return false;
        if (copyRef.isValid() && !ctx.claimAll({copyRef}))
            return false;

        MicroInstrOperand newMemOps[4];
        for (uint8_t i = 0; i < 4; ++i)
            newMemOps[i] = ops[i];
        newMemOps[baseIdx].reg     = originalReg;
        newMemOps[offIdx].valueU64 = newOff;
        ctx.emitRewrite(ref, inst.op, newMemOps);

        ctx.emitErase(reaching.instRef);
        if (copyRef.isValid())
            ctx.emitErase(copyRef);
        return true;
    }

    //===------------------------------------------------------------------===//
    //  Whole-IR scans (not per-instruction anchored)
    //===------------------------------------------------------------------===//

    // Store-to-load forwarding. Maintain a small cache of (base, off, bits) ->
    // source reg from recent LoadMemReg stores. When a matching LoadRegMem
    // shows up and its source is still live, rewrite it as LoadRegReg and
    // skip the memory round-trip. Any store we can't prove disjoint, any
    // control transfer, and any redefinition of a cached base/src flushes
    // the relevant entries.
    void runStoreToLoadForwarding(CombineCtx& ctx)
    {
        if (!ctx.ssa)
            return;

        struct CacheEntry
        {
            MicroReg    base;
            MicroReg    src;
            MicroOpBits bits = MicroOpBits::Zero;
            uint64_t    off  = 0;
        };
        SmallVector<CacheEntry, 8> cache;

        const auto dropUsing = [&](MicroReg reg) {
            for (uint32_t i = 0; i < cache.size();)
            {
                if (cache[i].base == reg || cache[i].src == reg)
                    cache.erase(cache.begin() + i);
                else
                    ++i;
            }
        };

        const auto view  = ctx.storage.view();
        const auto endIt = view.end();
        for (auto it = view.begin(); it != endIt; ++it)
        {
            MicroInstr&              inst = *it;
            const MicroInstrOperand* ops  = inst.ops(ctx.operands);

            if (inst.op == MicroInstrOpcode::LoadRegMem && inst.numOperands >= 4 && ops && !ctx.isClaimed(it.current))
            {
                const MicroReg    dst  = ops[0].reg;
                const MicroReg    base = ops[1].reg;
                const MicroOpBits bits = ops[2].opBits;
                const uint64_t    off  = ops[3].valueU64;

                for (const CacheEntry& e : cache)
                {
                    if (e.base == base && e.off == off && e.bits == bits && e.src.isValid() && e.src != dst)
                    {
                        if (!ctx.claimAll({it.current}))
                            break;

                        MicroInstrOperand moveOps[3];
                        moveOps[0].reg    = dst;
                        moveOps[1].reg    = e.src;
                        moveOps[2].opBits = bits;
                        ctx.emitRewrite(it.current, MicroInstrOpcode::LoadRegReg, moveOps);
                        break;
                    }
                }
                continue;
            }

            if (inst.op == MicroInstrOpcode::LoadMemReg && inst.numOperands >= 4 && ops)
            {
                // Any previous entry might alias this slot (no alias info), so
                // flush regardless.
                cache.clear();
                // A claimed store will be erased by another pattern (e.g.
                // memory-fold), and its source register's defining instructions
                // are typically erased with it. Caching the source here would
                // let a later load forward to a register with no live def.
                if (ctx.isClaimed(it.current))
                    continue;
                const MicroReg    base = ops[0].reg;
                const MicroReg    src  = ops[1].reg;
                const MicroOpBits bits = ops[2].opBits;
                const uint64_t    off  = ops[3].valueU64;
                cache.push_back({base, src, bits, off});
                continue;
            }

            if (isControlOrCall(inst) || writesMemory(inst))
            {
                cache.clear();
                continue;
            }

            const auto* useDef = ctx.ssa->instrUseDef(it.current);
            if (useDef)
            {
                for (const MicroReg def : useDef->defs)
                    dropUsing(def);
            }
        }
    }

    //===------------------------------------------------------------------===//
    //  Dispatch
    //===------------------------------------------------------------------===//

    using PatternFn = bool (*)(CombineCtx&, MicroInstrRef, const MicroInstr&);

    struct PatternRegistry
    {
        static constexpr size_t K_OPCODE_COUNT = MICRO_INSTR_OPCODE_INFOS.size();

        std::array<SmallVector<PatternFn, 2>, K_OPCODE_COUNT> byOpcode;

        void reg(MicroInstrOpcode op, PatternFn fn)
        {
            byOpcode[static_cast<size_t>(op)].push_back(fn);
        }

        std::span<PatternFn const> patternsFor(MicroInstrOpcode op) const
        {
            return byOpcode[static_cast<size_t>(op)].span();
        }
    };

    const PatternRegistry& registry()
    {
        static const PatternRegistry r = [] {
            PatternRegistry out;
            out.reg(MicroInstrOpcode::OpBinaryRegImm,      tryOpBinaryRegImm);
            out.reg(MicroInstrOpcode::OpBinaryRegReg,      tryOpBinaryRegReg);
            out.reg(MicroInstrOpcode::LoadRegMem,          tryMemoryFoldTriple);
            out.reg(MicroInstrOpcode::LoadRegMem,          tryFoldMemoryAddressing);
            out.reg(MicroInstrOpcode::LoadMemReg,          tryFoldMemoryAddressing);
            out.reg(MicroInstrOpcode::LoadZeroExtRegReg,   tryNarrowExtend);
            out.reg(MicroInstrOpcode::LoadSignedExtRegReg, tryNarrowExtend);
            return out;
        }();
        return r;
    }
}

Result MicroInstructionCombinePass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/InstCombine");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    MicroSsaState        localSsa;
    const MicroSsaState* ssa = MicroSsaState::ensureFor(context, localSsa);

    CombineCtx ctx{*context.instructions, *context.operands, ssa, {}, {}};

    // Per-instruction dispatch: one table lookup, then each registered pattern
    // for that opcode gets a shot. Patterns either claim the anchor and emit
    // actions, or return false and yield to the next pattern.
    const auto& reg   = registry();
    const auto  view  = ctx.storage.view();
    const auto  endIt = view.end();
    for (auto it = view.begin(); it != endIt; ++it)
    {
        for (const PatternFn fn : reg.patternsFor(it->op))
        {
            if (fn(ctx, it.current, *it))
                break;
        }
    }

    // Whole-IR scans: maintain per-position state (a small cache) and don't
    // fit the anchor-per-instruction model. They emit into the same action
    // queue, so claim tracking works uniformly.
    runStoreToLoadForwarding(ctx);

    if (ctx.actions.empty())
        return Result::Continue;

    for (const Action& a : ctx.actions)
        applyAction(a, ctx);

    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
