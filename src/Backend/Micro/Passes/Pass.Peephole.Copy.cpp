#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Micro/Passes/Pass.Peephole.Private.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
        bool forwardCopyIntoNextBinarySource(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroReg copyDstReg = ops[0].reg;
            const MicroReg copySrcReg = ops[1].reg;
            if (!copyDstReg.isSameClass(copySrcReg))
                return false;

            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&  scanInst = *scanIt;
                MicroInstrOperand* scanOps  = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                const MicroInstrUseDef useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                if (useDef.isCall || MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                    return false;

                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);

                bool hasUse = false;
                bool hasDef = false;
                bool srcDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    const MicroReg reg = *SWC_NOT_NULL(ref.reg);
                    if (reg == copyDstReg)
                    {
                        hasUse |= ref.use;
                        hasDef |= ref.def;
                    }
                    else if (reg == copySrcReg && ref.def)
                    {
                        srcDef = true;
                    }
                }

                if (srcDef)
                    return false;

                if (!hasUse)
                {
                    if (hasDef)
                        return false;
                    continue;
                }

                if (scanInst.op != MicroInstrOpcode::OpBinaryRegReg)
                    return false;
                if (scanOps[1].reg != copyDstReg)
                    return false;
                if (scanOps[0].reg == copyDstReg)
                    return false;
                if (getNumBits(ops[2].opBits) < getNumBits(scanOps[2].opBits))
                    return false;
                if (!isCopyDeadAfterInstruction(context, std::next(scanIt), endIt, copyDstReg))
                    return false;

                const MicroReg originalSrcReg = scanOps[1].reg;
                scanOps[1].reg                = copySrcReg;
                if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    scanOps[1].reg = originalSrcReg;
                    return false;
                }

                SWC_NOT_NULL(context.instructions)->erase(instRef);
                return true;
            }

            return false;
        }

        bool forwardCopyIntoFollowingCopySource(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroReg copyDstReg = ops[0].reg;
            const MicroReg copySrcReg = ops[1].reg;
            if (!copyDstReg.isSameClass(copySrcReg))
                return false;

            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&  scanInst = *scanIt;
                MicroInstrOperand* scanOps  = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                const MicroInstrUseDef useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                if (useDef.isCall || MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                    return false;

                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);

                bool hasUse = false;
                bool hasDef = false;
                bool srcDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    const MicroReg reg = *SWC_NOT_NULL(ref.reg);
                    if (reg == copyDstReg)
                    {
                        hasUse |= ref.use;
                        hasDef |= ref.def;
                    }
                    else if (reg == copySrcReg && ref.def)
                    {
                        srcDef = true;
                    }
                }

                if (srcDef)
                    return false;

                if (!hasUse)
                {
                    if (hasDef)
                        return false;
                    continue;
                }

                if (scanInst.op != MicroInstrOpcode::LoadRegReg)
                    return false;
                if (scanOps[1].reg != copyDstReg)
                    return false;
                if (getNumBits(ops[2].opBits) < getNumBits(scanOps[2].opBits))
                    return false;
                if (!isCopyDeadAfterInstruction(context, std::next(scanIt), endIt, copyDstReg))
                    return false;

                const MicroReg originalSrcReg = scanOps[1].reg;
                scanOps[1].reg                = copySrcReg;
                if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    scanOps[1].reg = originalSrcReg;
                    return false;
                }

                SWC_NOT_NULL(context.instructions)->erase(instRef);
                return true;
            }

            return false;
        }

        bool forwardCopyIntoRetRegionSourceUses(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroReg copyDstReg = ops[0].reg;
            const MicroReg copySrcReg = ops[1].reg;
            if (!copyDstReg.isSameClass(copySrcReg))
                return false;
            const MicroReg stackPointerReg = CallConv::get(context.callConvKind).stackPointer;
            if (copyDstReg == stackPointerReg || copySrcReg == stackPointerReg)
                return false;
            if (ops[2].opBits != MicroOpBits::B64)
                return false;

            bool reachedRet  = false;
            bool replacedUse = false;

            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&        scanInst = *scanIt;
                const MicroInstrOperand* scanOps  = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                const MicroInstrUseDef useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                if (useDef.isCall)
                    return false;
                if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                {
                    if (scanInst.op != MicroInstrOpcode::Ret)
                        return false;
                    reachedRet = true;
                    break;
                }

                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);

                bool hasUse = false;
                bool hasDef = false;
                bool srcDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    const MicroReg reg = *SWC_NOT_NULL(ref.reg);
                    if (reg == copyDstReg)
                    {
                        hasUse |= ref.use;
                        hasDef |= ref.def;
                    }
                    else if (reg == copySrcReg && ref.def)
                    {
                        srcDef = true;
                    }
                }

                if (srcDef || hasDef)
                    return false;
                if (!hasUse)
                    continue;

                SmallVector<MicroReg*> replaced;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg || !ref.use)
                        continue;

                    MicroReg& reg = *SWC_NOT_NULL(ref.reg);
                    if (reg != copyDstReg)
                        continue;

                    reg = copySrcReg;
                    replaced.push_back(&reg);
                }

                if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    for (MicroReg* reg : replaced)
                        *SWC_NOT_NULL(reg) = copyDstReg;
                    return false;
                }

                replacedUse = true;
            }

            if (!reachedRet || !replacedUse)
                return false;
            if (!isRegUnusedAfterInstruction(context, nextIt, endIt, copyDstReg))
                return false;

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool forwardCopyIntoNextCompareSource(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroInstr&  nextInst = *nextIt;
            MicroInstrOperand* nextOps  = nextInst.ops(*SWC_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            const MicroReg copyDstReg = ops[0].reg;
            const MicroReg copySrcReg = ops[1].reg;
            if (!copyDstReg.isSameClass(copySrcReg))
                return false;

            bool replacesOperand = false;

            if (nextInst.op == MicroInstrOpcode::CmpRegReg)
            {
                if (ops[2].opBits != nextOps[2].opBits)
                    return false;

                if (nextOps[0].reg == copyDstReg)
                {
                    nextOps[0].reg  = copySrcReg;
                    replacesOperand = true;
                }

                if (nextOps[1].reg == copyDstReg)
                {
                    nextOps[1].reg  = copySrcReg;
                    replacesOperand = true;
                }
            }
            else if (nextInst.op == MicroInstrOpcode::CmpRegImm)
            {
                if (ops[2].opBits != nextOps[1].opBits)
                    return false;

                if (nextOps[0].reg == copyDstReg)
                {
                    nextOps[0].reg  = copySrcReg;
                    replacesOperand = true;
                }
            }
            else
            {
                return false;
            }

            if (!replacesOperand)
                return false;

            if (!isCopyDeadAfterInstruction(context, std::next(nextIt), endIt, copyDstReg))
                return false;

            if (MicroOptimization::violatesEncoderConformance(context, nextInst, nextOps))
                return false;

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool foldCopyIntoNextMemoryBase(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroReg copyDstReg = ops[0].reg;
            const MicroReg copySrcReg = ops[1].reg;
            if (!copyDstReg.isSameClass(copySrcReg))
                return false;
            if (ops[2].opBits != MicroOpBits::B64)
                return false;

            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&  scanInst = *scanIt;
                MicroInstrOperand* scanOps  = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                const MicroInstrUseDef useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                if (useDef.isCall || MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                    return false;

                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);

                bool hasUse = false;
                bool hasDef = false;
                bool srcDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    const MicroReg reg = *SWC_NOT_NULL(ref.reg);
                    if (reg == copyDstReg)
                    {
                        hasUse |= ref.use;
                        hasDef |= ref.def;
                    }
                    else if (reg == copySrcReg && ref.def)
                    {
                        srcDef = true;
                    }
                }

                if (srcDef)
                    return false;

                if (!hasUse)
                {
                    if (hasDef)
                        return false;
                    continue;
                }

                uint8_t baseIndex = 0;
                switch (scanInst.op)
                {
                    case MicroInstrOpcode::LoadRegMem:
                        if (scanOps[0].reg == copyDstReg)
                            return false;
                        baseIndex = 1;
                        break;
                    case MicroInstrOpcode::LoadMemReg:
                        if (scanOps[1].reg == copyDstReg)
                            return false;
                        baseIndex = 0;
                        break;
                    case MicroInstrOpcode::LoadMemImm:
                        baseIndex = 0;
                        break;
                    default:
                        return false;
                }

                if (hasDef || scanOps[baseIndex].reg != copyDstReg)
                    return false;

                const MicroReg originalBaseReg = scanOps[baseIndex].reg;
                scanOps[baseIndex].reg         = copySrcReg;
                if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    scanOps[baseIndex].reg = originalBaseReg;
                    return false;
                }

                if (!isRegUnusedAfterInstruction(context, std::next(scanIt), endIt, copyDstReg))
                {
                    scanOps[baseIndex].reg = originalBaseReg;
                    return false;
                }

                SWC_NOT_NULL(context.instructions)->erase(instRef);
                return true;
            }

            return false;
        }

        bool classifyRegUseDef(const MicroPassContext& context, const MicroInstr& inst, MicroReg reg, bool& outUse, bool& outDef)
        {
            outUse = false;
            outDef = false;

            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);
            for (const MicroInstrRegOperandRef& ref : refs)
            {
                if (!ref.reg || *SWC_NOT_NULL(ref.reg) != reg)
                    continue;

                outUse |= ref.use;
                outDef |= ref.def;
            }

            return outUse || outDef;
        }

        bool rewriteAccumulatorInstruction(const MicroInstr& inst, MicroInstrOperand* instOps, MicroReg fromReg, MicroReg toReg)
        {
            if (!instOps)
                return false;

            switch (inst.op)
            {
                case MicroInstrOpcode::LoadRegReg:
                    if (instOps[0].reg != fromReg)
                        return false;
                    instOps[0].reg = toReg;
                    if (instOps[1].reg == fromReg)
                        instOps[1].reg = toReg;
                    return true;

                case MicroInstrOpcode::LoadRegImm:
                case MicroInstrOpcode::LoadRegPtrImm:
                case MicroInstrOpcode::LoadRegPtrReloc:
                    if (instOps[0].reg != fromReg)
                        return false;
                    instOps[0].reg = toReg;
                    return true;

                case MicroInstrOpcode::LoadRegMem:
                    if (instOps[0].reg != fromReg)
                        return false;
                    instOps[0].reg = toReg;
                    if (instOps[1].reg == fromReg)
                        instOps[1].reg = toReg;
                    return true;

                case MicroInstrOpcode::OpBinaryRegMem:
                    if (instOps[0].reg != fromReg)
                        return false;
                    instOps[0].reg = toReg;
                    if (instOps[1].reg == fromReg)
                        instOps[1].reg = toReg;
                    return true;

                case MicroInstrOpcode::OpBinaryRegImm:
                    if (instOps[0].reg != fromReg)
                        return false;
                    instOps[0].reg = toReg;
                    return true;

                case MicroInstrOpcode::OpBinaryRegReg:
                    if (instOps[0].reg != fromReg)
                        return false;
                    instOps[0].reg = toReg;
                    if (instOps[1].reg == fromReg)
                        instOps[1].reg = toReg;
                    return true;

                case MicroInstrOpcode::OpUnaryReg:
                    if (instOps[0].reg != fromReg)
                        return false;
                    instOps[0].reg = toReg;
                    return true;

                default:
                    return false;
            }
        }

        bool foldRetCopyIntoAccumulator(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroReg retReg = ops[0].reg;
            const MicroReg accReg = ops[1].reg;
            if (!retReg.isSameClass(accReg))
                return false;

            MicroStorage::Iterator retIt                 = endIt;
            bool                   accValueLiveAfterCopy = true;
            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                const MicroInstr& scanInst = *scanIt;
                if (scanInst.op == MicroInstrOpcode::Ret)
                {
                    retIt = scanIt;
                    break;
                }

                const MicroInstrUseDef useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                if (useDef.isCall || MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                    return false;

                if (!accValueLiveAfterCopy)
                    continue;

                bool usesAcc = false;
                bool defsAcc = false;
                classifyRegUseDef(context, scanInst, accReg, usesAcc, defsAcc);
                if (usesAcc)
                    return false;
                if (defsAcc)
                    accValueLiveAfterCopy = false;
            }

            if (retIt == endIt)
                return false;

            struct RewritePlan
            {
                MicroInstrRef                  ref = MicroInstrRef::invalid();
                SmallVector<MicroInstrOperand> rewrittenOps;
            };

            SmallVector<RewritePlan> rewritePlans;
            bool                     foundRootDef = false;

            MicroStorage::Iterator scanIt{SWC_NOT_NULL(context.instructions), instRef};
            while (scanIt.current.isValid())
            {
                --scanIt;
                if (scanIt.current.isInvalid())
                    break;

                const MicroInstr& scanInst = *scanIt;

                const MicroInstrUseDef useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                if (useDef.isCall || MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                    return false;

                bool usesRet = false;
                bool defsRet = false;
                classifyRegUseDef(context, scanInst, retReg, usesRet, defsRet);
                if (usesRet || defsRet)
                    return false;

                bool usesAcc = false;
                bool defsAcc = false;
                if (!classifyRegUseDef(context, scanInst, accReg, usesAcc, defsAcc))
                    continue;

                const MicroInstrOperand* scanOps = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                RewritePlan plan;
                plan.ref = scanIt.current;
                plan.rewrittenOps.reserve(scanInst.numOperands);
                for (uint8_t opIdx = 0; opIdx < scanInst.numOperands; ++opIdx)
                    plan.rewrittenOps.push_back(scanOps[opIdx]);

                if (!rewriteAccumulatorInstruction(scanInst, plan.rewrittenOps.data(), accReg, retReg))
                    return false;
                if (MicroOptimization::violatesEncoderConformance(context, scanInst, plan.rewrittenOps.data()))
                    return false;

                rewritePlans.push_back(std::move(plan));

                if (defsAcc && !usesAcc)
                {
                    foundRootDef = true;
                    break;
                }
            }

            if (!foundRootDef || rewritePlans.empty())
                return false;

            for (RewritePlan& plan : rewritePlans)
            {
                const MicroInstr* instPtr = SWC_NOT_NULL(context.instructions)->ptr(plan.ref);
                if (!instPtr)
                    return false;

                MicroInstrOperand* instOps = instPtr->ops(*SWC_NOT_NULL(context.operands));
                if (!instOps || instPtr->numOperands != plan.rewrittenOps.size())
                    return false;

                for (uint8_t opIdx = 0; opIdx < instPtr->numOperands; ++opIdx)
                    instOps[opIdx] = plan.rewrittenOps[opIdx];
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool foldCopyIntoNextSelfLoadMem(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroReg copyDstReg = ops[0].reg;
            const MicroReg copySrcReg = ops[1].reg;
            if (!copyDstReg.isSameClass(copySrcReg))
                return false;

            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&  scanInst = *scanIt;
                MicroInstrOperand* scanOps  = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                const MicroInstrUseDef useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                if (useDef.isCall || MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                    return false;

                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);

                bool usesCopyDst = false;
                bool defsCopyDst = false;
                bool defsCopySrc = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    const MicroReg reg = *SWC_NOT_NULL(ref.reg);
                    if (reg == copyDstReg)
                    {
                        usesCopyDst |= ref.use;
                        defsCopyDst |= ref.def;
                    }

                    if (reg == copySrcReg && ref.def)
                        defsCopySrc = true;
                }

                if (defsCopySrc)
                    return false;
                if (!usesCopyDst)
                {
                    if (defsCopyDst)
                        return false;
                    continue;
                }

                if (scanInst.op != MicroInstrOpcode::LoadRegMem)
                    return false;
                if (scanOps[0].reg != copyDstReg || scanOps[1].reg != copyDstReg)
                    return false;

                const MicroReg originalBaseReg = scanOps[1].reg;
                scanOps[1].reg                 = copySrcReg;
                if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    scanOps[1].reg = originalBaseReg;
                    return false;
                }

                SWC_NOT_NULL(context.instructions)->erase(instRef);
                return true;
            }

            return false;
        }

        bool foldCopyTwinLoadMemReuse(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroStorage::Iterator firstLoadIt = nextIt;
            if (firstLoadIt == endIt)
                return false;

            const MicroStorage::Iterator secondLoadIt = std::next(firstLoadIt);
            if (secondLoadIt == endIt)
                return false;

            const MicroInstr& firstLoadInst = *firstLoadIt;
            if (firstLoadInst.op != MicroInstrOpcode::LoadRegMem)
                return false;

            MicroInstr& secondLoadInst = *secondLoadIt;
            if (secondLoadInst.op != MicroInstrOpcode::LoadRegMem)
                return false;

            MicroInstrOperand* firstLoadOps  = firstLoadInst.ops(*SWC_NOT_NULL(context.operands));
            MicroInstrOperand* secondLoadOps = secondLoadInst.ops(*SWC_NOT_NULL(context.operands));
            if (!firstLoadOps || !secondLoadOps)
                return false;

            const MicroReg copiedBaseReg = ops[0].reg;
            const MicroReg baseSrcReg    = ops[1].reg;
            if (!copiedBaseReg.isSameClass(baseSrcReg))
                return false;

            if (firstLoadOps[1].reg != copiedBaseReg || secondLoadOps[1].reg != copiedBaseReg)
                return false;
            if (firstLoadOps[0].reg != baseSrcReg)
                return false;
            if (firstLoadOps[0].reg == secondLoadOps[0].reg)
                return false;
            if (!firstLoadOps[0].reg.isSameClass(secondLoadOps[0].reg))
                return false;
            if (firstLoadOps[2].opBits != secondLoadOps[2].opBits)
                return false;
            if (firstLoadOps[3].valueU64 != secondLoadOps[3].valueU64)
                return false;
            if (!isCopyDeadAfterInstruction(context, std::next(secondLoadIt), endIt, copiedBaseReg))
                return false;

            const std::array       originalFirstLoadOps  = {firstLoadOps[0], firstLoadOps[1], firstLoadOps[2], firstLoadOps[3]};
            const std::array       originalSecondLoadOps = {secondLoadOps[0], secondLoadOps[1], secondLoadOps[2], secondLoadOps[3]};
            const MicroInstrOpcode originalSecondLoadOp  = secondLoadInst.op;

            firstLoadOps[1].reg = baseSrcReg;
            if (MicroOptimization::violatesEncoderConformance(context, firstLoadInst, firstLoadOps))
            {
                for (uint32_t i = 0; i < 4; ++i)
                    firstLoadOps[i] = originalFirstLoadOps[i];
                return false;
            }

            const MicroReg copiedValueReg = firstLoadOps[0].reg;
            secondLoadInst.op             = MicroInstrOpcode::LoadRegReg;
            secondLoadOps[0].reg          = originalSecondLoadOps[0].reg;
            secondLoadOps[1].reg          = copiedValueReg;
            secondLoadOps[2].opBits       = originalSecondLoadOps[2].opBits;
            secondLoadOps[3].valueU64     = 0;
            if (MicroOptimization::violatesEncoderConformance(context, secondLoadInst, secondLoadOps))
            {
                for (uint32_t i = 0; i < 4; ++i)
                    firstLoadOps[i] = originalFirstLoadOps[i];
                secondLoadInst.op = originalSecondLoadOp;
                for (uint32_t i = 0; i < 4; ++i)
                    secondLoadOps[i] = originalSecondLoadOps[i];
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool foldCopyOpCopyBack(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroStorage::Iterator opIt       = nextIt;
            const MicroStorage::Iterator copyBackIt = std::next(opIt);
            if (copyBackIt == endIt)
                return false;

            const MicroInstr&        opInst = *opIt;
            const MicroInstrOperand* opOps  = opInst.ops(*SWC_NOT_NULL(context.operands));
            if (opInst.op != MicroInstrOpcode::OpBinaryRegReg || !opOps)
                return false;

            const MicroInstr&        copyBackInst = *copyBackIt;
            const MicroInstrOperand* copyBackOps  = copyBackInst.ops(*SWC_NOT_NULL(context.operands));
            if (copyBackInst.op != MicroInstrOpcode::LoadRegReg || !copyBackOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            const MicroReg srcReg = ops[1].reg;
            if (!tmpReg.isSameClass(srcReg))
                return false;
            if (opOps[0].reg != tmpReg)
                return false;
            if (copyBackOps[0].reg != srcReg || copyBackOps[1].reg != tmpReg)
                return false;
            if (ops[2].opBits != opOps[2].opBits || ops[2].opBits != copyBackOps[2].opBits)
                return false;
            if (opOps[1].reg == srcReg)
                return false;

            MicroInstrOperand* mutableOpOps   = opInst.ops(*SWC_NOT_NULL(context.operands));
            const MicroReg     originalDstReg = mutableOpOps[0].reg;
            mutableOpOps[0].reg               = srcReg;
            if (MicroOptimization::violatesEncoderConformance(context, opInst, mutableOpOps))
            {
                mutableOpOps[0].reg = originalDstReg;
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            SWC_NOT_NULL(context.instructions)->erase(copyBackIt.current);
            return true;
        }

        bool foldCopySwapAddIntoAccumulator(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroStorage::Iterator copySwapIt = nextIt;
            const MicroStorage::Iterator opIt       = std::next(copySwapIt);
            if (opIt == endIt)
                return false;

            const MicroStorage::Iterator accIt = std::next(opIt);
            if (accIt == endIt)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            const MicroReg idxReg = ops[1].reg;
            if (!tmpReg.isSameClass(idxReg) || tmpReg == idxReg)
                return false;

            const MicroInstr&        copySwapInst = *copySwapIt;
            const MicroInstrOperand* copySwapOps  = copySwapInst.ops(*SWC_NOT_NULL(context.operands));
            if (copySwapInst.op != MicroInstrOpcode::LoadRegReg || !copySwapOps)
                return false;
            if (copySwapOps[0].reg != idxReg || !copySwapOps[1].reg.isSameClass(idxReg))
                return false;
            if (copySwapOps[2].opBits != ops[2].opBits)
                return false;

            const MicroReg valueReg = copySwapOps[1].reg;
            if (valueReg == idxReg || valueReg == tmpReg)
                return false;

            const MicroInstr&        opInst = *opIt;
            const MicroInstrOperand* opOps  = opInst.ops(*SWC_NOT_NULL(context.operands));
            if (opInst.op != MicroInstrOpcode::OpBinaryRegReg || !opOps)
                return false;
            if (opOps[0].reg != idxReg || opOps[1].reg != tmpReg)
                return false;
            if (opOps[2].opBits != ops[2].opBits)
                return false;
            if (opOps[3].microOp != MicroOp::Add)
                return false;

            const MicroInstr&        accInst = *accIt;
            const MicroInstrOperand* accOps  = accInst.ops(*SWC_NOT_NULL(context.operands));
            if (accInst.op != MicroInstrOpcode::OpBinaryMemReg || !accOps)
                return false;
            if (accOps[1].reg != idxReg || accOps[2].opBits != opOps[2].opBits)
                return false;
            if (accOps[3].microOp != MicroOp::Add)
                return false;

            if (!isCopyDeadAfterInstruction(context, std::next(accIt), endIt, idxReg))
                return false;
            if (!isCopyDeadAfterInstruction(context, std::next(accIt), endIt, valueReg))
                return false;

            MicroInstrOperand* mutableOpOps  = opInst.ops(*SWC_NOT_NULL(context.operands));
            MicroInstrOperand* mutableAccOps = accInst.ops(*SWC_NOT_NULL(context.operands));
            if (!mutableOpOps || !mutableAccOps)
                return false;

            const MicroReg originalOpDst   = mutableOpOps[0].reg;
            const MicroReg originalOpSrc   = mutableOpOps[1].reg;
            const MicroReg originalAccSrc  = mutableAccOps[1].reg;
            mutableOpOps[0].reg            = valueReg;
            mutableOpOps[1].reg            = idxReg;
            mutableAccOps[1].reg           = valueReg;

            if (MicroOptimization::violatesEncoderConformance(context, opInst, mutableOpOps) ||
                MicroOptimization::violatesEncoderConformance(context, accInst, mutableAccOps))
            {
                mutableOpOps[0].reg  = originalOpDst;
                mutableOpOps[1].reg  = originalOpSrc;
                mutableAccOps[1].reg = originalAccSrc;
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            SWC_NOT_NULL(context.instructions)->erase(copySwapIt.current);
            return true;
        }

        bool foldCopyUnaryCopyBack(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroStorage::Iterator unaryIt    = nextIt;
            const MicroStorage::Iterator copyBackIt = std::next(unaryIt);
            if (copyBackIt == endIt)
                return false;

            const MicroInstr& unaryInst = *unaryIt;
            if (unaryInst.op != MicroInstrOpcode::OpUnaryReg)
                return false;

            MicroInstrOperand* unaryOps = unaryInst.ops(*SWC_NOT_NULL(context.operands));
            if (!unaryOps)
                return false;

            const MicroInstr&        copyBackInst = *copyBackIt;
            const MicroInstrOperand* copyBackOps  = copyBackInst.ops(*SWC_NOT_NULL(context.operands));
            if (copyBackInst.op != MicroInstrOpcode::LoadRegReg || !copyBackOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            const MicroReg srcReg = ops[1].reg;
            if (!tmpReg.isSameClass(srcReg))
                return false;

            if (unaryOps[0].reg != tmpReg)
                return false;
            if (copyBackOps[0].reg != srcReg || copyBackOps[1].reg != tmpReg)
                return false;

            if (ops[2].opBits != unaryOps[1].opBits || ops[2].opBits != copyBackOps[2].opBits)
                return false;

            const MicroReg originalDstReg = unaryOps[0].reg;
            unaryOps[0].reg               = srcReg;
            if (MicroOptimization::violatesEncoderConformance(context, unaryInst, unaryOps))
            {
                unaryOps[0].reg = originalDstReg;
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            SWC_NOT_NULL(context.instructions)->erase(copyBackIt.current);
            return true;
        }

        bool foldTailCopyBinaryIntoSource(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroReg copyDstReg = ops[0].reg;
            const MicroReg copySrcReg = ops[1].reg;
            if (copyDstReg == copySrcReg || !copyDstReg.isSameClass(copySrcReg))
                return false;
            if (copyDstReg.isInstructionPointer() || copySrcReg.isInstructionPointer())
                return false;

            const MicroReg stackPointerReg = context.encoder ? context.encoder->stackPointerReg() : MicroReg::invalid();
            if (stackPointerReg.isValid() && (copyDstReg == stackPointerReg || copySrcReg == stackPointerReg))
                return false;

            const CallConv& functionConv = CallConv::get(context.callConvKind);
            if (copySrcReg == functionConv.intReturn || copySrcReg == functionConv.floatReturn)
                return false;

            const MicroInstr& nextInst = *nextIt;
            if (nextInst.op != MicroInstrOpcode::OpBinaryRegReg)
                return false;

            const MicroInstrOperand* nextOps = nextInst.ops(*SWC_NOT_NULL(context.operands));
            if (!nextOps)
                return false;
            if (nextOps[0].reg != copyDstReg)
                return false;
            if (getNumBits(ops[2].opBits) < getNumBits(nextOps[2].opBits))
                return false;

            struct RegisterRewrite
            {
                MicroReg* reg;
                MicroReg  original;
            };

            SmallVector<RegisterRewrite> rewrites;
            bool                         reachedRet  = false;
            bool                         replacedAny = false;
            bool                         failed      = false;

            const auto rollback = [&rewrites]() {
                for (auto itRewrite = rewrites.rbegin(); itRewrite != rewrites.rend(); ++itRewrite)
                    SWC_NOT_NULL(itRewrite->reg)->packed = itRewrite->original.packed;
            };

            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&      scanInst = *scanIt;
                const MicroInstrUseDef useDef   = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                {
                    if (scanInst.op == MicroInstrOpcode::Ret)
                    {
                        reachedRet = true;
                        break;
                    }

                    failed = true;
                    break;
                }

                const bool isBinaryMutation = scanIt.current == nextIt.current;

                const MicroInstrOperand* scanOps = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (!scanOps)
                {
                    failed = true;
                    break;
                }

                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);

                bool changedInstruction = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    MicroReg& reg = *SWC_NOT_NULL(ref.reg);
                    if (reg == copySrcReg && !isBinaryMutation)
                    {
                        failed = true;
                        break;
                    }

                    if (reg != copyDstReg)
                        continue;

                    if (!ref.use)
                    {
                        failed = true;
                        break;
                    }

                    if (ref.def && !isBinaryMutation)
                    {
                        failed = true;
                        break;
                    }

                    rewrites.push_back({&reg, reg});
                    reg                = copySrcReg;
                    changedInstruction = true;
                }

                if (failed)
                    break;

                if (!isBinaryMutation && changedInstruction)
                    replacedAny = true;

                if (changedInstruction && MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    failed = true;
                    break;
                }
            }

            if (!reachedRet || failed || rewrites.empty())
            {
                rollback();
                return false;
            }

            if (!replacedAny)
            {
                rollback();
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool analyzeCopyCoalescing(const MicroPassContext& context, bool& outSawMutation, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg dstReg, MicroReg srcReg)
        {
            bool canCoalesce       = true;
            bool sawReplaceableUse = false;
            bool seenMutation      = false;

            for (; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&      scanInst = *scanIt;
                const MicroInstrUseDef useDef   = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                {
                    // Linear scan cannot prove liveness across control-flow barriers.
                    // Be conservative and keep the copy in place.
                    canCoalesce = false;
                    break;
                }

                const MicroInstrOperand* scanOps = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (scanInst.op == MicroInstrOpcode::LoadRegReg && scanOps && scanOps[0].reg == srcReg && scanOps[1].reg == dstReg)
                {
                    canCoalesce = false;
                    break;
                }

                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    const MicroReg reg = *SWC_NOT_NULL(ref.reg);
                    if (reg == srcReg)
                    {
                        if (seenMutation || ref.def)
                        {
                            canCoalesce = false;
                            break;
                        }
                    }

                    if (reg == dstReg)
                    {
                        if (ref.def && !ref.use)
                        {
                            canCoalesce = false;
                            break;
                        }

                        if (ref.use && ref.def)
                        {
                            seenMutation      = true;
                            sawReplaceableUse = true;
                            continue;
                        }

                        if (ref.use)
                        {
                            MicroReg&      mutableReg  = *SWC_NOT_NULL(ref.reg);
                            const MicroReg originalReg = mutableReg;
                            mutableReg                 = srcReg;
                            if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                            {
                                mutableReg  = originalReg;
                                canCoalesce = false;
                                break;
                            }

                            mutableReg        = originalReg;
                            sawReplaceableUse = true;
                        }
                    }
                }

                if (!canCoalesce)
                    break;
            }

            outSawMutation = seenMutation;
            return canCoalesce && sawReplaceableUse;
        }

        bool applyCopyCoalescing(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg dstReg, MicroReg srcReg)
        {
            bool changed = false;

            for (; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&      scanInst = *scanIt;
                const MicroInstrUseDef useDef   = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                    break;

                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    MicroReg& reg = *SWC_NOT_NULL(ref.reg);
                    if (reg != dstReg || !ref.use)
                        continue;

                    reg     = srcReg;
                    changed = true;
                }
            }

            return changed;
        }

        bool coalesceCopyInstruction(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef   = cursor.instRef;
            const MicroInstrOperand*     ops       = cursor.ops;
            const MicroStorage::Iterator scanBegin = cursor.nextIt;
            const MicroStorage::Iterator endIt     = cursor.endIt;
            if (!ops)
                return false;

            const MicroReg dstReg = ops[0].reg;
            const MicroReg srcReg = ops[1].reg;
            if (dstReg == srcReg || !dstReg.isSameClass(srcReg))
                return false;

            bool sawMutation = false;
            if (!analyzeCopyCoalescing(context, sawMutation, scanBegin, endIt, dstReg, srcReg))
                return false;

            if (!applyCopyCoalescing(context, scanBegin, endIt, dstReg, srcReg))
                return false;

            SWC_UNUSED(sawMutation);
            SWC_NOT_NULL(context.instructions)->erase(instRef);

            return true;
        }

        bool removeOverwrittenCopy(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroInstr&        nextInst = *nextIt;
            const MicroInstrOperand* nextOps  = nextInst.ops(*SWC_NOT_NULL(context.operands));
            if (nextInst.op != MicroInstrOpcode::LoadRegReg || !nextOps)
                return false;

            if (ops[0].reg != nextOps[0].reg || ops[2].opBits != nextOps[2].opBits)
                return false;

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool removeUnusedCopyDestination(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef      instRef = cursor.instRef;
            const MicroInstr*        inst    = cursor.inst;
            const MicroInstrOperand* ops     = cursor.ops;
            if (!inst || inst->op != MicroInstrOpcode::LoadRegReg || !ops)
                return false;

            const MicroReg dstReg = ops[0].reg;
            const MicroReg srcReg = ops[1].reg;
            if (dstReg == srcReg || !dstReg.isSameClass(srcReg))
                return false;

            if (dstReg.isInstructionPointer())
                return false;

            const MicroReg stackPointerReg = context.encoder ? context.encoder->stackPointerReg() : MicroReg::invalid();
            if (stackPointerReg.isValid() && dstReg == stackPointerReg)
                return false;

            if (!isRegUnusedAfterInstruction(context, cursor.nextIt, cursor.endIt, dstReg))
                return false;

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool removeDeadCopyBeforeUse(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef      instRef = cursor.instRef;
            const MicroInstr*        inst    = cursor.inst;
            const MicroInstrOperand* ops     = cursor.ops;
            if (!inst || inst->op != MicroInstrOpcode::LoadRegReg || !ops)
                return false;

            const MicroReg dstReg = ops[0].reg;
            const MicroReg srcReg = ops[1].reg;
            if (dstReg == srcReg || !dstReg.isSameClass(srcReg))
                return false;

            if (dstReg.isInstructionPointer())
                return false;

            const MicroReg stackPointerReg = context.encoder ? context.encoder->stackPointerReg() : MicroReg::invalid();
            if (stackPointerReg.isValid() && dstReg == stackPointerReg)
                return false;

            if (!isCopyDeadAfterInstruction(context, cursor.nextIt, cursor.endIt, dstReg))
                return false;

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool foldCopyBackWithPreviousOp(const MicroPassContext& context, const Cursor& cursor)
        {
            if (!cursor.ops)
                return false;

            MicroStorage::Iterator currentIt = cursor.nextIt;
            --currentIt;
            if (currentIt.current.isInvalid())
                return false;

            MicroStorage::Iterator prevOpIt = currentIt;
            --prevOpIt;
            if (prevOpIt.current.isInvalid())
                return false;

            MicroStorage::Iterator prevCopyIt = prevOpIt;
            --prevCopyIt;
            if (prevCopyIt.current.isInvalid())
                return false;

            const MicroInstr&        prevOpInst = *prevOpIt;
            const MicroInstrOperand* prevOpOps  = prevOpInst.ops(*SWC_NOT_NULL(context.operands));
            if (prevOpInst.op != MicroInstrOpcode::OpBinaryRegReg || !prevOpOps)
                return false;

            const MicroInstr&        prevCopyInst = *prevCopyIt;
            const MicroInstrOperand* prevCopyOps  = prevCopyInst.ops(*SWC_NOT_NULL(context.operands));
            if (prevCopyInst.op != MicroInstrOpcode::LoadRegReg || !prevCopyOps)
                return false;

            const MicroReg origReg = cursor.ops[0].reg;
            const MicroReg tmpReg  = cursor.ops[1].reg;
            if (!origReg.isSameClass(tmpReg))
                return false;

            if (prevOpOps[0].reg != tmpReg)
                return false;
            if (prevCopyOps[0].reg != tmpReg || prevCopyOps[1].reg != origReg)
                return false;
            if (prevOpOps[1].reg == origReg)
                return false;
            if (cursor.ops[2].opBits != prevOpOps[2].opBits || cursor.ops[2].opBits != prevCopyOps[2].opBits)
                return false;

            MicroInstrOperand* mutablePrevOpOps = prevOpInst.ops(*SWC_NOT_NULL(context.operands));
            if (!mutablePrevOpOps)
                return false;

            const MicroReg originalReg = prevOpOps[0].reg;
            mutablePrevOpOps[0].reg    = origReg;
            if (MicroOptimization::violatesEncoderConformance(context, prevOpInst, mutablePrevOpOps))
            {
                mutablePrevOpOps[0].reg = originalReg;
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(prevCopyIt.current);
            SWC_NOT_NULL(context.instructions)->erase(cursor.instRef);
            return true;
        }
    }

    void appendCopyRules(RuleList& outRules)
    {
        // Rule: forward_copy_into_next_binary_source
        // Purpose: forward copied source register into the next binary operation source.
        // Example: mov r8, r11; and r5, r8 -> and r5, r11
        outRules.push_back({RuleTarget::LoadRegReg, forwardCopyIntoNextBinarySource});

        // Rule: forward_copy_into_following_copy_source
        // Purpose: forward copied source register into a following copy source across neutral instructions.
        // Example: mov r11, rcx; mov r10, rdx; mov r9, r11 -> mov r10, rdx; mov r9, rcx
        outRules.push_back({RuleTarget::LoadRegReg, forwardCopyIntoFollowingCopySource});

        // Rule: forward_copy_into_ret_region_sources
        // Purpose: forward a b64 copy into later source-only uses up to ret and remove the copy.
        // Example: mov r11, rcx; mov rax, r11; sub rax, r11; ret -> mov rax, rcx; sub rax, rcx; ret
        outRules.push_back({RuleTarget::LoadRegReg, forwardCopyIntoRetRegionSourceUses});

        // Rule: forward_copy_into_next_compare_source
        // Purpose: forward copied source register into next compare.
        // Example: mov r8, r11; cmp r8, 0 -> cmp r11, 0
        outRules.push_back({RuleTarget::LoadRegReg, forwardCopyIntoNextCompareSource});

        // Rule: fold_copy_into_next_memory_base
        // Purpose: fold copied base register into next memory access base.
        // Example: mov r10, rsp; mov [r10], xmm3 -> mov [rsp], xmm3
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyIntoNextMemoryBase});

        // Rule: fold_copy_into_next_self_load_mem
        // Purpose: fold copied base into later self-load memory form.
        // Example: mov r11, rcx; mov r9, rdx; mov r11, [r11] -> mov r9, rdx; mov r11, [rcx]
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyIntoNextSelfLoadMem});

        // Rule: fold_copy_twin_load_mem_reuse
        // Purpose: reuse first identical memory load result and remove copied-base register.
        // Example: mov r10, rdx; mov rdx, [r10]; mov r9, [r10] -> mov rdx, [rdx]; mov r9, rdx
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyTwinLoadMemReuse});

        // Rule: fold_ret_copy_into_accumulator
        // Purpose: retarget the final accumulator chain to return register and drop trailing copy.
        // Example: add rdx, [r8]; mov rax, rdx; ret -> add rax, [r8]; ret
        outRules.push_back({RuleTarget::LoadRegReg, foldRetCopyIntoAccumulator});

        // Rule: fold_copy_op_copy_back
        // Purpose: fold copy-to-temp + binary-op + copy-back into direct binary-op on a source.
        // Example: mov r8, r11; and r8, rdx; mov r11, r8 -> and r11, rdx
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyOpCopyBack});

        // Rule: fold_copy_swap_add_into_accumulator
        // Purpose: fold copy old-index + copy loaded-value + add + accumulator-store into direct add on loaded value.
        // Example: mov rax,r8; mov r8,rcx; add r8,rax; add [rsp+30],r8 -> add rcx,r8; add [rsp+30],rcx
        outRules.push_back({RuleTarget::LoadRegReg, foldCopySwapAddIntoAccumulator});

        // Rule: fold_copy_unary_copy_back
        // Purpose: fold copy-to-temp + unary-op + copy-back into direct unary-op on source.
        // Example: mov r8, r11; neg r8; mov r11, r8 -> neg r11
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyUnaryCopyBack});

        // Rule: fold_tail_copy_binary_into_source
        // Purpose: fold a copy + binary accumulator mutation near function tail into source register.
        // Example: mov r9, r8; add r9, r10; mov [rax], r9; mov rax, r9; ret -> add r8, r10; mov [rax], r8; mov rax, r8; ret
        outRules.push_back({RuleTarget::LoadRegReg, foldTailCopyBinaryIntoSource});

        // Rule: fold_copy_back_with_previous_op
        // Purpose: same fold as above, detected from trailing copy-back instruction.
        // Example: mov r8, r11; xor r8, rdx; mov r11, r8 -> xor r11, rdx
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyBackWithPreviousOp});

        // Rule: coalesce_copy_instruction
        // Purpose: rewrite downstream uses of copy destination to copy source and remove copy.
        // Example: mov r8, r11; add r9, r8; or r10, r8 -> add r9, r11; or r10, r11
        outRules.push_back({RuleTarget::LoadRegReg, coalesceCopyInstruction});

        // Rule: remove_unused_copy_destination
        // Purpose: remove a copy when the destination register is never used afterward.
        // Example: mov r9, r11; add rax, rcx -> add rax, rcx
        outRules.push_back({RuleTarget::LoadRegReg, removeUnusedCopyDestination});

        // Rule: remove_dead_copy_before_use
        // Purpose: remove a copy when the destination value dies before any reachable use.
        // Example: mov rbp, rsp; push rdi; mov rbp, rsp -> push rdi; mov rbp, rsp
        outRules.push_back({RuleTarget::LoadRegReg, removeDeadCopyBeforeUse});

        // Rule: remove_overwritten_copy
        // Purpose: remove a copy when the destination is immediately overwritten by another copy.
        // Example: mov r8, r11; mov r8, rdx -> mov r8, rdx
        outRules.push_back({RuleTarget::LoadRegReg, removeOverwrittenCopy});
    }
}

SWC_END_NAMESPACE();
