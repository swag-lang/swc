#include "pch.h"
#include "Main/FileSystem.h"
#include "Main/CommandLine.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    FileSystem::FilePathDisplayMode resolveDisplayMode(const TaskContext* ctx)
    {
        if (!ctx)
            return FileSystem::FilePathDisplayMode::AsIs;
        return ctx->cmdLine().filePathDisplay;
    }

    fs::path toAbsolutePathNoThrow(const fs::path& filePath)
    {
        std::error_code ec;
        fs::path        absolutePath = fs::absolute(filePath, ec);
        if (ec)
            return filePath;
        return absolutePath;
    }
}

Result FileSystem::resolveFile(TaskContext& ctx, fs::path& file)
{
    std::error_code ec;

    // Make absolute first (preserves input if it's already absolute)
    fs::path resolved = fs::absolute(file, ec);
    if (ec)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_file);
        diag.addArgument(Diagnostic::ARG_PATH, formatFileName(&ctx, file));
        diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec));
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
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_file);
        diag.addArgument(Diagnostic::ARG_PATH, formatFileName(&ctx, file));
        if (ec)
            diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec));
        diag.report(ctx);
        return Result::Error;
    }
    ec.clear();

    // Be sure it's a regular file
    if (!fs::is_regular_file(resolved, ec))
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_file);
        diag.addArgument(Diagnostic::ARG_PATH, formatFileName(&ctx, file));
        if (ec)
            diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec));
        diag.report(ctx);
        return Result::Error;
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
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
        diag.addArgument(Diagnostic::ARG_PATH, formatFileName(&ctx, folder));
        diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec));
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
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
        diag.addArgument(Diagnostic::ARG_PATH, formatFileName(&ctx, folder));
        if (ec)
            diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec));
        else
            diag.addArgument(Diagnostic::ARG_BECAUSE, "path does not exist");
        diag.report(ctx);
        return Result::Error;
    }
    ec.clear();

    // Be sure it's a folder
    if (!fs::is_directory(resolved, ec))
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
        diag.addArgument(Diagnostic::ARG_PATH, formatFileName(&ctx, folder));
        if (ec)
            diag.addArgument(Diagnostic::ARG_BECAUSE, normalizeSystemMessage(ec));
        diag.report(ctx);
        return Result::Error;
    }

    folder = resolved;
    return Result::Continue;
}

Utf8 FileSystem::formatFileName(const TaskContext* ctx, const fs::path& filePath)
{
    const FilePathDisplayMode resolvedMode = resolveDisplayMode(ctx);
    switch (resolvedMode)
    {
        case FilePathDisplayMode::AsIs:
            return filePath.string();

        case FilePathDisplayMode::BaseName:
            return filePath.filename().string();

        case FilePathDisplayMode::Absolute:
            return toAbsolutePathNoThrow(filePath).string();

        default:
            SWC_UNREACHABLE();
    }
}

Utf8 FileSystem::formatFileLocation(const TaskContext* ctx, const fs::path& filePath, const uint32_t line, const uint32_t column, const uint32_t columnEnd)
{
    Utf8 out = formatFileName(ctx, filePath);
    if (line)
    {
        out += ":";
        out += std::to_string(line);
    }

    if (column)
    {
        out += ":";
        out += std::to_string(column);
    }

    if (columnEnd)
    {
        out += "-";
        out += std::to_string(columnEnd);
    }

    return out;
}

Utf8 FileSystem::toUtf8Path(const fs::path& path)
{
    return {path.generic_string()};
}

Utf8 FileSystem::sanitizeFileName(Utf8 value)
{
    if (value.empty())
        return "native";

    for (char& c : value)
    {
        if ((c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') ||
            c == '_' ||
            c == '-')
        {
            continue;
        }

        c = '_';
    }

    return value;
}

Utf8 FileSystem::normalizeLibraryFileName(const std::string_view value)
{
    Utf8 out(value);
    out.make_lower();

    if (out == "ucrtbase" || out == "ucrtbase.lib")
        return "ucrt.lib";
    if (out == "ucrtbased" || out == "ucrtbased.lib")
        return "ucrtd.lib";

    if (fs::path(std::string(out)).extension().empty())
        out += ".lib";
    return out;
}

Utf8 FileSystem::normalizeSystemMessage(const Utf8& msg)
{
    Utf8 result = msg;
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

SWC_END_NAMESPACE();
