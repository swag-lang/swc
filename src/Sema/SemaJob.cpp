#include "pch.h"
#include "Sema/SemaJob.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

SemaJob::SemaJob(TaskContext& ctx, Ast* ast, AstNodeRef root) :
    Job(ctx),
    sema_(ctx, ast, root)
{
    func = [this]() {
        return exec();
    };
}

JobResult SemaJob::exec()
{
    return sema_.exec();
}

SWC_END_NAMESPACE()
