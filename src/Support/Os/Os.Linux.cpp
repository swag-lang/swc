#include "pch.h"
#include "Support/Os/Os.h"
#include "Main/ExitCodes.h"
#include "Main/FileSystem.h"

#ifdef __linux__
#include <fcntl.h>
#include <pwd.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

SWC_BEGIN_NAMESPACE();

namespace
{
    int openOwnedDirectoryAt(const int parent, const char* name, const uid_t uid, const bool requirePrivate)
    {
        const bool created = mkdirat(parent, name, S_IRWXU) == 0;
        if (!created && errno != EEXIST)
            return -1;

        const int directory = openat(parent, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
        if (directory < 0)
            return -1;

        struct stat info{};
        bool        safe = fstat(directory, &info) == 0 && S_ISDIR(info.st_mode) && info.st_uid == uid;
        if (safe && created)
            safe = fchmod(directory, S_IRWXU) == 0 && fstat(directory, &info) == 0;
        if (safe)
        {
            const mode_t mode = info.st_mode & 07777;
            safe = requirePrivate ? mode == S_IRWXU : !(mode & (S_IWGRP | S_IWOTH));
        }
        if (!safe)
        {
            close(directory);
            return -1;
        }
        return directory;
    }

    fs::path compilerHome(const uid_t uid)
    {
        const long recommendedSize = sysconf(_SC_GETPW_R_SIZE_MAX);
        std::vector<char> buffer(static_cast<size_t>(recommendedSize > 0 ? recommendedSize : 16384));
        struct passwd account{};
        struct passwd* result = nullptr;
        if (getpwuid_r(uid, &account, buffer.data(), buffer.size(), &result) != 0 || !result || !account.pw_dir || !*account.pw_dir)
            return {};
        return account.pw_dir;
    }

    int openOwnedHome(const fs::path& home, const uid_t uid)
    {
        if (!home.is_absolute())
            return -1;

        int current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
        if (current < 0)
            return -1;
        std::vector<fs::path> components;
        for (const fs::path& component : home.relative_path())
        {
            if (component.empty() || component == "." || component == "..")
            {
                close(current);
                return -1;
            }
            components.push_back(component);
        }

        for (size_t index = 0; index < components.size(); ++index)
        {
            const int next = openat(current, components[index].c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
            close(current);
            if (next < 0)
                return -1;

            struct stat info{};
            if (fstat(next, &info) != 0 || !S_ISDIR(info.st_mode))
            {
                close(next);
                return -1;
            }

            const mode_t writableByOthers = info.st_mode & (S_IWGRP | S_IWOTH);
            if (index + 1 == components.size())
            {
                if (info.st_uid != uid || writableByOthers)
                {
                    close(next);
                    return -1;
                }
            }
            else if ((info.st_uid != 0 && info.st_uid != uid) || (writableByOthers && !(info.st_uid == 0 && (info.st_mode & S_ISVTX))))
            {
                close(next);
                return -1;
            }
            current = next;
        }
        return current;
    }

    fs::path createHomeCompilerCacheRoot(const uid_t uid)
    {
        const fs::path home = compilerHome(uid);
        const int       homeDirectory = openOwnedHome(home, uid);
        if (homeDirectory < 0)
            return {};

        const int cacheDirectory = openOwnedDirectoryAt(homeDirectory, ".cache", uid, false);
        close(homeDirectory);
        if (cacheDirectory < 0)
            return {};

        const int compilerDirectory = openOwnedDirectoryAt(cacheDirectory, "swag", uid, true);
        close(cacheDirectory);
        if (compilerDirectory < 0)
            return {};
        close(compilerDirectory);
        return home / ".cache" / "swag";
    }

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
            const int         directory = openOwnedDirectoryAt(parent, name.c_str(), uid, true);
            if (directory >= 0)
            {
                close(directory);
                close(parent);
                return temporaryRoot / name;
            }

            // Never adopt or replace a pre-existing unsafe name. Try the other stable
            // temporary root; if neither one is safe, the caller receives the disabled path.
            close(parent);
        }

        if (const fs::path homeRoot = createHomeCompilerCacheRoot(uid); !homeRoot.empty())
            return homeRoot;

        // Fail closed: no stable private directory is available, and a fresh temporary
        // directory per process would strand cache data outside later cleanup commands.
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
