#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Linker/Archive.h"
#include "Main/ExitCodes.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    ByteArray makeArchiveTestObject(const std::string_view symbol, const std::byte instruction)
    {
        SWC_ASSERT(symbol.size() <= IMAGE_SIZEOF_SHORT_NAME);
        // One byte of text makes each object odd-sized, exercising archive member padding.
        ByteArray bytes(83);
        bytes.writeLe16(0, IMAGE_FILE_MACHINE_AMD64);
        bytes.writeLe16(2, 1);
        bytes.writeLe32(8, 61);
        bytes.writeLe32(12, 1);
        std::memcpy(bytes.data() + 20, ".text", 5);
        bytes.writeLe32(36, 1);
        bytes.writeLe32(40, 60);
        bytes.writeLe32(56, IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_READ);
        bytes[60] = instruction;
        std::memcpy(bytes.data() + 61, symbol.data(), symbol.size());
        bytes.writeLe16(73, 1);
        bytes[77] = static_cast<std::byte>(IMAGE_SYM_CLASS_EXTERNAL);
        bytes.writeLe32(79, 4);
        return bytes;
    }

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

SWC_TEST_BEGIN(Linker_ArchivePreservesObjectBytes)
{
    std::vector<LinkArchiveMember> members = {
        {.name = "long_archive_member_name.obj", .bytes = makeArchiveTestObject("first", std::byte{0xC3})},
        {.name = "b.obj", .bytes = makeArchiveTestObject("second", std::byte{0x90})},
    };
    Diagnostic diag;
    ByteArray  bytes{std::byte{0xFF}};
    if (!buildCoffStaticArchive(bytes, diag, members))
        return Result::Error;

    Archive archive;
    if (!archive.load(diag, std::move(bytes)))
        return Result::Error;
    const uint32_t firstOffset  = archive.memberOffsetForSymbol("first");
    const uint32_t secondOffset = archive.memberOffsetForSymbol("second");
    if (!firstOffset || secondOffset <= firstOffset || (firstOffset & 1) || (secondOffset & 1))
        return Result::Error;
    if (!std::ranges::equal(archive.memberData(diag, firstOffset), members[0].bytes) || !std::ranges::equal(archive.memberData(diag, secondOffset), members[1].bytes))
        return Result::Error;

    if (!buildCoffStaticArchive(bytes, diag, {}) || !archive.load(diag, std::move(bytes)) || archive.memberOffsetForSymbol("first"))
        return Result::Error;

    const ByteArray firstObject = members[0].bytes;
    if (!buildCoffStaticArchive(members[0].bytes, diag, members) || !archive.load(diag, std::move(members[0].bytes)))
        return Result::Error;
    if (!std::ranges::equal(archive.memberData(diag, archive.memberOffsetForSymbol("first")), firstObject) || !std::ranges::equal(archive.memberData(diag, archive.memberOffsetForSymbol("second")), members[1].bytes))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Linker_ArchiveSymbolViewsFollowOwnership)
{
    static_assert(!std::is_copy_constructible_v<Archive>);
    static_assert(!std::is_copy_assignable_v<Archive>);
    static_assert(std::is_nothrow_move_constructible_v<Archive>);

    const Utf8 symbol = "archive_symbol_longer_than_small_string_storage";
    ByteArray  bytes;
    buildCoffImportLibrary(bytes, "archive-test.dll", {symbol, symbol, "other"});
    const uint32_t firstOffset = bytes.readBe32(72);
    Diagnostic diag;
    Archive    archive;
    if (!archive.load(diag, std::move(bytes)))
        return Result::Error;

    std::vector<Archive> archives;
    archives.push_back(std::move(archive));
    archives.reserve(archives.capacity() + 1);
    Archive assigned;
    buildCoffImportLibrary(bytes, "previous.dll", {"previous"});
    if (!assigned.load(diag, std::move(bytes)))
        return Result::Error;
    assigned = std::move(archives.front());
    archives.clear();
    if (assigned.memberOffsetForSymbol(symbol) != firstOffset || assigned.memberOffsetForSymbol("__imp_" + symbol) != firstOffset || assigned.memberOffsetForSymbol("missing") || assigned.memberOffsetForSymbol("previous"))
        return Result::Error;
    ArchiveImport imported;
    if (!assigned.tryReadImport(imported, diag, firstOffset) || imported.importName != symbol || imported.dll != "archive-test.dll")
        return Result::Error;

    buildCoffImportLibrary(bytes, "replacement.dll", {"replacement"});
    if (!assigned.load(diag, std::move(bytes)) || assigned.memberOffsetForSymbol(symbol) || !assigned.memberOffsetForSymbol("replacement"))
        return Result::Error;
    if (assigned.load(diag, {}) || assigned.memberOffsetForSymbol("replacement"))
        return Result::Error;
}
SWC_TEST_END()

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
