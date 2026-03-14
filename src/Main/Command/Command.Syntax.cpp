#include "pch.h"
#include "Main/Command/Command.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Memory/Heap.h"
#include "Support/Thread/Job.h"
#include "Support/Thread/JobManager.h"
#include "Compiler/Core/SourceFile.h"
#include "Compiler/Test/Verify.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    void syntax(CompilerInstance& compiler)
    {
        TaskContext       ctx(compiler);
        const Global&     global   = ctx.global();
        JobManager&       jobMgr   = global.jobMgr();
        const JobClientId clientId = compiler.jobClientId();

        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        for (SourceFile* const f : compiler.files())
        {
            auto* job = heapNew<ParserJob>(ctx, f);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(compiler.jobClientId());

        if (Stats::get().numErrors.load() == 0)
        {
            for (SourceFile* const f : compiler.files())
            {
                const SourceView& srcView = f->ast().srcView();
                if (srcView.mustSkip())
                    continue;
                f->unitTest().verifyUntouchedExpected(ctx, srcView);
            }
        }
    }
}

SWC_END_NAMESPACE();
