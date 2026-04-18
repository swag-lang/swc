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
    Utf8 formatStageStat(const size_t totalFiles, const size_t rewrittenFiles, const size_t skippedFiles)
    {
        Utf8 stat = Utf8Helper::countWithLabel(totalFiles, "file");
        std::vector<Utf8> details;
        if (rewrittenFiles)
            details.push_back(Utf8Helper::countWithLabel(rewrittenFiles, "rewritten file"));
        if (skippedFiles)
            details.push_back(Utf8Helper::countWithLabel(skippedFiles, "skipfmt file"));

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
        const Global&               global   = ctx.global();
        JobManager&                 jobMgr   = global.jobMgr();
        const JobClientId           clientId = compiler.jobClientId();

        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        const uint64_t   errorsBefore = Stats::getNumErrors();
        ParserJobOptions parserOptions = {
            .emitTrivia       = true,
            .ignoreGlobalSkip = true,
        };

        for (SourceFile* file : compiler.files())
        {
            auto* job = heapNew<ParserJob>(ctx, file, parserOptions);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);
        if (Stats::getNumErrors() != errorsBefore)
            return;

        Format::Options                  options;
        std::vector<Format::PreparedFile> preparedFiles;
        preparedFiles.reserve(compiler.files().size());

        for (SourceFile* file : compiler.files())
        {
            if (!file)
                continue;

            Format::PreparedFile preparedFile;
            if (Format::prepareFile(ctx, *file, options, preparedFile) != Result::Continue)
                return;
            preparedFiles.push_back(std::move(preparedFile));
        }

        size_t rewrittenFiles = 0;
        size_t skippedFiles   = 0;
        for (const Format::PreparedFile& preparedFile : preparedFiles)
        {
            if (Format::writeFile(ctx, preparedFile) != Result::Continue)
                return;
            if (preparedFile.skipped)
                skippedFiles++;
            if (preparedFile.changed)
                rewrittenFiles++;
        }

        stage.setStat(formatStageStat(preparedFiles.size(), rewrittenFiles, skippedFiles));
    }
}

SWC_END_NAMESPACE();
