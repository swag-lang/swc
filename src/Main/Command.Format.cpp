#include "pch.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Memory/Heap.h"
#include "Parser/ParserJob.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

namespace Command
{
    void format(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);
        const auto& global   = ctx.global();
        auto&       jobMgr   = global.jobMgr();
        const auto  clientId = compiler.jobClientId();

        if (compiler.collectFiles(ctx) == Result::Stop)
            return;

        for (const auto& f : compiler.files())
        {
            const auto job = heapNew<ParserJob>(ctx, f);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        global.jobMgr().waitAll(clientId);
    }
}

SWC_END_NAMESPACE()
