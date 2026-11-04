#include "pch.h"
#include "Main/ExitCodes.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"

#ifdef __linux__
#include <sys/resource.h>
#include <unistd.h>

SWC_BEGIN_NAMESPACE();

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
        uint32_t tracer = 0;
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
