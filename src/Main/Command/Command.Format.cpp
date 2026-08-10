#include "pch.h"
#include "Main/Command/Command.h"
#include "Format/FormatJob.h"
#include "Format/FormatOptionsLoader.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // `--dump-config` answers "what would you do here", so it resolves the
    // cascade for the first named input, exactly like a real run would. Without
    // an input there is still an answer: the configuration of the current
    // directory.
    fs::path dumpConfigDirectory(const CommandLine& cmdLine)
    {
        if (!cmdLine.files.empty())
            return cmdLine.files.begin()->parent_path();
        if (!cmdLine.directories.empty())
            return *cmdLine.directories.begin();
        if (!cmdLine.modulePath.empty())
            return cmdLine.modulePath;
        return FileSystem::currentPathNoThrow();
    }

    void dumpFormatConfig(TaskContext& ctx)
    {
        FormatOptionsLoader loader(ctx, ctx.cmdLine().formatStyle);
        FormatOptions       options;
        if (loader.resolveDirectory(dumpConfigDirectory(ctx.cmdLine()), options) != Result::Continue)
            return;
        Logger::print(ctx, FormatOptionsLoader::describe(options));
    }
}

namespace Command
{
    void format(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);
        if (ctx.cmdLine().dumpFormatConfig)
            return dumpFormatConfig(ctx);

        std::optional<ScopedTimedLog> stage;
        if (ScopedTimedLog::isOutputEnabled(ctx, ScopedTimedLog::Stage::Format))
            stage.emplace(ctx, ScopedTimedLog::Stage::Format);

        const Global&     global       = ctx.global();
        JobManager&       jobMgr       = global.jobMgr();
        const JobClientId clientId     = compiler.jobClientId();
        const uint64_t    errorsBefore = Stats::getNumErrors();

        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        // Reserved `__` identifiers are legal in runtime sources and must not
        // prevent the formatter from parsing them.
        constexpr ParserJobOptions parserOptions = {
            .emitTrivia                 = true,
            .ignoreGlobalCompilerIfSkip = true,
            .allowReservedIdentifiers   = true,
        };

        FormatOptionsLoader     optionsLoader(ctx, ctx.cmdLine().formatStyle);
        std::vector<FormatJob*> jobs;
        jobs.reserve(compiler.files().size());

        const auto insideDotDirectory = [](const fs::path& path) {
            for (const fs::path& part : path)
            {
                const std::string component = part.string();
                if (component.size() > 1 && component[0] == '.' && component != "..")
                    return true;
            }
            return false;
        };

        for (SourceFile* file : compiler.files())
        {
            if (!file)
                continue;

            // The runtime bootstrap is always part of the input set, but it is a compiler
            // resource and must never be rewritten by a user `format` invocation.
            if (file->isRuntime())
                continue;

            // Generated caches (`.dep`, ...) hold compiler-produced sources
            // that must never be reformatted.
            if (insideDotDirectory(file->path()))
                continue;

            FormatOptions formatOptions;
            if (optionsLoader.resolve(file->path(), formatOptions) != Result::Continue)
                return;

            auto* job = compiler.makeJob<FormatJob>(ctx, file, formatOptions, parserOptions);
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
            statItems.push_back(ScopedTimedLog::formatStatCount(ctx, skippedInvalidFiles, "parse-error file"));

        if (stage)
            stage->setStat(ScopedTimedLog::joinStatItems(ctx, statItems));
    }
}

SWC_END_NAMESPACE();
