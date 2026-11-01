#include "pch.h"
#include "Support/Os/Os.h"

#ifdef __linux__
#include <sys/stat.h>
#include <sys/sysmacros.h>

SWC_BEGIN_NAMESPACE();

namespace
{
    bool matchesFile(const fs::path& path, const struct stat& file)
    {
        struct stat candidate{};
        return stat(path.c_str(), &candidate) == 0 && candidate.st_dev == file.st_dev && candidate.st_ino == file.st_ino;
    }

    bool processUsesFile(const fs::path& process, const struct stat& file)
    {
        if (matchesFile(process / "exe", file))
            return true;

        std::error_code error;
        for (fs::directory_iterator descriptor(process / "fd", fs::directory_options::skip_permission_denied, error), end; !error && descriptor != end; descriptor.increment(error))
        {
            if (matchesFile(descriptor->path(), file))
                return true;
        }

        // A read-only cache view normally outlives its descriptor. Compare file identities,
        // not path strings: aliases and renamed-but-mapped files still refer to the same inode.
        std::ifstream maps(process / "maps");
        std::string line;
        while (std::getline(maps, line))
        {
            unsigned int deviceMajor = 0, deviceMinor = 0;
            unsigned long long inode = 0;
            if (std::sscanf(line.c_str(), "%*s %*s %*s %x:%x %llu", &deviceMajor, &deviceMinor, &inode) == 3 && inode == file.st_ino && deviceMajor == major(file.st_dev) && deviceMinor == minor(file.st_dev))
                return true;
        }
        return false;
    }
}

void Os::queryFileLockOwners(std::vector<FileLockOwner>& outOwners, const fs::path& path)
{
    outOwners.clear();
    struct stat file{};
    if (stat(path.c_str(), &file) != 0 || !S_ISREG(file.st_mode))
        return;

    std::error_code error;
    for (fs::directory_iterator process("/proc", fs::directory_options::skip_permission_denied, error), end; !error && process != end; process.increment(error))
    {
        const std::string name = process->path().filename().string();
        uint32_t pid = 0;
        const auto parsed = std::from_chars(name.data(), name.data() + name.size(), pid);
        if (parsed.ec != std::errc{} || parsed.ptr != name.data() + name.size() || !pid || !processUsesFile(process->path(), file))
            continue;

        std::error_code nameError;
        Utf8 processName = fs::read_symlink(process->path() / "exe", nameError).filename();
        if (processName.empty())
        {
            std::ifstream comm(process->path() / "comm");
            std::string text;
            std::getline(comm, text);
            processName = text;
        }
        outOwners.push_back({.processName = std::move(processName), .processId = pid});
    }
    std::ranges::sort(outOwners, {}, &FileLockOwner::processId);
}

Os::WindowsToolchainDiscoveryResult Os::discoverWindowsToolchainPaths(WindowsToolchainPaths& outToolchain)
{
    // Cross-linking may use an explicitly mounted SDK; Linux has no Visual Studio registry or
    // conventional installation directories. Missing inputs remain a reported discovery failure.
    outToolchain = {};
    std::error_code error;
    if (const auto root = readEnvironmentVariable("VCToolsInstallDir"))
    {
        const fs::path libraries = fs::path(root->c_str()) / "lib" / "x64";
        if (!root->empty() && fs::is_directory(libraries, error))
            outToolchain.vcLibPath = libraries;
    }

    std::vector<fs::path> candidates;
    if (const auto root = readEnvironmentVariable("WindowsSdkDir"); root && !root->empty())
    {
        const fs::path libraries = fs::path(root->c_str()) / "Lib";
        if (const auto version = readEnvironmentVariable("WindowsSDKVersion"); version && !version->empty())
            candidates.push_back(libraries / version->c_str());
        else
        {
            error.clear();
            for (fs::directory_iterator entry(libraries, fs::directory_options::skip_permission_denied, error), end; !error && entry != end; entry.increment(error))
                candidates.push_back(entry->path());
            std::ranges::sort(candidates, std::greater{});
        }
    }
    for (const auto& root : candidates)
    {
        const fs::path um = root / "um" / "x64";
        const fs::path ucrt = root / "ucrt" / "x64";
        if (fs::is_directory(um, error) && fs::is_directory(ucrt, error))
        {
            outToolchain.sdkUmLibPath = um;
            outToolchain.sdkUcrtLibPath = ucrt;
            break;
        }
    }
    if (outToolchain.vcLibPath.empty())
        return WindowsToolchainDiscoveryResult::MissingMsvcToolchain;
    return outToolchain.sdkUmLibPath.empty() ? WindowsToolchainDiscoveryResult::MissingWindowsSdk : WindowsToolchainDiscoveryResult::Ok;
}

SWC_END_NAMESPACE();
#endif
