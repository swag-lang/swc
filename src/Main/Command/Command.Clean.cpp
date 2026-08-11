#include "pch.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandPrint.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Main/WorkspaceLayout.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // One directory the command was pointed at, labelled by what a build puts there rather than by
    // its name on disk, so the report reads next to the command that produced it.
    struct CleanTarget
    {
        Utf8     label;
        fs::path path;
        size_t   files = 0;
        size_t   bytes = 0;
    };

    void addCleanTarget(std::vector<CleanTarget>& outTargets, const std::string_view label, const fs::path& path)
    {
        const fs::path normalizedPath = FileSystem::normalizePath(path);
        for (const CleanTarget& target : outTargets)
        {
            if (FileSystem::pathEquals(target.path, normalizedPath))
                return;
        }

        CleanTarget target;
        target.label = Utf8(label);
        target.path  = normalizedPath;
        outTargets.push_back(std::move(target));
    }

    void collectWorkspaceCleanTargets(std::vector<CleanTarget>& outTargets, const CommandLine& cmdLine)
    {
        const fs::path& workspacePath = cmdLine.workspacePath;
        if (cmdLine.workspaceModuleFilter.empty())
        {
            addCleanTarget(outTargets, "Artifacts", WorkspaceLayout::workspaceOutputDirectory(workspacePath));
            addCleanTarget(outTargets, "Intermediate", WorkspaceLayout::workspaceWorkDirectory(workspacePath));
            addCleanTarget(outTargets, "Dependencies", WorkspaceLayout::workspaceDependencyDirectory(workspacePath));
            return;
        }

        // The mirrored dependencies are shared by every module of the workspace, so naming one
        // module leaves them where they are.
        const fs::path moduleDir(cmdLine.workspaceModuleFilter.c_str());
        addCleanTarget(outTargets, "Artifacts", WorkspaceLayout::workspaceOutputDirectory(workspacePath) / moduleDir);
        addCleanTarget(outTargets, "Intermediate", WorkspaceLayout::workspaceWorkDirectory(workspacePath) / moduleDir);
    }

    // A module outside a workspace writes under its own root, unless the command line moved its
    // output elsewhere — in which case that is where the build put it.
    void collectModuleCleanTargets(std::vector<CleanTarget>& outTargets, const CommandLine& cmdLine)
    {
        addCleanTarget(outTargets, "Artifacts", WorkspaceLayout::workspaceOutputDirectory(cmdLine.modulePath));
        if (!cmdLine.outDir.empty())
            addCleanTarget(outTargets, "Artifacts", cmdLine.outDir);
        if (!cmdLine.workDir.empty())
            addCleanTarget(outTargets, "Intermediate", cmdLine.workDir);
    }

    // Cache entries nothing has asked for in a while. Only a directory carrying the marker written
    // when an entry is published is a candidate — whatever else lives under the cache root was put
    // there by somebody else — and that marker's date is the last time an entry was used.
    void collectUnusedCacheEntryTargets(std::vector<CleanTarget>& outTargets, const uint32_t days)
    {
        const auto      maxAge = std::chrono::seconds(86400ULL * days);
        const auto      now    = fs::file_time_type::clock::now();
        std::error_code ec;
        for (fs::directory_iterator it(WorkspaceLayout::dependencyCacheRoot(), fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return;

            ec.clear();
            if (!it->is_directory(ec) || ec)
                continue;

            ec.clear();
            const auto usedTime = fs::last_write_time(it->path() / fs::path(std::string(WorkspaceLayout::DEPENDENCY_CACHE_USED_MARKER)), ec);
            if (ec || std::chrono::duration_cast<std::chrono::seconds>(now - usedTime) < maxAge)
                continue;

            addCleanTarget(outTargets, "Unused entry", it->path());
        }
    }

    void collectCacheCleanTargets(std::vector<CleanTarget>& outTargets, const CommandLine& cmdLine)
    {
        if (cmdLine.cleanCacheDays)
        {
            collectUnusedCacheEntryTargets(outTargets, cmdLine.cleanCacheDays);
            return;
        }

        // Only the compiler's own subdirectories: the cache root is a shared temporary directory,
        // and nothing else that lives there was put there by a build.
        addCleanTarget(outTargets, "Dependency cache", WorkspaceLayout::dependencyCacheRoot());
        addCleanTarget(outTargets, "Legacy script cache", WorkspaceLayout::legacyScriptCacheRoot());
    }

    void collectCleanTargets(std::vector<CleanTarget>& outTargets, const CommandLine& cmdLine)
    {
        if (!cmdLine.workspacePath.empty())
            collectWorkspaceCleanTargets(outTargets, cmdLine);
        else if (!cmdLine.modulePath.empty())
            collectModuleCleanTargets(outTargets, cmdLine);

        if (cmdLine.cleanCache)
            collectCacheCleanTargets(outTargets, cmdLine);
    }

    // Measures what removing the target frees. A directory that is not there is not an error: an
    // already clean tree is the state the command exists to reach.
    bool measureCleanTarget(CleanTarget& ioTarget)
    {
        std::error_code ec;
        if (!fs::is_directory(ioTarget.path, ec) || ec)
            return false;

        for (fs::recursive_directory_iterator it(ioTarget.path, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                break;

            ec.clear();
            if (!it->is_regular_file(ec) || ec)
                continue;

            ec.clear();
            const uintmax_t fileSize = it->file_size(ec);
            ioTarget.files++;
            if (!ec)
                ioTarget.bytes += fileSize;
        }

        return true;
    }

    Result removeCleanTarget(TaskContext& ctx, const CleanTarget& target)
    {
        std::error_code ec;
        fs::remove_all(target.path, ec);
        if (!ec)
            return Result::Continue;

        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_clean_remove_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, target.path, FileSystem::normalizeSystemMessage(ec));
        diag.report(ctx);
        return Result::Error;
    }

    Utf8 formatCleanAmount(const size_t files, const size_t bytes)
    {
        return std::format("{}, {}", Utf8Helper::countWithLabel(files, "file").c_str(), Utf8Helper::toNiceSize(bytes).c_str());
    }

    void printCleanReport(const TaskContext& ctx, std::span<const CleanTarget> targets, const size_t totalFiles, const size_t totalBytes)
    {
        using CommandPrint::addInfoEntry;
        using CommandPrint::addInfoEntryParts;

        std::vector<Logger::FieldEntry> entries;
        for (const CleanTarget& target : targets)
        {
            std::vector<Logger::FieldValuePart> parts;
            parts.push_back({.text = Utf8(target.path), .color = LogColor::BrightGreen});
            parts.push_back({.text = std::format(" ({})", formatCleanAmount(target.files, target.bytes).c_str()), .color = LogColor::Gray});
            addInfoEntryParts(entries, target.label.view(), std::move(parts));
        }

        if (entries.empty())
            addInfoEntry(entries, "Nothing", "no generated directory is left to remove", LogColor::Gray);
        else if (targets.size() > 1)
            addInfoEntry(entries, "Total", formatCleanAmount(totalFiles, totalBytes));

        const Logger::FieldGroupStyle style = CommandPrint::infoGroupStyle(true, 18);
        Logger::printFieldGroup(ctx, ctx.cmdLine().dryRun ? "Would remove" : "Removed", entries, style);
    }
}

namespace Command
{
    Result clean(TaskContext& ctx)
    {
        std::vector<CleanTarget> candidates;
        collectCleanTargets(candidates, ctx.cmdLine());

        std::vector<CleanTarget> targets;
        for (CleanTarget& candidate : candidates)
        {
            if (measureCleanTarget(candidate))
                targets.push_back(std::move(candidate));
        }

        size_t totalFiles = 0;
        size_t totalBytes = 0;
        for (const CleanTarget& target : targets)
        {
            totalFiles += target.files;
            totalBytes += target.bytes;
            if (!ctx.cmdLine().dryRun)
                SWC_RESULT(removeCleanTarget(ctx, target));
        }

        printCleanReport(ctx, targets, totalFiles, totalBytes);
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
