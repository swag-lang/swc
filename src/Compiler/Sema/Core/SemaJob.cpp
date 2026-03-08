#include "pch.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Core/Sema.h"
#if SWC_HAS_STATS
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#endif

SWC_BEGIN_NAMESPACE();

SemaJob::SemaJob(const TaskContext& ctx, NodePayload& nodePayloadContext, bool declPass) :
    Job(ctx, JobKind::Sema),
    sema_(Job::ctx(), nodePayloadContext, declPass)
{
    func = [this] {
        return exec();
    };
}

SemaJob::SemaJob(const TaskContext& ctx, Sema& parentSema, AstNodeRef root) :
    Job(ctx, JobKind::Sema),
    sema_(Job::ctx(), parentSema, root)
{
    func = [this] {
        return exec();
    };
}

JobResult SemaJob::exec()
{
#if SWC_HAS_STATS
    Timer time(&Stats::get().timeSema);
#endif
    return sema_.exec();
}

SWC_END_NAMESPACE();
