#pragma once
#include "Main/TaskContext.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

namespace SemaCycle
{
    void check(TaskContext& ctx, JobClientId clientId);
}

SWC_END_NAMESPACE()
