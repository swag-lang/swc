#include "pch.h"
#include "Main/Command/Command.h"
#include "Format/FormatJob.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Memory/Heap.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 formatStageStat(const size_t totalFiles, const size_t rewrittenFiles, const size_t skippedFmtFiles, const size_t skippedInvalidFiles)
    {
        Utf8              stat = Utf8Helper::countWithLabel(totalFiles, "file");
        std::vector<Utf8> details;
        if (rewrittenFiles)
            details.push_back(Utf8Helper::countWithLabel(rewrittenFiles, "rewritten file"));
        if (skippedFmtFiles)
            details.push_back(Utf8Helper::countWithLabel(skippedFmtFiles, "skipfmt file"));
        if (skippedInvalidFiles)
            details.push_back(Utf8Helper::countWithLabel(skippedInvalidFiles, "skipped invalid file"));

        if (!details.empty())
        {
            stat += " (";
            for (size_t i = 0; i < details.size(); ++i)
            {
                if (i)
                    stat += ", ";
                stat += details[i];
            }

            stat += ")";
        }

        return stat;
    }
}

namespace Command
{
    void format(CompilerInstance& compiler)
    {
        TaskContext                 ctx(compiler);
        TimedActionLog::ScopedStage stage(ctx, TimedActionLog::Stage::Format);
        const Global&               global       = ctx.global();
        JobManager&                 jobMgr       = global.jobMgr();
        const JobClientId           clientId     = compiler.jobClientId();
        const uint64_t              errorsBefore = Stats::getNumErrors();

        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        constexpr ParserJobOptions parserOptions = {
            .emitTrivia       = true,
            .ignoreGlobalSkip = true,
        };

        constexpr FormatOptions formatOptions;
        std::vector<FormatJob*> jobs;
        jobs.reserve(compiler.files().size());

        for (SourceFile* file : compiler.files())
        {
            if (!file)
                continue;

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

        stage.setStat(formatStageStat(jobs.size(), rewrittenFiles, skippedFmtFiles, skippedInvalidFiles));
    }
}

SWC_END_NAMESPACE();
