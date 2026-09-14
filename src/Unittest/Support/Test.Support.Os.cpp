#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"
#include <latch>

SWC_BEGIN_NAMESPACE();

namespace
{
    class SharingLockedFile
    {
    public:
        explicit SharingLockedFile(const std::string_view name) :
            path_(Os::getTemporaryPath() / std::format("swc_sharing_{}_p{}.bin", name, Os::currentProcessId()))
        {
            handle_ = CreateFileW(path_.c_str(), GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
            if (handle_ != INVALID_HANDLE_VALUE)
            {
                DWORD written = 0;
                ready_        = WriteFile(handle_, "old", 3, &written, nullptr) && written == 3;
            }
        }

        ~SharingLockedFile()
        {
            release();
            std::error_code ec;
            fs::remove(path_, ec);
        }

        void release()
        {
            if (handle_ != INVALID_HANDLE_VALUE)
                CloseHandle(handle_);
            handle_ = INVALID_HANDLE_VALUE;
        }

        bool            ready() const { return ready_; }
        const fs::path& path() const { return path_; }

    private:
        fs::path path_;
        HANDLE   handle_ = INVALID_HANDLE_VALUE;
        bool     ready_  = false;
    };
}

SWC_FILESYSTEM_TEST_BEGIN(FileSystem_WriteWaitsForTransientSharingLock)
{
    SharingLockedFile file("transient");
    if (!file.ready())
        return Result::Error;

    std::latch              entered(1);
    Result                  result = Result::Error;
    FileSystem::IoErrorInfo error;
    std::jthread            writer([&] {
        entered.count_down();
        result = FileSystem::writeBinaryFile(file.path(), "new", 3, error);
    });
    entered.wait();
    std::this_thread::sleep_for(std::chrono::milliseconds(150));
    file.release();
    writer.join();
    if (result != Result::Continue)
        return Result::Error;

    std::string contents;
    SWC_RESULT(FileSystem::readTextFile(file.path(), contents, error));
    if (contents != "new")
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(FileSystem_PersistentSharingLockPreservesPreviousContents)
{
    SharingLockedFile file("persistent");
    if (!file.ready())
        return Result::Error;

    FileSystem::IoErrorInfo error;
    if (FileSystem::writeBinaryFile(file.path(), "new", 3, error) != Result::Error || error.problem != FileSystem::IoProblem::OpenWrite || error.because.empty())
        return Result::Error;
    file.release();

    std::string contents;
    SWC_RESULT(FileSystem::readTextFile(file.path(), contents, error));
    if (contents != "old")
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(FileSystem_AtomicWriteWaitsForTransientSharingLock)
{
    SharingLockedFile file("atomic_transient");
    if (!file.ready())
        return Result::Error;

    std::latch              entered(1);
    Result                  result = Result::Error;
    FileSystem::IoErrorInfo error;
    std::jthread            writer([&] {
        entered.count_down();
        result = FileSystem::writeBinaryFileAtomic(file.path(), "new", 3, error);
    });
    entered.wait();
    std::this_thread::sleep_for(std::chrono::milliseconds(150));
    file.release();
    writer.join();
    if (result != Result::Continue)
        return Result::Error;

    std::string contents;
    SWC_RESULT(FileSystem::readTextFile(file.path(), contents, error));
    if (contents != "new")
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(FileSystem_ConcurrentAtomicWritesKeepCompleteSnapshots)
{
    SharingLockedFile file("atomic_concurrent");
    if (!file.ready())
        return Result::Error;
    file.release();

    const std::array<std::string, 2> versions = {std::string(1024 * 1024, 'a'), std::string(2 * 1024 * 1024 + 4093, 'b')};
    std::atomic_uint32_t             running  = 2;
    std::atomic_bool                 failed   = false;
    std::latch                       start(3);
    std::array<std::jthread, 2>      writers;
    for (size_t i = 0; i < writers.size(); ++i)
    {
        writers[i] = std::jthread([&, i] {
            start.arrive_and_wait();
            FileSystem::IoErrorInfo error;
            for (uint32_t round = 0; round < 16; ++round)
                if (FileSystem::writeBinaryFileAtomic(file.path(), versions[i].data(), versions[i].size(), error) != Result::Continue)
                    if (!failed.exchange(true))
                        fprintf(stderr, "atomic writer %zu stopped: %s\n", i, FileSystem::describeIoFailure(error).c_str());
            running.fetch_sub(1);
        });
    }
    start.arrive_and_wait();
    do
    {
        std::string             contents;
        FileSystem::IoErrorInfo error;
        if (FileSystem::readTextFile(file.path(), contents, error) != Result::Continue)
        {
            if (!failed.exchange(true))
                fprintf(stderr, "atomic reader stopped: %s\n", FileSystem::describeIoFailure(error).c_str());
        }
        else if (contents != "old" && contents != versions[0] && contents != versions[1])
        {
            if (!failed.exchange(true))
                fprintf(stderr, "atomic reader received a mixed snapshot of %zu bytes\n", contents.size());
        }
    } while (running.load());
    for (auto& writer : writers)
        writer.join();
    if (failed.load())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Os_FatalHostExceptionClassificationExcludesCppExceptions)
{
    if (!Os::isFatalHostException(EXCEPTION_ACCESS_VIOLATION))
        return Result::Error;
    if (Os::isFatalHostException(0xE06D7363)) // MSVC C++ exception
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Os_FileLockOwnersNameTheProcessMappingAnImage)
{
    // The compiler's own executable is the one file whose lock owner is known in advance: it
    // stays mapped by this very process for as long as it runs.
    std::vector<Os::FileLockOwner> owners;
    Os::queryFileLockOwners(owners, Os::getExeFullName());

    bool foundSelf = false;
    for (const Os::FileLockOwner& owner : owners)
    {
        if (owner.processId == Os::currentProcessId())
            foundSelf = true;
    }

    if (!foundSelf)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FileSystem_AppendFileUsersNamesThisCompilerProcess)
{
    const Utf8 because = FileSystem::appendFileUsers("access is denied", Os::getExeFullName());
    if (because.view().find("access is denied; the file is in use by ") != 0)
        return Result::Error;
    if (because.view().find("this compiler process") == std::string_view::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FileSystem_AppendFileUsersLeavesAnUnheldFileAlone)
{
    const fs::path unheldPath = fs::path(Os::getTemporaryPath()) / "swc_unittest_no_such_file.dll";
    if (FileSystem::appendFileUsers("access is denied", unheldPath) != "access is denied")
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Os_RunProcessChildTreeDoesNotSurviveTheCall)
{
    // The contract on runProcess: the child and whatever it spawns die with the call, whichever
    // way it ends. The batch starts a detached grandchild that keeps a redirection handle on
    // 'lock.txt' for thirty seconds, waits for the file to exist so the handle provably predates
    // the return, then exits at once. A grandchild surviving the call keeps the file locked,
    // which is exactly the locked-artifact symptom the process job exists to prevent.
    const fs::path  testDir = (Os::getTemporaryPath() / "swc_unittest" / "os" / std::format("job_p{}", Os::currentProcessId())).lexically_normal();
    std::error_code ec;
    fs::remove_all(testDir, ec);
    fs::create_directories(testDir, ec);
    if (ec)
        return Result::Error;

    const fs::path          batchPath = testDir / "spawn.bat";
    const std::string_view  batch     = "@echo off\r\nstart \"\" /b cmd /d /c \"ping -n 30 127.0.0.1 > lock.txt\"\r\n:wait\r\nif not exist lock.txt goto wait\r\nexit /b 0\r\n";
    FileSystem::IoErrorInfo ioError;
    if (FileSystem::writeBinaryFile(batchPath, batch.data(), batch.size(), ioError) != Result::Continue)
        return Result::Error;

    const std::optional<Utf8> commandInterpreter = Os::readEnvironmentVariable("ComSpec");
    if (!commandInterpreter)
        return Result::Error;

    uint32_t                   exitCode  = 0;
    const std::vector<Utf8>    args      = {"/d", "/c", Utf8(batchPath.string())};
    const Os::ProcessRunResult runResult = Os::runProcess(exitCode, fs::path{commandInterpreter->c_str()}, args, testDir);
    if (runResult != Os::ProcessRunResult::Ok || exitCode != 0)
        return Result::Error;

    // Termination on job close is quick but not instantaneous, so the check gets a few seconds:
    // the lock file only becomes removable once the grandchild's handle is gone.
    const fs::path lockPath = testDir / "lock.txt";
    bool           released = false;
    for (uint32_t i = 0; i < 100 && !released; ++i)
    {
        ec.clear();
        fs::remove(lockPath, ec);
        released = !ec;
        if (!released)
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    fs::remove_all(testDir, ec);
    if (!released)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
