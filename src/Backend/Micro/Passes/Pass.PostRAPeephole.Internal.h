#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.Peephole.Core.h"
#include "Support/Core/RefTypes.h"

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

        // Copy/const forwarding is only run while this is set (the first
        // post-RA sweep). See MicroPassContext::isFirstOptimizationSweep.
        bool allowForwarding = true;

        const MicroPassContext*            passContext = nullptr;
        MicroPassHelpers::MicroPhysLiveness physicalLiveness;
        uint32_t                            instructionIndex      = 0;
        bool                                physicalLivenessReady = false;

        bool isRegDeadAfterCurrent(MicroReg reg);

        bool claimAll(std::span<const MicroInstrRef> refs);
        bool claimAll(std::initializer_list<MicroInstrRef> refs)
        {
            return claimAll(std::span<const MicroInstrRef>{refs.begin(), refs.size()});
        }
        bool isPrivateFrameBase(MicroReg reg) const;
    };

    using PatternFn = bool (*)(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);

    using PatternRegistry = MicroPeephole::PatternRegistry<PatternFn>;

    bool isTriviallyErasableNoEffect(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool instructionActuallyDefinesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool isRedundantFallthroughJumpToNextLabel(const Context& ctx, MicroInstrRef ref, const MicroInstr& inst, const MicroInstrOperand* ops);

    bool tryEraseTrivial(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryShortenAddressAdd(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowZeroExtendedShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldZeroExtendedBooleanCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldSubtractBoolean(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryInvertZeroSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowTruncatedRightShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryExtractSignBoolean(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryClearBeforeSetCondition(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryEraseDeadCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryReuseFlagsForCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryForwardLoadRegImm(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryFoldCopyRoundTrip(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryRetargetUnaryResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryInvertResultZeroSelect(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryRetargetAddressResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldIntegerAddResultCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldCopyIntoIntegerAdd(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryForwardCopySource(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryForwardCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryEraseRedundantCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryCanonicalizeZeroToClear(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryFoldCopyIntoFloatBinary(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldCopyIntoVecShiftImm(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldLoadIntoBinary(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryUseSelfOperandForFloatBinary(Context& ctx, MicroInstrRef opRef, const MicroInstr& opInst);
    bool tryEraseOverwrittenStore(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst);
    bool tryEraseRedundantStoreReload(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst);
    bool tryForwardStoredValueToReload(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst);

    // Walks forward from `fromRef`: the register is dead iff the next thing that
    // touches it is a redefinition, with no read in between.
    bool regIsDeadAfter(const Context& ctx, MicroInstrRef fromRef, MicroReg reg);
}

SWC_END_NAMESPACE();
