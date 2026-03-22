#include "pch.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

JobResult Job::toJobResult(const TaskContext& ctx, Result result, const char* source)
{
    if (result == Result::Pause)
    {
        // Sleeping jobs must expose an actionable wait state so deadlock/error reporting
        // can attribute the pause to the right semantic dependency.
        if (!ctx.state().canPause())
        {
            const TaskState& state = ctx.state();
            std::fprintf(stderr,
                         "invalid pause state: source=%s kind=%s nodeValid=%d codeValid=%d idValid=%d symbol=%p waiter=%p runJit=%p codeGen=%p\n",
                         source ? source : "<unknown>",
                         state.kindName(),
                         state.nodeRef.isValid() ? 1 : 0,
                         state.codeRef.isValid() ? 1 : 0,
                         state.idRef.isValid() ? 1 : 0,
                         static_cast<const void*>(state.symbol),
                         static_cast<const void*>(state.waiterSymbol),
                         static_cast<const void*>(state.runJitFunction),
                         static_cast<const void*>(state.codeGenFunction));
            SWC_ASSERT(false);
        }
        return JobResult::Sleep;
    }

    return JobResult::Done;
}

SWC_END_NAMESPACE();
