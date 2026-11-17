#include "pch.h"
#include "Main/ExitCodes.h"
#include "Main/WorkspaceLayout.h"
#include "Support/Os/Os.h"
#include "Unittest/Support/Host.Tests.Linux.h"
#include <fcntl.h>
#include <pthread.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

namespace swc::LinuxHostTests
{
    void testPrivateCompilerCacheRoot()
    {
        std::array<std::string, 2> processRoots;
        for (std::string& processRoot : processRoots)
        {
            int channel[2];
            require(pipe2(channel, O_CLOEXEC) == 0, "cannot create cache-root process channel");
            const pid_t child = fork();
            if (child == 0)
            {
                close(channel[0]);
                const std::string root = WorkspaceLayout::cacheRoot().string();
                const ssize_t       written = write(channel[1], root.c_str(), root.size() + 1);
                close(channel[1]);
                _exit(written == static_cast<ssize_t>(root.size() + 1) ? 0 : 1);
            }
            require(child > 0, "cannot fork cache-root process probe");
            close(channel[1]);

            char   buffer[4096];
            size_t length = 0;
            ssize_t count;
            while ((count = read(channel[0], buffer + length, sizeof(buffer) - length)) > 0)
            {
                length += static_cast<size_t>(count);
                if (length == sizeof(buffer))
                    break;
            }
            close(channel[0]);
            const int status = waitForChild(child);
            require(WIFEXITED(status) && WEXITSTATUS(status) == 0 && length > 1 && length < sizeof(buffer), "cache-root process probe failed");
            processRoot.assign(buffer, length - 1);
            require(buffer[length - 1] == '\0', "cache-root process probe returned an incomplete path");
        }
        require(processRoots[0] == processRoots[1], "compiler cache root changes between processes");

        const fs::path root = WorkspaceLayout::cacheRoot();
        struct stat info{};
        require(root.is_absolute() && lstat(root.c_str(), &info) == 0, "compiler cache root is unavailable");
        require(S_ISDIR(info.st_mode) && info.st_uid == geteuid() && (info.st_mode & 07777) == S_IRWXU, "compiler cache root is not a private user-owned directory");
    }

    void testThreadStorage()
    {
        const uint32_t before      = Os::tlsSlotsInUse();
        const uint64_t slot        = Os::tlsAlloc();
        int            parentValue = 7;
        require(Os::tlsSlotsInUse() == before + 1, "TLS slot accounting differs");
        require(Os::tlsGetValue(slot) == nullptr, "new TLS slot is not empty");
        Os::tlsSetValue(slot, &parentValue);
        std::array<std::jthread, 3> workers;
        std::atomic<bool>           isolated = true;
        std::barrier                barrier(3);
        for (auto& worker : workers)
        {
            worker = std::jthread([&] {
                int localValue = 9;
                if (Os::tlsGetValue(slot))
                    isolated = false;
                Os::tlsSetValue(slot, &localValue);
                barrier.arrive_and_wait();
                if (Os::tlsGetValue(slot) != &localValue)
                    isolated = false;
                Os::tlsSetValue(slot, nullptr);
            });
        }
        for (auto& worker : workers)
            worker.join();
        require(isolated && Os::tlsGetValue(slot) == &parentValue, "TLS values crossed thread boundaries");
        // Host slots live for the compiler process; only this fixture returns its borrowed slot.
        require(pthread_key_delete(static_cast<pthread_key_t>(slot)) == 0, "cannot delete test TLS slot");
        require(Os::tlsSlotsInUse() == before, "TLS probe leaked slots");
        require(Os::peakProcessMemoryUsage() > 0, "process peak memory is unavailable");
    }

    void testModuleLoading()
    {
        const fs::path directory  = fs::absolute("module path");
        const fs::path modulePath = directory / "libswc_host_test.so";
        require(fs::is_regular_file(modulePath), "shared-library fixture is missing");
        void* handle = reinterpret_cast<void*>(1);
        require(!Os::loadExternalModule(handle, "swc_missing_host_module.so") && !handle, "missing library retained a handle");
        require(!Os::loadExternalModule(handle, std::string_view("libc.so.6\0extra", 15)), "loader accepted an embedded NUL");
        Os::registerExternalModuleSearchPath(directory);
        Os::registerExternalModuleSearchPath(directory / ".");
        require(Os::loadExternalModule(handle, "swc_host_test") && handle, "registered module path did not resolve a library stem");
        void* address = nullptr;
        require(Os::getExternalSymbolAddress(address, handle, "swcLinuxHostAdd"), "cannot resolve shared-library export");
        const auto add = reinterpret_cast<int (*)(int, int)>(address);
        require(add(19, 23) == 42, "loaded C function returned another value");
        require(!Os::getExternalSymbolAddress(address, handle, "missingExport") && !address, "missing export retained an address");
        require(!Os::getExternalSymbolAddress(address, nullptr, "swcLinuxHostAdd"), "symbol lookup accepted a null handle");
        void* absoluteHandle = nullptr;
        require(Os::loadExternalModule(absoluteHandle, modulePath.string()) && absoluteHandle == handle, "absolute path did not retain module identity");
        require(Os::loadExternalModule(absoluteHandle, "libc.so.6"), "cannot load a versioned system library");
        require(Os::getExternalSymbolAddress(address, absoluteHandle, "getpid"), "cannot resolve a system-library export");
        const auto processId = reinterpret_cast<pid_t (*)()>(address);
        require(processId() == getpid(), "system-library call returned another process");
    }
}
