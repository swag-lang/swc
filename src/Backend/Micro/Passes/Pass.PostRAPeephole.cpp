#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"
#include "Support/Report/Assert.h"

// Post-RA peephole optimization on physical registers.
//
// Architecture
// ------------
// Mirrors instruction-combine on purpose:
// - rules are small self-contained functions;
// - rules are registered by anchor opcode;
// - scans batch Actions and apply them after the walk finishes.
//
// This keeps the pass cheap today while making it easy to add more post-RA
// cleanup rules later without growing one large if/else cascade.

SWC_BEGIN_NAMESPACE();

namespace
{
    using namespace PostRaPeephole;

    PatternRegistry buildRegistry()
    {
        PatternRegistry r;
        r.add(MicroInstrOpcode::Nop, tryEraseTrivial);
        r.add(MicroInstrOpcode::LoadRegReg, tryEraseTrivial);
        r.add(MicroInstrOpcode::JumpCond, tryEraseTrivial);
        r.add(MicroInstrOpcode::CmpRegImm, tryFoldConditionalBitwiseNot);
        r.add(MicroInstrOpcode::CmpRegImm, tryFactorCommonConditionalShiftNoCopy);
        r.add(MicroInstrOpcode::CmpRegImm, tryFactorCommonConditionalShiftBare);
        r.add(MicroInstrOpcode::CmpRegImm, tryReuseFlagsForCompare);
        r.add(MicroInstrOpcode::TestMemReg, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::TestMemImm, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::TestRegReg, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::TestRegImm, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::CmpRegReg, tryReuseAddFlagsForUnsignedWrap);
        r.add(MicroInstrOpcode::CmpRegReg, tryFactorCommonConditionalShiftNoCopy);
        r.add(MicroInstrOpcode::CmpRegReg, tryFactorCommonConditionalShiftBare);
        r.add(MicroInstrOpcode::CmpRegReg, tryEraseRepeatedCompare);
        r.add(MicroInstrOpcode::CmpRegReg, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::CmpRegImm, tryEraseDeadCompare);
        for (const MicroInstrOpcode op : {MicroInstrOpcode::CmpRegReg, MicroInstrOpcode::CmpRegImm, MicroInstrOpcode::CmpMemReg,
                                          MicroInstrOpcode::CmpMemImm, MicroInstrOpcode::CmpAmcReg, MicroInstrOpcode::CmpAmcImm,
                                          MicroInstrOpcode::TestRegReg, MicroInstrOpcode::TestRegImm, MicroInstrOpcode::TestMemReg,
                                          MicroInstrOpcode::TestMemImm})
            r.add(op, tryEraseCompareAfterBranch);
        r.add(MicroInstrOpcode::CmpMemReg, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::CmpMemImm, tryEraseDeadCompare);
        r.add(MicroInstrOpcode::OpUnaryReg, tryFoldCarryMask);
        r.add(MicroInstrOpcode::OpUnaryReg, tryFoldZeroComparisonMask);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldZeroBooleanProduct);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldUnsignedAverage);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldCarryArithmetic);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldCarryComparisonSum);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryFoldZeroTestBooleanSum);
        r.add(MicroInstrOpcode::OpBinaryRegReg, tryNarrowBitwiseZeroExtensions);
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryFoldConditionalAddSubtract);
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryUseTestForDeadMask);
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryFoldCarryOffset);
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryNarrowShiftedBoolean);
        r.add(MicroInstrOpcode::LoadAddrRegMem, tryShortenAddressUnitOffset);
        r.add(MicroInstrOpcode::LoadAddrRegMem, tryFoldCarryOffset);
        r.add(MicroInstrOpcode::LoadAddrAmcRegMem, tryShortenAddressAdd);
        r.add(MicroInstrOpcode::LoadAddrAmcRegMem, tryFoldScaledAdd);
        r.add(MicroInstrOpcode::LoadCondRegReg, tryFoldBooleanOrSelect);
        r.add(MicroInstrOpcode::LoadCondRegReg, tryReuseNegationForSignSelect);
        r.add(MicroInstrOpcode::LoadCondRegReg, tryFoldCarrySelectOfConstants);
        r.add(MicroInstrOpcode::OpBinaryRegImm, tryNarrowZeroExtendedShift);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryFoldSubtractBoolean);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryEraseBooleanRecanonicalization);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryFoldZeroExtendedBooleanCompare);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryExtractHighByte);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryNarrowTruncatedRightShift);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryExtractSignBoolean);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryClearBeforeSetCondition);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryHoistNarrowZeroExtendAcrossUnary);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryFoldNarrowUnsignedAverage);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryRetargetNarrowZeroSelect);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryRetargetNarrowAbsoluteDifference);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryRetargetNarrowSelectCascade);
        r.add(MicroInstrOpcode::LoadZeroExtRegReg, tryWidenNarrowSelectGraph);
        r.add(MicroInstrOpcode::LoadRegImm, tryClearZeroBeforeSelect);
        r.add(MicroInstrOpcode::LoadRegImm, tryForwardLoadRegImm);
        r.add(MicroInstrOpcode::LoadRegImm, tryCanonicalizeZeroToClear);
        r.add(MicroInstrOpcode::LoadRegMem, tryFoldLoadIntoTest);
        r.add(MicroInstrOpcode::LoadRegMem, tryFoldLoadIntoNarrowExtract);
        r.add(MicroInstrOpcode::LoadRegMem, tryFoldLoadIntoBinary);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldLoadIntoBinary);
        r.add(MicroInstrOpcode::LoadAmcRegMem, tryFoldIndexedByteAverage);
        r.add(MicroInstrOpcode::LoadMemReg, tryEraseOverwrittenStore);
        r.add(MicroInstrOpcode::LoadMemReg, tryEraseRedundantStoreReload);
        r.add(MicroInstrOpcode::LoadMemReg, tryForwardStoredValueToReload);
        r.add(MicroInstrOpcode::OpBinaryRegMem, tryUseSelfOperandForFloatBinary);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCopyIntoFloatBinary);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCopyIntoIntegerMultiply);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldMultiplyShiftResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldMultiplyIntoResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCopyIntoVecShiftImm);
        r.add(MicroInstrOpcode::LoadRegReg, tryInvertZeroSelect);
        r.add(MicroInstrOpcode::LoadRegReg, tryInvertResultZeroSelect);
        r.add(MicroInstrOpcode::LoadRegReg, tryRetargetUnaryResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCopyRoundTrip);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldIndexedByteSaturatingAdd);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldByteMultiplySelectCopies);
        r.add(MicroInstrOpcode::LoadRegReg, tryFactorNarrowConditionalShift);
        r.add(MicroInstrOpcode::LoadRegReg, tryFactorCommonConditionalShift);
        r.add(MicroInstrOpcode::LoadRegReg, tryFactorCommonConditionalBinary);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldSelectedIntegerAdd);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCopyIntoIntegerAdd);
        r.add(MicroInstrOpcode::LoadRegReg, tryRetargetAddressResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldCommutativeAddressCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryCommuteBinaryResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryNarrowShiftCountCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldSignedCeilAverage);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldSignedFloorAverage);
        r.add(MicroInstrOpcode::LoadRegReg, tryNarrowCopyOf32BitResult);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldAddMultiplyResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldIntegerAddResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldUnsignedCeilAverage64);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldUnsignedCeilAverage);
        r.add(MicroInstrOpcode::LoadRegReg, tryRetargetSelectedValueCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryRetargetSelectedIntermediate);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldConditionalCascadeResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldConditionalChainResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryFoldConditionalResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryRetargetNegatedConditionalResultCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryForwardCopySource);
        r.add(MicroInstrOpcode::LoadRegReg, tryCoalesceLocalCopyChain);
        r.add(MicroInstrOpcode::LoadRegReg, tryForwardCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryEraseRedundantCopy);
        r.add(MicroInstrOpcode::LoadRegReg, tryNarrowCopyBefore32BitWrite);
        r.add(MicroInstrOpcode::LoadSignedExtRegReg, tryFoldConditionalCascadeResultCopy);
        return r;
    }

    const PatternRegistry& registry()
    {
        static const PatternRegistry R = buildRegistry();
        return R;
    }

    void runPerInstructionPatterns(Context& ctx)
    {
        const PatternRegistry& reg   = registry();
        const auto             view  = ctx.storage->view();
        const auto             endIt = view.end();
        for (auto it = view.begin(); it != endIt; ++it, ++ctx.instructionIndex)
        {
            for (const PatternFn fn : reg.patternsFor(it->op))
            {
                if (fn(ctx, it.current, *it))
                    break;
            }
        }
    }
}

Result MicroPostRaPeepholePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    Context         ctx;
    const CallConv& conv = CallConv::get(context.callConvKind);
    ctx.passContext      = &context;
    ctx.storage          = context.instructions;
    ctx.operands         = context.operands;
    ctx.encoder          = context.encoder;
    ctx.builder          = context.builder;
    ctx.stackPointer     = conv.stackPointer;
    ctx.framePointer     = conv.framePointer;
    ctx.localStackBase   = context.debugStackBasePhysReg;
    ctx.allowForwarding  = context.isFirstOptimizationSweep;

    eraseRedundantUpperHalfClears(ctx);
    runPerInstructionPatterns(ctx);

    if (ctx.actions.empty())
        return Result::Continue;

    for (const Action& action : ctx.actions)
        MicroPeephole::applyAction(ctx, action);

    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
