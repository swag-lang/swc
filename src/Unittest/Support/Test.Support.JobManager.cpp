#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Support/Thread/JobManager.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class SleepOnceJob final : public Job
    {
    public:
        explicit SleepOnceJob(const TaskContext& ctx) :
            Job(ctx, JobKind::Parser)
        {
        }

        JobResult exec() override
        {
            if (slept_)
            {
                ctx().state().setNone();
                return JobResult::Done;
            }

            slept_ = true;

            TaskState& wait = ctx().state();
            wait.kind       = TaskStateKind::SemaWaitIdentifier;
            wait.codeRef    = SourceCodeRef::invalid();
            wait.nodeRef    = AstNodeRef::invalid();
            wait.idRef      = IdentifierRef::invalid();
            return JobResult::Sleep;
        }

    private:
        bool slept_ = false;
    };
}

SWC_TEST_BEGIN(JobManager_DebugStateReportsSleepingJobs)
{
    CommandLine cmdLine;
    cmdLine.numCores = 1;

    JobManager jobMgr;
    jobMgr.setup(cmdLine);

    const Global      global;
    const TaskContext jobCtx(global, cmdLine);
    const auto        clientId = jobMgr.newClientId();

    SleepOnceJob job(jobCtx);
    jobMgr.enqueue(job, JobPriority::Normal, clientId);
    jobMgr.waitAll(clientId);

#if SWC_DEV_MODE
    if (!jobMgr.debugHasWaitingJobs(clientId))
        return Result::Error;

    const Utf8 state = jobMgr.debugDescribeState(clientId);
    if (state.find("waiting=1") == Utf8::npos)
        return Result::Error;
    if (state.find("kind=Parser") == Utf8::npos)
        return Result::Error;
    if (state.find("wait=Wait identifier") == Utf8::npos)
        return Result::Error;
#endif

    if (!jobMgr.wakeAll(clientId))
        return Result::Error;

    jobMgr.waitAll(clientId);

#if SWC_DEV_MODE
    if (jobMgr.debugHasWaitingJobs(clientId))
        return Result::Error;
#endif
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
