#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Report/ScopedTimedAction.h"

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
                return Utf8(relative.generic_string());
        }

        return Utf8(path.generic_string());
    }

    Utf8 joinLabels(const std::vector<Utf8>& labels)
    {
        SWC_ASSERT(!labels.empty());

        Utf8 result;
        for (size_t i = 0; i < labels.size(); ++i)
        {
            if (i)
                result += ", ";
            result += labels[i];
        }

        return result;
    }

    std::vector<fs::path> collectChildRoots(const std::vector<fs::path>& roots, const fs::path& commonRoot)
    {
        std::vector<fs::path> result;
        const size_t          commonCount = std::distance(commonRoot.begin(), commonRoot.end());

        for (const fs::path& root : roots)
        {
            auto   it = root.begin();
            size_t i  = 0;
            while (it != root.end() && i < commonCount)
            {
                ++it;
                ++i;
            }

            if (it != root.end())
                result.push_back(commonRoot / *it);
        }

        std::ranges::sort(result);
        result.erase(std::ranges::unique(result).begin(), result.end());
        return result;
    }

    Utf8 formatSourceHierarchy(const std::vector<fs::path>& roots)
    {
        if (roots.empty())
            return "sources";

        fs::path commonRoot;
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
        {
            const auto childRoots = collectChildRoots(roots, commonRoot);
            if (!childRoots.empty())
            {
                std::vector<Utf8> childLabels;
                childLabels.reserve(childRoots.size());
                for (const fs::path& childRoot : childRoots)
                    childLabels.push_back(displayPath(childRoot));

                if (childLabels.size() <= 3)
                    return joinLabels(childLabels);

                return std::format("{} (+{} more)", childLabels.front(), childLabels.size() - 1);
            }

            return displayPath(commonRoot);
        }

        if (labels.size() <= 3)
            return joinLabels(labels);

        return std::format("{} (+{} more)", labels.front(), labels.size() - 1);
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

        return formatSourceHierarchy(roots);
    }

    bool hasNewErrors(const uint64_t errorsBefore)
    {
        return Stats::get().numErrors.load(std::memory_order_relaxed) != errorsBefore;
    }

    bool finishAction(ScopedTimedAction& action, const uint64_t errorsBefore)
    {
        if (hasNewErrors(errorsBefore))
        {
            action.fail();
            return false;
        }

        action.success();
        return true;
    }

    bool runNativeBackend(CompilerInstance& compiler, const Runtime::BuildCfgBackendKind backendKind, const bool runArtifact)
    {
        compiler.buildCfg().backendKind = backendKind;

        NativeBackendBuilder builder(compiler, runArtifact);
        if (builder.run() != Result::Continue)
            return false;

        return Stats::get().numErrors.load(std::memory_order_relaxed) == 0;
    }

    void runNativeCommand(CompilerInstance& compiler, const bool runArtifact)
    {
        const TaskContext ctx(compiler);
        TimedActionLog::printBuildConfiguration(ctx);
        ScopedTimedAction analyzeAction(ctx, "Analyze", formatCommandSourceRoots(ctx.cmdLine()));
        const uint64_t    errorsBefore = Stats::get().numErrors.load(std::memory_order_relaxed);
        Command::sema(compiler);
        if (!finishAction(analyzeAction, errorsBefore))
            return;

        const Runtime::BuildCfgBackendKind backendKind = compiler.buildCfg().backendKind;
        runNativeBackend(compiler, backendKind, runArtifact && backendKind == Runtime::BuildCfgBackendKind::Executable);
    }
}

namespace Command
{
    void build(CompilerInstance& compiler)
    {
        runNativeCommand(compiler, false);
    }

    void run(CompilerInstance& compiler)
    {
        runNativeCommand(compiler, true);
    }
}

SWC_END_NAMESPACE();
