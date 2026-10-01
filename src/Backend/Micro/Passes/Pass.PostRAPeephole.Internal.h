#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.Peephole.Core.h"
#include "Support/Core/RefTypes.h"
#include <algorithm>

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;
class Encoder;
class MicroBuilder;

namespace PostRaPeephole
{
    struct Action
    {
        // Indexed address forms carry eight operands.
        static constexpr uint8_t K_MAX_OPS = 8;

        MicroInstrRef     ref            = MicroInstrRef::invalid();
        MicroInstrOpcode  newOp          = MicroInstrOpcode::Nop;
        uint8_t           numOps         = 0;
        MicroInstrOperand ops[K_MAX_OPS] = {};
        bool              erase          = false;
        bool              allocOps       = false;
    };

    struct Context : MicroPeephole::RewriteQueue<Action>
    {
        const Encoder* encoder        = nullptr;
        MicroBuilder*  builder        = nullptr;
        MicroReg       stackPointer   = MicroReg::invalid();
        MicroReg       framePointer   = MicroReg::invalid();
        MicroReg       localStackBase = MicroReg::invalid();
        MicroReg       floatReturn    = MicroReg::invalid();

        // Copy/const forwarding is only run while this is set (the first
        // post-RA sweep). See MicroPassContext::isFirstOptimizationSweep.
        bool allowForwarding = true;

        const MicroPassContext*             passContext = nullptr;
        MicroPassHelpers::MicroPhysLiveness physicalLiveness;
        uint32_t                            instructionIndex      = 0;
        bool                                physicalLivenessReady = false;

        // Per instruction slot, the integer registers whose upper half is
        // clear on entry, on every path. Computed on first use.
        std::vector<uint32_t> upperHalfZeroIn;
        bool                  upperHalfReady = false;
        bool                  upperHalfValid = false;

        bool isUpperHalfZeroBefore(MicroInstrRef ref, MicroReg reg);
        bool isRegDeadAfterCurrent(MicroReg reg);
        bool isRegDeadAfter(MicroReg reg, uint32_t index);

        bool claimAll(std::span<const MicroInstrRef> refs);
        bool claimAll(std::initializer_list<MicroInstrRef> refs)
        {
            return claimAll(std::span<const MicroInstrRef>{refs.begin(), refs.size()});
        }
        bool isPrivateFrameBase(MicroReg reg) const;
    };

    struct WidenableAmcLoadPair
    {
        MicroInstrRef     resultRef;
        MicroInstrRef     otherRef;
        MicroInstrOperand resultOps[7];
        MicroInstrOperand otherOps[7];

        bool match(Context& ctx, MicroInstrRef afterRef, MicroReg result, MicroReg other, MicroOpBits bits)
        {
            otherRef = ctx.previousRef(afterRef);
            const MicroInstr*        otherLoad    = ctx.instruction(otherRef);
            const MicroInstrOperand* otherLoadOps = otherLoad ? otherLoad->ops(*ctx.operands) : nullptr;
            resultRef = ctx.previousRef(otherRef);
            const MicroInstr*        resultLoad    = ctx.instruction(resultRef);
            const MicroInstrOperand* resultLoadOps = resultLoad ? resultLoad->ops(*ctx.operands) : nullptr;
            if (!otherLoad || otherLoad->op != MicroInstrOpcode::LoadAmcRegMem || !otherLoadOps ||
                otherLoadOps[0].reg != other || otherLoadOps[3].opBits != bits || otherLoadOps[4].opBits != MicroOpBits::B64 ||
                !resultLoad || resultLoad->op != MicroInstrOpcode::LoadAmcRegMem || !resultLoadOps ||
                resultLoadOps[0].reg != result || resultLoadOps[3].opBits != bits || resultLoadOps[4].opBits != MicroOpBits::B64)
                return false;

            std::copy_n(resultLoadOps, 7, resultOps);
            std::copy_n(otherLoadOps, 7, otherOps);
            resultOps[3].opBits = MicroOpBits::B32;
            resultOps[4].opBits = bits;
            otherOps[3].opBits  = MicroOpBits::B32;
            otherOps[4].opBits  = bits;
            return true;
        }
    };

    using PatternFn = bool (*)(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);

    using PatternRegistry = MicroPeephole::PatternRegistry<PatternFn>;

    bool isTriviallyErasableNoEffect(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool instructionActuallyDefinesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool isRedundantFallthroughJumpToNextLabel(const Context& ctx, MicroInstrRef ref, const MicroInstr& inst, const MicroInstrOperand* ops);

    bool tryEraseTrivial(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldDeadScalarIncrement(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryErasePrivateFrameReloadAfterBranch(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool forwardPrivateFrameReloads(Context& ctx);
    bool tryFoldClearIntoResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryEraseRepeatedImmediate(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryEraseZeroExtendedSelfCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryEraseByteZeroExtendAfterSubtract(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldByteLoadSubtractExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryDropSignExtendBeforeNarrowCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryInvertBranchOverJump(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryEraseFloatClearBeforeFullWrite(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldFloatReturnSelectDiamond(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldCarryMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldZeroComparisonMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldCarryArithmetic(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldCarryComparisonSum(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldZeroTestBooleanSum(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowBitwiseZeroExtensions(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldCarryOffset(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldCarrySelectOfConstants(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowShiftedBoolean(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryShortenAddressUnitOffset(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryShortenAddressAdd(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldScaledAdd(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldDoubledAddressAdd(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldIndexedAddressIntoNextLoad(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldMaskedDoubleIntoAddress(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldPointerAddIntoNextLoad(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldAddIntoFieldAddress(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryReuseNegationForSignSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldBooleanOrSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowZeroExtendedShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldZeroExtendedBooleanCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryEraseBooleanRecanonicalization(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldSubtractBoolean(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryInvertZeroSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryClearZeroBeforeSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryExtractHighByte(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowTruncatedRightShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryExtractSignBoolean(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryClearBeforeSetCondition(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryUseTestForDeadMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryEraseDeadCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryEraseRepeatedCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldConstantBooleanSet(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldConditionalBitwiseNot(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldConditionalAddSubtract(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldFloatReturnXorCopyChain(Context& ctx, MicroInstrRef firstCopyRef, const MicroInstr& firstCopyInst);
    bool tryReuseAddFlagsForUnsignedWrap(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryReuseFlagsForCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryFoldZeroBooleanProduct(Context& ctx, MicroInstrRef multiplyRef, const MicroInstr& multiplyInst);
    bool tryFoldUnsignedAverage(Context& ctx, MicroInstrRef addRef, const MicroInstr& addInst);
    bool tryFoldNarrowUnsignedAverage(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryForwardLoadRegImm(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryFoldCopyRoundTrip(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryRetargetUnaryResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryInvertResultZeroSelect(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryRetargetAddressResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldCommutativeAddressCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryCommuteBinaryResultCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryRetargetFloatConversionBeforeCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowShiftCountCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowCopyBefore32BitWrite(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowCopyOf32BitResult(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldRepeatedZeroExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryHoistNarrowZeroExtendAcrossUnary(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryRetargetNarrowZeroSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryRetargetNarrowAbsoluteDifference(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryRetargetNarrowSelectCascade(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryWidenNarrowSelectGraph(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    void eraseRedundantUpperHalfClears(Context& ctx);
    void widenScalarFloatCopies(Context& ctx);
    bool areFloatUpperLanesDeadAfter(Context& ctx, MicroInstrRef afterRef, MicroReg reg, MicroOpBits copiedBits);
    bool tryLoadIntoFirstFloatConsumer(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldAddMultiplyResultCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldIntegerAddResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldMaskedIndexIncrement(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldSignedFloorAverage(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldSignedCeilAverage(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldUnsignedCeilAverage64(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldUnsignedCeilAverage(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryRetargetSelectedIntermediate(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryRetargetSelectedValueCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldConditionalCascadeResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldConditionalChainResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldConditionalResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryRetargetNegatedConditionalResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldCopyIntoIntegerAdd(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFactorCommonConditionalShift(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFactorCommonConditionalShiftNoCopy(Context& ctx, MicroInstrRef compareRef, const MicroInstr& compareInst);
    bool tryFactorCommonConditionalShiftBare(Context& ctx, MicroInstrRef compareRef, const MicroInstr& compareInst);
    bool tryFactorNarrowConditionalShift(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldByteMultiplySelectCopies(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldIndexedByteAverage(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldIndexedByteSaturatingAdd(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFactorCommonConditionalBinary(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldSelectedIntegerAdd(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryForwardCopySource(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryCoalesceLocalCopyChain(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryForwardCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryEraseRedundantCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryCanonicalizeZeroToClear(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryFoldCopyIntoFloatBinary(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldCopyIntoIntegerMultiply(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldMultiplyIntoResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldFloatBinaryIntoResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldMultiplyShiftResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryEraseCompareAfterBranch(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldBorrowDifference(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldCopyIntoVecShiftImm(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldLoadIntoTest(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldLoadIntoNarrowExtract(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldLoadIntoBinary(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldIndexedFloatAccumulation(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldIndexedFloatCompare(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryEraseScalarReturnConversionClear(Context& ctx, MicroInstrRef clearRef, const MicroInstr& clearInst);
    bool tryShareReturnEpilogue(Context& ctx, MicroInstrRef branchRef, const MicroInstr& branchInst);
    bool tryUseSelfOperandForFloatBinary(Context& ctx, MicroInstrRef opRef, const MicroInstr& opInst);
    bool tryEraseOverwrittenStore(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst);
    bool tryEraseRedundantStoreReload(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst);
    bool tryEraseStoreOfReloadedValue(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst);
    bool tryMoveSpillReloadBeforeSourceOverwrite(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst);
    bool tryForwardStoredValueToReload(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst);

    // Walks forward from `fromRef`: the register is dead iff the next thing that
    // touches it is a redefinition, with no read in between.
    bool regIsDeadAfter(const Context& ctx, MicroInstrRef fromRef, MicroReg reg);
}

SWC_END_NAMESPACE();
