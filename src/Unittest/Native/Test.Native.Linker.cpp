#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/ExitCodes.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class LinkerTestDirectory
    {
    public:
        explicit LinkerTestDirectory(const std::string_view name)
        {
            path_ = (Os::getTemporaryPath() / "swc_unittest" / "linker" / std::format("{}_p{}", name, Os::currentProcessId())).lexically_normal();
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        ~LinkerTestDirectory()
        {
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        const fs::path& path() const { return path_; }

        Result write(const fs::path& relativePath, const std::string_view source) const
        {
            const fs::path  path = path_ / relativePath;
            std::error_code ec;
            fs::create_directories(path.parent_path(), ec);
            if (ec)
                return Result::Error;
            FileSystem::IoErrorInfo ioError;
            return FileSystem::writeBinaryFile(path, source.data(), source.size(), ioError);
        }

    private:
        fs::path path_;
    };

    Result runCompiler(const std::vector<Utf8>& args, const ExitCode expectedExit, const std::string_view expectedOutput)
    {
        uint32_t                    exitCode = 0;
        std::string                 output;
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 30000};
        const Os::ProcessRunResult  result = Os::runProcess(exitCode, Os::getExeFullName(), args, fs::current_path(), &options);
        if (result != Os::ProcessRunResult::Ok || exitCode != static_cast<uint32_t>(expectedExit) || output.find(expectedOutput) == std::string::npos || output.find("mimalloc: error") != std::string::npos)
        {
            std::println(stderr, "[linker-test] compiler result={}, exit={}\n{}", static_cast<uint32_t>(result), exitCode, output);
            return Result::Error;
        }
        return Result::Continue;
    }
}

SWC_FILESYSTEM_TEST_BEGIN(Linker_NativeTestsDiscardRejectedCallees)
{
    const LinkerTestDirectory testDir("rejected_callee");
    const fs::path            source = Os::getExeFullName().parent_path() / "unittests" / "sanity" / "expected_error_native_roots.swg";
    // Running the JIT first would already filter the failed functions and hide this boundary.
    const std::vector<Utf8> args = {"test", "--artifact-kind", "executable", "-f", Utf8(source), "--out-dir", Utf8(testDir.path() / "output"), "--work-dir", Utf8(testDir.path() / "work"), "--build-cfg", "devmode", "--no-test-jit", "--num-cores", "6", "--no-log-color"};
    SWC_RESULT(runCompiler(args, ExitCode::Success, "1 passed"));
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_MissingResourceDrainsParallelReaders)
{
    const LinkerTestDirectory testDir("missing_resource");
    SWC_RESULT(testDir.write("module.swg", "#run\n{\n    let cfg = Swag.compiler().getBuildCfg()!\n    cfg.backendKind = .Executable\n    cfg.resAppIcoFileName = \"missing.ico\"\n}\n"));
    SWC_RESULT(testDir.write("src/main.swg", "#main {}\n"));
    const std::vector<Utf8> args = {"build", "--module", Utf8(testDir.path()), "--build-cfg", "devmode", "--num-cores", "6", "--no-log-color"};
    SWC_RESULT(runCompiler(args, ExitCode::CompileError, "cannot read resource"));
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
