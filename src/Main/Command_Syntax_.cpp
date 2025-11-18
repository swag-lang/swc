#include "pch.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Parser/Ast.h"
#include "Parser/Parser.h"
#include "Parser/ParserJob.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"
#include "Wmf/SourceFile.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE()

namespace Command
{
    void syntax(CompilerInstance& compiler)
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

        jobMgr.waitAll(compiler.jobClientId());

        for (const auto& f : compiler.files())
        {
            if (f->ast().lexOut().mustSkip())
                continue;
            f->unitTest().verifyUntouchedExpected(ctx, f->ast().lexOut());
        }
    }
}

SWC_END_NAMESPACE()
