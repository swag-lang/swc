#include "pch.h"
#include "CompilerInstance.h"
#include "Main/CompilerCommand.h"
#include "Main/FileManager.h"
#include "Main/Global.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

namespace CompilerCommand
{
    Result syntax(const CompilerInstance& compiler)
    {
        const TaskContext ctx(compiler.context());
        const auto&       global  = ctx.global();
        auto&             fileMgr = global.fileMgr();

        if (fileMgr.collectFiles(ctx) == Result::Error)
            return Result::Error;

        for (const auto& f : global.fileMgr().files())
        {
            auto job  = std::make_shared<Job>(compiler.context());
            job->func = [f](TaskContext& taskCtx) {
                Parser parser;
                taskCtx.setSourceFile(f);
                parser.parse(taskCtx);
                return JobResult::Done;
            };

            global.jobMgr().enqueue(job, JobPriority::Normal, compiler.context().jobClientId());
        }

        global.jobMgr().waitAll(compiler.context().jobClientId());

        auto result = Result::Success;
        for (const auto& f : fileMgr.files())
        {
            if (f->unittest().verifyUntouchedExpected(ctx) == Result::Error)
                result = Result::Error;
        }

        return result;
    }
}

SWC_END_NAMESPACE()
