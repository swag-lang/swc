#include "pch.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/FileManager.h"
#include "Main/Global.h"
#include "Parser/ParserJob.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

namespace Command
{
    void format(CompilerInstance& compiler)
    {
        const TaskContext ctx(compiler.context());
        const auto&       global   = ctx.global();
        auto&             fileMgr  = compiler.context().fileMgr();
        auto&             jobMgr   = global.jobMgr();
        const auto        clientId = compiler.context().jobClientId();

        if (fileMgr.collectFiles(ctx) == Result::Error)
            return;

        for (const auto& f : fileMgr.files())
        {
            auto job = std::make_shared<ParserJob>(ctx, f);
            jobMgr.enqueue(job, JobPriority::Normal, clientId);
        }

        global.jobMgr().waitAll(clientId);
    }
}

SWC_END_NAMESPACE()
