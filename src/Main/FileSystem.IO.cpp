#include "pch.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 fallbackIoBecause(const FileSystem::IoProblem problem)
    {
        Utf8 because = Os::systemError();
        if (!because.empty())
            return because;
        return FileSystem::describeIoProblem(problem);
    }

    template<typename BUF>
    Result readBinaryFileImpl(const fs::path& path, BUF& outData, FileSystem::IoErrorInfo& error, size_t extraCapacity = 0)
    {
        using T = BUF::value_type;
        static_assert(sizeof(T) == 1);

        outData.clear();
        error = {};

        std::ifstream                         file;
        std::chrono::steady_clock::time_point retryDeadline;
        while (true)
        {
            file.open(path, std::ios::binary | std::ios::ate);
            if (file.is_open())
                break;

            // During replacement Windows can report either a sharing violation or access denied.
            const bool sharingError = Os::isFileSharingError() || Os::isFileSharingError(std::error_code(errno, std::generic_category()));
            error.problem           = FileSystem::IoProblem::OpenRead;
            error.because           = fallbackIoBecause(error.problem);
            if (!sharingError)
                return Result::Error;

            const auto now = std::chrono::steady_clock::now();
            if (retryDeadline == std::chrono::steady_clock::time_point{})
                retryDeadline = now + std::chrono::seconds(2);
            if (now >= retryDeadline)
                return Result::Error;

            std::this_thread::sleep_for(std::chrono::milliseconds(25));
            file.clear();
        }

        error = {};

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

        if (extraCapacity)
            outData.reserve(static_cast<size_t>(fileSize) + extraCapacity);
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
}

Result FileSystem::readBinaryFile(const fs::path& path, std::vector<char>& outData, IoErrorInfo& error)
{
    return readBinaryFileImpl(path, outData, error);
}

Result FileSystem::readBinaryFile(const fs::path& path, std::vector<char8_t>& outData, IoErrorInfo& error, const size_t extraCapacity)
{
    return readBinaryFileImpl(path, outData, error, extraCapacity);
}

Result FileSystem::readBinaryFile(const fs::path& path, ByteArray& outData, IoErrorInfo& error)
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

    std::ofstream                         file;
    std::chrono::steady_clock::time_point retryDeadline;
    while (true)
    {
        file.open(path, std::ios::binary | std::ios::trunc);
        if (file.is_open())
            break;

        // Scanners can briefly hold a newly built image without write sharing.
        // Retry that lock only; a lasting lock still reports the original I/O error.
        const bool sharingError = Os::isFileSharingError();
        error.problem           = IoProblem::OpenWrite;
        error.because           = fallbackIoBecause(error.problem);
        if (!sharingError)
            return Result::Error;

        const auto now = std::chrono::steady_clock::now();
        if (retryDeadline == std::chrono::steady_clock::time_point{})
            retryDeadline = now + std::chrono::seconds(2);
        if (now >= retryDeadline)
            return Result::Error;
        std::this_thread::sleep_for(std::chrono::milliseconds(25));
        file.clear();
    }
    error = {};

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

namespace
{
    constexpr std::string_view K_MOVED_ASIDE_EXTENSION = ".swcstale";
}

bool FileSystem::isMovedAsidePath(const fs::path& path)
{
    return path.extension() == K_MOVED_ASIDE_EXTENSION;
}

bool FileSystem::moveFileAside(const fs::path& path)
{
    static std::atomic_uint64_t sequence  = 0;
    fs::path                    asidePath = path;
    asidePath += std::format(".{}.{}{}", Os::currentProcessId(), sequence.fetch_add(1, std::memory_order_relaxed), K_MOVED_ASIDE_EXTENSION);

    std::error_code ec;
    fs::rename(path, asidePath, ec);
    return !ec;
}

void FileSystem::removeMovedAsideFiles(const fs::path& directory)
{
    std::error_code ec;
    for (fs::directory_iterator it(directory, fs::directory_options::skip_permission_denied, ec), end; !ec && it != end; it.increment(ec))
    {
        if (!isMovedAsidePath(it->path()))
            continue;

        // Still mapped by another process: it stays until a later publication finds it free.
        std::error_code removeEc;
        fs::remove(it->path(), removeEc);
    }
}

// Readers and competing writers must only see complete artifacts. A rename on the same volume
// replaces the directory entry without overwriting the previous bytes.
Result FileSystem::renameOverFile(const fs::path& from, const fs::path& to, IoErrorInfo& error, const FileReplacement replacement)
{
    error = {};
    const auto deadline   = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    bool       movedAside = false;
    while (true)
    {
        std::error_code ec;
        fs::rename(from, to, ec);
        if (!ec)
        {
            // Whatever an earlier publication had to move aside goes as soon as nothing maps
            // it: the directory holds a handful of artifacts, so the sweep is cheap.
            removeMovedAsideFiles(to.parent_path());
            return Result::Continue;
        }

        // Windows also reports access denied when a reader did not share deletion.
        const bool sharingError = Os::isFileSharingError(ec);
        error.problem           = IoProblem::Write;
        error.because           = normalizeSystemMessage(ec);
        if (!sharingError)
            return Result::Error;

        // A deliberate mapping cannot disappear during a scanner retry. Preserve
        // its generation under the stale name and publish the complete new file.
        // Cache readers may miss during the two renames, but never see partial data.
        if (replacement == FileReplacement::Mapped && !movedAside && moveFileAside(to))
        {
            movedAside = true;
            continue;
        }

        if (std::chrono::steady_clock::now() < deadline)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(25));
            continue;
        }

        // A reader that outlives the wait is a compiler that loaded the library for its
        // compile-time calls: it keeps the file mapped for as long as it runs. The previous
        // bytes move aside, which the mapping allows, so the publication still completes.
        if (movedAside || !moveFileAside(to))
            return Result::Error;
        movedAside = true;
    }
}

Result FileSystem::writeBinaryFileAtomic(const fs::path& path, const void* data, const size_t size, IoErrorInfo& error, const FileReplacement replacement)
{
    static std::atomic_uint64_t sequence      = 0;
    fs::path                    temporaryPath = path;
    temporaryPath += std::format(".{}.{}.swctmp", Os::currentProcessId(), sequence.fetch_add(1, std::memory_order_relaxed));

    Result result = writeBinaryFile(temporaryPath, data, size, error);
    if (result == Result::Continue)
    {
        result = renameOverFile(temporaryPath, path, error, replacement);
        if (result == Result::Continue)
            return result;
    }

    std::error_code ec;
    fs::remove(temporaryPath, ec);
    return result;
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
