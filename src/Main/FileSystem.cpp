#include "pch.h"
#include "Main/FileSystem.h"
#include "Main/CommandLine.h"
#include "Main/TaskContext.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

Result FileSystem::resolveFile(TaskContext& ctx, fs::path& file)
{
    std::error_code ec;

    // Make absolute first (preserves input if it's already absolute)
    fs::path resolved = fs::absolute(file, ec);
    if (ec)
    {
        auto diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_file);
        diag.addArgument(Diagnostic::ARG_PATH, file.string());
        diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec), false);
        diag.report(ctx);
        return Result::Stop;
    }

    // Normalize/symlink-resolve if possible (does not throw)
    const fs::path normalized = fs::weakly_canonical(resolved, ec);
    if (!ec)
        resolved = normalized;
    ec.clear();

    // Check existence and type; don't conflate errors with "not found"
    if (!fs::exists(resolved, ec))
    {
        auto diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_file);
        diag.addArgument(Diagnostic::ARG_PATH, file.string());
        if (ec)
            diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec), false);
        diag.report(ctx);
        return Result::Stop;
    }
    ec.clear();

    // Be sure it's a regular file
    if (!fs::is_regular_file(resolved, ec))
    {
        auto diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_file);
        diag.addArgument(Diagnostic::ARG_PATH, file.string());
        if (ec)
            diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec), false);
        diag.report(ctx);
        return Result::Stop;
    }

    file = resolved;
    return Result::Continue;
}

Result FileSystem::resolveFolder(TaskContext& ctx, fs::path& folder)
{
    std::error_code ec;

    // Make absolute first (preserves input if it's already absolute)
    fs::path resolved = fs::absolute(folder, ec);
    if (ec)
    {
        auto diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
        diag.addArgument(Diagnostic::ARG_PATH, folder.string());
        diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec), false);
        diag.report(ctx);
        return Result::Stop;
    }

    // Normalize/symlink-resolve if possible (does not throw)
    const fs::path normalized = fs::weakly_canonical(resolved, ec);
    if (!ec)
        resolved = normalized;
    ec.clear();

    // Check existence and type; don't conflate errors with "not found"
    if (!fs::exists(resolved, ec))
    {
        auto diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
        diag.addArgument(Diagnostic::ARG_PATH, folder.string());
        if (ec)
            diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec), false);
        else
            diag.addArgument(Diagnostic::ARG_BECAUSE, "path does not exist", false);
        diag.report(ctx);
        return Result::Stop;
    }
    ec.clear();

    // Be sure it's a folder
    if (!fs::is_directory(resolved, ec))
    {
        auto diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
        diag.addArgument(Diagnostic::ARG_PATH, folder.string());
        if (ec)
            diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec), false);
        diag.report(ctx);
        return Result::Stop;
    }

    folder = resolved;
    return Result::Continue;
}

Utf8 FileSystem::normalizeSystemMessage(const Utf8& msg)
{
    auto result = msg;
    result.clean();
    result.trim();
    result.make_lower();
    if (!result.empty() && result.back() == '.')
        result.pop_back();
    return result;
}

Utf8 FileSystem::normalizeSystemMessage(std::error_code ec)
{
    return normalizeSystemMessage(ec.message());
}

void FileSystem::collectSwagFilesRec(const TaskContext& ctx, const fs::path& folder, std::vector<fs::path>& files, bool canFilter)
{
    for (const auto& entry : fs::recursive_directory_iterator(folder))
    {
        if (!entry.is_regular_file())
            continue;
        auto ext = entry.path().extension().string();
        if (ext != ".swg" && ext != ".swgs")
            continue;

        if (canFilter)
        {
            bool ignore = false;
            for (const auto& filter : ctx.cmdLine().fileFilter)
            {
                if (!entry.path().string().contains(filter))
                {
                    ignore = true;
                    break;
                }
            }
            if (ignore)
                continue;
        }

        files.push_back(entry.path());
    }
}

SWC_END_NAMESPACE()
