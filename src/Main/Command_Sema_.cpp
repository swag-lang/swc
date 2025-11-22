#include "pch.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Parser/Ast.h"
#include "Parser/ParserJob.h"
#include "Sema/SemaJob.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()

namespace Command
{
    void sema(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);
        const auto& global   = ctx.global();
        auto&       jobMgr   = global.jobMgr();
        const auto  clientId = compiler.jobClientId();

        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        for (const auto& f : compiler.files())
        {
            auto job = std::make_shared<ParserJob>(ctx, f);
            jobMgr.enqueue(job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

        for (const auto& f : compiler.files())
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
