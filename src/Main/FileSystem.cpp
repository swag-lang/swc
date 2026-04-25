#include "pch.h"
#include "Main/FileSystem.h"
#include "Main/Command/CommandLine.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
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

    fs::path lexicallyNormalize(const fs::path& path)
    {
        if (path.empty())
            return path;
        return path.lexically_normal();
    }

    Utf8 fallbackIoBecause(const FileSystem::IoProblem problem)
    {
        Utf8 because = FileSystem::currentSystemMessage();
        if (!because.empty())
            return because;
        return FileSystem::describeIoProblem(problem);
    }

    FileSystem::PathProblem expectedPathProblem(const bool expectFile)
    {
        return expectFile ? FileSystem::PathProblem::NotRegularFile : FileSystem::PathProblem::NotDirectory;
    }

    Result resolveExistingPath(fs::path& path, Utf8& because, const bool expectFile)
    {
        SWC_RESULT(FileSystem::normalizeAbsolutePath(path, because));

        std::error_code ec;
        if (!fs::exists(path, ec))
        {
            because = ec ? FileSystem::normalizeSystemMessage(ec) : FileSystem::describePathProblem(FileSystem::PathProblem::DoesNotExist);
            return Result::Error;
        }

        ec.clear();
        const bool validType = expectFile ? fs::is_regular_file(path, ec) : fs::is_directory(path, ec);
        if (!validType)
        {
            because = ec ? FileSystem::normalizeSystemMessage(ec) : FileSystem::describePathProblem(expectedPathProblem(expectFile));
            return Result::Error;
        }

        return Result::Continue;
    }

    template<typename T>
    Result readBinaryFileImpl(const fs::path& path, std::vector<T>& outData, FileSystem::IoErrorInfo& error)
    {
        static_assert(sizeof(T) == 1);

        outData.clear();
        error = {};

        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file.is_open())
        {
            error.problem = FileSystem::IoProblem::OpenRead;
            error.because = fallbackIoBecause(error.problem);
            return Result::Error;
        }

        const std::streampos fileSize = file.tellg();
        if (fileSize < 0)
        {
            error.problem = FileSystem::IoProblem::DetermineSize;
            error.because = FileSystem::describeIoProblem(error.problem);
            return Result::Error;
        }

        file.seekg(0, std::ios::beg);
        if (!file)
        {
            error.problem = FileSystem::IoProblem::Seek;
            error.because = fallbackIoBecause(error.problem);
            return Result::Error;
        }

        outData.resize(static_cast<size_t>(fileSize));
        if (!outData.empty() && !file.read(reinterpret_cast<char*>(outData.data()), fileSize))
        {
            outData.clear();
            error.problem = FileSystem::IoProblem::Read;
            error.because = fallbackIoBecause(error.problem);
            return Result::Error;
        }

        file.close();
        if (!file)
        {
            outData.clear();
            error.problem = FileSystem::IoProblem::CloseRead;
            error.because = fallbackIoBecause(error.problem);
            return Result::Error;
        }

        return Result::Continue;
    }

    Result reportClearDirectoryError(TaskContext& ctx, const DiagnosticId diagId, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(diagId);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }

    Result reportClearDirectoryError(TaskContext& ctx, const DiagnosticId diagId, const fs::path& path, const std::error_code& ec)
    {
        SWC_ASSERT(ec);
        return reportClearDirectoryError(ctx, diagId, path, FileSystem::normalizeSystemMessage(ec));
    }
}

fs::path FileSystem::normalizePath(const fs::path& path)
{
    if (path.empty())
        return path;

    std::error_code ec;
    fs::path        result = path;
    if (!result.is_absolute())
    {
        const fs::path absolutePath = fs::absolute(result, ec);
        if (!ec)
            result = absolutePath;
    }
    else
    {
        ec.clear();
    }

    ec.clear();
    const fs::path normalized = fs::weakly_canonical(result, ec);
    if (!ec)
        result = normalized;

    return lexicallyNormalize(result);
}

const char* FileSystem::filePathDisplayModeName(const FilePathDisplayMode mode)
{
    switch (mode)
    {
        case FilePathDisplayMode::AsIs:
            return "AsIs";
        case FilePathDisplayMode::BaseName:
            return "BaseName";
        case FilePathDisplayMode::Absolute:
            return "Absolute";
    }

    SWC_UNREACHABLE();
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

fs::path FileSystem::currentPathNoThrow()
{
    std::error_code ec;
    const fs::path  currentDir = fs::current_path(ec);
    if (ec)
        return {};
    return currentDir.lexically_normal();
}

Utf8 FileSystem::formatDiagnosticPath(const TaskContext* ctx, const fs::path& path)
{
    switch (resolveDisplayMode(ctx))
    {
        case FilePathDisplayMode::AsIs:
            return lexicallyNormalize(path).string();

        case FilePathDisplayMode::BaseName:
            return lexicallyNormalize(path).filename().string();

        case FilePathDisplayMode::Absolute:
            return normalizePath(path).string();

        default:
            SWC_UNREACHABLE();
    }
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
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_file);
        setDiagnosticPathAndBecause(diag, &ctx, file, because);
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Continue;
}

Result FileSystem::resolveFolder(TaskContext& ctx, fs::path& folder)
{
    Utf8 because;
    if (resolveExistingFolder(folder, because) != Result::Continue)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
        setDiagnosticPathAndBecause(diag, &ctx, folder, because);
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Continue;
}

Result FileSystem::clearDirectoryContents(TaskContext& ctx, const fs::path& path, const DiagnosticId diagId)
{
    if (path.empty())
        return Result::Continue;

    std::error_code ec;
    const bool      exists = fs::exists(path, ec);
    if (ec)
        return reportClearDirectoryError(ctx, diagId, path, ec);
    if (!exists)
        return Result::Continue;

    const bool isDirectory = fs::is_directory(path, ec);
    if (ec)
        return reportClearDirectoryError(ctx, diagId, path, ec);
    if (!isDirectory)
        return reportClearDirectoryError(ctx, diagId, path, describePathProblem(PathProblem::NotDirectory));

    for (fs::directory_iterator it(path, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
    {
        if (ec)
            return reportClearDirectoryError(ctx, diagId, path, ec);

        std::error_code removeEc;
        fs::remove_all(it->path(), removeEc);
        if (removeEc)
            return reportClearDirectoryError(ctx, diagId, it->path(), removeEc);
    }

    return Result::Continue;
}

Result FileSystem::readBinaryFile(const fs::path& path, std::vector<char>& outData, IoErrorInfo& error)
{
    return readBinaryFileImpl(path, outData, error);
}

Result FileSystem::readBinaryFile(const fs::path& path, std::vector<char8_t>& outData, IoErrorInfo& error)
{
    return readBinaryFileImpl(path, outData, error);
}

Result FileSystem::readBinaryFile(const fs::path& path, std::vector<std::byte>& outData, IoErrorInfo& error)
{
    return readBinaryFileImpl(path, outData, error);
}

Result FileSystem::readTextFile(const fs::path& path, std::string& outText, IoErrorInfo& error)
{
    std::vector<char> buffer;
    const Result      result = readBinaryFile(path, buffer, error);
    if (result != Result::Continue)
    {
        outText.clear();
        return result;
    }

    outText.assign(buffer.begin(), buffer.end());
    return Result::Continue;
}

Result FileSystem::writeBinaryFile(const fs::path& path, const void* data, const size_t size, IoErrorInfo& error)
{
    error = {};

    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    if (!file.is_open())
    {
        error.problem = IoProblem::OpenWrite;
        error.because = fallbackIoBecause(error.problem);
        return Result::Error;
    }

    if (size && !file.write(static_cast<const char*>(data), static_cast<std::streamsize>(size)))
    {
        error.problem = IoProblem::Write;
        error.because = fallbackIoBecause(error.problem);
        return Result::Error;
    }

    file.close();
    if (!file)
    {
        error.problem = IoProblem::CloseWrite;
        error.because = fallbackIoBecause(error.problem);
        return Result::Error;
    }

    return Result::Continue;
}

bool FileSystem::pathEquals(const fs::path& lhs, const fs::path& rhs)
{
    return lhs.lexically_normal() == rhs.lexically_normal();
}

void FileSystem::setDiagnosticPath(Diagnostic& diag, const TaskContext* ctx, const fs::path& path)
{
    diag.addArgument(Diagnostic::ARG_PATH, formatDiagnosticPath(ctx, path));
}

void FileSystem::setDiagnosticPathAndBecause(Diagnostic& diag, const TaskContext* ctx, const fs::path& path, const Utf8& because)
{
    setDiagnosticPath(diag, ctx, path);
    diag.addArgument(Diagnostic::ARG_BECAUSE, because);
}

Utf8 FileSystem::currentSystemMessage()
{
    return Os::systemError();
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

Utf8 FileSystem::describeIoProblem(const IoProblem problem)
{
    switch (problem)
    {
        case IoProblem::OpenRead:
            return "cannot open file";

        case IoProblem::OpenWrite:
            return "cannot open file for writing";

        case IoProblem::DetermineSize:
            return "cannot determine file size";

        case IoProblem::Seek:
            return "cannot reposition file cursor";

        case IoProblem::Read:
            return "cannot read file";

        case IoProblem::Write:
            return "cannot write file";

        case IoProblem::CloseRead:
            return "cannot finalize file read";

        case IoProblem::CloseWrite:
            return "cannot finalize file write";

        default:
            SWC_UNREACHABLE();
    }
}

Utf8 FileSystem::describeIoFailure(const IoErrorInfo& error)
{
    Utf8 prefix = describeIoProblem(error.problem);
    if (error.because.empty() || error.because == prefix)
        return prefix;

    Utf8 result = prefix;
    result += ": ";
    result += error.because;
    return result;
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
            return normalizePath(filePath).string();

        default:
            SWC_UNREACHABLE();
    }
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

Utf8 FileSystem::formatFileLocation(const TaskContext* ctx, const fs::path& filePath, const uint32_t line, const uint32_t column, const uint32_t columnEnd)
{
    return formatFileLocation(formatFileName(ctx, filePath), line, column, columnEnd);
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
