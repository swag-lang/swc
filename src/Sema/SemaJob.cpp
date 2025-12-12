#include "pch.h"
#include "Sema/SemaJob.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

SemaJob::SemaJob(const TaskContext& ctx, SemaInfo& semaInfo) :
    Job(ctx, JobKind::Sema),
    sema_(Job::ctx(), semaInfo)
{
    func = [this] {
        return exec();
    };
}

SemaJob::SemaJob(const TaskContext& ctx, const Sema& parentSema, AstNodeRef root) :
    Job(ctx, JobKind::Sema),
    sema_(Job::ctx(), parentSema, root)
{
    func = [this] {
        return exec();
    };
}

JobResult SemaJob::exec()
{
    return sema_.exec();
}

SWC_END_NAMESPACE()
