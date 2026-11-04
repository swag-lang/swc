#include "pch.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Support/Os/ReadOnlyFileMapping.h"
#include "Unittest/Support/LinuxHostTests.h"
#include <fcntl.h>
#include <poll.h>
#include <sys/wait.h>
#include <unistd.h>

namespace swc::LinuxHostTests
{
    namespace
    {
        struct Pipe
        {
            int descriptors[2]{};

            Pipe() { require(pipe2(descriptors, O_CLOEXEC) == 0, "cannot create test pipe"); }
            ~Pipe()
            {
                close(descriptors[0]);
                close(descriptors[1]);
            }

            void send() const { require(write(descriptors[1], "x", 1) == 1, "cannot signal test peer"); }
            bool readable(const int timeout) const
            {
                pollfd descriptor{descriptors[0], POLLIN, 0};
                int    result;
                do
                    result = poll(&descriptor, 1, timeout);
                while (result < 0 && errno == EINTR);
                require(result >= 0, "cannot poll test pipe");
                return result > 0 && (descriptor.revents & POLLIN);
            }
            void receive() const
            {
                require(readable(3000), "test peer did not signal within three seconds");
                char byte;
                require(read(descriptors[0], &byte, 1) == 1, "cannot read test signal");
            }
        };

        void checkChild(const pid_t child)
        {
            const int status = waitForChild(child);
            require(WIFEXITED(status) && WEXITSTATUS(status) == 0, "file-service child failed");
        }

        void checkDirectoryWaiter(const bool replace)
        {
            const fs::path directory = replace ? "replace-lock" : "alias-lock";
            const fs::path alias = directory.string() + "-alias";
            fs::create_directory(directory);
            fs::create_directory_symlink(directory, alias);

            // Fork before opening either lock: a fork inherits flock's open-file ownership.
            Pipe          start;
            Pipe          entered;
            Pipe          acquired;
            const pid_t   child = fork();
            if (child == 0)
            {
                try
                {
                    start.receive();
                    entered.send();
                    Os::DirectoryLock lock;
                    Utf8              because;
                    if (!lock.lock(because, alias))
                        _exit(1);
                    acquired.send();
                    _exit(0);
                }
                catch (...)
                {
                    _exit(2);
                }
            }
            require(child > 0, "cannot create directory-lock child");
            auto lock = std::make_unique<Os::DirectoryLock>();
            Utf8 because;
            require(lock->lock(because, directory), "cannot lock directory");
            start.send();
            entered.receive();
            require(!acquired.readable(150), "alias did not share the directory lock");

            std::unique_ptr<Os::DirectoryLock> newGeneration;
            if (replace)
            {
                fs::rename(directory, directory.string() + "-old");
                fs::create_directory(directory);
                newGeneration = std::make_unique<Os::DirectoryLock>();
                require(newGeneration->lock(because, directory), "cannot lock replacement directory");
            }
            lock.reset();
            if (replace)
            {
                require(!acquired.readable(150), "waiter used a stale directory generation");
                newGeneration.reset();
            }
            acquired.receive();
            checkChild(child);
            require(fs::is_empty(directory), "directory locking created a lock file");
        }
    }

    void testHostBasics()
    {
        require(std::string_view(Os::hostOsName()) == "linux", "host OS identity changed");
        require(std::string_view(Os::hostCpuName()) == "x64", "host CPU identity changed");
        require(Os::currentProcessId() == static_cast<uint32_t>(getpid()), "process identity differs");
        require(fs::equivalent(Os::getExeFullName(), "/proc/self/exe"), "executable path differs");
        require(fs::is_directory(Os::getTemporaryPath()), "temporary path is not a directory");
        uint32_t thread = 0;
        std::jthread worker([&] { thread = Os::currentThreadId(); });
        worker.join();
        require(thread && thread != Os::currentThreadId(), "thread identities are not distinct");

        constexpr const char* name = "SWC_LINUX_HOST_TEST_ENVIRONMENT";
        require(setenv(name, "", 1) == 0, "cannot set empty environment value");
        const auto empty = Os::readEnvironmentVariable(name);
        require(empty && empty->empty(), "empty environment value was treated as absent");
        require(setenv(name, "a value \xc3\xa9", 1) == 0, "cannot set environment value");
        require(Os::readEnvironmentVariable(name) == std::optional<Utf8>{"a value \xc3\xa9"}, "environment bytes changed");
        require(unsetenv(name) == 0 && !Os::readEnvironmentVariable(name), "missing environment value was present");
        require(!Os::readEnvironmentVariable("") && !Os::readEnvironmentVariable("a=b") && !Os::readEnvironmentVariable(std::string_view("a\0b", 3)), "environment accepted a malformed name");

        errno = EACCES;
        require(!Os::systemError().empty() && !Os::isFileSharingError(), "permissions were treated as a sharing lock");
        require(!Os::isFileSharingError(std::make_error_code(std::errc::permission_denied)), "permission error is transient");
        errno = ETXTBSY;
        require(Os::isFileSharingError() && Os::isFileSharingError(std::make_error_code(std::errc::text_file_busy)), "busy executable is not a sharing error");
        errno = 0;
        require(Os::systemError().empty(), "zero errno has a system error");
    }

    void testFileOwners()
    {
        const fs::path path = "file-users.bin";
        const fs::path alias = "file-users-alias.bin";
        { std::ofstream file(path); file << "mapped bytes"; }
        fs::create_symlink(path, alias);
        std::vector<Os::FileLockOwner> owners;
        const auto contains = [&](const uint32_t pid) { return std::ranges::any_of(owners, [pid](const auto& owner) { return owner.processId == pid && !owner.processName.empty(); }); };
        Os::queryFileLockOwners(owners, Os::getExeFullName());
        require(contains(Os::currentProcessId()), "executable user was not found");
        Os::queryFileLockOwners(owners, path);
        require(owners.empty(), "unheld file has a reported user");
        {
            Os::ReadOnlyFileMapping mapping;
            require(mapping.open(path, 64), "cannot map file-user fixture");
            Os::queryFileLockOwners(owners, alias);
            require(contains(Os::currentProcessId()), "mapped file without an open descriptor was not found through its alias");
        }
        Os::queryFileLockOwners(owners, path);
        require(owners.empty(), "unmapped file retained its earlier user");

        Pipe ready;
        Pipe finish;
        const pid_t child = fork();
        if (child == 0)
        {
            try
            {
                const int file = open(path.c_str(), O_RDONLY | O_CLOEXEC);
                if (file < 0)
                    _exit(1);
                ready.send();
                finish.receive();
                close(file);
                _exit(0);
            }
            catch (...) { _exit(2); }
        }
        require(child > 0, "cannot create file-user fixture child");
        ready.receive();
        Os::queryFileLockOwners(owners, path);
        require(contains(static_cast<uint32_t>(child)), "another process's open descriptor was not found");
        finish.send();
        checkChild(child);
        Os::queryFileLockOwners(owners, "missing-file-users.bin");
        require(owners.empty(), "missing file retained an earlier user");
    }

    void testCrossToolchainDiscovery()
    {
        // Isolate environment changes from later threaded process tests and the user's setup.
        const pid_t child = fork();
        if (child == 0)
        {
            try
            {
                unsetenv("VCToolsInstallDir");
                unsetenv("WindowsSdkDir");
                unsetenv("WindowsSDKVersion");
                Os::WindowsToolchainPaths paths;
                require(Os::discoverWindowsToolchainPaths(paths) == Os::WindowsToolchainDiscoveryResult::MissingMsvcToolchain, "missing cross toolchain was accepted");
                const fs::path vc = fs::absolute("cross toolchain/vc");
                const fs::path sdk = fs::absolute("cross toolchain/sdk");
                fs::create_directories(vc / "lib/x64");
                require(setenv("VCToolsInstallDir", vc.c_str(), 1) == 0, "cannot set cross toolchain path");
                require(Os::discoverWindowsToolchainPaths(paths) == Os::WindowsToolchainDiscoveryResult::MissingWindowsSdk, "missing cross SDK was accepted");
                for (const auto version : {"10.0.1", "10.0.2"})
                {
                    fs::create_directories(sdk / "Lib" / version / "um/x64");
                    fs::create_directories(sdk / "Lib" / version / "ucrt/x64");
                }
                fs::create_directories(sdk / "Lib/10.0.3/um/x64");
                require(setenv("WindowsSdkDir", sdk.c_str(), 1) == 0, "cannot set cross SDK path");
                require(Os::discoverWindowsToolchainPaths(paths) == Os::WindowsToolchainDiscoveryResult::Ok && paths.sdkUmLibPath == sdk / "Lib/10.0.2/um/x64", "newest complete cross SDK was not selected");
                require(setenv("WindowsSDKVersion", "10.0.1", 1) == 0, "cannot select explicit cross SDK");
                require(Os::discoverWindowsToolchainPaths(paths) == Os::WindowsToolchainDiscoveryResult::Ok && paths.sdkUcrtLibPath == sdk / "Lib/10.0.1/ucrt/x64", "explicit cross SDK version was ignored");
                unsetenv("VCToolsInstallDir");
                require(Os::discoverWindowsToolchainPaths(paths) == Os::WindowsToolchainDiscoveryResult::MissingMsvcToolchain && paths.vcLibPath.empty(), "failed cross discovery retained earlier VC inputs");
                _exit(0);
            }
            catch (const std::exception& error)
            {
                std::fprintf(stderr, "cross-toolchain test: %s\n", error.what());
                _exit(1);
            }
        }
        checkChild(child);
    }

    void testFileServices()
    {
        fs::create_directory("file-services");
        const fs::path cache = "file-services/cache.bin";
        const std::string oldBytes("old\0generation", 14);
        const std::string newBytes(16 * 1024, 'n');
        FileSystem::IoErrorInfo error;
        require(FileSystem::writeBinaryFileAtomic(cache, oldBytes.data(), oldBytes.size(), error) == Result::Continue, "cannot publish first cache");
        Os::ReadOnlyFileMapping oldMapping;
        require(oldMapping.open(cache, oldBytes.size()), "cannot map first cache");
        require(FileSystem::writeBinaryFileAtomic(cache, newBytes.data(), newBytes.size(), error, FileSystem::FileReplacement::Mapped) == Result::Continue, "cannot replace mapped cache");
        require(oldMapping.bytes().size() == oldBytes.size() && std::memcmp(oldMapping.bytes().data(), oldBytes.data(), oldBytes.size()) == 0, "publication changed the old generation");
        std::string contents;
        require(FileSystem::readTextFile(cache, contents, error) == Result::Continue && contents == newBytes, "cannot read published bytes");
        ByteArray bytes;
        require(FileSystem::readBinaryFile(cache, bytes, error) == Result::Continue && bytes.size() == newBytes.size(), "ByteArray read differs");
        std::vector<char8_t> utf8;
        require(FileSystem::readBinaryFile(cache, utf8, error, 64) == Result::Continue && utf8.size() == newBytes.size() && utf8.capacity() >= newBytes.size() + 64, "UTF-8 read reserve differs");

        fs::create_directory("file-services/destination-directory");
        require(FileSystem::writeBinaryFileAtomic("file-services/destination-directory", "x", 1, error) == Result::Error && !error.because.empty(), "publication over a directory succeeded");
        require(FileSystem::readTextFile("file-services/missing", contents, error) == Result::Error && contents.empty(), "missing read retained old output");
        require(FileSystem::writeBinaryFileAtomic(cache, nullptr, 0, error) == Result::Continue, "cannot publish empty file");
        require(FileSystem::readTextFile(cache, contents, error) == Result::Continue && contents.empty(), "empty publication retained old bytes");
        require(FileSystem::writeBinaryFile("file-services/replacement", "x", 1, error) == Result::Continue, "cannot create rename fixture");
        error.because = "previous error";
        require(FileSystem::renameOverFile("file-services/replacement", cache, error) == Result::Continue && error.because.empty(), "successful rename retained an error");
        for (const auto& entry : fs::directory_iterator("file-services"))
            require(entry.path().extension() != ".swctmp" && !FileSystem::isMovedAsidePath(entry.path()), "publication retained a temporary or stale file");

        const std::string valueA(64 * 1024, 'a');
        const std::string valueB(32 * 1024, 'b');
        require(FileSystem::writeBinaryFileAtomic(cache, valueA.data(), valueA.size(), error) == Result::Continue, "cannot initialize concurrent publication");
        std::atomic<bool> writerOk = true;
        std::jthread writer([&] {
            FileSystem::IoErrorInfo writeError;
            for (size_t i = 0; i < 64; ++i)
            {
                const auto& value = i % 2 ? valueA : valueB;
                if (FileSystem::writeBinaryFileAtomic(cache, value.data(), value.size(), writeError) != Result::Continue)
                    writerOk = false;
            }
        });
        for (size_t i = 0; i < 128; ++i)
            require(FileSystem::readTextFile(cache, contents, error) == Result::Continue && (contents == valueA || contents == valueB), "reader observed a partial atomic publication");
        writer.join();
        require(writerOk, "concurrent publication failed");
    }

    void testDirectoryLocks()
    {
        Os::DirectoryLock rejected;
        Utf8              because;
        require(!rejected.lock(because, "missing-lock-directory") && !because.empty(), "missing directory lock succeeded");
        require(!rejected.lock(because, "file-services/cache.bin") && !because.empty(), "regular-file directory lock succeeded");
        fs::create_directory("readonly-lock");
        fs::permissions("readonly-lock", fs::perms::owner_read | fs::perms::owner_exec);
        require(rejected.lock(because, "readonly-lock") && because.empty(), "read-only directory lock failed after rejected opens");
        require(fs::is_empty("readonly-lock"), "read-only directory contains a lock artifact");
        checkDirectoryWaiter(false);
        checkDirectoryWaiter(true);
    }
}
