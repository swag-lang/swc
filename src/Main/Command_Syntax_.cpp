#include "pch.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/FileManager.h"
#include "Main/Global.h"
#include "Parser/Ast.h"
#include "Parser/Parser.h"
#include "Parser/ParserJob.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE()

namespace Command
{
    void syntax(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler.context());
        const auto& global   = ctx.global();
        auto&       fileMgr  = compiler.context().fileMgr();
        auto&       jobMgr   = global.jobMgr();
        const auto  clientId = compiler.context().jobClientId();

        if (fileMgr.collectFiles(ctx) == Result::Error)
            return;

        for (const auto& f : fileMgr.files())
        {
            auto job = std::make_shared<ParserJob>(ctx, f);
            jobMgr.enqueue(job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(compiler.context().jobClientId());

        for (const auto& f : fileMgr.files())
        {
            if (f->ast().lexOut().mustSkip())
                continue;
            f->unitTest().verifyUntouchedExpected(ctx, f->ast().lexOut());
        }
    }
}

SWC_END_NAMESPACE()
