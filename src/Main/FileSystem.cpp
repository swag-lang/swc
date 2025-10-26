#include "pch.h"
#include "Main/FileSystem.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticIds.h"

SWC_BEGIN_NAMESPACE();

Result FileSystem::resolveFolder(const Context& ctx, fs::path& folder)
{
    std::error_code ec;

    // Make absolute first (preserves input if it's already absolute)
    fs::path resolved = fs::absolute(folder, ec);
    if (ec)
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidFolder);
        diag.last()->addArgument("path", folder.string());
        diag.last()->addArgument("reason", normalizeSystemMessage(ec));
        diag.report(ctx);
        return Result::Error;
    }

    // Normalize/symlink-resolve if possible (does not throw)
    const fs::path normalized = fs::weakly_canonical(resolved, ec);
    if (!ec)
        resolved = normalized;
    ec.clear();

    // Check existence and type; don't conflate errors with "not found"
    if (!fs::exists(resolved, ec))
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidFolder);
        diag.last()->addArgument("path", folder.string());
        if (ec)
            diag.last()->addArgument("reason", normalizeSystemMessage(ec));
        else
            diag.last()->addArgument("reason", "path does not exist");
        diag.report(ctx);
        return Result::Error;
    }
    ec.clear();

    // Be sure it's a folder
    if (!fs::is_directory(resolved, ec))
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidFolder);
        diag.last()->addArgument("path", folder.string());
        if (ec)
            diag.last()->addArgument("reason", normalizeSystemMessage(ec));
        else
            diag.last()->addArgument("reason", "not a directory");
        diag.report(ctx);
        return Result::Error;
    }

    folder = resolved;
    return Result::Success;
}

Result FileSystem::resolveFile(const Context& ctx, fs::path& file)
{
    std::error_code ec;

    // Make absolute first (preserves input if it's already absolute)
    fs::path resolved = fs::absolute(file, ec);
    if (ec)
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidFile);
        diag.last()->addArgument("path", file.string());
        diag.last()->addArgument("reason", normalizeSystemMessage(ec));
        diag.report(ctx);
        return Result::Error;
    }

    // Normalize/symlink-resolve if possible (does not throw)
    const fs::path normalized = fs::weakly_canonical(resolved, ec);
    if (!ec)
        resolved = normalized;
    ec.clear();

    // Check existence and type; don't conflate errors with "not found"
    if (!fs::exists(resolved, ec))
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidFile);
        diag.last()->addArgument("path", file.string());
        if (ec)
            diag.last()->addArgument("reason", normalizeSystemMessage(ec));
        else
            diag.last()->addArgument("reason", "path does not exist");
        diag.report(ctx);
        return Result::Error;
    }
    ec.clear();

    // Be sure it's a regular file
    if (!fs::is_regular_file(resolved, ec))
    {
        const auto diag = Diagnostic::error(DiagnosticId::CmdLineInvalidFile);
        diag.last()->addArgument("path", file.string());
        if (ec)
            diag.last()->addArgument("reason", normalizeSystemMessage(ec));
        else
            diag.last()->addArgument("reason", "not a regular file");
        diag.report(ctx);
        return Result::Error;
    }

    file = resolved;
    return Result::Success;
}

Utf8 FileSystem::normalizeSystemMessage(const Utf8& msg)
{
    auto result = msg;
    result.clean();
    result.trim();
    result.makeLower();
    if (!result.empty() && result.back() == '.')
        result.pop_back();
    return result;
}

Utf8 FileSystem::normalizeSystemMessage(std::error_code ec)
{
    return normalizeSystemMessage(ec.message());
}

SWC_END_NAMESPACE();
