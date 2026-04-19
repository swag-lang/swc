#include "pch.h"
#include "Format/FormatJob.h"
#include "Compiler/SourceFile.h"
#include "Format/Formatter.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

FormatJob::FormatJob(const TaskContext& ctx, SourceFile* file, const FormatOptions& formatOptions, const ParserJobOptions parserOptions) :
    Job(ctx, JobKind::Format),
    file_(file),
    formatOptions_(formatOptions),
    parserOptions_(parserOptions)
{
}

JobResult FormatJob::exec()
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
#if SWC_HAS_STATS
        Stats::get().numFormatSkippedInvalidFiles.fetch_add(1, std::memory_order_relaxed);
#endif
        return JobResult::Done;
    }

    Formatter formatter(formatOptions_);
    formatter.prepare(*file_);
    skippedFmt_ = formatter.skipped();
    if (skippedFmt_)
    {
#if SWC_HAS_STATS
        Stats::get().numFormatSkipFmtFiles.fetch_add(1, std::memory_order_relaxed);
#endif
    }

    const Result writeResult = formatter.write(jobCtx);
    rewritten_               = writeResult == Result::Continue && formatter.changed();
    if (rewritten_)
    {
        Stats::get().numFormatRewrittenFiles.fetch_add(1, std::memory_order_relaxed);
    }
    return toJobResult(jobCtx, writeResult);
}

SWC_END_NAMESPACE();
