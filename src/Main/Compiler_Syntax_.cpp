#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Main/FileManager.h"
#include "Main/Global.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

Result CompilerInstance::cmdSyntax()
{
    const Context ctx(context_);

    const auto& global  = ctx.global();
    auto&       fileMgr = global.fileMgr();

    if (fileMgr.collectFiles(ctx) == Result::Error)
        return Result::Error;

    for (const auto& f : global.fileMgr().files())
    {
        auto job  = std::make_shared<Job>(context_);
        job->func = [f](Context& fnCtx) {
            Parser parser;
            fnCtx.setSourceFile(f);
            parser.parse(fnCtx);
            return JobResult::Done;
        };

        global.jobMgr().enqueue(job, JobPriority::Normal, context_.jobClientId());
    }

    global.jobMgr().waitAll(context_.jobClientId());

    auto result = Result::Success;
    for (const auto& f : fileMgr.files())
    {
        if (f->unittest().verifyUntouchedExpected(ctx) == Result::Error)
            result = Result::Error;
    }

    return result;
}

SWC_END_NAMESPACE()
