#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/Passes/Pass.Peephole.Core.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;
class Encoder;

namespace PostRaPeephole
{
    struct Action
    {
        static constexpr uint8_t K_MAX_OPS = 5;

        MicroInstrRef     ref            = MicroInstrRef::invalid();
        MicroInstrOpcode  newOp          = MicroInstrOpcode::Nop;
        uint8_t           numOps         = 0;
        MicroInstrOperand ops[K_MAX_OPS] = {};
        bool              erase          = false;
        bool              allocOps       = false;
    };

    struct Context : MicroPeephole::RewriteQueue<Action>
    {
        const Encoder* encoder = nullptr;

        // Copy/const forwarding is only run while this is set (the first
        // post-RA sweep). See MicroPassContext::isFirstOptimizationSweep.
        bool allowForwarding = true;

        bool claimAll(std::initializer_list<MicroInstrRef> refs);
    };

    using PatternFn = bool (*)(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);

    using PatternRegistry = MicroPeephole::PatternRegistry<PatternFn>;

    bool isTriviallyErasableNoEffect(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool isRedundantFallthroughJumpToNextLabel(const Context& ctx, MicroInstrRef ref, const MicroInstr& inst, const MicroInstrOperand* ops);

    bool tryEraseTrivial(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryEraseDeadCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryReuseFlagsForCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryForwardLoadRegImm(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryForwardCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryCanonicalizeZeroToClear(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryFoldCopyIntoFloatBinary(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldLoadIntoFloatBinary(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryUseSelfOperandForFloatBinary(Context& ctx, MicroInstrRef opRef, const MicroInstr& opInst);

    // Walks forward from `fromRef`: the register is dead iff the next thing that
    // touches it is a redefinition, with no read in between.
    bool regIsDeadAfter(const Context& ctx, MicroInstrRef fromRef, MicroReg reg);
}

SWC_END_NAMESPACE();
