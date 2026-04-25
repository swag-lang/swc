#pragma once

SWC_BEGIN_NAMESPACE();

class TaskContext;
class Diagnostic;
enum class DiagnosticId;

namespace FileSystem
{
    enum class FilePathDisplayMode : uint8_t
    {
        AsIs,
        BaseName,
        Absolute,
    };

    enum class PathProblem : uint8_t
    {
        DoesNotExist,
        NotRegularFile,
        NotDirectory,
    };

    enum class IoProblem : uint8_t
    {
        OpenRead,
        OpenWrite,
        DetermineSize,
        Seek,
        Read,
        Write,
        CloseRead,
        CloseWrite,
    };

    struct IoErrorInfo
    {
        IoProblem problem = IoProblem::Read;
        Utf8      because;
    };

    const char* filePathDisplayModeName(FilePathDisplayMode mode);
    fs::path    absolutePathNoThrow(const fs::path& path);
    fs::path    currentPathNoThrow();
    fs::path    normalizePath(const fs::path& path);
    fs::path    commonPathPrefix(const fs::path& lhs, const fs::path& rhs);
    Utf8        formatDiagnosticPath(const TaskContext* ctx, const fs::path& path);
    Result      normalizeAbsolutePath(fs::path& path, Utf8& because);
    Result      resolveExistingFile(fs::path& file, Utf8& because);
    Result      resolveExistingFolder(fs::path& folder, Utf8& because);
    Result      resolveFile(TaskContext& ctx, fs::path& file);
    Result      resolveFolder(TaskContext& ctx, fs::path& folder);
    Result      clearDirectoryContents(TaskContext& ctx, const fs::path& path, DiagnosticId diagId);
    Result      readBinaryFile(const fs::path& path, std::vector<char>& outData, IoErrorInfo& error);
    Result      readBinaryFile(const fs::path& path, std::vector<char8_t>& outData, IoErrorInfo& error);
    Result      readBinaryFile(const fs::path& path, std::vector<std::byte>& outData, IoErrorInfo& error);
    Result      readTextFile(const fs::path& path, std::string& outText, IoErrorInfo& error);
    Result      writeBinaryFile(const fs::path& path, const void* data, size_t size, IoErrorInfo& error);
    bool     pathEquals(const fs::path& lhs, const fs::path& rhs);
    bool     pathStartsWith(const fs::path& path, const fs::path& prefix);
    void     setDiagnosticPath(Diagnostic& diag, const TaskContext* ctx, const fs::path& path);
    void     setDiagnosticPathAndBecause(Diagnostic& diag, const TaskContext* ctx, const fs::path& path, const Utf8& because);
    Utf8     describePathProblem(PathProblem problem);
    Utf8     describeIoProblem(IoProblem problem);
    Utf8     describeIoFailure(const IoErrorInfo& error);
    Utf8     formatFileName(const TaskContext* ctx, const fs::path& filePath);
    Utf8     formatFileLocation(Utf8 fileName, uint32_t line, uint32_t column = 0, uint32_t columnEnd = 0);
    Utf8     formatFileLocation(const TaskContext* ctx, const fs::path& filePath, uint32_t line, uint32_t column = 0, uint32_t columnEnd = 0);
    Utf8     sanitizeFileName(Utf8 value);
    Utf8     normalizeSystemMessage(const Utf8& msg);
    Utf8     normalizeSystemMessage(std::error_code ec);
}

SWC_END_NAMESPACE();
