#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/MicroVerify.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class SilentMutationPass final : public MicroPass
    {
    public:
        std::string_view name() const override
        {
            return "unittest-silent-mutation";
        }

        Result run(MicroPassContext& context) override
        {
            auto it = context.instructions->view().begin();
            if (it == context.instructions->view().end())
                return Result::Continue;

            it->op = MicroInstrOpcode::Breakpoint;
            return Result::Continue;
        }
    };

    class FalsePositiveChangedPass final : public MicroPass
    {
    public:
        std::string_view name() const override
        {
            return "unittest-false-positive-changed";
        }

        Result run(MicroPassContext& context) override
        {
            context.passChanged = true;
            return Result::Continue;
        }
    };

    class ToggleOscillationPass final : public MicroPass
    {
    public:
        std::string_view name() const override
        {
            return "unittest-toggle-oscillation";
        }

        Result run(MicroPassContext& context) override
        {
            auto it = context.instructions->view().begin();
            if (it == context.instructions->view().end())
                return Result::Continue;

            it->op              = it->op == MicroInstrOpcode::Nop ? MicroInstrOpcode::Breakpoint : MicroInstrOpcode::Nop;
            context.passChanged = true;
            return Result::Continue;
        }
    };
}

SWC_TEST_BEGIN(MicroVerify_RejectsUndefinedJumpLabel)
    MicroBuilder     builder(ctx);
    MicroPassContext passContext;
    passContext.microVerify = true;
    passContext.taskContext  = &ctx;
    passContext.builder      = &builder;
    passContext.instructions = &builder.instructions();
    passContext.operands     = &builder.operands();

    const MicroLabelRef missingLabel = builder.createLabel();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, missingLabel);

    if (MicroVerify::verify(passContext, "unit-verify") != Result::Error)
        return Result::Error;
SWC_TEST_END()

SWC_TEST_BEGIN(MicroVerify_IsDisabledByDefaultForPassManager)
    MicroBuilder builder(ctx);
    builder.emitNop();

    SilentMutationPass pass;
    MicroPassManager   passes;
    passes.addStartPass(pass);

    MicroPassContext passContext;
    const Result     result = builder.runPasses(passes, nullptr, passContext);
    if (result != Result::Continue)
        return Result::Error;
SWC_TEST_END()

SWC_TEST_BEGIN(MicroVerify_RejectsSilentMutationWithoutPassChanged)
    MicroBuilder builder(ctx);
    builder.emitNop();

    SilentMutationPass pass;
    MicroPassManager   passes;
    passes.addStartPass(pass);

    MicroPassContext passContext;
    passContext.microVerify = true;
    const Result result = builder.runPasses(passes, nullptr, passContext);

#if SWC_DEV_MODE
    if (result != Result::Error)
        return Result::Error;
#else
    if (result != Result::Continue)
        return Result::Error;
#endif
SWC_TEST_END()

SWC_TEST_BEGIN(MicroVerify_RejectsReportedChangeWithoutMutation)
    MicroBuilder builder(ctx);
    builder.emitNop();

    FalsePositiveChangedPass pass;
    MicroPassManager         passes;
    passes.addStartPass(pass);

    MicroPassContext passContext;
    passContext.microVerify = true;
    const Result result = builder.runPasses(passes, nullptr, passContext);

#if SWC_DEV_MODE
    if (result != Result::Error)
        return Result::Error;
#else
    if (result != Result::Continue)
        return Result::Error;
#endif
SWC_TEST_END()

SWC_TEST_BEGIN(MicroVerify_DetectsLoopOscillation)
    MicroBuilder builder(ctx);
    builder.emitNop();

    ToggleOscillationPass pass;
    MicroPassManager      passes;
    passes.addLoopPass(pass);

    MicroPassContext passContext;
    passContext.microVerify             = true;
    passContext.optimizationIterationLimit = 4;
    const Result result = builder.runPasses(passes, nullptr, passContext);

#if SWC_DEV_MODE
    if (result != Result::Error)
        return Result::Error;
#else
    if (result != Result::Continue)
        return Result::Error;
#endif
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
