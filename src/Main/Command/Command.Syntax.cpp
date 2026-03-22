#include "pch.h"
#include "Main/Command/Command.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Memory/Heap.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Support/Thread/Job.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    fs::path commonPathPrefix(const fs::path& lhs, const fs::path& rhs)
    {
        fs::path result;
        auto     itLhs = lhs.begin();
        auto     itRhs = rhs.begin();
        while (itLhs != lhs.end() && itRhs != rhs.end() && *itLhs == *itRhs)
        {
            result /= *itLhs;
            ++itLhs;
            ++itRhs;
        }

        return result;
    }

    Utf8 displayPath(const fs::path& path)
    {
        std::error_code ec;
        const fs::path  currentPath = fs::current_path(ec);
        if (!ec)
        {
            std::error_code relEc;
            const fs::path  relative = fs::relative(path, currentPath, relEc);
            if (!relEc && !relative.empty())
                return Utf8{relative.generic_string()};
        }

        return Utf8{path.generic_string()};
    }

    Utf8 formatSourceLocation(const std::vector<fs::path>& roots)
    {
        if (roots.empty())
            return "sources";

        fs::path          commonRoot;
        std::vector<Utf8> labels;
        for (const fs::path& root : roots)
        {
            const fs::path normalized = root.lexically_normal();
            if (commonRoot.empty())
                commonRoot = normalized;
            else
                commonRoot = commonPathPrefix(commonRoot, normalized);

            labels.push_back(displayPath(normalized));
        }

        std::ranges::sort(labels);
        labels.erase(std::ranges::unique(labels).begin(), labels.end());

        if (labels.size() == 1)
            return labels.front();

        if (!commonRoot.empty() && commonRoot != "." && commonRoot != commonRoot.root_path())
            return displayPath(commonRoot);

        return std::format("{} locations", Utf8Helper::toNiceBigNumber(labels.size()));
    }

    Utf8 formatCommandSourceRoots(const CommandLine& cmdLine)
    {
        std::vector<fs::path> roots;
        if (!cmdLine.modulePath.empty())
            roots.push_back(cmdLine.modulePath);
        for (const fs::path& folder : cmdLine.directories)
            roots.push_back(folder);
        for (const fs::path& file : cmdLine.files)
            roots.push_back(file.parent_path().empty() ? file : file.parent_path());

        return formatSourceLocation(roots);
    }
}

namespace Command
{
    void syntax(CompilerInstance& compiler)
    {
        TaskContext                 ctx(compiler);
        TimedActionLog::ScopedStage stage(ctx, {
                                                   .key    = "syntax",
                                                   .label  = "Syntax",
                                                   .verb   = "shaping syntax",
                                                   .detail = formatCommandSourceRoots(ctx.cmdLine()),
                                               });
        const Global&               global   = ctx.global();
        JobManager&                 jobMgr   = global.jobMgr();
        const JobClientId           clientId = compiler.jobClientId();

        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        for (SourceFile* f : compiler.files())
        {
            auto* job = heapNew<ParserJob>(ctx, f);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(compiler.jobClientId());

        if (Stats::get().numErrors.load() == 0)
        {
            for (SourceFile* f : compiler.files())
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
