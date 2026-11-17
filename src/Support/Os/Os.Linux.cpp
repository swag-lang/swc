#include "pch.h"
#include "Support/Os/Os.h"
#include "Main/ExitCodes.h"
#include "Main/FileSystem.h"

#ifdef __linux__
#include <fcntl.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

SWC_BEGIN_NAMESPACE();

namespace
{
    fs::path createPrivateCompilerCacheRoot()
    {
        const uid_t uid = geteuid();
        for (const fs::path& temporaryRoot : {fs::path("/tmp"), fs::path("/var/tmp")})
        {
            const int parent = open(temporaryRoot.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
            if (parent < 0)
                continue;

            struct stat parentInfo{};
            if (fstat(parent, &parentInfo) != 0 || !S_ISDIR(parentInfo.st_mode) || parentInfo.st_uid != 0 || !(parentInfo.st_mode & S_ISVTX))
            {
                close(parent);
                continue;
            }

            const std::string name = std::format("swag-{}", static_cast<uint64_t>(uid));
            bool               created = mkdirat(parent, name.c_str(), S_IRWXU) == 0;
            int                createError = created ? 0 : errno;
            if (!created && createError != EEXIST)
            {
                close(parent);
                continue;
            }

            const int directory = openat(parent, name.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
            if (directory >= 0)
            {
                struct stat info{};
                bool        safe = fstat(directory, &info) == 0 && S_ISDIR(info.st_mode) && info.st_uid == uid;
                if (safe && created)
                    safe = fchmod(directory, S_IRWXU) == 0 && fstat(directory, &info) == 0;
                safe = safe && (info.st_mode & 07777) == S_IRWXU;
                close(directory);
                if (safe)
                {
                    close(parent);
                    return temporaryRoot / name;
                }
            }

            // A pre-existing path may be a symlink, belong to another user, or have
            // permissions that let other users seed cache entries. Isolate this process
            // in a fresh directory instead of adopting any contents from that path.
            std::string pattern = (temporaryRoot / std::format("swag-{}-XXXXXX", static_cast<uint64_t>(uid))).string();
            std::vector<char> writablePattern(pattern.begin(), pattern.end());
            writablePattern.push_back('\0');
            char* unique = mkdtemp(writablePattern.data());
            if (unique)
            {
                struct stat info{};
                const int   directory = open(unique, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
                const bool  safe = directory >= 0 && fstat(directory, &info) == 0 && S_ISDIR(info.st_mode) && info.st_uid == uid && (info.st_mode & 07777) == S_IRWXU;
                if (directory >= 0)
                    close(directory);
                if (safe)
                {
                    close(parent);
                    return unique;
                }
                rmdir(unique);
            }
            close(parent);
        }

        // Fail closed: this path cannot be created beneath the /dev/null device, so
        // cache writes fail without falling back to a shared or attacker-controlled root.
        return "/dev/null/swc-cache-disabled";
    }
}

fs::path Os::compilerCacheRoot()
{
    static const fs::path root = createPrivateCompilerCacheRoot();
    return root;
}

Utf8 Os::systemError()
{
    const int error = errno;
    return error ? FileSystem::normalizeSystemMessage(std::error_code(error, std::generic_category())) : Utf8{};
}

bool Os::isFileSharingError()
{
    return errno == ETXTBSY;
}

bool Os::isFileSharingError(const std::error_code error)
{
    // Permission failures do not indicate a transient reader lock on Linux.
    return error == std::errc::text_file_busy;
}

uint32_t Os::currentProcessId()
{
    return static_cast<uint32_t>(getpid());
}

uint32_t Os::currentThreadId()
{
    return static_cast<uint32_t>(gettid());
}

fs::path Os::getTemporaryPath()
{
    std::error_code error;
    fs::path        result = fs::temp_directory_path(error);
    return error ? fs::path{} : result;
}

fs::path Os::getExeFullName()
{
    std::error_code error;
    fs::path        result = fs::read_symlink("/proc/self/exe", error);
    return error ? fs::path{} : result;
}

std::optional<Utf8> Os::readEnvironmentVariable(const std::string_view name)
{
    if (name.empty() || name.find('\0') != std::string_view::npos || name.find('=') != std::string_view::npos)
        return std::nullopt;
    const std::string terminated(name);
    const char*       value = std::getenv(terminated.c_str());
    return value ? std::optional<Utf8>{value} : std::nullopt;
}

const char* Os::hostOsName()
{
    return "linux";
}

const char* Os::hostCpuName()
{
#ifdef __x86_64__
    return "x64";
#else
    return "unknown-cpu";
#endif
}

bool Os::isDebuggerAttached()
{
    std::ifstream status("/proc/self/status");
    std::string   line;
    while (std::getline(status, line))
    {
        if (!line.starts_with("TracerPid:"))
            continue;
        const size_t start = line.find_first_not_of(" \t", 10);
        if (start == std::string::npos)
            return false;
        uint32_t   tracer = 0;
        const auto result = std::from_chars(line.data() + start, line.data() + line.size(), tracer);
        return result.ec == std::errc{} && tracer != 0;
    }
    return false;
}

size_t Os::peakProcessMemoryUsage()
{
    rusage usage{};
    return getrusage(RUSAGE_SELF, &usage) == 0 ? static_cast<size_t>(usage.ru_maxrss) * 1024 : 0;
}

void Os::exit(const ExitCode code)
{
    std::exit(static_cast<int>(code));
}

void Os::terminate()
{
    _exit(static_cast<int>(ExitCode::ErrorCommand));
}

SWC_END_NAMESPACE();
#endif
