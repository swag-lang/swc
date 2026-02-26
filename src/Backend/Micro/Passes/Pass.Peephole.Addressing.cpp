#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Micro/Passes/Pass.Peephole.Private.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
        bool foldZeroIndexAmcFromImmediate(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            if (ops[2].valueU64 != 0)
                return false;
            if (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64)
                return false;

            const MicroReg indexReg = ops[0].reg;
            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                MicroInstr&        scanInst = *scanIt;
                MicroInstrOperand* scanOps  = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                const MicroInstrUseDef               useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);

                bool hasUse = false;
                bool hasDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg || *SWC_NOT_NULL(ref.reg) != indexReg)
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

                if (!isTempDeadForAddressFold(context, std::next(scanIt), endIt, indexReg))
                    return false;

                const MicroInstrOpcode           originalOp = scanInst.op;
                std::array<MicroInstrOperand, 8> originalOps{};
                const uint32_t                   numSnapshotOps = std::min(static_cast<uint32_t>(scanInst.numOperands), static_cast<uint32_t>(originalOps.size()));
                for (uint32_t i = 0; i < numSnapshotOps; ++i)
                    originalOps[i] = scanOps[i];

                if (scanInst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
                {
                    if (scanOps[2].reg != indexReg)
                        return false;

                    scanInst.op         = MicroInstrOpcode::LoadAddrRegMem;
                    scanOps[2].opBits   = scanOps[3].opBits;
                    scanOps[3].valueU64 = scanOps[6].valueU64;
                }
                else if (scanInst.op == MicroInstrOpcode::LoadAmcRegMem)
                {
                    if (scanOps[2].reg != indexReg)
                        return false;

                    scanInst.op         = MicroInstrOpcode::LoadRegMem;
                    scanOps[2].opBits   = scanOps[3].opBits;
                    scanOps[3].valueU64 = scanOps[6].valueU64;
                }
                else if (scanInst.op == MicroInstrOpcode::LoadAmcMemReg)
                {
                    if (scanOps[1].reg != indexReg)
                        return false;

                    scanInst.op         = MicroInstrOpcode::LoadMemReg;
                    scanOps[1].reg      = scanOps[2].reg;
                    scanOps[2].opBits   = scanOps[4].opBits;
                    scanOps[3].valueU64 = scanOps[6].valueU64;
                }
                else if (scanInst.op == MicroInstrOpcode::LoadAmcMemImm)
                {
                    if (scanOps[1].reg != indexReg)
                        return false;

                    scanInst.op         = MicroInstrOpcode::LoadMemImm;
                    scanOps[1].opBits   = scanOps[4].opBits;
                    scanOps[2].valueU64 = scanOps[6].valueU64;
                    scanOps[3].valueU64 = scanOps[7].valueU64;
                }
                else
                {
                    return false;
                }

                if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    scanInst.op = originalOp;
                    for (uint32_t i = 0; i < 8; ++i)
                        scanOps[i] = originalOps[i];
                    return false;
                }

                SWC_NOT_NULL(context.instructions)->erase(instRef);
                return true;
            }

            return false;
        }

        bool foldCopyAddIntoLoadAddress(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            MicroInstr& nextInst = *nextIt;
            if (nextInst.op != MicroInstrOpcode::OpBinaryRegImm)
                return false;

            MicroInstrOperand* nextOps = nextInst.ops(*SWC_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            if (nextOps[0].reg != ops[0].reg)
                return false;
            if (ops[2].opBits != MicroOpBits::B64 || nextOps[1].opBits != MicroOpBits::B64)
                return false;
            if (nextOps[2].microOp != MicroOp::Add)
                return false;
            if (!ops[0].reg.isSameClass(ops[1].reg))
                return false;
            if (!areFlagsDeadAfterInstruction(context, nextIt, endIt))
                return false;

            const MicroReg    tmpReg       = ops[0].reg;
            const MicroReg    baseReg      = ops[1].reg;
            const uint64_t    offset       = nextOps[3].valueU64;
            const MicroReg    originalDst  = nextOps[0].reg;
            const MicroOpBits originalBits = nextOps[1].opBits;
            const MicroOp     originalOp   = nextOps[2].microOp;
            const uint64_t    originalImm  = nextOps[3].valueU64;

            nextInst.op         = MicroInstrOpcode::LoadAddrRegMem;
            nextOps[0].reg      = tmpReg;
            nextOps[1].reg      = baseReg;
            nextOps[2].opBits   = MicroOpBits::B64;
            nextOps[3].valueU64 = offset;
            if (MicroOptimization::violatesEncoderConformance(context, nextInst, nextOps))
            {
                nextInst.op         = MicroInstrOpcode::OpBinaryRegImm;
                nextOps[0].reg      = originalDst;
                nextOps[1].opBits   = originalBits;
                nextOps[2].microOp  = originalOp;
                nextOps[3].valueU64 = originalImm;
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool foldLoadRegMemIntoNextBinaryRegMem(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroInstr& nextInst = *nextIt;
            if (nextInst.op != MicroInstrOpcode::OpBinaryRegReg)
                return false;

            const MicroInstrOperand* nextOps = nextInst.ops(*SWC_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            if (nextOps[1].reg != tmpReg)
                return false;
            if (nextOps[0].reg == tmpReg)
                return false;
            if (ops[2].opBits != nextOps[2].opBits)
                return false;
            switch (nextOps[3].microOp)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                case MicroOp::MultiplySigned:
                    break;
                default:
                    return false;
            }
            if (!isCopyDeadAfterInstruction(context, std::next(nextIt), endIt, tmpReg))
                return false;

            std::array<MicroInstrOperand, 5> newOps;
            newOps[0].reg      = nextOps[0].reg;
            newOps[1].reg      = ops[1].reg;
            newOps[2].opBits   = nextOps[2].opBits;
            newOps[3].microOp  = nextOps[3].microOp;
            newOps[4].valueU64 = ops[3].valueU64;

            const MicroInstrRef newRef  = SWC_NOT_NULL(context.instructions)->insertBefore(*SWC_NOT_NULL(context.operands), nextIt.current, MicroInstrOpcode::OpBinaryRegMem, newOps);
            const MicroInstr*   newInst = SWC_NOT_NULL(context.instructions)->ptr(newRef);
            if (!newInst)
                return false;

            const MicroInstrOperand* newInstOps = newInst->ops(*SWC_NOT_NULL(context.operands));
            if (!newInstOps)
            {
                SWC_NOT_NULL(context.instructions)->erase(newRef);
                return false;
            }

            if (MicroOptimization::violatesEncoderConformance(context, *newInst, newInstOps))
            {
                SWC_NOT_NULL(context.instructions)->erase(newRef);
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            SWC_NOT_NULL(context.instructions)->erase(nextIt.current);
            return true;
        }

        bool foldLoadRegMemBinaryStoreBackIntoMemOp(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            auto thirdIt = nextIt;
            ++thirdIt;
            if (thirdIt == endIt)
                return false;

            const MicroInstr&        nextInst = *nextIt;
            const MicroInstrOperand* nextOps  = nextInst.ops(*SWC_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            const MicroInstr&        thirdInst = *thirdIt;
            const MicroInstrOperand* thirdOps  = thirdInst.ops(*SWC_NOT_NULL(context.operands));
            if (!thirdOps)
                return false;
            if (thirdInst.op != MicroInstrOpcode::LoadMemReg)
                return false;

            const MicroReg    tmpReg    = ops[0].reg;
            const MicroReg    memBase   = ops[1].reg;
            const MicroOpBits memOpBits = ops[2].opBits;
            const uint64_t    memOffset = ops[3].valueU64;
            if (thirdOps[0].reg != memBase || thirdOps[1].reg != tmpReg || thirdOps[2].opBits != memOpBits || thirdOps[3].valueU64 != memOffset)
                return false;
            if (!isCopyDeadAfterInstruction(context, std::next(thirdIt), endIt, tmpReg) &&
                !isRegUnusedAfterInstruction(context, std::next(thirdIt), endIt, tmpReg))
                return false;

            std::array<MicroInstrOperand, 5> newOps;
            auto                             newOpcode = MicroInstrOpcode::End;
            if (nextInst.op == MicroInstrOpcode::OpBinaryRegImm)
            {
                if (nextOps[0].reg != tmpReg || nextOps[1].opBits != memOpBits)
                    return false;

                newOpcode          = MicroInstrOpcode::OpBinaryMemImm;
                newOps[0].reg      = memBase;
                newOps[1].opBits   = memOpBits;
                newOps[2].microOp  = nextOps[2].microOp;
                newOps[3].valueU64 = memOffset;
                newOps[4]          = nextOps[3];
            }
            else if (nextInst.op == MicroInstrOpcode::OpBinaryRegReg)
            {
                if (nextOps[0].reg != tmpReg || nextOps[2].opBits != memOpBits)
                    return false;
                if (nextOps[1].reg == tmpReg)
                    return false;

                newOpcode          = MicroInstrOpcode::OpBinaryMemReg;
                newOps[0].reg      = memBase;
                newOps[1].reg      = nextOps[1].reg;
                newOps[2].opBits   = memOpBits;
                newOps[3].microOp  = nextOps[3].microOp;
                newOps[4].valueU64 = memOffset;
            }
            else
            {
                return false;
            }

            const MicroInstrRef newRef  = SWC_NOT_NULL(context.instructions)->insertBefore(*SWC_NOT_NULL(context.operands), instRef, newOpcode, newOps);
            const MicroInstr*   newInst = SWC_NOT_NULL(context.instructions)->ptr(newRef);
            if (!newInst)
            {
                SWC_NOT_NULL(context.instructions)->erase(newRef);
                return false;
            }

            const MicroInstrOperand* newInstOps = newInst->ops(*SWC_NOT_NULL(context.operands));
            if (!newInstOps)
            {
                SWC_NOT_NULL(context.instructions)->erase(newRef);
                return false;
            }

            if (MicroOptimization::violatesEncoderConformance(context, *newInst, newInstOps))
            {
                SWC_NOT_NULL(context.instructions)->erase(newRef);
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            SWC_NOT_NULL(context.instructions)->erase(nextIt.current);
            SWC_NOT_NULL(context.instructions)->erase(thirdIt.current);
            return true;
        }

        bool foldLoadRegMemBinaryStoreBackIntoMemOpTail(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef      storeRef  = cursor.instRef;
            const MicroInstr*        storeInst = cursor.inst;
            const MicroInstrOperand* storeOps  = cursor.ops;
            if (!storeInst || !storeOps || storeInst->op != MicroInstrOpcode::LoadMemReg)
                return false;

            MicroStorage* const instructions = SWC_NOT_NULL(context.instructions);
            const MicroInstrRef prevRef      = instructions->findPreviousInstructionRef(storeRef);
            if (prevRef.isInvalid())
                return false;

            const MicroInstrRef prevPrevRef = instructions->findPreviousInstructionRef(prevRef);
            if (prevPrevRef.isInvalid())
                return false;

            const MicroInstr* const prevInst     = instructions->ptr(prevRef);
            const MicroInstr* const prevPrevInst = instructions->ptr(prevPrevRef);
            if (!prevInst || !prevPrevInst)
                return false;
            if (prevPrevInst->op != MicroInstrOpcode::LoadRegMem)
                return false;

            const MicroInstrOperand* loadOps = prevPrevInst->ops(*SWC_NOT_NULL(context.operands));
            const MicroInstrOperand* binOps  = prevInst->ops(*SWC_NOT_NULL(context.operands));
            if (!loadOps || !binOps)
                return false;

            const MicroReg    memBase   = storeOps[0].reg;
            const MicroReg    tmpReg    = storeOps[1].reg;
            const MicroOpBits memOpBits = storeOps[2].opBits;
            const uint64_t    memOffset = storeOps[3].valueU64;

            if (loadOps[0].reg != tmpReg || loadOps[1].reg != memBase || loadOps[2].opBits != memOpBits || loadOps[3].valueU64 != memOffset)
                return false;
            if (!isCopyDeadAfterInstruction(context, cursor.nextIt, cursor.endIt, tmpReg) &&
                !isRegUnusedAfterInstruction(context, cursor.nextIt, cursor.endIt, tmpReg))
                return false;

            std::array<MicroInstrOperand, 5> newOps;
            auto                             newOpcode = MicroInstrOpcode::End;
            if (prevInst->op == MicroInstrOpcode::OpBinaryRegImm)
            {
                if (binOps[0].reg != tmpReg || binOps[1].opBits != memOpBits)
                    return false;

                newOpcode          = MicroInstrOpcode::OpBinaryMemImm;
                newOps[0].reg      = memBase;
                newOps[1].opBits   = memOpBits;
                newOps[2].microOp  = binOps[2].microOp;
                newOps[3].valueU64 = memOffset;
                newOps[4]          = binOps[3];
            }
            else if (prevInst->op == MicroInstrOpcode::OpBinaryRegReg)
            {
                if (binOps[0].reg != tmpReg || binOps[2].opBits != memOpBits)
                    return false;
                if (binOps[1].reg == tmpReg)
                    return false;

                newOpcode          = MicroInstrOpcode::OpBinaryMemReg;
                newOps[0].reg      = memBase;
                newOps[1].reg      = binOps[1].reg;
                newOps[2].opBits   = memOpBits;
                newOps[3].microOp  = binOps[3].microOp;
                newOps[4].valueU64 = memOffset;
            }
            else
            {
                return false;
            }

            const MicroInstrRef newRef  = instructions->insertBefore(*SWC_NOT_NULL(context.operands), storeRef, newOpcode, newOps);
            const MicroInstr*   newInst = instructions->ptr(newRef);
            if (!newInst)
            {
                instructions->erase(newRef);
                return false;
            }

            const MicroInstrOperand* newInstOps = newInst->ops(*SWC_NOT_NULL(context.operands));
            if (!newInstOps)
            {
                instructions->erase(newRef);
                return false;
            }

            if (MicroOptimization::violatesEncoderConformance(context, *newInst, newInstOps))
            {
                instructions->erase(newRef);
                return false;
            }

            instructions->erase(prevPrevRef);
            instructions->erase(prevRef);
            instructions->erase(storeRef);
            return true;
        }

        bool foldLoadRegMemIntoNextCmpMemImm(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroInstr&        nextInst = *nextIt;
            const MicroInstrOperand* nextOps  = nextInst.ops(*SWC_NOT_NULL(context.operands));
            if (nextInst.op != MicroInstrOpcode::CmpRegImm || !nextOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            if (nextOps[0].reg != tmpReg)
                return false;
            if (ops[2].opBits != nextOps[1].opBits)
                return false;
            if (!isCopyDeadAfterInstruction(context, std::next(nextIt), endIt, tmpReg))
                return false;

            std::array<MicroInstrOperand, 4> newOps;
            newOps[0].reg      = ops[1].reg;
            newOps[1].opBits   = ops[2].opBits;
            newOps[2].valueU64 = ops[3].valueU64;
            newOps[3].setImmediateValue(ApInt(nextOps[2].valueU64, getNumBits(nextOps[1].opBits)));

            const MicroInstrRef newRef  = SWC_NOT_NULL(context.instructions)->insertBefore(*SWC_NOT_NULL(context.operands), nextIt.current, MicroInstrOpcode::CmpMemImm, newOps);
            const MicroInstr*   newInst = SWC_NOT_NULL(context.instructions)->ptr(newRef);
            if (!newInst)
                return false;

            const MicroInstrOperand* newInstOps = newInst->ops(*SWC_NOT_NULL(context.operands));
            if (!newInstOps)
            {
                SWC_NOT_NULL(context.instructions)->erase(newRef);
                return false;
            }

            if (MicroOptimization::violatesEncoderConformance(context, *newInst, newInstOps))
            {
                SWC_NOT_NULL(context.instructions)->erase(newRef);
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            SWC_NOT_NULL(context.instructions)->erase(nextIt.current);
            return true;
        }

        bool foldLoadRegMemIntoNextLoadAddrCopy(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            MicroInstr& nextInst = *nextIt;
            if (nextInst.op != MicroInstrOpcode::LoadAddrRegMem)
                return false;

            MicroInstrOperand* nextOps = nextInst.ops(*SWC_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            if (nextOps[1].reg != tmpReg)
                return false;
            if (nextOps[3].valueU64 != 0)
                return false;
            if (ops[2].opBits != MicroOpBits::B64 || nextOps[2].opBits != MicroOpBits::B64)
                return false;
            if (!isCopyDeadAfterInstruction(context, std::next(nextIt), endIt, tmpReg))
                return false;

            const MicroInstrOpcode originalOp  = nextInst.op;
            const std::array       originalOps = {nextOps[0], nextOps[1], nextOps[2], nextOps[3]};

            nextInst.op         = MicroInstrOpcode::LoadRegMem;
            nextOps[0].reg      = originalOps[0].reg;
            nextOps[1].reg      = ops[1].reg;
            nextOps[2].opBits   = ops[2].opBits;
            nextOps[3].valueU64 = ops[3].valueU64;
            if (MicroOptimization::violatesEncoderConformance(context, nextInst, nextOps))
            {
                nextInst.op = originalOp;
                for (uint32_t i = 0; i < 4; ++i)
                    nextOps[i] = originalOps[i];
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool foldLoadAddrIntoNextLoadAddr(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroInstr&  nextInst = *nextIt;
            MicroInstrOperand* nextOps  = nextInst.ops(*SWC_NOT_NULL(context.operands));
            if (nextInst.op != MicroInstrOpcode::LoadAddrRegMem || !nextOps)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            if (nextOps[1].reg != tmpReg)
                return false;
            if (ops[2].opBits != nextOps[2].opBits)
                return false;
            if (ops[2].opBits != MicroOpBits::B64)
                return false;
            if (!isCopyDeadAfterInstruction(context, std::next(nextIt), endIt, tmpReg))
                return false;

            const uint64_t baseOffset = ops[3].valueU64;
            const uint64_t nextOffset = nextOps[3].valueU64;
            if (baseOffset > std::numeric_limits<uint64_t>::max() - nextOffset)
                return false;
            const uint64_t foldedOffset = baseOffset + nextOffset;

            const MicroReg originalBaseReg = nextOps[1].reg;
            const uint64_t originalOffset  = nextOps[3].valueU64;
            nextOps[1].reg                 = ops[1].reg;
            nextOps[3].valueU64            = foldedOffset;
            if (MicroOptimization::violatesEncoderConformance(context, nextInst, nextOps))
            {
                nextOps[1].reg      = originalBaseReg;
                nextOps[3].valueU64 = originalOffset;
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool normalizeLoadAddrStackBaseToFramePointer(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef      instRef = cursor.instRef;
            const MicroInstrOperand* ops     = cursor.ops;
            if (!ops)
                return false;

            const CallConv& conv = CallConv::get(context.callConvKind);
            if (!conv.framePointer.isValid() || conv.framePointer == conv.stackPointer)
                return false;
            if (ops[1].reg != conv.stackPointer)
                return false;

            bool frameMatchesStack = false;
            for (const MicroInstr& scanInst : SWC_NOT_NULL(context.instructions)->view())
            {
                if (scanInst.op == MicroInstrOpcode::Label)
                    frameMatchesStack = false;

                if (scanInst.op == MicroInstrOpcode::LoadRegReg)
                {
                    const MicroInstrOperand* scanOps = scanInst.ops(*SWC_NOT_NULL(context.operands));
                    if (!scanOps)
                        return false;

                    if (scanOps[0].reg == conv.framePointer)
                    {
                        frameMatchesStack = scanOps[1].reg == conv.stackPointer && scanOps[2].opBits == MicroOpBits::B64;
                    }
                }

                if (scanInst.op == MicroInstrOpcode::JumpCond ||
                    scanInst.op == MicroInstrOpcode::JumpReg ||
                    scanInst.op == MicroInstrOpcode::JumpTable ||
                    scanInst.op == MicroInstrOpcode::Ret)
                {
                    frameMatchesStack = false;
                }

                if (scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder).isCall)
                    frameMatchesStack = false;

                if (scanInst.op == MicroInstrOpcode::Push ||
                    scanInst.op == MicroInstrOpcode::Pop)
                {
                    frameMatchesStack = false;
                }
                else if (scanInst.op == MicroInstrOpcode::OpBinaryRegImm)
                {
                    const MicroInstrOperand* scanOps = scanInst.ops(*SWC_NOT_NULL(context.operands));
                    if (!scanOps)
                        return false;
                    if (scanOps[0].reg == conv.stackPointer && scanOps[1].opBits == MicroOpBits::B64 &&
                        (scanOps[2].microOp == MicroOp::Add || scanOps[2].microOp == MicroOp::Subtract))
                    {
                        frameMatchesStack = false;
                    }
                }

                if (scanInst.op == MicroInstrOpcode::LoadRegReg)
                {
                    const MicroInstrOperand* scanOps = scanInst.ops(*SWC_NOT_NULL(context.operands));
                    if (!scanOps)
                        return false;
                    if (scanOps[0].reg == conv.framePointer && scanOps[1].reg == conv.stackPointer && scanOps[2].opBits == MicroOpBits::B64)
                        frameMatchesStack = true;
                }

                if (&scanInst == cursor.inst)
                    break;
            }

            if (!frameMatchesStack)
                return false;

            const MicroInstr* rewriteInst = SWC_NOT_NULL(context.instructions)->ptr(instRef);
            if (!rewriteInst)
                return false;

            MicroInstrOperand* rewriteOps = rewriteInst->ops(*SWC_NOT_NULL(context.operands));
            if (!rewriteOps)
                return false;

            const MicroReg originalBase = rewriteOps[1].reg;
            rewriteOps[1].reg           = conv.framePointer;
            if (MicroOptimization::violatesEncoderConformance(context, *rewriteInst, rewriteOps))
            {
                rewriteOps[1].reg = originalBase;
                return false;
            }

            return true;
        }

        bool foldLoadAddrIntoNextMemOffset(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroReg tmpReg  = ops[0].reg;
            const MicroReg baseReg = ops[1].reg;
            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&  scanInst = *scanIt;
                MicroInstrOperand* scanOps  = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                const MicroInstrUseDef               useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);

                bool hasUse     = false;
                bool hasDef     = false;
                bool hasBaseDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    const MicroReg reg = *SWC_NOT_NULL(ref.reg);
                    if (reg == tmpReg)
                    {
                        hasUse |= ref.use;
                        hasDef |= ref.def;
                    }

                    if (reg == baseReg && ref.def)
                        hasBaseDef = true;
                }

                if (hasBaseDef)
                    return false;

                if (hasDef)
                    return false;

                if (!hasUse)
                {
                    if (useDef.isCall)
                    {
                        const CallConv& conv         = CallConv::get(context.callConvKind);
                        bool            survivesCall = false;
                        if (tmpReg.isInt())
                            survivesCall = conv.isIntPersistentReg(tmpReg);
                        else if (tmpReg.isFloat())
                            survivesCall = conv.isFloatPersistentReg(tmpReg);

                        if (!survivesCall)
                            return false;
                        continue;
                    }

                    if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                        return false;

                    continue;
                }

                uint8_t baseIndex   = 0;
                uint8_t offsetIndex = 0;
                if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(baseIndex, offsetIndex, scanInst))
                    return false;
                if (scanOps[baseIndex].reg != tmpReg)
                    return false;

                const uint64_t extraOffset  = ops[3].valueU64;
                const uint64_t oldMemOffset = scanOps[offsetIndex].valueU64;
                if (oldMemOffset > std::numeric_limits<uint64_t>::max() - extraOffset)
                    return false;
                const uint64_t foldedMemOffset = oldMemOffset + extraOffset;

                const MicroReg originalBaseReg = scanOps[baseIndex].reg;
                const uint64_t originalOffset  = scanOps[offsetIndex].valueU64;
                scanOps[baseIndex].reg         = ops[1].reg;
                scanOps[offsetIndex].valueU64  = foldedMemOffset;
                if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    scanOps[baseIndex].reg        = originalBaseReg;
                    scanOps[offsetIndex].valueU64 = originalOffset;
                    return false;
                }

                if (isCopyDeadAfterInstruction(context, std::next(scanIt), endIt, tmpReg))
                    SWC_NOT_NULL(context.instructions)->erase(instRef);
                return true;
            }

            return false;
        }

        bool foldImmediateIndexAmcIntoNextLoadRegMem(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            if (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64)
                return false;
            if (ops[2].valueU64 > 0x7FFFFFFF)
                return false;

            const MicroReg indexReg = ops[0].reg;
            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                MicroInstr&        scanInst = *scanIt;
                MicroInstrOperand* scanOps  = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                const MicroInstrUseDef               useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);

                bool hasUse = false;
                bool hasDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg || *SWC_NOT_NULL(ref.reg) != indexReg)
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

                if (scanInst.op != MicroInstrOpcode::LoadAmcRegMem)
                    return false;
                if (scanOps[2].reg != indexReg)
                    return false;
                if (scanOps[1].reg.isNoBase())
                    return false;
                if (!isTempDeadForAddressFold(context, std::next(scanIt), endIt, indexReg))
                    return false;

                const uint64_t mulValue = scanOps[5].valueU64;
                if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                    return false;
                if (ops[2].valueU64 > std::numeric_limits<uint64_t>::max() / mulValue)
                    return false;
                const uint64_t scaledIndex = ops[2].valueU64 * mulValue;
                if (scanOps[6].valueU64 > std::numeric_limits<uint64_t>::max() - scaledIndex)
                    return false;
                const uint64_t mergedOffset = scanOps[6].valueU64 + scaledIndex;

                const MicroInstrOpcode originalOp  = scanInst.op;
                const std::array       originalOps = {scanOps[0], scanOps[1], scanOps[2], scanOps[3], scanOps[4], scanOps[5], scanOps[6], scanOps[7]};
                scanInst.op                        = MicroInstrOpcode::LoadRegMem;
                scanOps[2].opBits                  = scanOps[3].opBits;
                scanOps[3].valueU64                = mergedOffset;
                if (MicroOptimization::violatesEncoderConformance(context, scanInst, scanOps))
                {
                    scanInst.op = originalOp;
                    for (uint32_t i = 0; i < 8; ++i)
                        scanOps[i] = originalOps[i];
                    return false;
                }

                SWC_NOT_NULL(context.instructions)->erase(instRef);
                return true;
            }

            return false;
        }

        bool foldLoadAddrIntoAllMemOffsets(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const MicroReg tmpReg    = ops[0].reg;
            const MicroReg baseReg   = ops[1].reg;
            const uint64_t baseExtra = ops[3].valueU64;

            struct RewriteCandidate
            {
                MicroInstrRef ref         = MicroInstrRef::invalid();
                uint8_t       baseIndex   = 0;
                uint8_t       offsetIndex = 0;
                MicroReg      originalBase;
                uint64_t      originalOffset = 0;
            };

            bool                          baseWasRedefined = false;
            std::vector<RewriteCandidate> candidates;
            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&                    scanInst = *scanIt;
                const MicroInstrUseDef               useDef   = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);

                bool hasTmpUse  = false;
                bool hasTmpDef  = false;
                bool hasBaseDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    const MicroReg reg = *SWC_NOT_NULL(ref.reg);
                    if (reg == tmpReg)
                    {
                        hasTmpUse |= ref.use;
                        hasTmpDef |= ref.def;
                    }

                    if (reg == baseReg && ref.def)
                        hasBaseDef = true;
                }

                if (hasTmpDef)
                    return false;

                if (hasTmpUse)
                {
                    if (baseWasRedefined)
                        return false;

                    uint8_t baseIndex   = 0;
                    uint8_t offsetIndex = 0;
                    if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(baseIndex, offsetIndex, scanInst))
                        return false;

                    const MicroInstrOperand* scanOps = scanInst.ops(*SWC_NOT_NULL(context.operands));
                    if (!scanOps)
                        return false;
                    if (scanOps[baseIndex].reg != tmpReg)
                        return false;

                    RewriteCandidate candidate;
                    candidate.ref            = scanIt.current;
                    candidate.baseIndex      = baseIndex;
                    candidate.offsetIndex    = offsetIndex;
                    candidate.originalBase   = scanOps[baseIndex].reg;
                    candidate.originalOffset = scanOps[offsetIndex].valueU64;
                    candidates.push_back(candidate);
                }

                if (hasBaseDef)
                    baseWasRedefined = true;

                if (useDef.isCall && !candidates.empty())
                {
                    const CallConv& conv         = CallConv::get(context.callConvKind);
                    bool            survivesCall = false;
                    if (tmpReg.isInt())
                        survivesCall = conv.isIntPersistentReg(tmpReg);
                    else if (tmpReg.isFloat())
                        survivesCall = conv.isFloatPersistentReg(tmpReg);

                    if (!survivesCall)
                        return false;
                }
            }

            if (candidates.empty())
                return false;

            for (const RewriteCandidate& candidate : candidates)
            {
                const MicroInstr* rewriteInst = SWC_NOT_NULL(context.instructions)->ptr(candidate.ref);
                if (!rewriteInst)
                    return false;
                MicroInstrOperand* rewriteOps = rewriteInst->ops(*SWC_NOT_NULL(context.operands));
                if (!rewriteOps)
                    return false;

                if (rewriteOps[candidate.offsetIndex].valueU64 > std::numeric_limits<uint64_t>::max() - baseExtra)
                    return false;
                const uint64_t newOffset = rewriteOps[candidate.offsetIndex].valueU64 + baseExtra;

                rewriteOps[candidate.baseIndex].reg        = baseReg;
                rewriteOps[candidate.offsetIndex].valueU64 = newOffset;
                if (MicroOptimization::violatesEncoderConformance(context, *rewriteInst, rewriteOps))
                {
                    for (const RewriteCandidate& rollback : candidates)
                    {
                        if (rollback.ref.isInvalid())
                            continue;

                        const MicroInstr* rollbackInst = SWC_NOT_NULL(context.instructions)->ptr(rollback.ref);
                        if (!rollbackInst)
                            continue;
                        MicroInstrOperand* rollbackOps = rollbackInst->ops(*SWC_NOT_NULL(context.operands));
                        if (!rollbackOps)
                            continue;

                        rollbackOps[rollback.baseIndex].reg        = rollback.originalBase;
                        rollbackOps[rollback.offsetIndex].valueU64 = rollback.originalOffset;

                        if (rollback.ref == candidate.ref)
                            break;
                    }

                    return false;
                }
            }

            SWC_NOT_NULL(context.instructions)->erase(instRef);
            return true;
        }

        bool foldLoadAddrAmcIntoNextMemoryAccess(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const uint64_t mulValue = ops[5].valueU64;
            if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                return false;

            const MicroReg tmpReg = ops[0].reg;
            if (!isTempDeadForAddressFold(context, std::next(nextIt), endIt, tmpReg))
                return false;

            const MicroInstr&        nextInst = *nextIt;
            const MicroInstrOperand* nextOps  = nextInst.ops(*SWC_NOT_NULL(context.operands));
            if (!nextOps)
                return false;

            auto     newOpcode = MicroInstrOpcode::End;
            uint64_t nextOffset{};
            if (nextInst.op == MicroInstrOpcode::LoadRegMem)
            {
                if (nextOps[1].reg != tmpReg)
                    return false;

                newOpcode  = MicroInstrOpcode::LoadAmcRegMem;
                nextOffset = nextOps[3].valueU64;
            }
            else if (nextInst.op == MicroInstrOpcode::LoadMemReg)
            {
                if (nextOps[0].reg != tmpReg)
                    return false;

                newOpcode  = MicroInstrOpcode::LoadAmcMemReg;
                nextOffset = nextOps[3].valueU64;
            }
            else if (nextInst.op == MicroInstrOpcode::LoadMemImm)
            {
                if (nextOps[0].reg != tmpReg)
                    return false;

                newOpcode  = MicroInstrOpcode::LoadAmcMemImm;
                nextOffset = nextOps[2].valueU64;
            }
            else
            {
                return false;
            }

            if (ops[6].valueU64 > std::numeric_limits<uint64_t>::max() - nextOffset)
                return false;
            const uint64_t combinedAdd = ops[6].valueU64 + nextOffset;

            MicroInstr* rewriteInst = SWC_NOT_NULL(context.instructions)->ptr(instRef);
            if (!rewriteInst)
                return false;

            MicroInstrOperand* rewriteOps = rewriteInst->ops(*SWC_NOT_NULL(context.operands));
            if (!rewriteOps)
                return false;

            const MicroInstrOpcode originalOp  = rewriteInst->op;
            const std::array       originalOps = {rewriteOps[0], rewriteOps[1], rewriteOps[2], rewriteOps[3], rewriteOps[4], rewriteOps[5], rewriteOps[6], rewriteOps[7]};

            rewriteInst->op        = newOpcode;
            rewriteOps[5].valueU64 = ops[5].valueU64;
            rewriteOps[6].valueU64 = combinedAdd;
            rewriteOps[7].valueU64 = 0;

            if (newOpcode == MicroInstrOpcode::LoadAmcRegMem)
            {
                rewriteOps[0].reg    = nextOps[0].reg;
                rewriteOps[1].reg    = ops[1].reg;
                rewriteOps[2].reg    = ops[2].reg;
                rewriteOps[3].opBits = nextOps[2].opBits;
                rewriteOps[4].opBits = ops[4].opBits;
            }
            else if (newOpcode == MicroInstrOpcode::LoadAmcMemReg)
            {
                rewriteOps[0].reg    = ops[1].reg;
                rewriteOps[1].reg    = ops[2].reg;
                rewriteOps[2].reg    = nextOps[1].reg;
                rewriteOps[3].opBits = ops[4].opBits;
                rewriteOps[4].opBits = nextOps[2].opBits;
            }
            else
            {
                rewriteOps[0].reg      = ops[1].reg;
                rewriteOps[1].reg      = ops[2].reg;
                rewriteOps[3].opBits   = ops[4].opBits;
                rewriteOps[4].opBits   = nextOps[1].opBits;
                rewriteOps[7].valueU64 = nextOps[3].valueU64;
            }

            if (MicroOptimization::violatesEncoderConformance(context, *rewriteInst, rewriteOps))
            {
                rewriteInst->op = originalOp;
                for (uint32_t i = 0; i < 8; ++i)
                    rewriteOps[i] = originalOps[i];
                return false;
            }

            SWC_NOT_NULL(context.instructions)->erase(nextIt.current);
            return true;
        }

        bool foldLoadAddrAmcIntoLaterLoadRegMem(const MicroPassContext& context, const Cursor& cursor)
        {
            const MicroInstrRef          instRef = cursor.instRef;
            const MicroInstrOperand*     ops     = cursor.ops;
            const MicroStorage::Iterator nextIt  = cursor.nextIt;
            const MicroStorage::Iterator endIt   = cursor.endIt;
            if (!ops || nextIt == endIt)
                return false;

            const uint64_t mulValue = ops[5].valueU64;
            if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                return false;

            const MicroReg tmpReg   = ops[0].reg;
            const MicroReg baseReg  = ops[1].reg;
            const MicroReg indexReg = ops[2].reg;
            for (auto scanIt = nextIt; scanIt != endIt; ++scanIt)
            {
                const MicroInstr&        scanInst = *scanIt;
                const MicroInstrOperand* scanOps  = scanInst.ops(*SWC_NOT_NULL(context.operands));
                if (!scanOps)
                    return false;

                const MicroInstrUseDef               useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
                SmallVector<MicroInstrRegOperandRef> refs;
                scanInst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);

                bool hasTmpUse   = false;
                bool hasTmpDef   = false;
                bool hasBaseDef  = false;
                bool hasIndexDef = false;
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg)
                        continue;

                    const MicroReg reg = *SWC_NOT_NULL(ref.reg);
                    if (reg == tmpReg)
                    {
                        hasTmpUse |= ref.use;
                        hasTmpDef |= ref.def;
                    }

                    if (ref.def && reg == baseReg)
                        hasBaseDef = true;
                    if (ref.def && reg == indexReg)
                        hasIndexDef = true;
                }

                if (hasBaseDef || hasIndexDef || hasTmpDef)
                    return false;

                if (!hasTmpUse)
                {
                    if (useDef.isCall || MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                        return false;
                    continue;
                }

                if (scanInst.op != MicroInstrOpcode::LoadRegMem)
                    return false;
                if (scanOps[1].reg != tmpReg)
                    return false;
                if (!isTempDeadForAddressFold(context, std::next(scanIt), endIt, tmpReg))
                    return false;

                const uint64_t nextOffset = scanOps[3].valueU64;
                if (ops[6].valueU64 > std::numeric_limits<uint64_t>::max() - nextOffset)
                    return false;
                const uint64_t combinedAdd = ops[6].valueU64 + nextOffset;

                std::array<MicroInstrOperand, 8> newOps;
                newOps[0].reg      = scanOps[0].reg;
                newOps[1].reg      = baseReg;
                newOps[2].reg      = indexReg;
                newOps[3].opBits   = scanOps[2].opBits;
                newOps[4].opBits   = ops[4].opBits;
                newOps[5].valueU64 = ops[5].valueU64;
                newOps[6].valueU64 = combinedAdd;
                newOps[7].valueU64 = 0;

                const MicroInstrRef newRef  = SWC_NOT_NULL(context.instructions)->insertBefore(*SWC_NOT_NULL(context.operands), scanIt.current, MicroInstrOpcode::LoadAmcRegMem, newOps);
                const MicroInstr*   newInst = SWC_NOT_NULL(context.instructions)->ptr(newRef);
                if (!newInst)
                {
                    SWC_NOT_NULL(context.instructions)->erase(newRef);
                    return false;
                }

                const MicroInstrOperand* newInstOps = newInst->ops(*SWC_NOT_NULL(context.operands));
                if (!newInstOps)
                {
                    SWC_NOT_NULL(context.instructions)->erase(newRef);
                    return false;
                }

                if (MicroOptimization::violatesEncoderConformance(context, *newInst, newInstOps))
                {
                    SWC_NOT_NULL(context.instructions)->erase(newRef);
                    return false;
                }

                SWC_NOT_NULL(context.instructions)->erase(instRef);
                SWC_NOT_NULL(context.instructions)->erase(scanIt.current);
                return true;
            }

            return false;
        }

    }

    void appendAddressingRules(RuleList& outRules)
    {
        outRules.push_back({RuleTarget::LoadRegImm, foldZeroIndexAmcFromImmediate});
        outRules.push_back({RuleTarget::LoadRegImm, foldImmediateIndexAmcIntoNextLoadRegMem});

        // Rule: fold_copy_add_into_load_address
        // Purpose: fold copy + add-immediate into one address load.
        // Example: mov r11, rdx; add r11, 8 -> lea r11, [rdx + 8]
        outRules.push_back({RuleTarget::LoadRegReg, foldCopyAddIntoLoadAddress});

        // Rule: fold_loadaddr_into_next_loadaddr
        // Purpose: collapse chained address computations into one.
        // Example: lea r11, [rsp + 8]; lea rdx, [r11] -> lea rdx, [rsp + 8]
        outRules.push_back({RuleTarget::LoadAddrRegMem, foldLoadAddrIntoNextLoadAddr});

        // Rule: fold_loadaddr_into_next_mem_offset
        // Purpose: consume temporary address register in next memory instruction.
        // Example: lea r11, [rdx + 8]; mov [r11], rax -> mov [rdx + 8], rax
        outRules.push_back({RuleTarget::LoadAddrRegMem, foldLoadAddrIntoNextMemOffset});
        outRules.push_back({RuleTarget::LoadAddrRegMem, normalizeLoadAddrStackBaseToFramePointer});
        outRules.push_back({RuleTarget::LoadAddrRegMem, foldLoadAddrIntoAllMemOffsets});

        outRules.push_back({RuleTarget::LoadRegMem, foldLoadRegMemIntoNextLoadAddrCopy});

        // Rule: fold_loadregmem_into_next_cmpmemimm
        // Purpose: fold loaded temporary compared with immediate into direct memory compare.
        // Example: mov r8, [rsp + 8]; cmp r8, 0 -> cmp [rsp + 8], 0
        outRules.push_back({RuleTarget::LoadRegMem, foldLoadRegMemIntoNextCmpMemImm});

        outRules.push_back({RuleTarget::LoadRegMem, foldLoadRegMemIntoNextBinaryRegMem});
        outRules.push_back({RuleTarget::LoadRegMem, foldLoadRegMemBinaryStoreBackIntoMemOp});
        outRules.push_back({RuleTarget::AnyInstruction, foldLoadRegMemBinaryStoreBackIntoMemOpTail});

        // Rule: fold_loadaddramc_into_next_memory_access
        // Purpose: consume temporary AMC address register by folding next memory access into AMC form.
        // Example: lea r11, [r8 + r9 * 16]; mov rdx, [r11] -> mov rdx, [r8 + r9 * 16]
        outRules.push_back({RuleTarget::LoadAddrAmcRegMem, foldLoadAddrAmcIntoNextMemoryAccess});
        outRules.push_back({RuleTarget::LoadAddrAmcRegMem, foldLoadAddrAmcIntoLaterLoadRegMem});
    }
}

SWC_END_NAMESPACE();
