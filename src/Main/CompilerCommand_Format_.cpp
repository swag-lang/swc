#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Main/FileManager.h"
#include "Main/Global.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void parseFile(JobContext& taskCtx, SourceFile* f)
    {
        Parser parser;
        taskCtx.setSourceFile(f);
        parser.parse(taskCtx);
    }
}

namespace CompilerCommand
{
    Result format(const CompilerInstance& compiler)
    {
        const TaskContext ctx(compiler.context());
        const auto&       global   = ctx.global();
        auto&             fileMgr  = global.fileMgr();
        const auto        clientId = compiler.context().jobClientId();

        if (fileMgr.collectFiles(ctx) == Result::Error)
            return Result::Error;

        for (const auto& f : global.fileMgr().files())
        {
            auto job  = std::make_shared<Job>(ctx);
            job->func = [f](JobContext& taskCtx) {
                parseFile(taskCtx, f);
                return JobResult::Done;
            };

            global.jobMgr().enqueue(job, JobPriority::Normal, clientId);
        }

        global.jobMgr().waitAll(clientId);

        for (const auto& f : fileMgr.files())
        {
        }

        return Result::Success;
    }
}

SWC_END_NAMESPACE()
