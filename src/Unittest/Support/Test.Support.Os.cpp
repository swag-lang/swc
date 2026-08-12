#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

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
