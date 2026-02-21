#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Micro/Passes/MicroPeepholePass.Private.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
        bool tryRemoveNoOpInstruction(const MicroPassContext& context, Ref instRef, const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            if (!MicroOptimization::isNoOpEncoderInstruction(inst, ops))
                return false;

            SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool tryCanonicalizeCmpRegImmZero(const MicroPassContext& context, const Cursor& cursor)
        {
            SWC_UNUSED(context);
            if (!cursor.ops)
                return false;

            if (cursor.inst->op != MicroInstrOpcode::CmpRegImm)
                return false;
            if (cursor.ops[2].valueU64 != 0)
                return false;

            cursor.inst->op = MicroInstrOpcode::CmpRegZero;
            return true;
        }

        bool tryFoldSetCondZeroExtCopy(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroStorage::Iterator& nextIt, const MicroStorage::Iterator& endIt)
        {
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

        bool matchRemoveNoOpInstruction(const MicroPassContext& context, const Cursor& cursor)
        {
            SWC_UNUSED(context);
            return MicroOptimization::isNoOpEncoderInstruction(*SWC_CHECK_NOT_NULL(cursor.inst), cursor.ops);
        }

        bool rewriteRemoveNoOpInstruction(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryRemoveNoOpInstruction(context, cursor.instRef, *SWC_CHECK_NOT_NULL(cursor.inst), cursor.ops);
        }

        bool matchCanonicalizeCmpRegImmZero(const MicroPassContext& context, const Cursor& cursor)
        {
            SWC_UNUSED(context);
            return cursor.inst->op == MicroInstrOpcode::CmpRegImm && cursor.ops && cursor.ops[2].valueU64 == 0;
        }

        bool rewriteCanonicalizeCmpRegImmZero(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryCanonicalizeCmpRegImmZero(context, cursor);
        }

        bool matchFoldSetCondZeroExtCopy(const MicroPassContext& context, const Cursor& cursor)
        {
            if (cursor.inst->op != MicroInstrOpcode::SetCondReg || !cursor.ops || cursor.nextIt == cursor.endIt)
                return false;

            const MicroStorage::Iterator zeroExtIt = cursor.nextIt;
            const MicroStorage::Iterator copyIt    = std::next(zeroExtIt);
            if (copyIt == cursor.endIt)
                return false;

            const MicroInstr& zeroExtInst = *zeroExtIt;
            if (zeroExtInst.op != MicroInstrOpcode::LoadZeroExtRegReg)
                return false;

            const MicroInstr& copyInst = *copyIt;
            SWC_UNUSED(context);
            return copyInst.op == MicroInstrOpcode::LoadRegReg;
        }

        bool rewriteFoldSetCondZeroExtCopy(const MicroPassContext& context, const Cursor& cursor)
        {
            return tryFoldSetCondZeroExtCopy(context, cursor.instRef, cursor.ops, cursor.nextIt, cursor.endIt);
        }
    }

    void appendCleanupRules(RuleList& outRules)
    {
        // Rule: canonicalize_cmp_reg_imm_zero
        // Purpose: normalize compare-against-zero into dedicated zero-compare opcode.
        // Example: cmp r11, 0 -> cmp_zero r11
        outRules.push_back({"canonicalize_cmp_reg_imm_zero", RuleTarget::AnyInstruction, matchCanonicalizeCmpRegImmZero, rewriteCanonicalizeCmpRegImmZero});

        // Rule: fold_setcond_zeroext_copy
        // Purpose: route setcc and zero-extend directly to final destination register.
        // Example: setcc r10; zero_extend r10; mov rax, r10 -> setcc rax; zero_extend rax
        outRules.push_back({"fold_setcond_zeroext_copy", RuleTarget::AnyInstruction, matchFoldSetCondZeroExtCopy, rewriteFoldSetCondZeroExtCopy});

        // Rule: remove_no_op_instruction
        // Purpose: remove encoder-level no-op instructions.
        // Example: mov r8, r8 -> <removed>
        outRules.push_back({"remove_no_op_instruction", RuleTarget::AnyInstruction, matchRemoveNoOpInstruction, rewriteRemoveNoOpInstruction});
    }
}

SWC_END_NAMESPACE();

