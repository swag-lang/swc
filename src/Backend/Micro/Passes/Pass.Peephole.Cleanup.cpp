#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.Peephole.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_STACK_ADDRESS_ESCAPE_WINDOW_BYTES = 32;

    bool isSingleLinearPredecessorLabel(const MicroPassContext& context, const MicroInstrRef labelRef)
    {
        if (!context.builder || labelRef.isInvalid())
            return false;

        const MicroControlFlowGraph&         cfg             = context.builder->controlFlowGraph();
        const std::span<const MicroInstrRef> instructionRefs = cfg.instructionRefs();
        if (instructionRefs.empty())
            return false;

        uint32_t labelIndex = std::numeric_limits<uint32_t>::max();
        for (uint32_t idx = 0; idx < instructionRefs.size(); ++idx)
        {
            if (instructionRefs[idx] == labelRef)
            {
                labelIndex = idx;
                break;
            }
        }

        if (labelIndex == std::numeric_limits<uint32_t>::max() || labelIndex == 0)
            return false;

        const uint32_t expectedPredIndex = labelIndex - 1;
        uint32_t       predCount         = 0;
        for (uint32_t idx = 0; idx < instructionRefs.size(); ++idx)
        {
            for (const uint32_t succIndex : cfg.successors(idx))
            {
                if (succIndex != labelIndex)
                    continue;

                if (idx != expectedPredIndex)
                    return false;

                ++predCount;
            }
        }

        return predCount == 1;
    }

    bool foldBoolAndChainIntoDirectJumps(MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&  context  = pass.context();
        const MicroInstr*        cmp1Inst = cursor.inst;
        const MicroInstrOperand* cmp1Ops  = cursor.ops;
        if (!cmp1Inst || cmp1Inst->op != MicroInstrOpcode::CmpRegImm || !cmp1Ops)
            return false;

        const MicroStorage::Iterator set1It = cursor.nextIt;
        if (set1It == cursor.endIt)
            return false;
        const MicroStorage::Iterator zext1It = std::next(set1It);
        if (zext1It == cursor.endIt)
            return false;
        const MicroStorage::Iterator cmp2It = std::next(zext1It);
        if (cmp2It == cursor.endIt)
            return false;
        const MicroStorage::Iterator set2It = std::next(cmp2It);
        if (set2It == cursor.endIt)
            return false;
        const MicroStorage::Iterator zext2It = std::next(set2It);
        if (zext2It == cursor.endIt)
            return false;
        const MicroStorage::Iterator copyAIt = std::next(zext2It);
        if (copyAIt == cursor.endIt)
            return false;
        const MicroStorage::Iterator copyBIt = std::next(copyAIt);
        if (copyBIt == cursor.endIt)
            return false;
        const MicroStorage::Iterator copyCIt = std::next(copyBIt);
        if (copyCIt == cursor.endIt)
            return false;
        const MicroStorage::Iterator andIt = std::next(copyCIt);
        if (andIt == cursor.endIt)
            return false;
        const MicroStorage::Iterator cmpZeroIt = std::next(andIt);
        if (cmpZeroIt == cursor.endIt)
            return false;
        const MicroStorage::Iterator jumpIt = std::next(cmpZeroIt);
        if (jumpIt == cursor.endIt)
            return false;

        const MicroInstr& set1Inst    = *set1It;
        const MicroInstr& zext1Inst   = *zext1It;
        const MicroInstr& cmp2Inst    = *cmp2It;
        const MicroInstr& set2Inst    = *set2It;
        const MicroInstr& zext2Inst   = *zext2It;
        const MicroInstr& copyAInst   = *copyAIt;
        const MicroInstr& copyBInst   = *copyBIt;
        const MicroInstr& copyCInst   = *copyCIt;
        const MicroInstr& andInst     = *andIt;
        const MicroInstr& cmpZeroInst = *cmpZeroIt;
        const MicroInstr& jumpInst    = *jumpIt;

        const MicroInstrOperand* set1Ops    = set1Inst.ops(*context.operands);
        const MicroInstrOperand* zext1Ops   = zext1Inst.ops(*context.operands);
        const MicroInstrOperand* cmp2Ops    = cmp2Inst.ops(*context.operands);
        const MicroInstrOperand* set2Ops    = set2Inst.ops(*context.operands);
        const MicroInstrOperand* zext2Ops   = zext2Inst.ops(*context.operands);
        const MicroInstrOperand* copyAOps   = copyAInst.ops(*context.operands);
        const MicroInstrOperand* copyBOps   = copyBInst.ops(*context.operands);
        const MicroInstrOperand* copyCOps   = copyCInst.ops(*context.operands);
        const MicroInstrOperand* andOps     = andInst.ops(*context.operands);
        const MicroInstrOperand* cmpZeroOps = cmpZeroInst.ops(*context.operands);
        const MicroInstrOperand* jumpOps    = jumpInst.ops(*context.operands);
        if (!set1Ops || !zext1Ops || !cmp2Ops || !set2Ops || !zext2Ops || !copyAOps || !copyBOps || !copyCOps || !andOps || !cmpZeroOps || !jumpOps)
            return false;

        if (set1Inst.op != MicroInstrOpcode::SetCondReg ||
            zext1Inst.op != MicroInstrOpcode::LoadZeroExtRegReg ||
            cmp2Inst.op != MicroInstrOpcode::CmpRegImm ||
            set2Inst.op != MicroInstrOpcode::SetCondReg ||
            zext2Inst.op != MicroInstrOpcode::LoadZeroExtRegReg ||
            copyAInst.op != MicroInstrOpcode::LoadRegReg ||
            copyBInst.op != MicroInstrOpcode::LoadRegReg ||
            copyCInst.op != MicroInstrOpcode::LoadRegReg ||
            andInst.op != MicroInstrOpcode::OpBinaryRegReg ||
            cmpZeroInst.op != MicroInstrOpcode::CmpRegImm ||
            jumpInst.op != MicroInstrOpcode::JumpCond)
        {
            return false;
        }

        if (zext1Ops[2].opBits != MicroOpBits::B32 || zext1Ops[3].opBits != MicroOpBits::B8 ||
            zext2Ops[2].opBits != MicroOpBits::B32 || zext2Ops[3].opBits != MicroOpBits::B8)
        {
            return false;
        }

        if (andOps[3].microOp != MicroOp::And || andOps[2].opBits != MicroOpBits::B8)
            return false;
        if (cmpZeroOps[1].opBits != MicroOpBits::B8 || cmpZeroOps[2].valueU64 != 0)
            return false;
        if (jumpOps[0].cpuCond != MicroCond::Equal && jumpOps[0].cpuCond != MicroCond::Zero)
            return false;

        const MicroReg cond1Reg = set1Ops[0].reg;
        const MicroReg cond2Reg = set2Ops[0].reg;
        if (zext1Ops[0].reg != cond1Reg || zext1Ops[1].reg != cond1Reg ||
            zext2Ops[0].reg != cond2Reg || zext2Ops[1].reg != cond2Reg)
        {
            return false;
        }

        if (copyAOps[1].reg != cond1Reg || copyBOps[1].reg != cond2Reg)
            return false;
        if (copyCOps[1].reg != copyAOps[0].reg)
            return false;
        if (andOps[0].reg != copyCOps[0].reg || andOps[1].reg != copyBOps[0].reg)
            return false;
        if (cmpZeroOps[0].reg != andOps[0].reg)
            return false;
        if (copyAOps[2].opBits != MicroOpBits::B8 || copyBOps[2].opBits != MicroOpBits::B8 || copyCOps[2].opBits != MicroOpBits::B8)
            return false;

        const MicroReg cmp1Reg = cmp1Ops[0].reg;
        if (cmp2Ops[0].reg != cmp1Reg || cmp2Ops[1].opBits != cmp1Ops[1].opBits)
            return false;

        if (!pass.areFlagsDeadAfterInstruction(jumpIt, cursor.endIt))
            return false;

        MicroCond invertedCond1;
        MicroCond invertedCond2;
        if (!MicroPassHelpers::tryInvertCondition(invertedCond1, set1Ops[1].cpuCond) || !MicroPassHelpers::tryInvertCondition(invertedCond2, set2Ops[1].cpuCond))
            return false;

        const MicroInstrRef      set1Ref        = set1It.current;
        const MicroInstrRef      set2Ref        = set2It.current;
        MicroInstr*              set1Mutable    = context.instructions->ptr(set1Ref);
        MicroInstr*              set2Mutable    = context.instructions->ptr(set2Ref);
        MicroInstrOperand*       set1MutableOps = set1Mutable ? set1Mutable->ops(*context.operands) : nullptr;
        MicroInstrOperand*       set2MutableOps = set2Mutable ? set2Mutable->ops(*context.operands) : nullptr;
        const MicroInstrOperand* jumpMutableOps = jumpInst.ops(*context.operands);
        if (!set1Mutable || !set2Mutable || !set1MutableOps || !set2MutableOps || !jumpMutableOps)
            return false;

        const MicroInstr originalSet1    = *set1Mutable;
        const MicroInstr originalSet2    = *set2Mutable;
        const std::array originalSet1Ops = {set1MutableOps[0], set1MutableOps[1], set1MutableOps[2]};
        const std::array originalSet2Ops = {set2MutableOps[0], set2MutableOps[1], set2MutableOps[2]};

        set1Mutable->op            = MicroInstrOpcode::JumpCond;
        set1Mutable->numOperands   = 3;
        set1MutableOps[0].cpuCond  = invertedCond1;
        set1MutableOps[1].opBits   = MicroOpBits::B32;
        set1MutableOps[2].valueU64 = jumpOps[2].valueU64;

        set2Mutable->op            = MicroInstrOpcode::JumpCond;
        set2Mutable->numOperands   = 3;
        set2MutableOps[0].cpuCond  = invertedCond2;
        set2MutableOps[1].opBits   = MicroOpBits::B32;
        set2MutableOps[2].valueU64 = jumpOps[2].valueU64;

        if (MicroPassHelpers::violatesEncoderConformance(context, *set1Mutable, set1MutableOps) ||
            MicroPassHelpers::violatesEncoderConformance(context, *set2Mutable, set2MutableOps))
        {
            *set1Mutable   = originalSet1;
            *set2Mutable   = originalSet2;
            set1MutableOps = set1Mutable->ops(*context.operands);
            set2MutableOps = set2Mutable->ops(*context.operands);
            if (set1MutableOps)
            {
                for (uint32_t i = 0; i < 3; ++i)
                    set1MutableOps[i] = originalSet1Ops[i];
            }
            if (set2MutableOps)
            {
                for (uint32_t i = 0; i < 3; ++i)
                    set2MutableOps[i] = originalSet2Ops[i];
            }
            return false;
        }

        context.instructions->erase(zext1It.current);
        context.instructions->erase(zext2It.current);
        context.instructions->erase(copyAIt.current);
        context.instructions->erase(copyBIt.current);
        context.instructions->erase(copyCIt.current);
        context.instructions->erase(andIt.current);
        context.instructions->erase(cmpZeroIt.current);
        context.instructions->erase(jumpIt.current);
        return true;
    }

    bool tryResolveOriginalSetCond(MicroCond& outCond, MicroInstrRef& outSetCondRef, const MicroPassContext& context, MicroInstrRef startRef, MicroReg reg)
    {
        MicroInstrRef scanRef    = context.instructions->findPreviousInstructionRef(startRef);
        MicroReg      trackedReg = reg;
        while (scanRef.isValid())
        {
            const MicroInstr*        scanInst = context.instructions->ptr(scanRef);
            const MicroInstrOperand* scanOps  = scanInst ? scanInst->ops(*context.operands) : nullptr;
            if (!scanInst || !scanOps)
                return false;

            const MicroInstrUseDef useDef = scanInst->collectUseDef(*context.operands, context.encoder);
            if (MicroInstrInfo::isLocalDataflowBarrier(*scanInst, useDef))
                return false;

            bool regDefined = false;
            for (const MicroReg defReg : useDef.defs)
            {
                if (defReg == trackedReg)
                {
                    regDefined = true;
                    break;
                }
            }

            if (!regDefined)
            {
                scanRef = context.instructions->findPreviousInstructionRef(scanRef);
                continue;
            }

            if (scanInst->op == MicroInstrOpcode::SetCondReg && scanOps[0].reg == trackedReg)
            {
                outCond       = scanOps[1].cpuCond;
                outSetCondRef = scanRef;
                return true;
            }

            if (scanInst->op == MicroInstrOpcode::LoadZeroExtRegReg &&
                scanOps[0].reg == trackedReg &&
                scanOps[1].reg == trackedReg &&
                scanOps[2].opBits == MicroOpBits::B32 &&
                scanOps[3].opBits == MicroOpBits::B8)
            {
                scanRef = context.instructions->findPreviousInstructionRef(scanRef);
                continue;
            }

            if (scanInst->op == MicroInstrOpcode::LoadRegReg &&
                scanOps[0].reg == trackedReg &&
                scanOps[2].opBits == MicroOpBits::B8)
            {
                trackedReg = scanOps[1].reg;
                scanRef    = context.instructions->findPreviousInstructionRef(scanRef);
                continue;
            }

            return false;
        }

        return false;
    }

    bool foldSetCondCompareZeroIntoDirectJump(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&  context = pass.context();
        const MicroInstrRef      cmpRef  = cursor.instRef;
        const MicroInstr*        cmpInst = cursor.inst;
        const MicroInstrOperand* cmpOps  = cursor.ops;
        const auto               endIt   = cursor.endIt;
        if (!cmpInst || cmpInst->op != MicroInstrOpcode::CmpRegImm || !cmpOps)
            return false;

        if (cmpOps[2].hasWideImmediateValue() || cmpOps[2].valueU64 != 0)
            return false;

        auto          setCondCond = MicroCond::Equal;
        MicroInstrRef setCondRef  = MicroInstrRef::invalid();
        if (!tryResolveOriginalSetCond(setCondCond, setCondRef, context, cmpRef, cmpOps[0].reg))
            return false;

        MicroStorage::Iterator jumpIt = cursor.nextIt;
        for (; jumpIt != endIt; ++jumpIt)
        {
            const MicroInstr&        scanInst = *jumpIt;
            const MicroInstrOperand* scanOps  = scanInst.ops(*context.operands);
            if (!scanOps)
                return false;

            const MicroInstrUseDef useDef = scanInst.collectUseDef(*context.operands, context.encoder);
            if (MicroInstrInfo::usesCpuFlags(scanInst))
                break;
            if (MicroInstrInfo::definesCpuFlags(scanInst))
                return false;
            if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                return false;
        }

        if (jumpIt == endIt)
            return false;

        const MicroInstr&  jumpInst = *jumpIt;
        MicroInstrOperand* jumpOps  = jumpInst.ops(*context.operands);
        if (jumpInst.op != MicroInstrOpcode::JumpCond || !jumpOps)
            return false;

        if (jumpOps[0].cpuCond != MicroCond::Equal &&
            jumpOps[0].cpuCond != MicroCond::Zero &&
            jumpOps[0].cpuCond != MicroCond::NotEqual &&
            jumpOps[0].cpuCond != MicroCond::NotZero)
        {
            return false;
        }

        MicroCond newJumpCond = setCondCond;
        if (jumpOps[0].cpuCond == MicroCond::Equal || jumpOps[0].cpuCond == MicroCond::Zero)
        {
            if (!MicroPassHelpers::tryInvertCondition(newJumpCond, newJumpCond))
                return false;
        }

        const MicroCond originalJumpCond = jumpOps[0].cpuCond;
        jumpOps[0].cpuCond               = newJumpCond;
        if (MicroPassHelpers::violatesEncoderConformance(context, jumpInst, jumpOps))
        {
            jumpOps[0].cpuCond = originalJumpCond;
            return false;
        }

        context.instructions->erase(cmpRef);
        return true;
    }

    bool foldSetCondCompareSetCondChain(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&      context = pass.context();
        const MicroInstrRef          cmpRef  = cursor.instRef;
        const MicroInstr*            cmpInst = cursor.inst;
        const MicroInstrOperand*     cmpOps  = cursor.ops;
        const MicroStorage::Iterator nextIt  = cursor.nextIt;
        const MicroStorage::Iterator endIt   = cursor.endIt;
        if (!cmpInst || cmpInst->op != MicroInstrOpcode::CmpRegImm || !cmpOps || nextIt == endIt)
            return false;

        if (cmpOps[2].hasWideImmediateValue() || cmpOps[2].valueU64 != 0)
            return false;

        const MicroInstr& nextSetCondInst = *nextIt;
        if (nextSetCondInst.op != MicroInstrOpcode::SetCondReg)
            return false;

        MicroInstrOperand* nextSetCondOps = nextSetCondInst.ops(*context.operands);
        if (!nextSetCondOps)
            return false;

        const MicroCond cmpToBoolCond = nextSetCondOps[1].cpuCond;
        if (cmpToBoolCond != MicroCond::Equal &&
            cmpToBoolCond != MicroCond::Zero &&
            cmpToBoolCond != MicroCond::NotEqual &&
            cmpToBoolCond != MicroCond::NotZero)
        {
            return false;
        }

        auto          originalSetCond    = MicroCond::Equal;
        MicroInstrRef originalSetCondRef = MicroInstrRef::invalid();
        if (!tryResolveOriginalSetCond(originalSetCond, originalSetCondRef, context, cmpRef, cmpOps[0].reg))
            return false;

        MicroCond foldedCond = originalSetCond;
        if (cmpToBoolCond == MicroCond::Equal || cmpToBoolCond == MicroCond::Zero)
        {
            if (!MicroPassHelpers::tryInvertCondition(foldedCond, foldedCond))
                return false;
        }

        const MicroCond originalNextSetCond = nextSetCondOps[1].cpuCond;
        nextSetCondOps[1].cpuCond           = foldedCond;
        if (MicroPassHelpers::violatesEncoderConformance(context, nextSetCondInst, nextSetCondOps))
        {
            nextSetCondOps[1].cpuCond = originalNextSetCond;
            return false;
        }

        context.instructions->erase(cmpRef);
        if (originalSetCondRef.isValid())
        {
            const MicroInstr*        originalSetCondInst = context.instructions->ptr(originalSetCondRef);
            const MicroInstrOperand* originalSetCondOps  = originalSetCondInst ? originalSetCondInst->ops(*context.operands) : nullptr;
            if (originalSetCondOps && pass.isCopyDeadAfterInstruction(std::next(nextIt), endIt, originalSetCondOps[0].reg))
                context.instructions->erase(originalSetCondRef);
        }

        return true;
    }

    bool isStackPointerRegister(const MicroPassContext& context, const MicroReg reg)
    {
        const CallConv& conv = CallConv::get(context.callConvKind);
        if (reg == conv.stackPointer)
            return true;

        if (context.encoder)
        {
            const MicroReg stackPointerReg = context.encoder->stackPointerReg();
            if (stackPointerReg.isValid() && reg == stackPointerReg)
                return true;
        }

        return false;
    }

    bool isAddressOnlyInstruction(const MicroInstr& inst)
    {
        return inst.op == MicroInstrOpcode::LoadAddrRegMem || inst.op == MicroInstrOpcode::LoadAddrAmcRegMem;
    }

    bool isMemoryReadInstruction(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::CmpMemReg:
            case MicroInstrOpcode::CmpMemImm:
            case MicroInstrOpcode::OpUnaryMem:
            case MicroInstrOpcode::OpBinaryRegMem:
            case MicroInstrOpcode::OpBinaryMemReg:
            case MicroInstrOpcode::OpBinaryMemImm:
            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::Pop:
            case MicroInstrOpcode::LoadAmcRegMem:
                return true;
            default:
                return false;
        }
    }

    bool isMemoryWriteInstruction(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::LoadMemImm:
            case MicroInstrOpcode::OpUnaryMem:
            case MicroInstrOpcode::OpBinaryMemReg:
            case MicroInstrOpcode::OpBinaryMemImm:
            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::Pop:
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
                return true;
            default:
                return false;
        }
    }

    bool isStackWriteCandidate(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::LoadMemImm:
            case MicroInstrOpcode::OpUnaryMem:
            case MicroInstrOpcode::OpBinaryMemReg:
            case MicroInstrOpcode::OpBinaryMemImm:
                return true;
            default:
                return false;
        }
    }

    bool isAmcInstructionUsingStackBase(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!ops)
            return true;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                return MicroPassHelpers::isStackBaseRegister(context, ops[1].reg) || MicroPassHelpers::isStackBaseRegister(context, ops[2].reg);
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
                return MicroPassHelpers::isStackBaseRegister(context, ops[0].reg) || MicroPassHelpers::isStackBaseRegister(context, ops[1].reg);
            default:
                return false;
        }
    }

    bool isShiftLikeImmediateOp(MicroOp op)
    {
        return op == MicroOp::ShiftLeft ||
               op == MicroOp::ShiftRight ||
               op == MicroOp::ShiftArithmeticLeft ||
               op == MicroOp::ShiftArithmeticRight ||
               op == MicroOp::RotateLeft ||
               op == MicroOp::RotateRight;
    }

    bool isEpilogStackAdjustBeforeReturn(const MicroStorage::Iterator& it, const MicroStorage::Iterator& endIt, const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg stackReg)
    {
        if (!ops)
            return false;

        if (inst.op != MicroInstrOpcode::OpBinaryRegImm || ops[0].reg != stackReg)
            return false;

        const auto nextIt = std::next(it);
        if (nextIt == endIt)
            return false;

        if (nextIt->op == MicroInstrOpcode::Ret)
            return true;

        if (nextIt->op != MicroInstrOpcode::Pop)
            return false;

        const auto nextNextIt = std::next(nextIt);
        return nextNextIt != endIt && nextNextIt->op == MicroInstrOpcode::Ret;
    }

    bool canTreatStackBaseRegistersAsEquivalent(const MicroPassContext& context)
    {
        const CallConv& conv = CallConv::get(context.callConvKind);
        if (!conv.framePointer.isValid())
            return false;

        const MicroReg stackReg = conv.stackPointer;
        const MicroReg frameReg = conv.framePointer;
        if (!stackReg.isValid() || !frameReg.isValid() || stackReg == frameReg)
            return false;

        bool       sawFrameAliasToStack = false;
        const auto view                 = context.instructions->view();
        for (auto it = view.begin(); it != view.end(); ++it)
        {
            const MicroInstr&        inst = *it;
            const MicroInstrOperand* ops  = inst.ops(*context.operands);
            if (!ops)
            {
                if (inst.op == MicroInstrOpcode::Label ||
                    inst.op == MicroInstrOpcode::Nop ||
                    inst.op == MicroInstrOpcode::Ret)
                {
                    continue;
                }

                return false;
            }

            const MicroInstrUseDef useDef = inst.collectUseDef(*context.operands, context.encoder);
            if (inst.op == MicroInstrOpcode::LoadRegReg &&
                ops[0].reg == frameReg &&
                ops[1].reg == stackReg &&
                ops[2].opBits == MicroOpBits::B64)
            {
                sawFrameAliasToStack = true;
                continue;
            }

            bool stackRegDefined = false;
            bool frameRegDefined = false;
            for (const MicroReg defReg : useDef.defs)
            {
                if (defReg == stackReg)
                    stackRegDefined = true;
                if (defReg == frameReg)
                    frameRegDefined = true;
            }

            if (frameRegDefined)
            {
                if (inst.op == MicroInstrOpcode::Pop)
                {
                    const auto nextIt = std::next(it);
                    if (nextIt != view.end() && nextIt->op == MicroInstrOpcode::Ret)
                        continue;
                }

                return false;
            }

            if (!stackRegDefined)
                continue;

            if (!sawFrameAliasToStack)
                continue;

            if (isEpilogStackAdjustBeforeReturn(it, view.end(), inst, ops, stackReg))
                continue;

            if (inst.op == MicroInstrOpcode::Pop)
            {
                const auto nextIt = std::next(it);
                if (nextIt != view.end() && nextIt->op == MicroInstrOpcode::Ret)
                    continue;
            }

            sawFrameAliasToStack = false;
        }

        return sawFrameAliasToStack;
    }

    bool hasAnyReadOrAddressTakenForStackSlot(const MicroPassContext& context, const MicroInstrRef excludedInstRef, const MicroReg slotBaseReg, const uint64_t slotOffset, const uint32_t slotSize, const bool equivalentStackBases)
    {
        const MicroStorage::View view                       = context.instructions->view();
        bool                     reachedExcludedInstruction = false;

        for (auto it = view.begin(); it != view.end(); ++it)
        {
            if (it.current == excludedInstRef)
            {
                reachedExcludedInstruction = true;
                continue;
            }

            const bool               afterExcludedInstruction = reachedExcludedInstruction;
            const MicroInstr&        scanInst                 = *it;
            const MicroInstrOperand* scanOps                  = scanInst.ops(*context.operands);
            if (!scanOps)
            {
                if (scanInst.op == MicroInstrOpcode::Label ||
                    scanInst.op == MicroInstrOpcode::Nop ||
                    scanInst.op == MicroInstrOpcode::Ret)
                {
                    continue;
                }

                return true;
            }

            const MicroInstrUseDef scanUseDef = scanInst.collectUseDef(*context.operands, context.encoder);
            if (afterExcludedInstruction && scanUseDef.isCall)
                return true;

            if (afterExcludedInstruction)
            {
                bool slotBaseDefined = false;
                for (const MicroReg defReg : scanUseDef.defs)
                {
                    if (defReg == slotBaseReg)
                    {
                        slotBaseDefined = true;
                        break;
                    }
                }

                if (slotBaseDefined)
                {
                    if (isEpilogStackAdjustBeforeReturn(it, view.end(), scanInst, scanOps, slotBaseReg))
                        continue;

                    if (scanInst.op == MicroInstrOpcode::Pop)
                    {
                        const auto nextIt = std::next(it);
                        if (nextIt != view.end() && nextIt->op == MicroInstrOpcode::Ret)
                            continue;
                    }

                    return true;
                }
            }

            if (afterExcludedInstruction &&
                scanInst.op == MicroInstrOpcode::LoadMemReg &&
                (scanOps[1].reg == slotBaseReg ||
                 (equivalentStackBases &&
                  MicroPassHelpers::isStackBaseRegister(context, scanOps[1].reg) &&
                  MicroPassHelpers::isStackBaseRegister(context, slotBaseReg))))
            {
                return true;
            }

            if (!isAddressOnlyInstruction(scanInst) && !isMemoryReadInstruction(scanInst) && !isMemoryWriteInstruction(scanInst))
                continue;

            uint8_t scanBaseIndex   = 0;
            uint8_t scanOffsetIndex = 0;
            if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(scanBaseIndex, scanOffsetIndex, scanInst))
            {
                if (scanInst.op == MicroInstrOpcode::LoadAmcRegMem ||
                    scanInst.op == MicroInstrOpcode::LoadAmcMemReg ||
                    scanInst.op == MicroInstrOpcode::LoadAmcMemImm ||
                    scanInst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
                {
                    if (isAmcInstructionUsingStackBase(context, scanInst, scanOps))
                        return true;

                    continue;
                }

                if (scanInst.op == MicroInstrOpcode::Pop)
                {
                    const auto nextIt = std::next(it);
                    if (nextIt != view.end() && nextIt->op == MicroInstrOpcode::Ret)
                        continue;
                }

                if (afterExcludedInstruction && (isAddressOnlyInstruction(scanInst) || isMemoryReadInstruction(scanInst)))
                    return true;

                continue;
            }

            const MicroReg scanBaseReg = scanOps[scanBaseIndex].reg;
            if (scanBaseReg != slotBaseReg)
            {
                if (!MicroPassHelpers::isStackBaseRegister(context, scanBaseReg))
                    continue;

                if (!equivalentStackBases)
                    continue;
            }

            if (scanOps[scanOffsetIndex].hasWideImmediateValue())
                return true;

            const uint64_t scanSlotOffset = scanOps[scanOffsetIndex].valueU64;
            if (isAddressOnlyInstruction(scanInst))
            {
                if (MicroPassHelpers::rangesOverlap(slotOffset, slotSize, scanSlotOffset, K_STACK_ADDRESS_ESCAPE_WINDOW_BYTES))
                    return true;

                continue;
            }

            auto scanOpBits = MicroOpBits::Zero;
            if (!MicroPassHelpers::getMemAccessOpBits(scanOpBits, scanInst, scanOps))
                return true;

            const uint32_t scanSlotSize = getNumBytes(scanOpBits);
            if (!scanSlotSize)
                return true;

            if (MicroPassHelpers::rangesOverlap(slotOffset, slotSize, scanSlotOffset, scanSlotSize) && isMemoryReadInstruction(scanInst))
                return true;
        }

        return false;
    }

    bool getStoreLocation(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg& outBaseReg, uint64_t& outOffset, MicroOpBits& outOpBits)
    {
        if (!ops)
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadMemReg:
                outBaseReg = ops[0].reg;
                outOffset  = ops[3].valueU64;
                outOpBits  = ops[2].opBits;
                return true;
            case MicroInstrOpcode::LoadMemImm:
                outBaseReg = ops[0].reg;
                outOffset  = ops[2].valueU64;
                outOpBits  = ops[1].opBits;
                return true;
            default:
                return false;
        }
    }

    bool getLoadLocation(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg& outDstReg, MicroReg& outBaseReg, uint64_t& outOffset, MicroOpBits& outOpBits)
    {
        if (!ops)
            return false;

        if (inst.op != MicroInstrOpcode::LoadRegMem)
            return false;

        outDstReg  = ops[0].reg;
        outBaseReg = ops[1].reg;
        outOffset  = ops[3].valueU64;
        outOpBits  = ops[2].opBits;
        return true;
    }

    bool removeRedundantStackLoadStorePair(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&      context = pass.context();
        const MicroInstr*            inst    = cursor.inst;
        const MicroInstrOperand*     ops     = cursor.ops;
        const MicroStorage::Iterator nextIt  = cursor.nextIt;
        const MicroStorage::Iterator endIt   = cursor.endIt;
        if (!inst || !ops)
            return false;

        MicroReg dstReg;
        MicroReg baseReg;
        uint64_t slotOffset = 0;
        auto     opBits     = MicroOpBits::Zero;
        if (!getLoadLocation(*inst, ops, dstReg, baseReg, slotOffset, opBits))
            return false;

        if (!dstReg.isValid() || dstReg == baseReg)
            return false;
        if (!MicroPassHelpers::isStackBaseRegister(context, baseReg))
            return false;

        const uint32_t slotSize = getNumBytes(opBits);
        if (!slotSize)
            return false;

        for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
        {
            const MicroInstr&      scanInst = *scanIt;
            const MicroInstrUseDef useDef   = scanInst.collectUseDef(*context.operands, context.encoder);
            if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                return false;

            for (const MicroReg defReg : useDef.defs)
            {
                if (defReg == baseReg || defReg == dstReg)
                    return false;
            }

            const MicroInstrOperand* scanOps = scanInst.ops(*context.operands);
            if (!scanOps)
                return false;

            if (scanInst.op == MicroInstrOpcode::LoadMemReg &&
                scanOps[0].reg == baseReg &&
                scanOps[1].reg == dstReg &&
                scanOps[2].opBits == opBits &&
                scanOps[3].valueU64 == slotOffset)
            {
                context.instructions->erase(scanIt.current);
                context.instructions->erase(cursor.instRef);
                return true;
            }

            SmallVector<MicroInstrRegOperandRef> refs;
            scanInst.collectRegOperands(*context.operands, refs, context.encoder);
            for (const MicroInstrRegOperandRef& ref : refs)
            {
                if (!ref.reg || *(ref.reg) != dstReg)
                    continue;

                if (ref.use || ref.def)
                    return false;
            }

            if (!isMemoryWriteInstruction(scanInst))
                continue;

            uint8_t scanBaseIndex   = 0;
            uint8_t scanOffsetIndex = 0;
            if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(scanBaseIndex, scanOffsetIndex, scanInst))
                return false;

            const MicroReg scanBaseReg = scanOps[scanBaseIndex].reg;
            if (!MicroPassHelpers::isStackBaseRegister(context, scanBaseReg))
                return false;

            auto scanOpBits = MicroOpBits::Zero;
            if (!MicroPassHelpers::getMemAccessOpBits(scanOpBits, scanInst, scanOps))
                return false;

            const uint32_t scanSlotSize = getNumBytes(scanOpBits);
            if (!scanSlotSize)
                return false;

            const uint64_t scanSlotOffset = scanOps[scanOffsetIndex].valueU64;
            if (MicroPassHelpers::rangesOverlap(slotOffset, slotSize, scanSlotOffset, scanSlotSize))
                return false;
        }

        return false;
    }

    bool hasUseBeforeNextDef(const MicroPassContext& context, const MicroStorage::Iterator& startIt, const MicroStorage::Iterator& endIt, const MicroReg reg)
    {
        if (!reg.isValid())
            return true;

        auto scanIt = startIt;

        SmallVector<uint32_t> visitedJumpTargets;
        uint32_t              followedJumpCount = 0;
        while (scanIt != endIt)
        {
            const MicroInstr&        scanInst = *scanIt;
            const MicroInstrOperand* scanOps  = scanInst.ops(*context.operands);
            if (!scanOps)
                return true;

            if (scanInst.op == MicroInstrOpcode::Nop || scanInst.op == MicroInstrOpcode::Label)
            {
                ++scanIt;
                continue;
            }

            const MicroInstrUseDef useDef = scanInst.collectUseDef(*context.operands, context.encoder);

            for (const MicroReg useReg : useDef.uses)
            {
                if (useReg == reg)
                    return true;
            }

            for (const MicroReg defReg : useDef.defs)
            {
                if (defReg == reg)
                    return false;
            }

            if (scanInst.op == MicroInstrOpcode::JumpCond && MicroInstrInfo::isUnconditionalJumpInstruction(scanInst, scanOps))
            {
                if (scanOps[2].valueU64 > std::numeric_limits<uint32_t>::max())
                    return true;

                const uint32_t targetLabelId = static_cast<uint32_t>(scanOps[2].valueU64);
                if (std::ranges::find(visitedJumpTargets, targetLabelId) != visitedJumpTargets.end())
                    return true;
                visitedJumpTargets.push_back(targetLabelId);

                followedJumpCount++;
                if (followedJumpCount > 16)
                    return true;

                MicroStorage::Iterator targetLabelIt;
                bool                   foundTarget = false;
                for (auto it = context.instructions->view().begin(); it != endIt; ++it)
                {
                    const MicroInstr& candidate = *it;
                    if (candidate.op != MicroInstrOpcode::Label)
                        continue;

                    const MicroInstrOperand* labelOps = candidate.ops(*context.operands);
                    if (!labelOps || labelOps[0].valueU64 > std::numeric_limits<uint32_t>::max())
                        continue;
                    if (static_cast<uint32_t>(labelOps[0].valueU64) != targetLabelId)
                        continue;

                    targetLabelIt = it;
                    foundTarget   = true;
                    break;
                }

                if (!foundTarget)
                    return true;

                scanIt = std::next(targetLabelIt);
                continue;
            }

            if (useDef.isCall || MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                return true;

            ++scanIt;
        }

        return false;
    }

    bool foldLateLoadBinaryStoreBackIntoMemOp(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&      context = pass.context();
        const MicroInstrRef          instRef = cursor.instRef;
        const MicroInstr*            inst    = cursor.inst;
        const MicroInstrOperand*     ops     = cursor.ops;
        const MicroStorage::Iterator nextIt  = cursor.nextIt;
        const MicroStorage::Iterator endIt   = cursor.endIt;
        if (!inst || !ops || inst->op != MicroInstrOpcode::LoadRegMem || nextIt == endIt)
            return false;

        auto thirdIt = nextIt;
        ++thirdIt;
        if (thirdIt == endIt)
            return false;

        const MicroInstr&        nextInst = *nextIt;
        const MicroInstrOperand* nextOps  = nextInst.ops(*context.operands);
        if (!nextOps)
            return false;

        const bool hasRhsCopy = nextInst.op == MicroInstrOpcode::LoadRegReg;

        auto storeIt = thirdIt;
        auto binIt   = nextIt;
        if (hasRhsCopy)
        {
            binIt = thirdIt;
            ++storeIt;
            if (storeIt == endIt)
                return false;
        }

        const MicroInstr&        binInst = *binIt;
        const MicroInstrOperand* binOps  = binInst.ops(*context.operands);
        if (!binOps)
            return false;

        const MicroInstr&        storeInst = *storeIt;
        const MicroInstrOperand* storeOps  = storeInst.ops(*context.operands);
        if (!storeOps || storeInst.op != MicroInstrOpcode::LoadMemReg)
            return false;

        const MicroReg    tmpReg    = ops[0].reg;
        const MicroReg    memBase   = ops[1].reg;
        const MicroOpBits memOpBits = ops[2].opBits;
        const uint64_t    memOffset = ops[3].valueU64;
        if (storeOps[0].reg != memBase || storeOps[1].reg != tmpReg || storeOps[2].opBits != memOpBits || storeOps[3].valueU64 != memOffset)
            return false;
        if (hasUseBeforeNextDef(context, std::next(storeIt), endIt, tmpReg))
            return false;

        auto rhsReg       = MicroReg{};
        bool eraseRhsCopy = false;
        if (hasRhsCopy)
        {
            if (nextOps[2].opBits != memOpBits)
                return false;

            const MicroReg copyTmpReg = nextOps[0].reg;
            eraseRhsCopy              = !hasUseBeforeNextDef(context, std::next(storeIt), endIt, copyTmpReg);
        }

        MicroOp microOp;
        if (binInst.op == MicroInstrOpcode::OpBinaryRegImm)
            microOp = binOps[2].microOp;
        else if (binInst.op == MicroInstrOpcode::OpBinaryRegReg)
            microOp = binOps[3].microOp;
        else
            return false;
        switch (microOp)
        {
            case MicroOp::Add:
            case MicroOp::Subtract:
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Xor:
                break;
            default:
                return false;
        }

        const MicroInstrRef binRef   = binIt.current;
        const MicroInstrRef storeRef = storeIt.current;
        const MicroInstrRef copyRef  = hasRhsCopy ? nextIt.current : MicroInstrRef::invalid();

        MicroInstr*        binMutable    = context.instructions->ptr(binRef);
        MicroInstrOperand* binMutableOps = binMutable ? binMutable->ops(*context.operands) : nullptr;
        if (!binMutable || !binMutableOps)
            return false;

        MicroInstr        probeBinInst         = *binMutable;
        std::array        rewrittenBinOps      = {binMutableOps[0], binMutableOps[1], binMutableOps[2], binMutableOps[3], MicroInstrOperand{}};
        auto              rewrittenBinOpcode   = MicroInstrOpcode::End;
        constexpr uint8_t rewrittenBinOperands = 5;

        if (binInst.op == MicroInstrOpcode::OpBinaryRegImm)
        {
            if (hasRhsCopy)
                return false;
            if (binOps[0].reg != tmpReg || binOps[1].opBits != memOpBits)
                return false;

            rewrittenBinOpcode          = MicroInstrOpcode::OpBinaryMemImm;
            rewrittenBinOps[0].reg      = memBase;
            rewrittenBinOps[1].opBits   = memOpBits;
            rewrittenBinOps[2].microOp  = binOps[2].microOp;
            rewrittenBinOps[3].valueU64 = memOffset;
            rewrittenBinOps[4]          = binOps[3];
        }
        else if (binInst.op == MicroInstrOpcode::OpBinaryRegReg)
        {
            if (binOps[0].reg != tmpReg || binOps[2].opBits != memOpBits)
                return false;

            rhsReg = binOps[1].reg;
            if (hasRhsCopy)
            {
                if (rhsReg != nextOps[0].reg)
                    return false;
                rhsReg = nextOps[1].reg;
            }

            if (rhsReg == tmpReg)
                return false;

            rewrittenBinOpcode          = MicroInstrOpcode::OpBinaryMemReg;
            rewrittenBinOps[0].reg      = memBase;
            rewrittenBinOps[1].reg      = rhsReg;
            rewrittenBinOps[2].opBits   = memOpBits;
            rewrittenBinOps[3].microOp  = binOps[3].microOp;
            rewrittenBinOps[4].valueU64 = memOffset;
        }
        else
        {
            return false;
        }

        probeBinInst.op          = rewrittenBinOpcode;
        probeBinInst.numOperands = rewrittenBinOperands;
        if (MicroPassHelpers::violatesEncoderConformance(context, probeBinInst, rewrittenBinOps.data()))
            return false;

        binMutable->op          = rewrittenBinOpcode;
        binMutable->numOperands = rewrittenBinOperands;
        for (uint32_t i = 0; i < rewrittenBinOperands; ++i)
            binMutableOps[i] = rewrittenBinOps[i];

        context.instructions->erase(instRef);
        context.instructions->erase(storeRef);
        if (hasRhsCopy && eraseRhsCopy)
            context.instructions->erase(copyRef);
        return true;
    }

    bool forwardStackStoreToFollowingLoad(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&      context = pass.context();
        const MicroInstr*            inst    = cursor.inst;
        const MicroInstrOperand*     ops     = cursor.ops;
        const MicroStorage::Iterator nextIt  = cursor.nextIt;
        const MicroStorage::Iterator endIt   = cursor.endIt;
        if (!inst || !ops)
            return false;

        if (inst->op != MicroInstrOpcode::LoadMemReg)
            return false;

        const MicroReg baseReg = ops[0].reg;
        if (!MicroPassHelpers::isStackBaseRegister(context, baseReg))
            return false;

        if (ops[3].hasWideImmediateValue())
            return false;

        const MicroReg srcReg = ops[1].reg;
        if (!srcReg.isValid())
            return false;

        const auto opBits = ops[2].opBits;
        if (opBits == MicroOpBits::Zero)
            return false;

        const uint32_t slotSize = getNumBytes(opBits);
        if (!slotSize)
            return false;

        const uint64_t slotOffset = ops[3].valueU64;
        for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
        {
            auto&              scanInst = const_cast<MicroInstr&>(*scanIt);
            MicroInstrOperand* scanOps  = scanInst.ops(*context.operands);
            if (scanInst.op == MicroInstrOpcode::Label)
            {
                if (!isSingleLinearPredecessorLabel(context, scanIt.current))
                    return false;
                continue;
            }
            if (scanInst.op == MicroInstrOpcode::Nop)
                continue;
            if (!scanOps)
                return false;

            const MicroInstrUseDef useDef = scanInst.collectUseDef(*context.operands, context.encoder);
            if (useDef.isCall)
                return false;
            if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef) && scanInst.op != MicroInstrOpcode::JumpCond)
                return false;

            for (const MicroReg defReg : useDef.defs)
            {
                if (defReg == baseReg || defReg == srcReg)
                    return false;
            }

            if (scanInst.op == MicroInstrOpcode::LoadRegMem &&
                scanOps[1].reg == baseReg &&
                !scanOps[3].hasWideImmediateValue() &&
                scanOps[2].opBits == opBits &&
                scanOps[3].valueU64 == slotOffset)
            {
                if (scanOps[0].reg == srcReg)
                {
                    context.instructions->erase(scanIt.current);
                    return true;
                }

                const MicroInstr originalLoadInst = scanInst;
                const std::array originalLoadOps  = {scanOps[0], scanOps[1], scanOps[2], scanOps[3]};

                scanInst.op          = MicroInstrOpcode::LoadRegReg;
                scanInst.numOperands = 3;
                scanOps[0]           = originalLoadOps[0];
                scanOps[1].reg       = srcReg;
                scanOps[2].opBits    = opBits;
                if (MicroPassHelpers::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    scanInst = originalLoadInst;
                    for (uint32_t i = 0; i < 4; ++i)
                        scanOps[i] = originalLoadOps[i];
                    return false;
                }

                return true;
            }

            if (!isMemoryWriteInstruction(scanInst))
                continue;

            uint8_t memBaseIndex   = 0;
            uint8_t memOffsetIndex = 0;
            if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(memBaseIndex, memOffsetIndex, scanInst))
                return false;

            const MicroReg scanBaseReg = scanOps[memBaseIndex].reg;
            if (!MicroPassHelpers::isStackBaseRegister(context, scanBaseReg))
                continue;

            if (scanOps[memOffsetIndex].hasWideImmediateValue())
                return false;

            auto scanOpBits = MicroOpBits::Zero;
            if (!MicroPassHelpers::getMemAccessOpBits(scanOpBits, scanInst, scanOps))
                return false;

            const uint32_t scanSlotSize = getNumBytes(scanOpBits);
            if (!scanSlotSize)
                return false;

            const uint64_t scanSlotOffset = scanOps[memOffsetIndex].valueU64;
            if (MicroPassHelpers::rangesOverlap(slotOffset, slotSize, scanSlotOffset, scanSlotSize))
                return false;
        }

        return false;
    }

    bool removeOverwrittenStoreToSameSlot(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&      context = pass.context();
        const MicroInstrRef          instRef = cursor.instRef;
        const MicroInstr*            inst    = cursor.inst;
        const MicroInstrOperand*     ops     = cursor.ops;
        const MicroStorage::Iterator nextIt  = cursor.nextIt;
        const MicroStorage::Iterator endIt   = cursor.endIt;
        if (!inst || !ops)
            return false;

        MicroReg baseReg;
        uint64_t offset = 0;
        auto     opBits = MicroOpBits::Zero;
        if (!getStoreLocation(*inst, ops, baseReg, offset, opBits))
            return false;

        for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
        {
            const MicroInstr&      scanInst = *scanIt;
            const MicroInstrUseDef useDef   = scanInst.collectUseDef(*context.operands, context.encoder);
            if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                return false;

            for (const MicroReg defReg : useDef.defs)
            {
                if (defReg == baseReg)
                    return false;
            }

            const MicroInstrOperand* scanOps = scanInst.ops(*context.operands);
            if (!scanOps)
                return false;

            MicroReg scanBaseReg;
            uint64_t scanOffset = 0;
            auto     scanBits   = MicroOpBits::Zero;
            if (getStoreLocation(scanInst, scanOps, scanBaseReg, scanOffset, scanBits))
            {
                if (scanBaseReg == baseReg && scanOffset == offset && scanBits == opBits)
                {
                    context.instructions->erase(instRef);
                    return true;
                }

                return false;
            }

            uint8_t memBaseIndex   = 0;
            uint8_t memOffsetIndex = 0;
            if (MicroInstrInfo::getMemBaseOffsetOperandIndices(memBaseIndex, memOffsetIndex, scanInst))
                return false;
        }

        return false;
    }

    bool removeDeadStackStoreBeforeRet(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&      context = pass.context();
        const MicroInstrRef          instRef = cursor.instRef;
        const MicroInstr*            inst    = cursor.inst;
        const MicroInstrOperand*     ops     = cursor.ops;
        const MicroStorage::Iterator nextIt  = cursor.nextIt;
        const MicroStorage::Iterator endIt   = cursor.endIt;
        if (!inst || !ops)
            return false;

        if (!isStackWriteCandidate(*inst))
            return false;

        uint8_t baseIndex   = 0;
        uint8_t offsetIndex = 0;
        if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(baseIndex, offsetIndex, *inst))
            return false;

        const MicroReg baseReg = ops[baseIndex].reg;
        if (!MicroPassHelpers::isStackBaseRegister(context, baseReg))
            return false;

        auto opBits = MicroOpBits::Zero;
        if (!MicroPassHelpers::getMemAccessOpBits(opBits, *inst, ops))
            return false;

        const uint32_t slotSize = getNumBytes(opBits);
        if (!slotSize)
            return false;
        const uint64_t slotOffset = ops[offsetIndex].valueU64;

        if (MicroInstrInfo::definesCpuFlags(*inst))
        {
            const MicroStorage::View view = context.instructions->view();
            auto                     it   = view.begin();
            for (; it != view.end(); ++it)
            {
                if (it.current == instRef)
                    break;
            }

            if (it == view.end())
                return false;
            if (!pass.areFlagsDeadAfterInstruction(it, view.end()))
                return false;
        }

        for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
        {
            const MicroInstr&      scanInst = *scanIt;
            const MicroInstrUseDef useDef   = scanInst.collectUseDef(*context.operands, context.encoder);

            if (scanInst.op == MicroInstrOpcode::Ret)
            {
                context.instructions->erase(instRef);
                return true;
            }

            if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                return false;

            const MicroInstrOperand* scanOps = scanInst.ops(*context.operands);
            if (!scanOps)
                return false;

            bool baseRegDefined = false;
            for (const MicroReg defReg : useDef.defs)
            {
                if (defReg == baseReg)
                {
                    baseRegDefined = true;
                    break;
                }
            }

            if (baseRegDefined)
            {
                if (scanInst.op == MicroInstrOpcode::OpBinaryRegImm &&
                    scanOps[0].reg == baseReg &&
                    std::next(scanIt) != endIt &&
                    std::next(scanIt)->op == MicroInstrOpcode::Ret)
                {
                    continue;
                }

                return false;
            }

            if (isAddressOnlyInstruction(scanInst))
                continue;

            if (!isMemoryReadInstruction(scanInst) && !isMemoryWriteInstruction(scanInst))
                continue;

            uint8_t scanBaseIndex   = 0;
            uint8_t scanOffsetIndex = 0;
            if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(scanBaseIndex, scanOffsetIndex, scanInst))
                return false;

            const MicroReg scanBaseReg = scanOps[scanBaseIndex].reg;
            if (!MicroPassHelpers::isStackBaseRegister(context, scanBaseReg))
                return false;

            auto scanOpBits = MicroOpBits::Zero;
            if (!MicroPassHelpers::getMemAccessOpBits(scanOpBits, scanInst, scanOps))
                return false;

            const uint32_t scanSlotSize = getNumBytes(scanOpBits);
            if (!scanSlotSize)
                return false;

            const uint64_t scanSlotOffset = scanOps[scanOffsetIndex].valueU64;
            if (MicroPassHelpers::rangesOverlap(slotOffset, slotSize, scanSlotOffset, scanSlotSize) && isMemoryReadInstruction(scanInst))
                return false;
        }

        return false;
    }

    bool removeNeverReadStackStore(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&  context = pass.context();
        const MicroInstrRef      instRef = cursor.instRef;
        const MicroInstr*        inst    = cursor.inst;
        const MicroInstrOperand* ops     = cursor.ops;
        if (!inst || !ops)
            return false;

        if (!isStackWriteCandidate(*inst))
            return false;

        uint8_t baseIndex   = 0;
        uint8_t offsetIndex = 0;
        if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(baseIndex, offsetIndex, *inst))
            return false;

        const MicroReg baseReg = ops[baseIndex].reg;
        if (!isStackPointerRegister(context, baseReg))
            return false;

        if (ops[offsetIndex].hasWideImmediateValue())
            return false;

        auto opBits = MicroOpBits::Zero;
        if (!MicroPassHelpers::getMemAccessOpBits(opBits, *inst, ops))
            return false;

        const uint32_t slotSize = getNumBytes(opBits);
        if (!slotSize)
            return false;

        const uint64_t slotOffset           = ops[offsetIndex].valueU64;
        const bool     equivalentStackBases = canTreatStackBaseRegistersAsEquivalent(context);

        if (MicroInstrInfo::definesCpuFlags(*inst))
        {
            const MicroStorage::View view = context.instructions->view();
            auto                     it   = view.begin();
            for (; it != view.end(); ++it)
            {
                if (it.current == instRef)
                    break;
            }

            if (it == view.end())
                return false;
            if (!pass.areFlagsDeadAfterInstruction(it, view.end()))
                return false;
        }

        if (hasAnyReadOrAddressTakenForStackSlot(context, instRef, baseReg, slotOffset, slotSize, equivalentStackBases))
            return false;

        context.instructions->erase(instRef);
        return true;
    }

    bool removeRedundantStackSaveRestoreAroundImmediateShift(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&  context  = pass.context();
        const MicroInstr*        saveInst = cursor.inst;
        const MicroInstrOperand* saveOps  = cursor.ops;
        if (!saveInst || !saveOps)
            return false;

        if (saveInst->op != MicroInstrOpcode::LoadMemReg)
            return false;
        if (saveOps[2].opBits != MicroOpBits::B64)
            return false;
        if (!MicroPassHelpers::isStackBaseRegister(context, saveOps[0].reg))
            return false;

        const MicroReg savedReg = saveOps[1].reg;
        if (!savedReg.isValid() || !savedReg.isInt())
            return false;

        const MicroStorage::Iterator shiftIt = cursor.nextIt;
        if (shiftIt == cursor.endIt)
            return false;

        const MicroStorage::Iterator restoreIt = std::next(shiftIt);
        if (restoreIt == cursor.endIt)
            return false;

        const MicroInstr&        shiftInst = *shiftIt;
        const MicroInstrOperand* shiftOps  = shiftInst.ops(*context.operands);
        if (!shiftOps)
            return false;
        if (shiftInst.op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        if (!isShiftLikeImmediateOp(shiftOps[2].microOp))
            return false;
        if (shiftOps[0].reg == savedReg)
            return false;

        const MicroInstr&        restoreInst = *restoreIt;
        const MicroInstrOperand* restoreOps  = restoreInst.ops(*context.operands);
        if (!restoreOps)
            return false;
        if (restoreInst.op != MicroInstrOpcode::LoadRegMem)
            return false;
        if (restoreOps[2].opBits != MicroOpBits::B64)
            return false;
        if (restoreOps[0].reg != savedReg)
            return false;
        if (restoreOps[1].reg != saveOps[0].reg)
            return false;

        if (saveOps[3].hasWideImmediateValue() || restoreOps[3].hasWideImmediateValue())
            return false;
        if (saveOps[3].valueU64 != restoreOps[3].valueU64)
            return false;

        context.instructions->erase(restoreIt.current);
        context.instructions->erase(cursor.instRef);
        return true;
    }

    bool removeRedundantClearBeforeConvertFloatToInt(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&      context = pass.context();
        const MicroInstr*            inst    = cursor.inst;
        const MicroInstrOperand*     ops     = cursor.ops;
        const MicroStorage::Iterator nextIt  = cursor.nextIt;
        const MicroStorage::Iterator endIt   = cursor.endIt;
        if (!inst || inst->op != MicroInstrOpcode::ClearReg || !ops || nextIt == endIt)
            return false;

        const MicroInstr& nextInst = *nextIt;
        if (nextInst.op != MicroInstrOpcode::OpBinaryRegReg)
            return false;

        const MicroInstrOperand* nextOps = nextInst.ops(*context.operands);
        if (!nextOps)
            return false;
        if (nextOps[3].microOp != MicroOp::ConvertFloatToInt)
            return false;

        const MicroReg clearReg = ops[0].reg;
        if (nextOps[0].reg != clearReg)
            return false;
        if (!clearReg.isInt())
            return false;

        if (getNumBits(ops[1].opBits) < getNumBits(nextOps[2].opBits))
            return false;

        context.instructions->erase(cursor.instRef);
        return true;
    }

    bool removeNoOpInstruction(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&  context = pass.context();
        const MicroInstrRef      instRef = cursor.instRef;
        const MicroInstr&        inst    = *(cursor.inst);
        const MicroInstrOperand* ops     = cursor.ops;
        if (!MicroPassHelpers::isNoOpEncoderInstruction(inst, ops))
            return false;

        context.instructions->erase(instRef);
        return true;
    }

    bool removeDeadCompareInstruction(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&  context = pass.context();
        const MicroInstrRef      instRef = cursor.instRef;
        const MicroInstr&        inst    = *(cursor.inst);
        const MicroInstrOperand* ops     = cursor.ops;
        if (inst.op != MicroInstrOpcode::CmpRegImm &&
            inst.op != MicroInstrOpcode::CmpRegReg &&
            inst.op != MicroInstrOpcode::CmpMemImm &&
            inst.op != MicroInstrOpcode::CmpMemReg)
            return false;
        if (!ops)
            return false;

        const MicroStorage::View view        = context.instructions->view();
        auto                     it          = view.begin();
        MicroInstrRef            previousRef = MicroInstrRef::invalid();
        for (; it != view.end(); ++it)
        {
            if (it.current == instRef)
                break;
            previousRef = it.current;
        }

        if (it == view.end())
            return false;
        if (!pass.areFlagsDeadAfterInstruction(it, view.end()))
            return false;

        const bool     compareUsesRegisterLhs = inst.op == MicroInstrOpcode::CmpRegImm || inst.op == MicroInstrOpcode::CmpRegReg;
        const MicroReg compareLhsReg          = compareUsesRegisterLhs ? ops[0].reg : MicroReg{};
        if (compareUsesRegisterLhs && previousRef.isValid() && compareLhsReg.isValid() && compareLhsReg.isInt())
        {
            const MicroInstr* prevInst = context.instructions->ptr(previousRef);
            if (prevInst && prevInst->op == MicroInstrOpcode::LoadRegImm)
            {
                const MicroInstrOperand* prevOps = prevInst->ops(*context.operands);
                if (prevOps && prevOps[0].reg == compareLhsReg && pass.isCopyDeadAfterInstruction(cursor.nextIt, cursor.endIt, compareLhsReg))
                    context.instructions->erase(previousRef);
            }
        }

        context.instructions->erase(instRef);
        return true;
    }

    bool foldSetCondZeroExtCopy(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&      context = pass.context();
        const MicroInstrRef          instRef = cursor.instRef;
        const MicroInstrOperand*     ops     = cursor.ops;
        const MicroStorage::Iterator nextIt  = cursor.nextIt;
        const MicroStorage::Iterator endIt   = cursor.endIt;
        if ((cursor.inst)->op != MicroInstrOpcode::SetCondReg)
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

        MicroInstrOperand* zeroExtOps = zeroExtInst.ops(*context.operands);
        if (!zeroExtOps)
            return false;

        const MicroInstr& copyInst = *copyIt;
        if (copyInst.op != MicroInstrOpcode::LoadRegReg)
            return false;

        const MicroInstrOperand* copyOps = copyInst.ops(*context.operands);
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

        const MicroReg dstReg = copyOps[0].reg;

        struct RegRewrite
        {
            MicroReg* reg = nullptr;
            MicroReg  oldReg;
        };

        auto rollbackRewritesFrom = [](SmallVector<RegRewrite>& rewrites, const size_t start) {
            for (size_t i = rewrites.size(); i > start; --i)
            {
                const RegRewrite& rewrite = rewrites[i - 1];
                if (rewrite.reg)
                    *rewrite.reg = rewrite.oldReg;
            }

            rewrites.resize(start);
        };

        auto isCopyDeadNoBarrier = [&](MicroStorage::Iterator scanIt, const MicroReg reg) {
            for (; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&                    scanInst = *scanIt;
                const MicroInstrUseDef               useDef   = scanInst.collectUseDef(*context.operands, context.encoder);
                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*context.operands, refs, context.encoder);

                bool hasUse = false;
                bool hasDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg || *(ref.reg) != reg)
                        continue;

                    hasUse |= ref.use;
                    hasDef |= ref.def;
                }

                if (hasUse)
                    return false;
                if (hasDef)
                    return true;
                if (scanInst.op == MicroInstrOpcode::Ret)
                    return true;
                if (useDef.isCall)
                {
                    return false;
                }
            }

            return true;
        };

        auto forwardUses = [&](const MicroReg fromReg, const MicroReg toReg, const MicroReg stopOnDefReg, SmallVector<RegRewrite>& rewrites) {
            bool replacedUse = false;
            for (auto scanIt = std::next(copyIt); scanIt != endIt; ++scanIt)
            {
                MicroInstr&              scanInst = *scanIt;
                const MicroInstrOperand* scanOps  = scanInst.ops(*context.operands);
                if (!scanOps)
                {
                    rollbackRewritesFrom(rewrites, 0);
                    return false;
                }

                const MicroInstrUseDef               useDef = scanInst.collectUseDef(*context.operands, context.encoder);
                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*context.operands, refs, context.encoder);

                bool hasFromUse   = false;
                bool hasFromDef   = false;
                bool hasStopOnDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    const MicroReg reg = *(ref.reg);
                    if (reg == fromReg)
                    {
                        hasFromUse |= ref.use;
                        hasFromDef |= ref.def;
                    }
                    else if (reg == stopOnDefReg && ref.def)
                    {
                        hasStopOnDef = true;
                    }
                }

                if (hasFromUse)
                {
                    const size_t rewriteStart = rewrites.size();
                    for (const MicroInstrRegOperandRef& ref : refs)
                    {
                        if (!ref.reg || !ref.use)
                            continue;

                        MicroReg& reg = *(ref.reg);
                        if (reg != fromReg)
                            continue;

                        rewrites.push_back({&reg, reg});
                        reg = toReg;
                    }

                    if (MicroPassHelpers::violatesEncoderConformance(context, scanInst, scanOps))
                    {
                        rollbackRewritesFrom(rewrites, rewriteStart);
                        rollbackRewritesFrom(rewrites, 0);
                        return false;
                    }

                    replacedUse = true;
                }

                if (hasFromDef ||
                    hasStopOnDef ||
                    useDef.isCall ||
                    scanInst.op == MicroInstrOpcode::JumpCond ||
                    scanInst.op == MicroInstrOpcode::Ret)
                {
                    break;
                }
            }

            return replacedUse;
        };

        auto retargetSetCondToDst = [&] {
            const MicroInstr*  setCondInst = context.instructions->ptr(instRef);
            MicroInstrOperand* setCondOps  = setCondInst ? setCondInst->ops(*context.operands) : nullptr;
            if (!setCondOps)
                return false;

            const MicroReg originalSetCondReg = setCondOps[0].reg;
            setCondOps[0].reg                 = dstReg;
            if (MicroPassHelpers::violatesEncoderConformance(context, *setCondInst, setCondOps))
            {
                setCondOps[0].reg = originalSetCondReg;
                return false;
            }

            const MicroReg originalZeroExtDst = zeroExtOps[0].reg;
            const MicroReg originalZeroExtSrc = zeroExtOps[1].reg;
            zeroExtOps[0].reg                 = dstReg;
            zeroExtOps[1].reg                 = dstReg;
            if (MicroPassHelpers::violatesEncoderConformance(context, zeroExtInst, zeroExtOps))
            {
                setCondOps[0].reg = originalSetCondReg;
                zeroExtOps[0].reg = originalZeroExtDst;
                zeroExtOps[1].reg = originalZeroExtSrc;
                return false;
            }

            return true;
        };

        bool                    canRetargetSetCondToDst = pass.isCopyDeadAfterInstruction(std::next(copyIt), endIt, tmpReg);
        SmallVector<RegRewrite> tmpToDstRewrites;
        if (!canRetargetSetCondToDst)
        {
            if (forwardUses(tmpReg, dstReg, dstReg, tmpToDstRewrites) && isCopyDeadNoBarrier(std::next(copyIt), tmpReg))
            {
                canRetargetSetCondToDst = true;
            }
            else
            {
                rollbackRewritesFrom(tmpToDstRewrites, 0);
            }
        }

        if (canRetargetSetCondToDst)
        {
            if (!retargetSetCondToDst())
            {
                rollbackRewritesFrom(tmpToDstRewrites, 0);
                return false;
            }

            context.instructions->erase(copyIt.current);
            return true;
        }

        SmallVector<RegRewrite> dstToTmpRewrites;
        const bool              replacedDstUse = forwardUses(dstReg, tmpReg, tmpReg, dstToTmpRewrites);
        if (!replacedDstUse || !isCopyDeadNoBarrier(std::next(copyIt), dstReg))
        {
            rollbackRewritesFrom(dstToTmpRewrites, 0);
            return false;
        }

        context.instructions->erase(copyIt.current);
        return true;
    }

    bool foldClearRegIntoNextMemStoreZero(const MicroPeepholePass& pass, const MicroPeepholePass::Cursor& cursor)
    {
        const MicroPassContext&      context = pass.context();
        const MicroInstrRef          instRef = cursor.instRef;
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
            MicroInstrOperand* scanOps  = scanInst.ops(*context.operands);
            if (!scanOps)
                return false;

            const MicroInstrUseDef useDef = scanInst.collectUseDef(*context.operands, context.encoder);

            SmallVector<MicroInstrRegOperandRef> refs;
            scanInst.collectRegOperands(*context.operands, refs, context.encoder);

            bool hasUse = false;
            bool hasDef = false;
            for (const MicroInstrRegOperandRef& ref : refs)
            {
                if (!ref.reg || *(ref.reg) != tmpReg)
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

            if (!pass.isTempDeadForAddressFold(std::next(scanIt), endIt, tmpReg))
                return false;

            if (!pass.areFlagsDeadAfterInstruction(scanIt, endIt))
                return false;

            const MicroInstrOpcode originalOp  = scanInst.op;
            const std::array       originalOps = {scanOps[0], scanOps[1], scanOps[2], scanOps[3]};

            scanInst.op         = MicroInstrOpcode::LoadMemImm;
            scanOps[0]          = originalOps[0];
            scanOps[1].opBits   = originalOps[2].opBits;
            scanOps[2].valueU64 = originalOps[3].valueU64;
            scanOps[3].setImmediateValue(ApInt(0, getNumBits(originalOps[2].opBits)));
            if (MicroPassHelpers::violatesEncoderConformance(context, scanInst, scanOps))
            {
                scanInst.op = originalOp;
                for (uint32_t i = 0; i < 4; ++i)
                    scanOps[i] = originalOps[i];
                return false;
            }

            context.instructions->erase(instRef);
            return true;
        }

        return false;
    }

}

void MicroPeepholePass::appendCleanupRules(RuleList& outRules)
{
    // Rule: remove_overwritten_store_to_same_slot
    // Purpose: remove an earlier store when a later store overwrites the exact same address before any read.
    // Example: mov [rsp], 3; mov r10, 42; mov [rsp], r10 -> mov r10, 42; mov [rsp], r10
    outRules.emplace_back(RuleTarget::AnyInstruction, removeOverwrittenStoreToSameSlot);

    // Rule: remove_dead_stack_store_before_ret
    // Purpose: remove stores to local stack slots that are never observed before returning.
    // Example: mov [rsp], r9; mov rax, r9; ret -> mov rax, r9; ret
    outRules.emplace_back(RuleTarget::AnyInstruction, removeDeadStackStoreBeforeRet);

    // Rule: fold_late_load_binary_store_back_into_mem_op
    // Purpose: late fold of load/copy/op/store patterns into direct memory ops after regalloc introduced copies.
    // Example: mov r11,[rbp]; mov r9,rcx; add r11,r9; mov [rbp],r11 -> add [rbp],rcx
    outRules.emplace_back(RuleTarget::LoadRegMem, foldLateLoadBinaryStoreBackIntoMemOp);

    // Rule: forward_stack_store_to_following_load
    // Purpose: forward stack-slot stores directly to later loads when the source register is still available.
    // Example: mov [rsp+64], r10; ...; mov rax, [rsp+64] -> mov [rsp+64], r10; ...; mov rax, r10
    outRules.emplace_back(RuleTarget::AnyInstruction, forwardStackStoreToFollowingLoad);

    // Rule: remove_never_read_stack_store
    // Purpose: remove stack-pointer slot stores that are never read/address-taken anywhere in the function.
    // Example: mov [rsp+0x70], r9; ... (no read) -> <removed>
    outRules.emplace_back(RuleTarget::AnyInstruction, removeNeverReadStackStore);

    // Rule: remove_redundant_stack_load_store_pair
    // Purpose: remove a stack load restored unchanged later, with no observable intervening effect.
    // Example: mov rax, [rsp+56]; mov rcx, [rsp+64]; mov [rsp+56], rax -> mov rcx, [rsp+64]
    outRules.emplace_back(RuleTarget::LoadRegMem, removeRedundantStackLoadStorePair);

    // Rule: remove_dead_compare_instruction
    // Purpose: remove compare operations whose flags are never consumed.
    // Example: cmp r11, 0; mov rax, 11; ret -> mov rax, 11; ret
    outRules.emplace_back(RuleTarget::AnyInstruction, removeDeadCompareInstruction);

    // Rule: fold_setcond_compare_setcond_chain
    // Purpose: collapse bool rematerialization chain into one setcc.
    // Example: setne r9; cmp r9, 0; sete r10 -> sete r10
    outRules.emplace_back(RuleTarget::AnyInstruction, foldSetCondCompareSetCondChain);

    // Rule: fold_setcond_compare_zero_into_direct_jump
    // Purpose: consume bool materialization compare in front of conditional jump.
    // Example: setcc r11; cmp r11, 0; je L0 -> setcc r11; j!cc L0
    outRules.emplace_back(RuleTarget::AnyInstruction, foldSetCondCompareZeroIntoDirectJump);

    // Rule: fold_bool_and_chain_into_direct_jumps
    // Purpose: replace materialized bool-and chains with direct conditional branches.
    // Example: cmp/setcc/.../and/cmp/jz L0 -> cmp/jcc L0; cmp/jcc L0
    outRules.emplace_back(RuleTarget::AnyInstruction, foldBoolAndChainIntoDirectJumps);

    // Rule: fold_setcond_zeroext_copy
    // Purpose: route setcc and zero-extend directly to final destination register.
    // Example: setcc r10; zero_extend r10; mov rax, r10 -> setcc rax; zero_extend rax
    outRules.emplace_back(RuleTarget::AnyInstruction, foldSetCondZeroExtCopy);

    // Rule: fold_clearreg_into_next_mem_store_zero
    // Purpose: store zero immediate directly to memory instead of through a cleared temp register.
    // Example: xor rdx, rdx; mov [rsp], rdx -> mov [rsp], 0
    outRules.emplace_back(RuleTarget::AnyInstruction, foldClearRegIntoNextMemStoreZero);

    // Rule: remove_redundant_stack_save_restore_around_immediate_shift
    // Purpose: remove save/restore pairs that became unnecessary after shift-count folding.
    // Example: mov [rsp+32], rcx; shl r8, 1; mov rcx, [rsp+32] -> shl r8, 1
    outRules.emplace_back(RuleTarget::AnyInstruction, removeRedundantStackSaveRestoreAroundImmediateShift);

    // Rule: remove_redundant_clear_before_convert_float_to_int
    // Purpose: remove clears of a destination register that is fully overwritten by cvtf2i.
    // Example: xor r10, r10; cvtf2i r10, xmm0 -> cvtf2i r10, xmm0
    outRules.emplace_back(RuleTarget::AnyInstruction, removeRedundantClearBeforeConvertFloatToInt);

    // Rule: remove_no_op_instruction
    // Purpose: remove encoder-level no-op instructions.
    // Example: mov r8, r8 -> <removed>
    outRules.emplace_back(RuleTarget::AnyInstruction, removeNoOpInstruction);
}
SWC_END_NAMESPACE();
