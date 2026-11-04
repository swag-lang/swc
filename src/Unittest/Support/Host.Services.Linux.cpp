#include "pch.h"
#include "Main/ExitCodes.h"
#include "Support/Os/Os.h"
#include "Unittest/Support/Host.Tests.Linux.h"
#include <fcntl.h>
#include <pthread.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

namespace swc::LinuxHostTests
{
    void testThreadStorage()
    {
        const uint32_t before = Os::tlsSlotsInUse();
        const uint64_t slot = Os::tlsAlloc();
        int            parentValue = 7;
        require(Os::tlsSlotsInUse() == before + 1, "TLS slot accounting differs");
        require(Os::tlsGetValue(slot) == nullptr, "new TLS slot is not empty");
        Os::tlsSetValue(slot, &parentValue);
        std::array<std::jthread, 3> workers;
        std::atomic<bool>          isolated = true;
        std::barrier               barrier(3);
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
        const fs::path directory = fs::absolute("module path");
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

    void testTerminal()
    {
        // Each child owns its terminal descriptors and environment; never change the user's tty.
        std::fflush(nullptr);
        const int master = posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
        require(master >= 0 && grantpt(master) == 0 && unlockpt(master) == 0, "cannot create pseudo-terminal");
        const char* slaveName = ptsname(master);
        require(slaveName != nullptr, "cannot resolve pseudo-terminal slave");
        const int slave = open(slaveName, O_RDWR | O_NOCTTY | O_CLOEXEC);
        require(slave >= 0, "cannot open pseudo-terminal slave");
        winsize size{};
        size.ws_col = 123;
        require(ioctl(slave, TIOCSWINSZ, &size) == 0, "cannot set pseudo-terminal width");
        const pid_t child = fork();
        if (child == 0)
        {
            close(master);
            if (dup2(slave, STDOUT_FILENO) < 0 || dup2(slave, STDERR_FILENO) < 0 || setenv("TERM", "xterm-256color", 1) != 0)
                _exit(1);
            close(slave);
            if (!Os::stdoutSupportsAnsi() || !Os::stderrSupportsAnsi() || !Os::stdoutSupportsAnimation() || Os::stdoutColumnCount() != 123)
                _exit(2);
            if (setenv("TERM", "dumb", 1) != 0 || Os::stdoutSupportsAnsi() || Os::stdoutSupportsAnimation())
                _exit(3);
            if (setenv("TERM", "xterm", 1) != 0)
                _exit(4);
            Os::setStdoutCursorVisible(false);
            Os::exit(ExitCode::Success);
        }
        close(slave);
        const int status = waitForChild(child);
        require(WIFEXITED(status) && WEXITSTATUS(status) == 0, "terminal capability child failed");
        char buffer[64];
        const auto length = read(master, buffer, sizeof(buffer));
        close(master);
        require(length == 12 && std::string_view(buffer, static_cast<size_t>(length)) == "\x1b[?25l\x1b[?25h", "cursor was not restored on normal exit");

        const pid_t redirected = fork();
        if (redirected == 0)
        {
            const int output = open("terminal-output.txt", O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
            if (output < 0 || dup2(output, STDOUT_FILENO) < 0 || dup2(output, STDERR_FILENO) < 0)
                _exit(1);
            close(output);
            if (Os::stdoutSupportsAnsi() || Os::stderrSupportsAnsi() || Os::stdoutSupportsAnimation() || Os::stdoutColumnCount())
                _exit(2);
            Os::setStdoutCursorVisible(false);
            _exit(0);
        }
        const int redirectStatus = waitForChild(redirected);
        require(WIFEXITED(redirectStatus) && WEXITSTATUS(redirectStatus) == 0, "redirected terminal reported interactive capabilities");
        require(fs::file_size("terminal-output.txt") == 0, "cursor sequence leaked into redirected output");
    }
}
