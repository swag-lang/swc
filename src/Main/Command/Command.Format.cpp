#include "pch.h"
#include "Main/Command/Command.h"
#include "Format/FormatJob.h"
#include "Format/FormatOptionsLoader.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Memory/Heap.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    void format(CompilerInstance& compiler)
    {
        TaskContext    ctx(compiler);
        ScopedTimedLog stage(ctx, ScopedTimedLog::Stage::Format);

        const Global&     global       = ctx.global();
        JobManager&       jobMgr       = global.jobMgr();
        const JobClientId clientId     = compiler.jobClientId();
        const uint64_t    errorsBefore = Stats::getNumErrors();

        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        constexpr ParserJobOptions parserOptions = {
            .emitTrivia                 = true,
            .ignoreGlobalCompilerIfSkip = true,
        };

        FormatOptionsLoader     optionsLoader(ctx);
        std::vector<FormatJob*> jobs;
        jobs.reserve(compiler.files().size());

        for (SourceFile* file : compiler.files())
        {
            if (!file)
                continue;

            // The runtime bootstrap is always part of the input set, but it is a compiler
            // resource and must never be rewritten by a user `format` invocation.
            if (file->isRuntime())
                continue;

            FormatOptions formatOptions;
            if (optionsLoader.resolve(file->path(), formatOptions) != Result::Continue)
                return;

            auto* job = heapNew<FormatJob>(ctx, file, formatOptions, parserOptions);
            jobs.push_back(job);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

        if (Stats::getNumErrors() != errorsBefore)
            return;

        size_t rewrittenFiles      = 0;
        size_t skippedFmtFiles     = 0;
        size_t skippedInvalidFiles = 0;
        for (const FormatJob* job : jobs)
        {
            if (job->rewritten())
                rewrittenFiles++;
            if (job->skippedFmt())
                skippedFmtFiles++;
            if (job->skippedInvalid())
                skippedInvalidFiles++;
        }

        std::vector<Utf8> statItems;
        statItems.push_back(ScopedTimedLog::formatStatCount(ctx, jobs.size(), "file"));
        if (rewrittenFiles)
            statItems.push_back(ScopedTimedLog::formatStatCount(ctx, rewrittenFiles, "rewritten file"));
        if (skippedFmtFiles)
            statItems.push_back(ScopedTimedLog::formatStatCount(ctx, skippedFmtFiles, "format-skipped file"));
        if (skippedInvalidFiles)
            statItems.push_back(ScopedTimedLog::formatStatCount(ctx, skippedInvalidFiles, "skipped invalid file"));

        stage.setStat(ScopedTimedLog::joinStatItems(ctx, statItems));
    }
}

SWC_END_NAMESPACE();
