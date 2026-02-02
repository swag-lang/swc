#include "pch.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

SemaJob::SemaJob(const TaskContext& ctx, SemaContext& semaContext, bool declPass) :
    Job(ctx, JobKind::Sema),
    sema_(Job::ctx(), semaContext, declPass)
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

SWC_END_NAMESPACE();
