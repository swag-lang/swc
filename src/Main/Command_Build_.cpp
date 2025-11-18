#include "pch.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/FileManager.h"
#include "Main/Global.h"
#include "Parser/Ast.h"
#include "Parser/ParserJob.h"
#include "Sema/SemaJob.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

namespace Command
{
    void build(CompilerInstance& compiler)
    {
        const TaskContext ctx(compiler.context());
        const auto&       global   = ctx.global();
        auto&             jobMgr   = global.jobMgr();
        auto&             fileMgr  = compiler.context().fileMgr();
        const auto        clientId = compiler.context().jobClientId();

        if (fileMgr.collectFiles(ctx) == Result::Error)
            return;

        for (const auto& f : fileMgr.files())
        {
            auto job = std::make_shared<ParserJob>(ctx, f);
            jobMgr.enqueue(job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

        for (const auto& f : fileMgr.files())
        {
            if (f->ast().root().isInvalid())
                continue;

            auto job = std::make_shared<SemaJob>(ctx, &f->ast(), f->ast().root());
            jobMgr.enqueue(job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);
    }
}

SWC_END_NAMESPACE()
