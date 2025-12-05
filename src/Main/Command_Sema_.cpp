#include "pch.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Memory/Heap.h"
#include "Parser/ParserJob.h"
#include "Report/DiagnosticDef.h"
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

        const auto&       global   = ctx.global();
        auto&             jobMgr   = global.jobMgr();
        const JobClientId clientId = compiler.jobClientId();

        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        for (const auto& f : compiler.files())
        {
            const auto job = heapNew<ParserJob>(ctx, f);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

        compiler.setupSema(ctx);

        for (const auto& f : compiler.files())
        {
            if (f->hasError())
                continue;
            const auto job = heapNew<SemaJob>(ctx, f->semaCtx());
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        while (true)
        {
            compiler.setSemaAlive(false);
            jobMgr.waitAll(clientId);
            if (!compiler.semaAlive())
                break;
            jobMgr.wakeAll(clientId);
        }

        std::vector<Job*> jobs;
        jobMgr.waitingJobs(jobs, clientId);
        for (const auto job : jobs)
        {
            const auto& state = job->ctx().state();
            if (const auto semaJob = job->safeCast<SemaJob>())
            {
                if (state.kind == TaskStateKind::SemaWaitingIdentifier)
                {
                    semaJob->sema().raiseError(DiagnosticId::sema_err_unknown_identifier, state.nodeRef);
                }
            }
        }
    }
}

SWC_END_NAMESPACE()
