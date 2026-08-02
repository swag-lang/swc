#include "pch.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// An ordered float `<` or `<=` costs six instructions where the hardware needs
// one, and the fix is to compare the other way round.
//
// `ucomisd` reports "unordered" as below-or-equal (CF = ZF = PF = 1), so `setb`
// alone would answer true for a NaN. The front end therefore guards it with the
// parity flag:
//
//     cmp   a, b               cmp   b, a
//     setb  X                  seta  X
//     zext  X            ->    zext  X
//     setnp Y                  (Y's chain left for DCE)
//     zext  Y
//     and   X, Y
//
// Comparing `b` against `a` and asking `above` instead needs no guard: `seta`
// wants CF = 0 and ZF = 0, and the unordered result sets both, so a NaN answers
// false on its own. Parity is symmetric in the operands, so a surviving reader
// of `Y` keeps seeing the flag it asked for.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        // The ordered counterpart reached by swapping the compare operands.
        bool swappedOrderedCond(const MicroCond cond, MicroCond& outSwapped)
        {
            switch (cond)
            {
                case MicroCond::Below: outSwapped = MicroCond::Above; return true;
                case MicroCond::BelowOrEqual: outSwapped = MicroCond::AboveOrEqual; return true;
                default: return false;
            }
        }

        // Walk back to the next instruction that takes part in the idiom, over
        // instructions that leave the flags and both boolean registers alone.
        // Every step of the chain is matched explicitly afterwards, so anything
        // that touches either is returned rather than skipped, and a surprise is
        // a mismatch. Control-flow boundaries end the search.
        const MicroInstr* previousChainStep(const MicroStorage& storage, const MicroOperandStorage& operands, MicroInstrRef fromRef, MicroReg valueReg, MicroReg guardReg, MicroInstrRef& outRef)
        {
            for (MicroInstrRef scanRef = storage.findPreviousInstructionRef(fromRef); scanRef.isValid(); scanRef = storage.findPreviousInstructionRef(scanRef))
            {
                const MicroInstr* scanInst = storage.ptr(scanRef);
                if (!scanInst)
                    return nullptr;

                const MicroInstrFlags flags = MicroInstr::info(scanInst->op).flags;
                if (scanInst->op == MicroInstrOpcode::Label ||
                    flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                    flags.has(MicroInstrFlagsE::JumpInstruction) ||
                    flags.has(MicroInstrFlagsE::IsCallInstruction))
                    return nullptr;

                if (flags.has(MicroInstrFlagsE::DefinesCpuFlags) || flags.has(MicroInstrFlagsE::UsesCpuFlags))
                {
                    outRef = scanRef;
                    return scanInst;
                }

                const MicroInstrUseDef useDef = scanInst->collectUseDef(operands, nullptr);
                for (const MicroReg reg : useDef.defs)
                {
                    if (reg == valueReg || reg == guardReg)
                    {
                        outRef = scanRef;
                        return scanInst;
                    }
                }
                for (const MicroReg reg : useDef.uses)
                {
                    if (reg == valueReg || reg == guardReg)
                    {
                        outRef = scanRef;
                        return scanInst;
                    }
                }
            }

            return nullptr;
        }

        // The byte-to-dword widening a materialized boolean always carries.
        bool isWideningOf(const MicroOperandStorage& operands, const MicroInstr& inst, MicroReg reg)
        {
            if (inst.op != MicroInstrOpcode::LoadZeroExtRegReg)
                return false;
            const MicroInstrOperand* ops = inst.ops(operands);
            return ops && ops[0].reg == reg && ops[1].reg == reg && ops[2].opBits == MicroOpBits::B32 && ops[3].opBits == MicroOpBits::B8;
        }

        // `setcc reg` reached through its widening. Returns the condition it read.
        bool matchWidenedSetCond(const MicroStorage& storage, const MicroOperandStorage& operands, MicroInstrRef fromRef, MicroReg valueReg, MicroReg guardReg, MicroReg reg, MicroCond& outCond, MicroInstrRef& outSetRef)
        {
            MicroInstrRef     extRef  = MicroInstrRef::invalid();
            const MicroInstr* extInst = previousChainStep(storage, operands, fromRef, valueReg, guardReg, extRef);
            if (!extInst || !isWideningOf(operands, *extInst, reg))
                return false;

            MicroInstrRef     setRef  = MicroInstrRef::invalid();
            const MicroInstr* setInst = previousChainStep(storage, operands, extRef, valueReg, guardReg, setRef);
            if (!setInst || setInst->op != MicroInstrOpcode::SetCondReg)
                return false;

            const MicroInstrOperand* setOps = setInst->ops(operands);
            if (!setOps || setOps[0].reg != reg)
                return false;

            outCond   = setOps[1].cpuCond;
            outSetRef = setRef;
            return true;
        }
    }

    bool tryDropFloatOrderedGuard(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;

        const MicroInstrOperand* andOps = inst.ops(*ctx.operands);
        if (!andOps || andOps[3].microOp != MicroOp::And || andOps[2].opBits != MicroOpBits::B32)
            return false;

        const MicroStorage&        storage  = *ctx.storage;
        const MicroOperandStorage& operands = *ctx.operands;

        const MicroReg valueReg = andOps[0].reg;
        const MicroReg guardReg = andOps[1].reg;
        if (!valueReg.isVirtual() || !guardReg.isVirtual() || valueReg == guardReg)
            return false;

        // ... setnp Y, through its widening
        MicroCond     guardCond = MicroCond::Equal;
        MicroInstrRef guardSetRef;
        if (!matchWidenedSetCond(storage, operands, ref, valueReg, guardReg, guardReg, guardCond, guardSetRef))
            return false;
        if (guardCond != MicroCond::NotParity)
            return false;

        // ... setb X, through its widening
        MicroCond     valueCond = MicroCond::Equal;
        MicroInstrRef valueSetRef;
        if (!matchWidenedSetCond(storage, operands, guardSetRef, valueReg, guardReg, valueReg, valueCond, valueSetRef))
            return false;

        MicroCond swappedCond = MicroCond::Equal;
        if (!swappedOrderedCond(valueCond, swappedCond))
            return false;

        // ... cmp a, b
        MicroInstrRef     cmpRef  = MicroInstrRef::invalid();
        const MicroInstr* cmpInst = previousChainStep(storage, operands, valueSetRef, valueReg, guardReg, cmpRef);
        if (!cmpInst || cmpInst->op != MicroInstrOpcode::CmpRegReg)
            return false;

        const MicroInstrOperand* cmpOps = cmpInst->ops(operands);
        if (!cmpOps || !cmpOps[0].reg.isAnyFloat() || !cmpOps[1].reg.isAnyFloat())
            return false;

        // Dropping the `and` drops a flags definition, so the flags it leaves
        // must be dead by the time control can leave this straight-line run.
        if (!MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(storage, operands, ref))
            return false;

        if (!ctx.claimAll({ref, cmpRef, valueSetRef}))
            return false;

        MicroInstrOperand cmpNewOps[3];
        cmpNewOps[0].reg    = cmpOps[1].reg;
        cmpNewOps[1].reg    = cmpOps[0].reg;
        cmpNewOps[2].opBits = cmpOps[2].opBits;
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpRegReg, cmpNewOps);

        MicroInstrOperand setNewOps[2];
        setNewOps[0].reg     = valueReg;
        setNewOps[1].cpuCond = swappedCond;
        ctx.emitRewrite(valueSetRef, MicroInstrOpcode::SetCondReg, setNewOps);

        // `and` wrote into X, which now already holds the answer; the guard's
        // own chain falls to dead-code elimination once nothing reads Y.
        ctx.emitErase(ref);
        return true;
    }
}

SWC_END_NAMESPACE();
