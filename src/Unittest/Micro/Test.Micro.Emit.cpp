#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Encoder/Encoder.X64.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.Emit.h"
#include "Backend/Micro/Passes/Pass.Legalize.h"
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr MicroReg RAX = MicroReg::intReg(0);
    constexpr MicroReg RCX = MicroReg::intReg(2);

    constexpr uint8_t K_JB_SHORT = 0x72;
    constexpr uint8_t K_RET      = 0xC3;

    struct EmittedLoop
    {
        uint32_t size            = 0;
        uint32_t codeAlignment   = 0;
        uint32_t groupStart      = 0; // cmp rax, rcx
        uint32_t groupEnd        = 0; // after the short jb
        uint32_t entryGroupStart = 0;
        uint32_t entryGroupEnd   = 0;
        uint32_t nestedStart     = 0;
        uint32_t nestedEnd       = 0;
    };

    enum class EntryBranch : uint8_t
    {
        None,
        Interior,
        WideInterior,
        FlatInterior,
        Exit,
    };

    // One nop, then a loop of `bodyNops` nops closed by `cmp rax, rcx; jb header`, then ret.
    // With the header on its 16-byte boundary the closing pair starts at 16 + bodyNops.
    Result emitLoop(TaskContext& ctx, const uint32_t bodyNops, EmittedLoop& out, const EntryBranch entryBranch = EntryBranch::None)
    {
        MicroBuilder        builder(ctx);
        const MicroLabelRef header = builder.createLabel();
        const MicroLabelRef exit   = builder.createLabel();
        const bool          nested = entryBranch == EntryBranch::Interior || entryBranch == EntryBranch::WideInterior;
        for (uint32_t i = 0; i < (entryBranch == EntryBranch::WideInterior ? 33u : 1u); ++i)
            builder.emitNop();
        builder.placeLabel(header);
        for (uint32_t i = 0; i < bodyNops; ++i)
            builder.emitNop();
        if (entryBranch != EntryBranch::None)
        {
            builder.emitCmpRegReg(RAX, RCX, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, exit);
            for (uint32_t i = 0; i < 7; ++i)
                builder.emitNop();
        }
        if (nested || entryBranch == EntryBranch::FlatInterior)
            builder.placeLabel(exit);
        if (nested)
        {
            const MicroLabelRef inner = builder.createLabel();
            builder.placeLabel(inner);
            for (uint32_t i = 0; i < (entryBranch == EntryBranch::WideInterior ? 43u : 13u); ++i)
                builder.emitNop();
            builder.emitCmpRegReg(RAX, RCX, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, inner);
        }
        builder.emitCmpRegReg(RAX, RCX, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, header);
        if (entryBranch == EntryBranch::Exit)
            builder.placeLabel(exit);
        builder.emitRet();

        MicroRegisterAllocationPass regAllocPass;
        MicroLegalizePass           legalizePass;
        MicroEmitPass               emitPass;
        emitPass.setAlignLoopHeaders(true);
        MicroPassManager passes;
        passes.addStartPass(regAllocPass);
        passes.addStartPass(legalizePass);
        passes.addStartPass(regAllocPass);
        passes.addStartPass(emitPass);

        X64Encoder       encoder(ctx);
        MicroPassContext passContext;
        SWC_RESULT(builder.runPasses(passes, &encoder, passContext));

        out.size          = encoder.size();
        out.codeAlignment = passContext.codeAlignment;
        if (out.size < 6 || encoder.byteAt(out.size - 1) != K_RET || encoder.byteAt(out.size - 3) != K_JB_SHORT)
            return Result::Error;
        if (entryBranch != EntryBranch::None)
        {
            for (uint32_t index = 0; index + 1 < out.size - 3; ++index)
                if (encoder.byteAt(index) == K_JB_SHORT && encoder.byteAt(index + 1) < 128)
                {
                    out.entryGroupStart = index - 3;
                    out.entryGroupEnd   = index + 2;
                    break;
                }
        }
        out.groupEnd   = out.size - 1;
        out.groupStart = out.groupEnd - 2 - 3;
        if (nested)
        {
            out.nestedEnd   = out.groupStart;
            out.nestedStart = out.nestedEnd + static_cast<int8_t>(encoder.byteAt(out.nestedEnd - 1));
        }
        return Result::Continue;
    }

    bool groupClearOfBoundary(const EmittedLoop& loop)
    {
        return loop.groupStart / 32 == (loop.groupEnd - 1) / 32 && loop.groupEnd % 32 != 0;
    }
}

// The closing cmp/jb would sit at 29..33 and cross the 32-byte boundary; the header moves
// to the other half of the window and the function asks for a 32-byte start.
SWC_TEST_BEGIN(MicroEmit_LoopBranchGroupAvoidsBoundary)
{
    EmittedLoop loop;
    SWC_RESULT(emitLoop(ctx, 13, loop));
    if (!groupClearOfBoundary(loop) || loop.codeAlignment != 32)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A closing pair already inside its window leaves the header on its 16-byte boundary.
SWC_TEST_BEGIN(MicroEmit_LoopBranchGroupInsideWindowStays)
{
    EmittedLoop loop;
    SWC_RESULT(emitLoop(ctx, 5, loop));
    if (!groupClearOfBoundary(loop) || loop.codeAlignment != 16 || loop.groupStart != 16 + 5)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A first forward branch can cross the boundary even when the back edge fits.
// Header padding repairs both groups without putting a nop on either loop path.
SWC_TEST_BEGIN(MicroEmit_LoopEntryBranchGroupAvoidsBoundary)
{
    EmittedLoop loop;
    SWC_RESULT(emitLoop(ctx, 13, loop, EntryBranch::Interior));
    if (!groupClearOfBoundary(loop) || loop.codeAlignment != 32 || !loop.entryGroupEnd ||
        loop.entryGroupStart / 32 != (loop.entryGroupEnd - 1) / 32 || loop.entryGroupEnd % 32 == 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Exit tests and flat loops cannot repay a header shift with nested padding.
SWC_TEST_BEGIN(MicroEmit_LoopEntryBranchNeedsReusablePadding)
{
    EmittedLoop exitLoop;
    SWC_RESULT(emitLoop(ctx, 13, exitLoop, EntryBranch::Exit));
    EmittedLoop conflicting;
    SWC_RESULT(emitLoop(ctx, 15, conflicting, EntryBranch::FlatInterior));
    EmittedLoop flat;
    SWC_RESULT(emitLoop(ctx, 13, flat, EntryBranch::FlatInterior));
    if (exitLoop.codeAlignment != 16 || conflicting.codeAlignment != 16 || flat.codeAlignment != 16 ||
        !groupClearOfBoundary(exitLoop) || !groupClearOfBoundary(conflicting))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The containing header may choose the other half of a 64-byte line. Padding
// stays outside the outer loop, and the nested loop keeps its 32-byte branch phase.
SWC_TEST_BEGIN(MicroEmit_LoopEntryShiftPreservesNestedFetchWindow)
{
    EmittedLoop loop;
    SWC_RESULT(emitLoop(ctx, 13, loop, EntryBranch::WideInterior));
    if (loop.codeAlignment != 64 || loop.nestedStart % 64 || loop.nestedEnd - loop.nestedStart != 48 ||
        !groupClearOfBoundary(loop) || loop.entryGroupStart / 32 != (loop.entryGroupEnd - 1) / 32)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
