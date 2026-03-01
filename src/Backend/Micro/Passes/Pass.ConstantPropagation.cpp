#include "pch.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.Private.h"

// Propagates known constants through register operations.
// Example: load r1, 5; add r2, r1  ->  add r2, 5.
// Example: load r1, 5; shl r1, 1    ->  load r1, 10.
// This removes dynamic work and creates simpler instruction forms.

SWC_BEGIN_NAMESPACE();

Result MicroConstantPropagationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    initRunState(context);
    const MicroInstr*        prevInst = nullptr;
    const MicroInstrOperand* prevOps  = nullptr;

    for (auto it = storage_->view().begin(); it != storage_->view().end(); ++it)
    {
        const MicroInstrRef instRef = it.current;
        MicroInstr&         inst    = *it;
        auto* const         ops     = inst.ops(*operands_);
        DeferredDef         deferredKnownDef;
        DeferredDef         deferredAddressDef;

        // Phase 1: rewrite the instruction from currently known values.
        if (ops && stackPointerReg_.isValid())
        {
            uint8_t memBaseIndex   = 0;
            uint8_t memOffsetIndex = 0;
            if (MicroInstrInfo::getMemBaseOffsetOperandIndices(memBaseIndex, memOffsetIndex, inst))
            {
                const MicroReg baseReg = ops[memBaseIndex].reg;
                if (baseReg.isInt() && baseReg != stackPointerReg_)
                {
                    uint64_t stackOffset = 0;
                    if (tryResolveStackOffset(stackOffset, knownAddresses_, stackPointerReg_, baseReg, ops[memOffsetIndex].valueU64))
                    {
                        const MicroReg originalBase   = ops[memBaseIndex].reg;
                        const uint64_t originalOffset = ops[memOffsetIndex].valueU64;
                        ops[memBaseIndex].reg         = stackPointerReg_;
                        ops[memOffsetIndex].valueU64  = stackOffset;
                        if (MicroPassHelpers::violatesEncoderConformance(context, inst, ops))
                        {
                            ops[memBaseIndex].reg        = originalBase;
                            ops[memOffsetIndex].valueU64 = originalOffset;
                        }
                        else
                        {
                            context.passChanged = true;
                        }
                    }
                }
            }
        }

        SWC_RESULT_VERIFY(rewriteInstructionFromKnownValues(context, instRef, inst, ops, deferredKnownDef, deferredAddressDef));

        // Phase 2: consume defs/calls and invalidate stale state.
        updateCompareStateForInstruction(inst, ops, deferredKnownDef);

        const MicroInstrUseDef useDef = inst.collectUseDef(*operands_, context.encoder);
        invalidateStateForDefinitions(useDef);

        if (useDef.isCall)
        {
            clearForCallBoundary(useDef.callConv);
            prevInst = &inst;
            prevOps  = ops;
            continue;
        }

        // Phase 3: update tracked stack facts for memory writes.
        SWC_RESULT_VERIFY(trackKnownMemoryWrite(context, instRef, prevInst, prevOps, inst, ops));

        // Phase 4: rebuild facts produced by the rewritten instruction.
        SWC_RESULT_VERIFY(updateKnownRegistersForInstruction(context, instRef, inst, ops));

        applyDeferredKnownDefinition(deferredKnownDef);
        updateKnownConstantPointersForInstruction(instRef, inst, ops);
        updateKnownAddressesForInstruction(inst, ops);
        applyDeferredAddressDefinition(deferredAddressDef);
        clearControlFlowBoundaryForInstruction(inst, ops);

        prevInst = &inst;
        prevOps  = ops;
    }

    return Result::Continue;
}
SWC_END_NAMESPACE();
