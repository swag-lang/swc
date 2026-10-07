#include "pch.h"
#include "Backend/Micro/Passes/Pass.ColdBlockLayout.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroLabelHelpers.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Report/Assert.h"

// Cold block layout. See the header for why it exists and why it runs last.
//
// Two shapes reach this pass, both straight-line and both holding a report:
//
//     jcc  L                        jncc C
//     ...report...           ->   L:
//   L:                              ...
//                                 C:
//                                   ...report...
//                                   jmp  L
//
//     jmp  L                      L:
//   F:                              ...
//     ...report...           ->   F:
//   L:                              ...report...
//                                   jmp  L
//
// The first is a guard whose success jumps over the report. The second is a
// report several tests branch to, behind a jump the passing path takes; once
// the report is gone that jump targets the next instruction and is dropped.
// A report that already ends with a jump of its own keeps it and needs none
// added.

SWC_BEGIN_NAMESPACE();

namespace
{
    using MicroLabelHelpers::tryGetJumpTargetLabelId;
    using MicroLabelHelpers::tryGetLabelId;

    bool isUnconditionalLabelJump(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        return inst.op == MicroInstrOpcode::JumpCond && ops && ops[0].cpuCond == MicroCond::Unconditional;
    }

    // Control never runs past this instruction into the next one.
    bool endsControlFlow(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        return inst.op == MicroInstrOpcode::Ret || inst.op == MicroInstrOpcode::Trap || inst.op == MicroInstrOpcode::JumpReg ||
               inst.op == MicroInstrOpcode::JumpTableData || isUnconditionalLabelJump(inst, ops);
    }

    struct ColdBlock
    {
        MicroInstrRef guardRef = MicroInstrRef::invalid(); // The jump skipping the block, or the one in front of its label.
        MicroInstrRef firstRef = MicroInstrRef::invalid();
        MicroInstrRef lastRef  = MicroInstrRef::invalid();
        MicroInstrRef joinRef  = MicroInstrRef::invalid(); // The label the block falls into; invalid when it jumps away.
        uint32_t      joinId   = 0;
        bool          skipped  = false; // First shape: the guard jumps over the block.
    };

    // Walks the straight line opened at `firstRef`. It is a report when it holds
    // one of the calls and ends either by falling into a label or with a jump of
    // its own. `skipTarget` is the label a guard jumps to; the block then has to
    // end exactly there.
    bool matchColdBlock(ColdBlock& outBlock, const MicroPassContext& context, const std::unordered_set<uint32_t>& reportCalls, MicroInstrRef firstRef, const uint32_t* skipTarget)
    {
        const MicroStorage&        storage  = *context.instructions;
        const MicroOperandStorage& operands = *context.operands;

        bool          hasReport = false;
        bool          jumpsAway = false;
        MicroInstrRef lastRef   = MicroInstrRef::invalid();
        for (MicroInstrRef ref = firstRef; ref.isValid(); ref = storage.findNextInstructionRef(ref))
        {
            const MicroInstr*        inst = storage.ptr(ref);
            const MicroInstrOperand* ops  = inst->ops(operands);

            if (inst->op == MicroInstrOpcode::Label)
            {
                // The label that opens the second shape belongs to the block.
                if (ref == firstRef && !skipTarget)
                {
                    lastRef = ref;
                    continue;
                }

                uint32_t labelId = 0;
                if (!hasReport || !tryGetLabelId(labelId, *inst, ops) || (skipTarget && labelId != *skipTarget))
                    return false;
                outBlock.firstRef = firstRef;
                outBlock.lastRef  = lastRef;
                outBlock.joinRef  = jumpsAway ? MicroInstrRef::invalid() : ref;
                outBlock.joinId   = labelId;
                return true;
            }

            // A jump of its own may only close the block, and nothing else may leave it.
            if (jumpsAway || inst->op == MicroInstrOpcode::JumpTableData || inst->op == MicroInstrOpcode::LoadLabelAddress)
                return false;
            jumpsAway = isUnconditionalLabelJump(*inst, ops);
            if (MicroInstrInfo::isTerminatorInstruction(*inst) && !jumpsAway)
                return false;

            hasReport = hasReport || reportCalls.contains(ref.get());
            lastRef   = ref;
        }

        return false;
    }
}

Result MicroColdBlockLayoutPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    context.coldTailRef = MicroInstrRef::invalid();
    if (!context.builder)
        return Result::Continue;

    const std::unordered_set<uint32_t> reportCalls = MicroPassHelpers::collectReportCallRefs(*context.builder);
    if (reportCalls.empty())
        return Result::Continue;

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;

    // The blocks land behind the last instruction, which must not run into them.
    const MicroInstr* tail = storage.ptr(storage.lastInstructionRef());
    if (!tail || !endsControlFlow(*tail, tail->ops(operands)))
        return Result::Continue;

    // Recognition reads the listing as lowering left it; the moves come after,
    // so a block never sees another one's relocated half.
    SmallVector<ColdBlock> blocks;
    MicroInstrRef          previousRef = MicroInstrRef::invalid();
    for (MicroInstrRef ref = storage.findNextInstructionRef(MicroInstrRef::invalid()); ref.isValid();)
    {
        const MicroInstr*        inst = storage.ptr(ref);
        const MicroInstrOperand* ops  = inst->ops(operands);
        ColdBlock                block;
        bool                     matched = false;

        uint32_t targetId = 0;
        if (tryGetJumpTargetLabelId(targetId, *inst, ops) && ops[0].cpuCond != MicroCond::Unconditional)
        {
            MicroCond inverted = MicroCond::Unconditional;
            if (MicroPassHelpers::invertCondition(inverted, ops[0].cpuCond))
            {
                matched        = matchColdBlock(block, context, reportCalls, storage.findNextInstructionRef(ref), &targetId);
                block.skipped  = true;
                block.guardRef = ref;
            }
        }
        else if (inst->op == MicroInstrOpcode::Label && previousRef.isValid())
        {
            const MicroInstr* previous = storage.ptr(previousRef);
            if (endsControlFlow(*previous, previous->ops(operands)))
            {
                matched        = matchColdBlock(block, context, reportCalls, ref, nullptr);
                block.guardRef = previousRef;
            }
        }

        if (!matched)
        {
            previousRef = ref;
            ref         = storage.findNextInstructionRef(ref);
            continue;
        }

        blocks.push_back(block);
        previousRef = block.lastRef;
        ref         = storage.findNextInstructionRef(block.lastRef);
    }

    if (blocks.empty())
        return Result::Continue;

    for (const ColdBlock& block : blocks)
    {
        MicroInstrRef firstRef = block.firstRef;
        MicroInstrRef lastRef  = block.lastRef;

        if (block.skipped)
        {
            const uint64_t    coldId = context.builder->createLabel().get();
            MicroInstrOperand labelOps[1];
            labelOps[0].valueU64 = coldId;
            firstRef             = storage.insertDerivedBefore(operands, block.firstRef, MicroInstrOpcode::Label, labelOps);

            MicroInstrOperand* guardOps = storage.ptr(block.guardRef)->ops(operands);
            MicroCond          inverted = MicroCond::Unconditional;
            SWC_INTERNAL_CHECK(MicroPassHelpers::invertCondition(inverted, guardOps[0].cpuCond));
            guardOps[0].cpuCond  = inverted;
            guardOps[2].valueU64 = coldId;
        }

        if (block.joinRef.isValid())
        {
            MicroInstrOperand jumpOps[3] = {};
            jumpOps[0].cpuCond           = MicroCond::Unconditional;
            jumpOps[1].opBits            = MicroOpBits::B32;
            jumpOps[2].valueU64          = block.joinId;
            lastRef                      = storage.insertDerivedBefore(operands, block.joinRef, MicroInstrOpcode::JumpCond, jumpOps);
        }

        storage.moveRangeToEnd(firstRef, lastRef);
        if (context.coldTailRef.isInvalid())
            context.coldTailRef = firstRef;
    }

    // The jump the passing path took over a report now reaches the next instruction.
    for (const ColdBlock& block : blocks)
    {
        if (block.skipped)
            continue;
        const MicroInstr* guard = storage.ptr(block.guardRef);
        const MicroInstr* next  = storage.ptr(storage.findNextInstructionRef(block.guardRef));
        if (!guard || !next)
            continue;
        const MicroInstrOperand* guardOps = guard->ops(operands);
        uint32_t                 guardId  = 0;
        uint32_t                 nextId   = 0;
        if (isUnconditionalLabelJump(*guard, guardOps) && tryGetJumpTargetLabelId(guardId, *guard, guardOps) &&
            tryGetLabelId(nextId, *next, next->ops(operands)) && guardId == nextId)
            storage.erase(block.guardRef);
    }

    context.builder->invalidateControlFlowGraph();
    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
