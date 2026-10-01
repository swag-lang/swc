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
    if (!buildCoffStaticArchive(bytes, diag, {}) || bytes.size() != 140 || bytes.readBe32(68) != 0 ||
        !matchesArchiveHeader(bytes, 8, "/", 4) || !matchesArchiveHeader(bytes, 72, "/", 8) || bytes.readLe32(132) || bytes.readLe32(136))
        return Result::Error;

    const std::vector<LinkArchiveMember> shortMembers = {{.name = "f.obj", .bytes = makeArchiveTestObject("a", std::byte{0xC3})}};
    if (!buildCoffStaticArchive(bytes, diag, shortMembers) || bytes.size() != 298 || !bytes.contains("!<arch>\n") ||
        !matchesArchiveHeader(bytes, 8, "/", 10) || !matchesArchiveHeader(bytes, 78, "/", 16) || !matchesArchiveHeader(bytes, 154, "f.obj/", 83) ||
        bytes.readBe32(68) != 1 || bytes.readBe32(72) != 154 || bytes[76] != std::byte{'a'} || bytes[77] != std::byte{0} || bytes[297] != std::byte{'\n'} ||
        bytes.readLe32(138) != 1 || bytes.readLe32(142) != 154 || bytes.readLe32(146) != 1 || bytes.readLe16(150) != 1 ||
        bytes[152] != std::byte{'a'} || bytes[153] != std::byte{0} || !std::ranges::equal(bytes.span().subspan(214, 83), shortMembers[0].bytes))
        return Result::Error;

    // Both linker directories, the long-names table and the object need separate alignment bytes.
    const std::vector<LinkArchiveMember> longMembers = {{.name = "0123456789abcdef", .bytes = makeArchiveTestObject("bb", std::byte{0x90})}};
    if (!buildCoffStaticArchive(bytes, diag, longMembers) || bytes.size() != 380 ||
        !matchesArchiveHeader(bytes, 8, "/", 11) || !matchesArchiveHeader(bytes, 80, "/", 17) ||
        !matchesArchiveHeader(bytes, 158, "//", 17) || !matchesArchiveHeader(bytes, 236, "/0", 83) ||
        bytes.readBe32(68) != 1 || bytes.readBe32(72) != 236 || bytes[76] != std::byte{'b'} || bytes[77] != std::byte{'b'} || bytes[78] != std::byte{0} ||
        bytes.readLe32(140) != 1 || bytes.readLe32(144) != 236 || bytes.readLe32(148) != 1 || bytes.readLe16(152) != 1 ||
        std::memcmp(bytes.data() + 154, "bb\0", 3) != 0 || bytes[79] != std::byte{'\n'} || bytes[157] != std::byte{'\n'} ||
        bytes[235] != std::byte{'\n'} || bytes[379] != std::byte{'\n'} ||
        std::memcmp(bytes.data() + 218, "0123456789abcdef\0", 17) != 0 || !std::ranges::equal(bytes.span().subspan(296, 83), longMembers[0].bytes))
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
        ByteArray longNames;
        longNames.appendCString(Utf8(16, 'b').view());
        longNames.appendCString(Utf8(middleNameSize, 'c').view());
        longNames.appendCString(Utf8(16, 'd').view());
        const std::array<Utf8, 6> headerNames = {"/", "aaaaaaaaaaaaaaa/", "/0", "/17", middleNameSize == 100 ? "/118" : "/119", "end.obj/"};
        Diagnostic                diag;
        ByteArray                 bytes;
        if (!buildCoffStaticArchive(bytes, diag, members) || bytes.size() != 1284 || bytes.readBe32(68) != 6 ||
            !matchesArchiveHeader(bytes, 8, "/", 40) || !matchesArchiveHeader(bytes, 108, "/", 56) ||
            !matchesArchiveHeader(bytes, 224, "//", static_cast<uint32_t>(longNames.size())))
            return Result::Error;
        if (!std::ranges::equal(bytes.span().subspan(284, longNames.size()), longNames) || bytes[419] != (middleNameSize == 100 ? std::byte{'\n'} : std::byte{0}))
            return Result::Error;

        // Both tables end at offset 420: one needs padding, the other ends on its last NUL.
        for (size_t index = 0; index < members.size(); ++index)
        {
            const uint32_t offset = 420 + static_cast<uint32_t>(index) * 144;
            if (bytes.readBe32(72 + index * 4) != offset || !matchesArchiveHeader(bytes, offset, headerNames[index].view(), 83) ||
                !std::ranges::equal(bytes.span().subspan(offset + 60, 83), members[index].bytes) || bytes[offset + 143] != std::byte{'\n'})
                return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Linker_ArchiveSecondDirectorySortsNamesAndPreservesFirstDefinition)
{
    std::vector<LinkArchiveMember> members = {
        {.name = "one.obj", .bytes = makeArchiveTestObject("zeta", std::byte{0xC3})},
        {.name = "empty.obj", .bytes = makeArchiveTestObject("unused", std::byte{0x90})},
        {.name = "three.obj", .bytes = makeArchiveTestObject("alpha", std::byte{0xC3})},
        {.name = "four.obj", .bytes = makeArchiveTestObject("zeta", std::byte{0x90})},
    };
    members[1].bytes.writeLe32(8, 0);
    members[1].bytes.writeLe32(12, 0);
    Diagnostic diag;
    ByteArray  bytes;
    if (!buildCoffStaticArchive(bytes, diag, members) || bytes.size() != 776 ||
        !matchesArchiveHeader(bytes, 8, "/", 32) || !matchesArchiveHeader(bytes, 100, "/", 39))
        return Result::Error;
    // The first directory follows object order, including the later duplicate definition.
    if (bytes.readBe32(68) != 3 || bytes.readBe32(72) != 200 || bytes.readBe32(76) != 488 || bytes.readBe32(80) != 632 ||
        std::memcmp(bytes.data() + 84, "zeta\0alpha\0zeta\0", 16) != 0)
        return Result::Error;
    // Every object has an offset, including the one with no symbols. The lexical directory
    // selects member three for alpha and the earliest defining member, one, for zeta.
    if (bytes.readLe32(160) != 4 || bytes.readLe32(164) != 200 || bytes.readLe32(168) != 344 || bytes.readLe32(172) != 488 || bytes.readLe32(176) != 632 ||
        bytes.readLe32(180) != 2 || bytes.readLe16(184) != 3 || bytes.readLe16(186) != 1 ||
        std::memcmp(bytes.data() + 188, "alpha\0zeta\0", 11) != 0 || bytes[199] != std::byte{'\n'})
        return Result::Error;
    Archive archive;
    if (!archive.load(diag, std::move(bytes)) || archive.memberOffsetForSymbol("alpha") != 488 || archive.memberOffsetForSymbol("zeta") != 200)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Linker_ImportSecondDirectoryMapsThunkAndIatNames)
{
    Diagnostic diag;
    ByteArray  bytes;
    if (!buildCoffImportLibrary(bytes, diag, "names.dll", {"z", "a"}) ||
        !matchesArchiveHeader(bytes, 8, "/", 40) || !matchesArchiveHeader(bytes, 108, "/", 44))
        return Result::Error;
    if (bytes.readLe32(168) != 2 || bytes.readLe32(172) != 212 || bytes.readLe32(176) != 304 || bytes.readLe32(180) != 4 ||
        bytes.readLe16(184) != 2 || bytes.readLe16(186) != 1 || bytes.readLe16(188) != 2 || bytes.readLe16(190) != 1 ||
        std::memcmp(bytes.data() + 192, "__imp_a\0__imp_z\0a\0z\0", 20) != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Linker_ArchiveRejectsUnrepresentableMemberIndices)
{
    const std::vector<LinkArchiveMember> members(65536);
    const std::vector<Utf8>              exports(65536);
    Diagnostic                           diag;
    ByteArray                            bytes{std::byte{0xAA}};
    if (buildCoffStaticArchive(bytes, diag, members) || diag.elements().empty() || diag.elements().front()->id() != DiagnosticId::cmd_err_link_archive_member_limit ||
        bytes.size() != 1 || bytes[0] != std::byte{0xAA})
        return Result::Error;
    if (buildCoffImportLibrary(bytes, diag, "limit.dll", exports) || diag.elements().empty() || diag.elements().front()->id() != DiagnosticId::cmd_err_link_archive_member_limit ||
        bytes.size() != 1 || bytes[0] != std::byte{0xAA})
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Linker_ImportLibraryNamesSurviveAliasedOutput)
{
    std::vector<Utf8> exports = {"short"};
    for (uint32_t index = 0; index < 32; ++index)
        exports.push_back(std::format("export_name_longer_than_inline_storage_{}", index));

    for (const Utf8& dll : {Utf8("a.dll"), Utf8("12345678901.dll"), Utf8("long_library_name_that_must_survive_output_reallocation.dll")})
    {
        ByteArray bytes;
        bytes.append(dll.view());
        const std::string_view aliasedDll{reinterpret_cast<const char*>(bytes.data()), bytes.size()};
        Diagnostic             diag;
        if (!buildCoffImportLibrary(bytes, diag, aliasedDll, exports))
            return Result::Error;
        if (bytes.readBe32(68) != exports.size() * 2)
            return Result::Error;

        if (dll.size() > 15)
        {
            const size_t namesSize   = (dll.size() + 1) * exports.size();
            const size_t firstOffset = bytes.readBe32(72);
            const size_t paddedSize  = (namesSize + 1) & ~size_t{1};
            if (firstOffset < paddedSize + 60)
                return Result::Error;
            const size_t tableOffset = firstOffset - paddedSize - 60;
            if (!matchesArchiveHeader(bytes, tableOffset, "//", static_cast<uint32_t>(namesSize)) || !bytes.containsRange(tableOffset + 60, namesSize))
                return Result::Error;
            for (size_t index = 0; index < exports.size(); ++index)
            {
                const size_t offset = tableOffset + 60 + index * (dll.size() + 1);
                if (std::memcmp(bytes.data() + offset, dll.data(), dll.size()) != 0 || bytes[offset + dll.size()] != std::byte{0})
                    return Result::Error;
            }
        }

        for (size_t index = 0; index < exports.size(); ++index)
        {
            const uint32_t offset     = bytes.readBe32(72 + index * 8);
            const Utf8     headerName = dll.size() <= 15 ? dll + "/" : std::format("/{}", index * (dll.size() + 1));
            const uint32_t recordSize = static_cast<uint32_t>(20 + exports[index].size() + 1 + dll.size() + 1);
            if (bytes.readBe32(76 + index * 8) != offset || !matchesArchiveHeader(bytes, offset, headerName.view(), recordSize))
                return Result::Error;
        }

        Archive archive;
        if (!archive.load(diag, std::move(bytes)))
            return Result::Error;
        for (const Utf8& name : exports)
        {
            const uint32_t offset = archive.memberOffsetForSymbol(name);
            ArchiveImport  imported;
            if (!offset || archive.memberOffsetForSymbol("__imp_" + name) != offset || !archive.tryReadImport(imported, diag, offset) ||
                imported.dll != dll || imported.importName != name || imported.byOrdinal || imported.isData)
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
    Diagnostic diag;
    if (!buildCoffImportLibrary(bytes, diag, "archive-test.dll", {symbol, symbol, "other"}))
        return Result::Error;
    const uint32_t firstOffset = bytes.readBe32(72);
    Archive        archive;
    if (!archive.load(diag, std::move(bytes)))
        return Result::Error;

    std::vector<Archive> archives;
    archives.push_back(std::move(archive));
    archives.reserve(archives.capacity() + 1);
    Archive assigned;
    if (!buildCoffImportLibrary(bytes, diag, "previous.dll", {"previous"}))
        return Result::Error;
    if (!assigned.load(diag, std::move(bytes)))
        return Result::Error;
    assigned = std::move(archives.front());
    archives.clear();
    if (assigned.memberOffsetForSymbol(symbol) != firstOffset || assigned.memberOffsetForSymbol("__imp_" + symbol) != firstOffset || assigned.memberOffsetForSymbol("missing") || assigned.memberOffsetForSymbol("previous"))
        return Result::Error;
    ArchiveImport imported;
    if (!assigned.tryReadImport(imported, diag, firstOffset) || imported.importName != symbol || imported.dll != "archive-test.dll")
        return Result::Error;

    if (!buildCoffImportLibrary(bytes, diag, "replacement.dll", {"replacement"}))
        return Result::Error;
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
