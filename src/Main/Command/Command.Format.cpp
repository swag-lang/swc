#include "pch.h"
#include "Main/Command/Command.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/SourceFile.h"
#include "Format/Formatter.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct DiagnosticCounters
    {
        size_t errors   = 0;
        size_t warnings = 0;
    };

    DiagnosticCounters captureDiagnosticCounters()
    {
        const Stats& stats = Stats::get();
        return {
            .errors   = stats.numErrors.load(std::memory_order_relaxed),
            .warnings = stats.numWarnings.load(std::memory_order_relaxed),
        };
    }

    void restoreDiagnosticCounters(const DiagnosticCounters& counters)
    {
        Stats& stats = Stats::get();
        stats.numErrors.store(counters.errors, std::memory_order_relaxed);
        stats.numWarnings.store(counters.warnings, std::memory_order_relaxed);
    }

    Result parseFileForFormat(CompilerInstance& compiler, TaskContext& ctx, SourceFile& file, const ParserJobOptions& parserOptions, bool& parsedOk)
    {
        parsedOk = false;
        SWC_RESULT(file.loadContent(ctx));

        const DiagnosticCounters counters = captureDiagnosticCounters();
        TaskContext              parseCtx(compiler);
        parseCtx.setMuteOutput(true);

        ParserJob parseJob(parseCtx, &file, parserOptions);
        parseJob.exec();

        parsedOk = !file.hasError() && Stats::getNumErrors() == counters.errors;
        if (!parsedOk)
            restoreDiagnosticCounters(counters);

        return Result::Continue;
    }

    Utf8 formatStageStat(const size_t totalFiles, const size_t rewrittenFiles, const size_t skippedFmtFiles, const size_t skippedInvalidFiles)
    {
        Utf8 stat = Utf8Helper::countWithLabel(totalFiles, "file");
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

        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        ParserJobOptions parserOptions = {
            .emitTrivia       = true,
            .ignoreGlobalSkip = true,
        };

        Format::Options                   options;
        std::vector<Format::PreparedFile> preparedFiles;
        preparedFiles.reserve(compiler.files().size());

        size_t totalFiles          = 0;
        size_t skippedInvalidFiles = 0;
        for (SourceFile* file : compiler.files())
        {
            if (!file)
                continue;
            totalFiles++;

            bool parsedOk = false;
            if (parseFileForFormat(compiler, ctx, *file, parserOptions, parsedOk) != Result::Continue)
                return;
            if (!parsedOk)
            {
                skippedInvalidFiles++;
                continue;
            }

            Format::PreparedFile preparedFile;
            if (Format::prepareFile(ctx, *file, options, preparedFile) != Result::Continue)
                return;
            preparedFiles.push_back(std::move(preparedFile));
        }

        size_t rewrittenFiles = 0;
        size_t skippedFmtFiles = 0;
        for (const Format::PreparedFile& preparedFile : preparedFiles)
        {
            if (Format::writeFile(ctx, preparedFile) != Result::Continue)
                return;
            if (preparedFile.skipped)
                skippedFmtFiles++;
            if (preparedFile.changed)
                rewrittenFiles++;
        }

        stage.setStat(formatStageStat(totalFiles, rewrittenFiles, skippedFmtFiles, skippedInvalidFiles));
    }
}

SWC_END_NAMESPACE();
