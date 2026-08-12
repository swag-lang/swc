#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

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

SWC_END_NAMESPACE();

#endif
