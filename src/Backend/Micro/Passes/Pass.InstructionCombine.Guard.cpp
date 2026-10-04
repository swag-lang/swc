#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroLabelHelpers.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// A runtime guard asked a second time.
//
//     cmp  i, 16                      cmp  i, 16
//     jb   A                          jb   A
//     ...report...                    ...report...
//   A:                              A:
//     ...                     ->      ...
//     cmp  i, 16                      cmp  i, 16
//     jb   B                          jmp  B
//     ...report...                    ...report...
//   B:                              B:
//
// `state[a] = f(state[a], state[b])` indexes the same array with the same
// index three times, and lowering guards each access on its own. The later
// guards test a value the first one already tested, with nothing in between
// but other guards, so they can only fail where the first one did - and that
// fault is already reported. The second jump becomes unconditional; its
// report is then unreachable, and its compare dead.
//
// Both jumps have to be guards. A program's own test of the same condition
// keeps its branch: after a report a hook chose to return from, the program
// still takes the arm the value selects.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        using MicroLabelHelpers::tryGetJumpTargetLabelId;

        // How far back an earlier guard is looked for.
        constexpr uint32_t K_MAX_SCAN = 96;

        struct GuardTest
        {
            MicroInstrOpcode op        = MicroInstrOpcode::Nop;
            MicroOpBits      bits      = MicroOpBits::Zero;
            MicroCond        cond      = MicroCond::Unconditional;
            uint32_t         leftId    = 0;
            uint32_t         rightId   = 0;
            uint64_t         immediate = 0;

            bool operator==(const GuardTest&) const = default;
        };

        bool readGuardTest(GuardTest& out, const Context& ctx, const MicroInstrRef cmpRef, const MicroCond cond)
        {
            const MicroInstr* cmp = ctx.instruction(cmpRef);
            if (!cmp || (cmp->op != MicroInstrOpcode::CmpRegImm && cmp->op != MicroInstrOpcode::CmpRegReg))
                return false;
            const MicroInstrOperand* ops = cmp->ops(*ctx.operands);
            if (!ops || !ops[0].reg.isVirtualInt())
                return false;

            const MicroSsaState::ReachingDef left = ctx.ssa->reachingDef(ops[0].reg, cmpRef);
            if (!left.valid())
                return false;

            out.op     = cmp->op;
            out.cond   = cond;
            out.leftId = left.valueId;
            if (cmp->op == MicroInstrOpcode::CmpRegImm)
            {
                if (ops[2].hasWideImmediateValue())
                    return false;
                out.bits      = ops[1].opBits;
                out.immediate = ops[2].valueU64;
                return true;
            }

            if (!ops[1].reg.isVirtualInt())
                return false;
            const MicroSsaState::ReachingDef right = ctx.ssa->reachingDef(ops[1].reg, cmpRef);
            if (!right.valid())
                return false;
            out.bits    = ops[2].opBits;
            out.rightId = right.valueId;
            return true;
        }

        // Whether `jumpRef` skips a straight-line report that ends at the label `joinRef`.
        bool skipsReport(Context& ctx, const MicroInstrRef jumpRef, const MicroInstrRef joinRef)
        {
            bool hasReport = false;
            for (MicroInstrRef ref = ctx.nextRef(jumpRef); ref != joinRef; ref = ctx.nextRef(ref))
            {
                const MicroInstr* inst = ref.isValid() ? ctx.instruction(ref) : nullptr;
                if (!inst || inst->op == MicroInstrOpcode::Label || MicroInstrInfo::isTerminatorInstruction(*inst))
                    return false;
                hasReport = hasReport || ctx.isReportCall(ref);
            }
            return hasReport;
        }
    }

    bool tryDropRepeatedGuard(Context& ctx, MicroInstrRef cmpRef, const MicroInstr&)
    {
        if (!ctx.ssa || !ctx.builder)
            return false;

        const MicroInstrRef jumpRef = ctx.nextRef(cmpRef);
        const MicroInstr*   jump    = jumpRef.isValid() ? ctx.instruction(jumpRef) : nullptr;
        if (!jump || ctx.isClaimed(jumpRef))
            return false;
        const MicroInstrOperand* jumpOps  = jump->ops(*ctx.operands);
        uint32_t                 targetId = 0;
        if (!tryGetJumpTargetLabelId(targetId, *jump, jumpOps) || jumpOps[0].cpuCond == MicroCond::Unconditional)
            return false;

        GuardTest test;
        if (!readGuardTest(test, ctx, cmpRef, jumpOps[0].cpuCond))
            return false;

        // Back over straight-line code and over whole guards, to one that made the same
        // test. Every label crossed is the join of a guard and of nothing else, so the
        // guard found is the only way down to this one.
        const MicroControlFlowGraph& cfg      = ctx.builder->controlFlowGraph();
        bool                         repeated = false;
        uint32_t                     steps    = 0;
        for (MicroInstrRef ref = ctx.previousRef(cmpRef); ref.isValid() && !repeated && steps < K_MAX_SCAN; ++steps)
        {
            const MicroInstr* inst = ctx.instruction(ref);
            if (!inst)
                return false;
            if (inst->op != MicroInstrOpcode::Label)
            {
                if (MicroInstrInfo::isTerminatorInstruction(*inst))
                    return false;
                ref = ctx.previousRef(ref);
                continue;
            }

            const uint32_t joinIndex = cfg.indexOf(ref);
            if (joinIndex == MicroControlFlowGraph::K_NO_INDEX || joinIndex == 0)
                return false;
            const auto  addressTaken = cfg.addressTakenLabelIndices();
            const auto& incoming     = cfg.predecessors(joinIndex);
            if (incoming.size() != 2 || std::ranges::find(addressTaken, joinIndex) != addressTaken.end())
                return false;
            const uint32_t jumpIndex = incoming[0] == joinIndex - 1 ? incoming[1] : incoming[0];
            if (jumpIndex >= joinIndex - 1 || (incoming[0] != joinIndex - 1 && incoming[1] != joinIndex - 1))
                return false;

            const MicroInstrRef      earlierJumpRef = cfg.instructionRefs()[jumpIndex];
            const MicroInstr*        earlierJump    = ctx.instruction(earlierJumpRef);
            const MicroInstrOperand* earlierOps     = earlierJump ? earlierJump->ops(*ctx.operands) : nullptr;
            uint32_t                 earlierTarget  = 0;
            if (!earlierJump || !tryGetJumpTargetLabelId(earlierTarget, *earlierJump, earlierOps) ||
                earlierOps[0].cpuCond == MicroCond::Unconditional || !skipsReport(ctx, earlierJumpRef, ref))
                return false;

            const MicroInstrRef earlierCmpRef = ctx.previousRef(earlierJumpRef);
            GuardTest           earlier;
            repeated = earlierCmpRef.isValid() && readGuardTest(earlier, ctx, earlierCmpRef, earlierOps[0].cpuCond) && earlier == test;
            ref      = ctx.previousRef(earlierJumpRef);
        }

        if (!repeated)
            return false;

        // The jump being resolved must be a guard as well: see the note above.
        const uint32_t joinIndex = cfg.indexOfLabel(targetId);
        if (joinIndex == MicroControlFlowGraph::K_NO_INDEX || !skipsReport(ctx, jumpRef, cfg.instructionRefs()[joinIndex]))
            return false;

        if (!ctx.claimAll({jumpRef}))
            return false;

        MicroInstrOperand newOps[3] = {jumpOps[0], jumpOps[1], jumpOps[2]};
        newOps[0].cpuCond           = MicroCond::Unconditional;
        ctx.emitRewrite(jumpRef, MicroInstrOpcode::JumpCond, newOps);
        return true;
    }
}

SWC_END_NAMESPACE();
