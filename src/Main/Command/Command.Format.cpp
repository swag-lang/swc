#include "pch.h"
#include "Main/Command/Command.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/SourceFile.h"
#include "Format/Formatter.h"
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
    class FormatJob final : public Job
    {
    public:
        FormatJob(const TaskContext& ctx, SourceFile* file, const FormatOptions& formatOptions, const ParserJobOptions parserOptions) :
            Job(ctx, JobKind::Format),
            file_(file),
            formatOptions_(formatOptions),
            parserOptions_(parserOptions)
        {
        }

        JobResult exec() override
        {
            TaskContext& jobCtx = ctx();
            if (file_->loadContent(jobCtx) != Result::Continue)
                return JobResult::Done;

            const bool savedMuteOutput    = jobCtx.muteOutput();
            const bool savedReportToStats = jobCtx.reportToStats();
            jobCtx.setMuteOutput(true);
            jobCtx.setReportToStats(false);

            const Result parseResult = parseLoadedSourceFile(jobCtx, *file_, parserOptions_);

            jobCtx.setReportToStats(savedReportToStats);
            jobCtx.setMuteOutput(savedMuteOutput);

            if (parseResult != Result::Continue)
                return toJobResult(jobCtx, parseResult);
            if (jobCtx.hasError())
            {
                skippedInvalid_ = true;
                return JobResult::Done;
            }

            Formatter formatter(formatOptions_);
            formatter.prepare(*file_);
            skippedFmt_ = formatter.skipped();

            const Result writeResult = formatter.write(jobCtx);
            rewritten_               = writeResult == Result::Continue && formatter.changed();
            return toJobResult(jobCtx, writeResult);
        }

        bool rewritten() const { return rewritten_; }
        bool skippedFmt() const { return skippedFmt_; }
        bool skippedInvalid() const { return skippedInvalid_; }

    private:
        SourceFile*      file_ = nullptr;
        FormatOptions    formatOptions_{};
        ParserJobOptions parserOptions_{};
        bool             rewritten_      = false;
        bool             skippedFmt_     = false;
        bool             skippedInvalid_ = false;
    };

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
