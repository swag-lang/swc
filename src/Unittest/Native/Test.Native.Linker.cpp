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

    bool matchesArchiveHeader(const ByteArray& bytes, const size_t offset, const std::string_view name, const uint32_t dataSize)
    {
        const std::string expected = std::format("{:<16}{:<12}{:<6}{:<6}{:<8}{:<10}`\n", name, 0, 0, 0, 0, dataSize);
        return bytes.containsRange(offset, expected.size()) && std::memcmp(bytes.data() + offset, expected.data(), expected.size()) == 0;
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

SWC_TEST_BEGIN(Linker_ArchivePreservesMemberLayout)
{
    Diagnostic diag;
    ByteArray  bytes;
    if (!buildCoffStaticArchive(bytes, diag, {}) || bytes.size() != 72 || bytes.readBe32(68) != 0 || !matchesArchiveHeader(bytes, 8, "/", 4))
        return Result::Error;

    const std::vector<LinkArchiveMember> shortMembers = {{.name = "f.obj", .bytes = makeArchiveTestObject("a", std::byte{0xC3})}};
    if (!buildCoffStaticArchive(bytes, diag, shortMembers) || bytes.size() != 222 || !bytes.contains("!<arch>\n") ||
        !matchesArchiveHeader(bytes, 8, "/", 10) || !matchesArchiveHeader(bytes, 78, "f.obj/", 83) ||
        bytes.readBe32(68) != 1 || bytes.readBe32(72) != 78 || bytes[76] != std::byte{'a'} || bytes[77] != std::byte{0} || bytes[221] != std::byte{'\n'} ||
        !std::ranges::equal(bytes.span().subspan(138, 83), shortMembers[0].bytes))
        return Result::Error;

    // The linker member, long-names table and object all need an alignment byte.
    const std::vector<LinkArchiveMember> longMembers = {{.name = "0123456789abcdef", .bytes = makeArchiveTestObject("bb", std::byte{0x90})}};
    if (!buildCoffStaticArchive(bytes, diag, longMembers) || bytes.size() != 302 ||
        !matchesArchiveHeader(bytes, 8, "/", 11) || !matchesArchiveHeader(bytes, 80, "//", 17) || !matchesArchiveHeader(bytes, 158, "/0", 83) ||
        bytes.readBe32(68) != 1 || bytes.readBe32(72) != 158 || bytes[76] != std::byte{'b'} || bytes[77] != std::byte{'b'} || bytes[78] != std::byte{0} ||
        bytes[79] != std::byte{'\n'} || bytes[157] != std::byte{'\n'} || bytes[301] != std::byte{'\n'} ||
        std::memcmp(bytes.data() + 140, "0123456789abcdef\n", 17) != 0 || !std::ranges::equal(bytes.span().subspan(218, 83), longMembers[0].bytes))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Linker_ArchiveNamesPreserveInlineBoundariesAndOffsets)
{
    for (const uint32_t middleNameSize : {100u, 101u})
    {
        const std::vector<LinkArchiveMember> members = {
            {.name = "", .bytes = makeArchiveTestObject("a", std::byte{0xC3})},
            {.name = Utf8(15, 'a'), .bytes = makeArchiveTestObject("b", std::byte{0xC3})},
            {.name = Utf8(16, 'b'), .bytes = makeArchiveTestObject("c", std::byte{0x90})},
            {.name = Utf8(middleNameSize, 'c'), .bytes = makeArchiveTestObject("d", std::byte{0x90})},
            {.name = Utf8(16, 'd'), .bytes = makeArchiveTestObject("e", std::byte{0x90})},
            {.name = "end.obj", .bytes = makeArchiveTestObject("f", std::byte{0xC3})},
        };
        const Utf8                longNames   = Utf8(16, 'b') + "\n" + Utf8(middleNameSize, 'c') + "\n" + Utf8(16, 'd') + "\n";
        const std::array<Utf8, 6> headerNames = {"/", "aaaaaaaaaaaaaaa/", "/0", "/17", middleNameSize == 100 ? "/118" : "/119", "end.obj/"};
        Diagnostic                diag;
        ByteArray                 bytes;
        if (!buildCoffStaticArchive(bytes, diag, members) || bytes.size() != 1168 || bytes.readBe32(68) != 6 ||
            !matchesArchiveHeader(bytes, 8, "/", 40) || !matchesArchiveHeader(bytes, 108, "//", static_cast<uint32_t>(longNames.size())))
            return Result::Error;
        if (std::memcmp(bytes.data() + 168, longNames.data(), longNames.size()) != 0 || bytes[303] != std::byte{'\n'})
            return Result::Error;

        // Both table sizes end at offset 304: one needs padding, the other ends on its own newline.
        for (size_t index = 0; index < members.size(); ++index)
        {
            const uint32_t offset = 304 + static_cast<uint32_t>(index) * 144;
            if (bytes.readBe32(72 + index * 4) != offset || !matchesArchiveHeader(bytes, offset, headerNames[index].view(), 83) ||
                !std::ranges::equal(bytes.span().subspan(offset + 60, 83), members[index].bytes) || bytes[offset + 143] != std::byte{'\n'})
                return Result::Error;
        }
    }
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
