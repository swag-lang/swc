#include "pch.h"
#include "Main/FileSystem.h"
#include "Main/Command/CommandLine.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    fs::path lexicallyNormalize(const fs::path& path)
    {
        if (path.empty())
            return path;
        return path.lexically_normal();
    }

    Result resolveExistingPath(fs::path& path, Utf8& because, const bool expectFile)
    {
        SWC_RESULT(FileSystem::normalizeAbsolutePath(path, because));

        std::error_code      ec;
        const fs::file_status status = fs::status(path, ec);
        if (!fs::exists(status))
        {
            because = ec && !fs::status_known(status) ? FileSystem::normalizeSystemMessage(ec) : FileSystem::describePathProblem(FileSystem::PathProblem::DoesNotExist);
            return Result::Error;
        }

        const bool validType = expectFile ? fs::is_regular_file(status) : fs::is_directory(status);
        if (!validType)
        {
            because = FileSystem::describePathProblem(expectFile ? FileSystem::PathProblem::NotRegularFile : FileSystem::PathProblem::NotDirectory);
            return Result::Error;
        }

        return Result::Continue;
    }
}

namespace
{
    // normalizePath() resolves symlinks via fs::weakly_canonical(), which is a relatively expensive
    // disk round-trip. The same handful of dependency roots and module paths are normalized over and
    // over during setup, and for a given input the result is stable for the lifetime of the process
    // (the working directory and on-disk symlink topology do not change during a build). Memoize it.
    struct NormalizePathCache
    {
        std::shared_mutex                                   mutex;
        std::unordered_map<fs::path::string_type, fs::path> entries;
    };

    NormalizePathCache& normalizePathCache()
    {
        static NormalizePathCache cache;
        return cache;
    }

    fs::path computeNormalizePath(const fs::path& path)
    {
        std::error_code ec;
        fs::path        result = path;
        if (!result.is_absolute())
        {
            const fs::path absolutePath = fs::absolute(result, ec);
            if (!ec)
                result = absolutePath;
        }

        ec.clear();
        const fs::path normalized = fs::weakly_canonical(result, ec);
        if (!ec)
            result = normalized;

        return result.lexically_normal();
    }
}

fs::path FileSystem::normalizePath(const fs::path& path)
{
    if (path.empty())
        return path;

    const auto&         key   = path.native();
    NormalizePathCache& cache = normalizePathCache();

    {
        const std::shared_lock lock(cache.mutex);
        const auto             it = cache.entries.find(key);
        if (it != cache.entries.end())
            return it->second;
    }

    fs::path result = computeNormalizePath(path);

    {
        const std::unique_lock lock(cache.mutex);
        cache.entries.try_emplace(key, result);
    }

    return result;
}

fs::path FileSystem::commonPathPrefix(const fs::path& lhs, const fs::path& rhs)
{
    fs::path result;
    auto     lhsIt = lhs.begin();
    auto     rhsIt = rhs.begin();
    while (lhsIt != lhs.end() && rhsIt != rhs.end() && *lhsIt == *rhsIt)
    {
        result /= *lhsIt;
        ++lhsIt;
        ++rhsIt;
    }

    return result;
}

fs::path FileSystem::absolutePathNoThrow(const fs::path& path)
{
    if (path.empty())
        return {};

    std::error_code ec;
    const fs::path  absolutePath = fs::absolute(path, ec);
    if (ec)
        return path.lexically_normal();
    return absolutePath.lexically_normal();
}

fs::path FileSystem::compilerResourceRoot(const fs::path& exeFullName)
{
    const fs::path  exeDir = exeFullName.parent_path();
    std::error_code ec;
    if (fs::is_directory(exeDir / "runtime", ec))
        return lexicallyNormalize(exeDir);

    ec.clear();
    const fs::path repositoryBinDir = exeDir.parent_path() / "bin";
    if (fs::is_directory(repositoryBinDir / "runtime", ec))
        return lexicallyNormalize(repositoryBinDir);

    return lexicallyNormalize(exeDir);
}

fs::path FileSystem::standardLibraryWorkspaceRoot(const fs::path& exeFullName)
{
    const fs::path  localRoot = compilerResourceRoot(exeFullName) / "std";
    std::error_code ec;
    if (fs::is_directory(localRoot, ec))
        return lexicallyNormalize(localRoot);

    const std::optional<Utf8> installRoot = Os::readEnvironmentVariable("SWAG_PATH");
    if (!installRoot || installRoot->empty())
        return {};
    return absolutePathNoThrow(fs::path(installRoot->c_str()) / "std");
}

fs::path FileSystem::currentPathNoThrow()
{
    std::error_code ec;
    const fs::path  currentDir = fs::current_path(ec);
    if (ec)
        return {};
    return currentDir.lexically_normal();
}

fs::path FileSystem::generatedDependencyApiDir(const fs::path& exeFullName, const std::string_view moduleName)
{
    fs::path result = compilerResourceRoot(exeFullName);
    result /= "std";
    result /= ".output";
    result /= fs::path(std::string(moduleName));
    return lexicallyNormalize(result);
}

Result FileSystem::normalizeAbsolutePath(fs::path& path, Utf8& because)
{
    because.clear();

    std::error_code ec;
    const fs::path  absolutePath = fs::absolute(path, ec);
    if (ec)
    {
        path    = lexicallyNormalize(path);
        because = normalizeSystemMessage(ec);
        return Result::Error;
    }

    path = normalizePath(absolutePath);
    return Result::Continue;
}

Result FileSystem::resolveExistingFile(fs::path& file, Utf8& because)
{
    return resolveExistingPath(file, because, true);
}

Result FileSystem::resolveExistingFolder(fs::path& folder, Utf8& because)
{
    return resolveExistingPath(folder, because, false);
}

Result FileSystem::resolveFile(TaskContext& ctx, fs::path& file)
{
    Utf8 because;
    if (resolveExistingFile(file, because) != Result::Continue)
        return reportPathError(ctx, DiagnosticId::cmd_err_invalid_file, file, because);

    return Result::Continue;
}

Result FileSystem::resolveFolder(TaskContext& ctx, fs::path& folder)
{
    Utf8 because;
    if (resolveExistingFolder(folder, because) != Result::Continue)
    {
        return reportInvalidFolder(ctx, folder, because);
    }

    return Result::Continue;
}

Result FileSystem::reportInvalidFolder(TaskContext& ctx, const fs::path& path, const Utf8& because)
{
    return reportPathError(ctx, DiagnosticId::cmd_err_invalid_folder, path, because);
}

Result FileSystem::reportPathError(TaskContext& ctx, DiagnosticId id, const fs::path& path)
{
    Diagnostic diag = Diagnostic::get(id);
    setDiagnosticPath(diag, path);
    diag.report(ctx);
    return Result::Error;
}

Result FileSystem::reportPathError(TaskContext& ctx, DiagnosticId id, const fs::path& path, const Utf8& because)
{
    Diagnostic diag = Diagnostic::get(id);
    setDiagnosticPathAndBecause(diag, path, because);
    diag.report(ctx);
    return Result::Error;
}

bool FileSystem::pathEquals(const fs::path& lhs, const fs::path& rhs)
{
    return lhs.lexically_normal() == rhs.lexically_normal();
}

bool FileSystem::pathStartsWith(const fs::path& path, const fs::path& prefix)
{
    auto pathIt   = path.begin();
    auto prefixIt = prefix.begin();
    while (prefixIt != prefix.end())
    {
        if (pathIt == path.end() || *pathIt != *prefixIt)
            return false;

        ++pathIt;
        ++prefixIt;
    }

    return true;
}

void FileSystem::setDiagnosticPath(Diagnostic& diag, const fs::path& path)
{
    diag.addArgument(Diagnostic::ARG_PATH, formatFileName(path));
}

void FileSystem::setDiagnosticPathAndBecause(Diagnostic& diag, const fs::path& path, const Utf8& because)
{
    setDiagnosticPath(diag, path);
    diag.addArgument(Diagnostic::ARG_BECAUSE, because);
}

Utf8 FileSystem::describePathProblem(const PathProblem problem)
{
    switch (problem)
    {
        case PathProblem::DoesNotExist:
            return "path does not exist";

        case PathProblem::NotRegularFile:
            return "path is not a regular file";

        case PathProblem::NotDirectory:
            return "path is not a directory";

        default:
            SWC_UNREACHABLE();
    }
}

// Completes a failure message with the processes holding the file. An access-denied on a shared
// library names the symptom; the process mapping it names what to close. Asked on failure paths
// only, and best effort: when nobody is found, the message stays as it was.
Utf8 FileSystem::appendFileUsers(Utf8 because, const fs::path& path)
{
    std::vector<Os::FileLockOwner> owners;
    Os::queryFileLockOwners(owners, path);
    if (owners.empty())
        return because;

    because += "; the file is in use by ";
    bool first = true;
    for (const Os::FileLockOwner& owner : owners)
    {
        if (!first)
            because += ", ";
        first = false;

        if (owner.processId == Os::currentProcessId())
        {
            because += "this compiler process";
            continue;
        }

        if (owner.processName.empty())
        {
            because += std::format("process {}", owner.processId);
            continue;
        }

        because += std::format("'{}' (process {})", owner.processName.c_str(), owner.processId);
    }

    return because;
}

// Where the compiler was launched. Read once, before a program the compiler runs could move the
// process elsewhere.
const fs::path& FileSystem::displayRoot()
{
    static const fs::path root = normalizePath(currentPathNoThrow());
    return root;
}

// A path as the agent that launched the compiler opens it: relative to the working directory when
// the file lies under it, absolute otherwise.
Utf8 FileSystem::formatFileName(const fs::path& filePath)
{
    if (filePath.empty())
        return {};

    const fs::path  absolute = normalizePath(filePath);
    const fs::path& root     = displayRoot();
    if (!root.empty() && pathStartsWith(absolute, root))
    {
        const fs::path relative = absolute.lexically_relative(root);
        if (!relative.empty() && relative != ".")
            return relative.string();
    }

    return absolute.string();
}

Utf8 FileSystem::formatFileLocation(Utf8 fileName, const uint32_t line, const uint32_t column, const uint32_t columnEnd)
{
    if (line)
    {
        fileName += ":";
        fileName += std::to_string(line);
    }

    if (column)
    {
        fileName += ":";
        fileName += std::to_string(column);
    }

    if (columnEnd)
    {
        fileName += "-";
        fileName += std::to_string(columnEnd);
    }

    return fileName;
}

Utf8 FileSystem::formatPathLocation(const fs::path& filePath, const uint32_t line, const uint32_t column, const uint32_t columnEnd)
{
    return formatFileLocation(formatFileName(filePath), line, column, columnEnd);
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

SWC_END_NAMESPACE();
