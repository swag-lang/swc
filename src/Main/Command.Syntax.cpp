#include "pch.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Parser/Ast/Ast.h"
#include "Parser/Parser/Parser.h"
#include "Parser/Parser/ParserJob.h"
#include "Support/Memory/Heap.h"
#include "Support/Thread/Job.h"
#include "Support/Thread/JobManager.h"
#include "Wmf/SourceFile.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE();

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
            const auto job = heapNew<ParserJob>(ctx, f);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(compiler.jobClientId());

        for (const auto& f : compiler.files())
        {
            const auto& srcView = f->ast().srcView();
            if (srcView.mustSkip())
                continue;
            f->unitTest().verifyUntouchedExpected(ctx, srcView);
        }
    }
}

SWC_END_NAMESPACE();
