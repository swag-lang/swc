#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Encoder/X64Encoder.h"
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
        uint32_t size          = 0;
        uint32_t codeAlignment = 0;
        uint32_t groupStart    = 0; // cmp rax, rcx
        uint32_t groupEnd      = 0; // after the short jb
    };

    // One nop, then a loop of `bodyNops` nops closed by `cmp rax, rcx; jb header`, then ret.
    // With the header on its 16-byte boundary the closing pair starts at 16 + bodyNops.
    Result emitLoop(TaskContext& ctx, const uint32_t bodyNops, EmittedLoop& out)
    {
        MicroBuilder        builder(ctx);
        const MicroLabelRef header = builder.createLabel();
        builder.emitNop();
        builder.placeLabel(header);
        for (uint32_t i = 0; i < bodyNops; ++i)
            builder.emitNop();
        builder.emitCmpRegReg(RAX, RCX, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, header);
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
        out.groupEnd   = out.size - 1;
        out.groupStart = out.groupEnd - 2 - 3;
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

SWC_END_NAMESPACE();

#endif
