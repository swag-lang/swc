#include "pch.h"

#if SWC_HAS_UNITTEST
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Unittest/Compiler/CompilerTestFile.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class TargetTestDirectory
    {
    public:
        TargetTestDirectory()
        {
            path_ = (Os::getTemporaryPath() / "swc_unittest" / "target_windows_o0_indirect_call" / std::format("p{}", Os::currentProcessId())).lexically_normal();
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        ~TargetTestDirectory()
        {
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        const fs::path& path() const { return path_; }

    private:
        fs::path path_;
    };
}

SWC_TEST_BEGIN(Compiler_CommandLineDefaultsToHostTarget)
{
    CommandLine       commandLine;
    char              arg0[] = "swc";
    char              arg1[] = "syntax";
    char*             argv[] = {arg0, arg1};
    CommandLineParser parser(const_cast<Global&>(ctx.global()), commandLine);
    SWC_RESULT(parser.parse(std::size(argv), argv));
    if (commandLine.targetOs != hostTargetOs())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineSelectsTargetOs)
{
    for (const auto target : {Runtime::TargetOs::Windows, Runtime::TargetOs::Linux})
    {
        CommandLine       commandLine;
        char              arg0[]    = "swc";
        char              arg1[]    = "syntax";
        char              arg2[]    = "--os";
        char              windows[] = "windows";
        char              linuxOs[] = "linux";
        char*             argv[]    = {arg0, arg1, arg2, target == Runtime::TargetOs::Windows ? windows : linuxOs};
        CommandLineParser parser(const_cast<Global&>(ctx.global()), commandLine);
        SWC_RESULT(parser.parse(std::size(argv), argv));
        if (commandLine.targetOs != target)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_TargetWindowsO0AllowsDeadIndirectCallTargetInClobberedRegister)
{
    const TargetTestDirectory directory;
    const fs::path            sourcePath = directory.path() / "minimal.swg";
    SWC_RESULT(CompilerTestFile::writeText(sourcePath, "func main()\n{\n}\n"));

    const std::vector<Utf8> args = {
        "build",
        "--os",
        "windows",
        "--artifact-kind",
        "export",
        "--optim-level",
        "0",
        "--num-cores",
        "1",
        "--work-dir",
        (directory.path() / "work").string(),
        "--out-dir",
        (directory.path() / "out").string(),
        "--file",
        sourcePath.string(),
    };

    uint32_t              exitCode = UINT32_MAX;
    Os::ProcessRunOptions options;
    options.forwardOutput = false;
    if (Os::runProcess(exitCode, Os::getExeFullName(), args, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();
#endif
