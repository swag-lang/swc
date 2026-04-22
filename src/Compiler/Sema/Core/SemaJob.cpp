#include "pch.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"
#include "Support/Memory/MemoryProfile.h"
#if SWC_HAS_STATS
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#endif

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

JobResult SemaJob::exec()
{
    SWC_MEM_SCOPE("Sema");
#if SWC_HAS_STATS
    Timer time(&Stats::get().timeSema);
#endif
    const JobResult result = sema_.exec();
    if (result == JobResult::Done &&
        enqueueFullPassAfterDecl_ &&
        sema_.isDeclPass())
    {
        auto* fullPassJob = heapNew<SemaJob>(Job::ctx(), sema_.nodePayloadContext(), false);
        sema_.compiler().global().jobMgr().enqueue(*fullPassJob, JobPriority::Normal, sema_.compiler().jobClientId());
        sema_.compiler().notifyAlive();
    }

    return result;
}

SWC_END_NAMESPACE();
