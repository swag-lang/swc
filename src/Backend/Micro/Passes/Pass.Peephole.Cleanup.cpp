#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Micro/Passes/Pass.Peephole.Private.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
        bool isStackBaseRegister(const MicroReg reg)
        {
            return reg == MicroReg::intReg(4) || reg == MicroReg::intReg(5);
        }

        bool removeDeadStackStoreBeforeRet(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstr*            inst    = cursor.inst;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!inst || !ops)
                return false;

            if (inst->op != MicroInstrOpcode::LoadMemReg && inst->op != MicroInstrOpcode::LoadMemImm)
                return false;

            uint8_t baseIndex   = 0;
            uint8_t offsetIndex = 0;
            if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(baseIndex, offsetIndex, *inst))
                return false;

            const MicroReg baseReg = ops[baseIndex].reg;
            if (!isStackBaseRegister(baseReg))
                return false;

            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&      scanInst = *scanIt;
                const MicroInstrUseDef useDef   = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);

                if (scanInst.op == MicroInstrOpcode::Ret)
                {
                    SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
                    return true;
                }

                if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                    return false;

                uint8_t scanBaseIndex   = 0;
                uint8_t scanOffsetIndex = 0;
                if (MicroInstrInfo::getMemBaseOffsetOperandIndices(scanBaseIndex, scanOffsetIndex, scanInst))
                {
                    const MicroInstrOperand* scanOps = scanInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
                    if (!scanOps)
                        return false;

                    if ((scanInst.op == MicroInstrOpcode::LoadMemReg || scanInst.op == MicroInstrOpcode::LoadMemImm) &&
                        isStackBaseRegister(scanOps[scanBaseIndex].reg))
                    {
                        continue;
                    }

                    return false;
                }
            }

            return false;
        }

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

        bool foldClearRegIntoNextMemStoreZero(const MicroPassContext& context, const Cursor& cursor)
        {
            const Ref                    instRef = cursor.instRef;
            const MicroInstr*            inst    = cursor.inst;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!inst || inst->op != MicroInstrOpcode::ClearReg)
                return false;
            if (!ops || nextIt == endIt)
                return false;

            const MicroReg    tmpReg    = ops[0].reg;
            const MicroOpBits clearBits = ops[1].opBits;

            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                MicroInstr&        scanInst = *scanIt;
                MicroInstrOperand* scanOps  = scanInst.ops(*SWC_CHECK_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                const MicroInstrUseDef useDef = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);

                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_CHECK_NOT_NULL(context.operands), refs, context.encoder);

                bool hasUse = false;
                bool hasDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg || *SWC_CHECK_NOT_NULL(ref.reg) != tmpReg)
                        continue;

                    hasUse |= ref.use;
                    hasDef |= ref.def;
                }

                if (hasDef)
                    return false;

                if (!hasUse)
                {
                    if (useDef.isCall || MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                        return false;
                    continue;
                }

                if (scanInst.op != MicroInstrOpcode::LoadMemReg || scanOps[1].reg != tmpReg)
                    return false;

                if (getNumBits(clearBits) < getNumBits(scanOps[2].opBits))
                    return false;

                if (!isTempDeadForAddressFold(context, std::next(scanIt), endIt, tmpReg))
                    return false;

                if (!areFlagsDeadAfterInstruction(context, scanIt, endIt))
                    return false;

                const MicroInstrOpcode originalOp  = scanInst.op;
                const std::array       originalOps = {scanOps[0], scanOps[1], scanOps[2], scanOps[3]};

                scanInst.op         = MicroInstrOpcode::LoadMemImm;
                scanOps[0]          = originalOps[0];
                scanOps[1].opBits   = originalOps[2].opBits;
                scanOps[2].valueU64 = originalOps[3].valueU64;
                scanOps[3].setImmediateValue(ApInt(0, getNumBits(originalOps[2].opBits)));
                if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    scanInst.op = originalOp;
                    for (uint32_t i = 0; i < 4; ++i)
                        scanOps[i] = originalOps[i];
                    return false;
                }

                SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
                return true;
            }

            return false;
        }

    }

    void appendCleanupRules(RuleList& outRules)
    {
        // Rule: remove_dead_stack_store_before_ret
        // Purpose: remove stores to local stack slots that are never observed before returning.
        // Example: mov [rsp], r9; mov rax, r9; ret -> mov rax, r9; ret
        outRules.push_back({RuleTarget::AnyInstruction, removeDeadStackStoreBeforeRet});

        // Rule: remove_dead_compare_instruction
        // Purpose: remove compare operations whose flags are never consumed.
        // Example: cmp r11, 0; mov rax, 11; ret -> mov rax, 11; ret
        outRules.push_back({RuleTarget::AnyInstruction, removeDeadCompareInstruction});

        // Rule: fold_setcond_zeroext_copy
        // Purpose: route setcc and zero-extend directly to final destination register.
        // Example: setcc r10; zero_extend r10; mov rax, r10 -> setcc rax; zero_extend rax
        outRules.push_back({RuleTarget::AnyInstruction, foldSetCondZeroExtCopy});

        // Rule: fold_clearreg_into_next_mem_store_zero
        // Purpose: store zero immediate directly to memory instead of through a cleared temp register.
        // Example: xor rdx, rdx; mov [rsp], rdx -> mov [rsp], 0
        outRules.push_back({RuleTarget::AnyInstruction, foldClearRegIntoNextMemStoreZero});

        // Rule: remove_no_op_instruction
        // Purpose: remove encoder-level no-op instructions.
        // Example: mov r8, r8 -> <removed>
        outRules.push_back({RuleTarget::AnyInstruction, removeNoOpInstruction});
    }
}

SWC_END_NAMESPACE();
