#include "pch.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

JobResult Job::toJobResult(const TaskContext& ctx, Result result)
{
    if (result == Result::Pause)
    {
        // Sleeping jobs must expose an actionable wait state so deadlock/error reporting
        // can attribute the pause to the right semantic dependency.
        SWC_INTERNAL_CHECK(ctx.state().canPause());
        return JobResult::Sleep;
    }

    return JobResult::Done;
}

SWC_END_NAMESPACE();
