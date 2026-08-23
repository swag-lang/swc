#include "pch.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Main/Global.h"

SWC_BEGIN_NAMESPACE();

SemaJob::SemaJob(const TaskContext& ctx, NodePayload& nodePayloadContext, const bool declPass) :
    SemaJob(ctx, nodePayloadContext, declPass, false)
{
}

SemaJob::SemaJob(const TaskContext& ctx, NodePayload& nodePayloadContext, const bool declPass, const bool enqueueFullPassAfterDecl) :
    Job(ctx, JobKind::Sema),
    sema_(Job::ctx(), nodePayloadContext, declPass),
    enqueueFullPassAfterDecl_(enqueueFullPassAfterDecl)
{
}

SemaJob::SemaJob(const TaskContext& ctx, Sema& parentSema, AstNodeRef root) :
    Job(ctx, JobKind::Sema),
    sema_(Job::ctx(), parentSema, root)
{
}

SemaJob::SemaJob(const TaskContext& ctx, Sema& parentSema, NodePayload& nodePayloadContext, AstNodeRef root) :
    Job(ctx, JobKind::Sema),
    sema_(Job::ctx(), parentSema, nodePayloadContext, root)
{
}

JobResult SemaJob::exec()
{
    const JobResult result = sema_.exec();
    if (result == JobResult::Done &&
        enqueueFullPassAfterDecl_ &&
        sema_.isDeclPass())
    {
        auto* fullPassJob = sema_.compiler().makeJob<SemaJob>(ctx(), sema_.nodePayloadContext(), false);
        sema_.compiler().global().jobMgr().enqueue(*fullPassJob, JobPriority::Normal, sema_.compiler().jobClientId());
        sema_.compiler().notifyAlive();
    }

    return result;
}

SWC_END_NAMESPACE();
