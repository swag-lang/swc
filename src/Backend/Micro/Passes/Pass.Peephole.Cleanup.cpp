#include "pch.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Micro/Passes/Pass.Peephole.Private.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
        bool removeNoOpInstruction(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                instRef = cursor.instRef;
            const MicroInstr&        inst    = *SWC_CHECK_NOT_NULL(cursor.inst);
            const MicroInstrOperand* ops     = cursor.ops;
            if (!MicroOptimization::isNoOpEncoderInstruction(inst, ops))
                return false;

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool removeDeadCompareInstruction(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                instRef = cursor.instRef;
            const MicroInstr&        inst    = *SWC_CHECK_NOT_NULL(cursor.inst);
            const MicroInstrOperand* ops     = cursor.ops;
            if (inst.op != MicroInstrOpcode::CmpRegImm && inst.op != MicroInstrOpcode::CmpRegReg)
                return false;
            if (!ops)
                return false;

            const MicroStorage::View view        = SWC_CHECK_NOT_NULL(context.instructions)->view();
            auto                     it          = view.begin();
            Ref                      previousRef = INVALID_REF;
            for (; it != view.end(); ++it)
            {
                if (it.current == instRef)
                    break;
                if (it->op != MicroInstrOpcode::Debug)
                    previousRef = it.current;
            }

            if (it == view.end())
                return false;
            if (!areFlagsDeadAfterInstruction(context, it, view.end()))
                return false;

            const MicroReg compareLhsReg = ops[0].reg;
            if (previousRef != INVALID_REF && compareLhsReg.isValid() && compareLhsReg.isInt())
            {
                const MicroInstr* prevInst = SWC_CHECK_NOT_NULL(context.instructions)->ptr(previousRef);
                if (prevInst && prevInst->op == MicroInstrOpcode::LoadRegImm)
                {
                    const MicroInstrOperand* prevOps = prevInst->ops(*SWC_CHECK_NOT_NULL(context.operands));
                    if (prevOps && prevOps[0].reg == compareLhsReg && isCopyDeadAfterInstruction(context, cursor.nextIt, cursor.endIt, compareLhsReg))
                        SWC_CHECK_NOT_NULL(context.instructions)->erase(previousRef);
                }
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool foldSetCondZeroExtCopy(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (SWC_CHECK_NOT_NULL(cursor.inst)->op != MicroInstrOpcode::SetCondReg)
                return false;
            if (!ops || nextIt == endIt)
                return false;

            const MicroStorage::Iterator zeroExtIt = nextIt;
            const MicroStorage::Iterator copyIt    = std::next(zeroExtIt);
            if (copyIt == endIt)
                return false;

            const MicroInstr& zeroExtInst = *zeroExtIt;
            if (zeroExtInst.op != MicroInstrOpcode::LoadZeroExtRegReg)
                return false;

            MicroInstrOperand* zeroExtOps = zeroExtInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!zeroExtOps)
                return false;

            const MicroInstr& copyInst = *copyIt;
            if (copyInst.op != MicroInstrOpcode::LoadRegReg)
                return false;

            const MicroInstrOperand* copyOps = copyInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
            if (!copyOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            if (zeroExtOps[0].reg != tmpReg || zeroExtOps[1].reg != tmpReg)
                return false;
            if (zeroExtOps[2].opBits != MicroOpBits::B32 || zeroExtOps[3].opBits != MicroOpBits::B8)
                return false;
            if (copyOps[1].reg != tmpReg)
                return false;
            if (!copyOps[0].reg.isSameClass(tmpReg))
                return false;

            if (!isCopyDeadAfterInstruction(context, std::next(copyIt), endIt, tmpReg))
                return false;

            const MicroReg dstReg = copyOps[0].reg;

            const MicroInstr*  setCondInst = SWC_CHECK_NOT_NULL(context.instructions)->ptr(instRef);
            MicroInstrOperand* setCondOps  = setCondInst ? setCondInst->ops(*SWC_CHECK_NOT_NULL(context.operands)) : nullptr;
            if (!setCondOps)
                return false;

            const MicroReg originalSetCondReg = setCondOps[0].reg;
            setCondOps[0].reg                 = dstReg;
            if (MicroOptimization::violatesEncoderConformance(context, *setCondInst, setCondOps))
            {
                setCondOps[0].reg = originalSetCondReg;
                return false;
            }

            const MicroReg originalZeroExtDst = zeroExtOps[0].reg;
            const MicroReg originalZeroExtSrc = zeroExtOps[1].reg;
            zeroExtOps[0].reg                 = dstReg;
            zeroExtOps[1].reg                 = dstReg;
            if (MicroOptimization::violatesEncoderConformance(context, zeroExtInst, zeroExtOps))
            {
                setCondOps[0].reg = originalSetCondReg;
                zeroExtOps[0].reg = originalZeroExtDst;
                zeroExtOps[1].reg = originalZeroExtSrc;
                return false;
            }

            SWC_CHECK_NOT_NULL(context.instructions)->erase(copyIt.current);
            return true;
        }

    }

    void appendCleanupRules(RuleList& outRules)
    {
        // Rule: remove_dead_compare_instruction
        // Purpose: remove compare operations whose flags are never consumed.
        // Example: cmp r11, 0; mov rax, 11; ret -> mov rax, 11; ret
        outRules.push_back({RuleTarget::AnyInstruction, removeDeadCompareInstruction});

        // Rule: fold_setcond_zeroext_copy
        // Purpose: route setcc and zero-extend directly to final destination register.
        // Example: setcc r10; zero_extend r10; mov rax, r10 -> setcc rax; zero_extend rax
        outRules.push_back({RuleTarget::AnyInstruction, foldSetCondZeroExtCopy});

        // Rule: remove_no_op_instruction
        // Purpose: remove encoder-level no-op instructions.
        // Example: mov r8, r8 -> <removed>
        outRules.push_back({RuleTarget::AnyInstruction, removeNoOpInstruction});
    }
}

SWC_END_NAMESPACE();
