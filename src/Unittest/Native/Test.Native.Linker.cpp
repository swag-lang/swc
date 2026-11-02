#include "pch.h"
#include "Backend/Linker/PEFormat.h"

#if SWC_HAS_UNITTEST

#include "Backend/Linker/Archive.h"
#include "Backend/Linker/ELFObjectWriter.h"
#include "Backend/RuntimeName.h"
#include "Backend/Encoder/X64DwarfFrame.h"
#include "Unittest/Native/NativeTestBytes.h"
#include "Main/ExitCodes.h"
#include "Main/FileSystem.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view K_HOST_TARGET_ARGUMENT = hostTargetOs() == Runtime::TargetOs::Windows ? "windows" : "linux";

    ByteArray makeArchiveTestObject(const std::string_view symbol, const std::byte instruction)
    {
        SWC_ASSERT(symbol.size() <= PE::SIZEOF_SHORT_NAME);
        // One byte of text makes each object odd-sized, exercising archive member padding.
        ByteArray bytes(83);
        bytes.writeLe16(0, PE::FILE_MACHINE_AMD64);
        bytes.writeLe16(2, 1);
        bytes.writeLe32(8, 61);
        bytes.writeLe32(12, 1);
        std::memcpy(bytes.data() + 20, ".text", 5);
        bytes.writeLe32(36, 1);
        bytes.writeLe32(40, 60);
        bytes.writeLe32(56, PE::SCN_CNT_CODE | PE::SCN_MEM_EXECUTE | PE::SCN_MEM_READ);
        bytes[60] = instruction;
        std::memcpy(bytes.data() + 61, symbol.data(), symbol.size());
        bytes.writeLe16(73, 1);
        bytes[77] = static_cast<std::byte>(PE::SYM_CLASS_EXTERNAL);
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

#ifdef __linux__
    Result copyWorkspaceModules(const fs::path& destination, const std::initializer_list<std::string_view> modules)
    {
        const fs::path sourceModules = Os::getExeFullName().parent_path() / "unittests" / "workspace" / "modules";
        for (const std::string_view module : modules)
        {
            std::error_code error;
            const fs::path moduleDirectory = destination / "modules" / module;
            fs::create_directories(moduleDirectory, error);
            if (error)
                return Result::Error;
            fs::copy(sourceModules / module, moduleDirectory, fs::copy_options::recursive, error);
            if (error)
                return Result::Error;
        }
        return Result::Continue;
    }
#endif

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

SWC_FILESYSTEM_TEST_BEGIN(Linker_OptimizedCallsDoNotRetainReflection)
{
    const LinkerTestDirectory  testDir("emitted_roots");
    constexpr std::string_view source = R"(struct UnreachableReflectionPayload
{
    value: [64] u64
}

struct RetainedReflectionPayload
{
    value: u64
}

#[Swag.NoInline]
func deadReflection()
{
    reflect(#typeof(UnreachableReflectionPayload))
}

#[Swag.NoInline]
func reflect(type: typeinfo)
{
    let info = assume cast(const *Swag.TypeInfoStruct, type)
    Swag.assert(info.fields.count == 1)
    Swag.print(type.fullname)
}

var gCallback = &reflect

#main
{
    var enabled = false
    if enabled do
        deadReflection()
    gCallback(#typeof(RetainedReflectionPayload))
}
)";
    SWC_RESULT(testDir.write("main.swg", source));
    const std::vector<Utf8> args = {"run", "--os", Utf8(K_HOST_TARGET_ARGUMENT), "-f", Utf8(testDir.path() / "main.swg"), "-n", "emitted", "--artifact-kind", "executable", "--out-dir", Utf8(testDir.path() / "output"), "--work-dir", Utf8(testDir.path() / "work"), "--build-cfg", "devmode", "--num-cores", std::to_string(Unittest::compilerWorkerCount(ctx)), "--no-log-color"};
    SWC_RESULT(runCompiler(args, ExitCode::Success, "RetainedReflectionPayload"));

    ByteArray               bytes;
    FileSystem::IoErrorInfo ioError;
    SWC_RESULT(FileSystem::readBinaryFile(testDir.path() / "output" / (hostTargetOs() == Runtime::TargetOs::Windows ? "emitted.exe" : "emitted"), bytes, ioError));
    const std::string_view image{reinterpret_cast<const char*>(bytes.data()), bytes.size()};
    // The branch disappears during lowering, after its semantic call edge was recorded.
    // Its callee must not retain type records, names or transitive field descriptors.
    if (image.contains("UnreachableReflectionPayload") || !image.contains("RetainedReflectionPayload"))
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
    const std::span<const std::byte> importData = assigned.memberData(diag, firstOffset);
    ArchiveImport                    importedFromBytes;
    if (importData.empty() || !assigned.tryReadImport(importedFromBytes, importData))
        return Result::Error;
    if (importedFromBytes.importName != symbol || importedFromBytes.dll != "archive-test.dll")
        return Result::Error;

    if (!buildCoffImportLibrary(bytes, diag, "replacement.dll", {"replacement"}))
        return Result::Error;
    if (!assigned.load(diag, std::move(bytes)) || assigned.memberOffsetForSymbol(symbol) || !assigned.memberOffsetForSymbol("replacement"))
        return Result::Error;
    if (assigned.load(diag, {}) || assigned.memberOffsetForSymbol("replacement"))
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_MappedArchivesKeepBytesAcrossMovesAndReplacement)
{
    const LinkerTestDirectory testDir("mapped_archive");
    const fs::path            path = testDir.path() / "input.lib";
    ByteArray                 bytes;
    Diagnostic                diag;
    if (!buildCoffImportLibrary(bytes, diag, "old.dll", {"original"}))
        return Result::Error;
    SWC_RESULT(testDir.write("input.lib", {reinterpret_cast<const char*>(bytes.data()), bytes.size()}));

    Archive original;
    if (!original.loadFile(diag, path))
        return Result::Error;
    const uint32_t           offset = original.memberOffsetForSymbol("original");
    const auto               member = original.memberData(diag, offset);
    if (member.empty() || !Unittest::isFileMapping(member.data()))
        return Result::Error;

    std::vector<Archive> archives;
    archives.push_back(std::move(original));
    archives.reserve(archives.capacity() + 1);
    Archive assigned;
    if (!assigned.load(diag, bytes))
        return Result::Error;
    assigned = std::move(archives.front());
    archives.clear();
    if (assigned.memberData(diag, offset).data() != member.data())
        return Result::Error;

    if (!buildCoffImportLibrary(bytes, diag, "new.dll", {"replacement"}))
        return Result::Error;
    FileSystem::IoErrorInfo ioError;
    SWC_RESULT(FileSystem::writeBinaryFileAtomic(path, bytes.data(), bytes.size(), ioError, FileSystem::FileReplacement::Mapped));
    if (!original.loadFile(diag, path))
        return Result::Error;
    ArchiveImport imported;
    if (!assigned.tryReadImport(imported, diag, offset) || imported.dll != "old.dll" || imported.importName != "original")
        return Result::Error;
    if (assigned.memberOffsetForSymbol("replacement") || original.memberOffsetForSymbol("original"))
        return Result::Error;
    const uint32_t replacementOffset = original.memberOffsetForSymbol("replacement");
    if (!replacementOffset || !original.tryReadImport(imported, diag, replacementOffset) || imported.dll != "new.dll")
        return Result::Error;

    // Reload a mapped owner from memory, then reuse that owner for another mapping.
    if (!assigned.load(diag, std::move(bytes)) || assigned.memberOffsetForSymbol("original") || !assigned.memberOffsetForSymbol("replacement"))
        return Result::Error;
    if (!assigned.loadFile(diag, path) || !assigned.memberOffsetForSymbol("replacement"))
        return Result::Error;
    if (assigned.loadFile(diag, testDir.path() / "missing.lib") || !assigned.memberOffsetForSymbol("replacement"))
        return Result::Error;
    SWC_RESULT(testDir.write("invalid.lib", "not an archive"));
    if (assigned.loadFile(diag, testDir.path() / "invalid.lib") || assigned.memberOffsetForSymbol("replacement"))
        return Result::Error;
    // Empty files cannot be mapped; the ordinary-read fallback still rejects their contents.
    SWC_RESULT(testDir.write("empty.lib", ""));
    if (assigned.loadFile(diag, testDir.path() / "empty.lib") || assigned.memberOffsetForSymbol("replacement"))
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_NativeStartupPreservesArguments)
{
    const LinkerTestDirectory testDir("native_arguments");
    constexpr std::string_view source = R"(#main
{
    let actual = Swag.args()
    let values: [6] string = ["", "two words", "a\"b", "tail\\", "\t", "café"]
    Swag.assert(actual.count == 7)
    for expected, index in values do
        Swag.assert(actual[index + 1] == expected)
    Swag.print("native arguments passed\n")
}
)";
    SWC_RESULT(testDir.write("main.swg", source));
    const std::vector<Utf8> args = {"run", "--os", Utf8(K_HOST_TARGET_ARGUMENT), "-f", Utf8(testDir.path() / "main.swg"), "-n", "arguments", "--artifact-kind", "executable", "--out-dir", Utf8(testDir.path() / "output"), "--work-dir", Utf8(testDir.path() / "work"), "--num-cores", "3", "--no-log-color", "--run-arg", "", "--run-arg", "two words", "--run-arg", "a\"b", "--run-arg", "tail\\", "--run-arg", "\t", "--run-arg", "caf\xc3\xa9"};
    SWC_RESULT(runCompiler(args, ExitCode::Success, "native arguments passed"));
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_NativeTestsDiscardRejectedCallees)
{
    const LinkerTestDirectory testDir("rejected_callee");
    const fs::path            source = Os::getExeFullName().parent_path() / "unittests" / "sanity" / "expected_error_native_roots.swg";
    // Running the JIT first would already filter the failed functions and hide this boundary.
    const std::vector<Utf8> args = {"test", "--os", Utf8(K_HOST_TARGET_ARGUMENT), "--artifact-kind", "executable", "-f", Utf8(source), "--out-dir", Utf8(testDir.path() / "output"), "--work-dir", Utf8(testDir.path() / "work"), "--build-cfg", "devmode", "--no-test-jit", "--num-cores", std::to_string(Unittest::compilerWorkerCount(ctx)), "--no-log-color"};
    SWC_RESULT(runCompiler(args, ExitCode::Success, "1 passed"));
}
SWC_TEST_END()

#ifdef __linux__
SWC_FILESYSTEM_TEST_BEGIN(Linker_LinuxDependencyUsesPublishedArtifactName)
{
    LinkerTestDirectory directory("published_artifact_name");
    SWC_RESULT(copyWorkspaceModules(directory.path(), {"artifact_name_provider", "artifact_name_consumer"}));
    const std::vector<Utf8> arguments = {
        "run", "--os", "linux", "--workspace", Utf8(directory.path()), "--workspace-module", "artifact_name_consumer",
        "--num-cores", "3", "--no-log-color"};
    return runCompiler(arguments, ExitCode::Success, "artifact provider dropped");
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_LinuxSharedModulesUseChildLibraryPaths)
{
    LinkerTestDirectory directory("shared_library_paths");
    SWC_RESULT(copyWorkspaceModules(directory.path(), {"artifact_shared_provider", "artifact_shared_consumer"}));
    const std::vector<Utf8> arguments = {
        "run", "--os", "linux", "--workspace", Utf8(directory.path()), "--workspace-module", "artifact_shared_consumer",
        "--num-cores", "3", "--no-log-color", "--run-arg", "", "--run-arg", "two words", "--run-arg", "café"};
    return runCompiler(arguments, ExitCode::Success, "shared provider dropped");
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_LinuxSharedModulesExecuteDuringCompilation)
{
    LinkerTestDirectory directory("shared_library_jit");
    SWC_RESULT(copyWorkspaceModules(directory.path(), {"artifact_shared_provider", "artifact_shared_jit_consumer"}));
    const std::vector<Utf8> arguments = {
        "run", "--os", "linux", "--workspace", Utf8(directory.path()), "--workspace-module", "artifact_shared_jit_consumer",
        "--num-cores", "3", "--no-log-color", "--run-arg", "", "--run-arg", "two words", "--run-arg", "café"};
    return runCompiler(arguments, ExitCode::Success, "compile-time shared artifact passed");
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_LinuxTransitiveSharedModulesExecuteDuringCompilation)
{
    LinkerTestDirectory directory("transitive_shared_library_jit");
    SWC_RESULT(copyWorkspaceModules(directory.path(), {"artifact_transitive_leaf", "artifact_transitive_middle", "artifact_transitive_consumer"}));
    // Build providers in a separate process so their earlier compilation cannot preload them.
    const std::vector<Utf8> dependencies = {
        "build", "--os", "linux", "--workspace", Utf8(directory.path()), "--workspace-module", "artifact_transitive_middle",
        "--num-cores", "3", "--no-log-color"};
    SWC_RESULT(runCompiler(dependencies, ExitCode::Success, ""));
    const std::vector<Utf8> arguments = {
        "run", "--os", "linux", "--workspace", Utf8(directory.path()), "--workspace-module", "artifact_transitive_consumer",
        "--num-cores", "3", "--no-log-color"};
    SWC_RESULT(runCompiler(arguments, ExitCode::Success, "transitive shared artifact passed"));
    return runCompiler(arguments, ExitCode::Success, "transitive shared artifact passed");
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_LinuxCompanionArchivesKeepRuntimeHooksDistinct)
{
    LinkerTestDirectory directory("companion_archive_runtime_hooks");
    SWC_RESULT(copyWorkspaceModules(directory.path(), {"artifact_transitive_leaf", "artifact_transitive_middle", "artifact_transitive_consumer"}));
    for (const std::string_view module : {"artifact_transitive_middle", "artifact_transitive_consumer"})
    {
        const fs::path setupPath = fs::path("modules") / module / "module.swg";
        std::string setup;
        FileSystem::IoErrorInfo ioError;
        SWC_RESULT(FileSystem::readTextFile(directory.path() / setupPath, setup, ioError));
        constexpr std::string_view sharedLink = ", link: \"shared-library\"";
        const size_t offset = setup.find(sharedLink);
        if (offset == std::string::npos)
            return Result::Error;
        setup.erase(offset, sharedLink.size());
        SWC_RESULT(directory.write(setupPath, setup));
    }
    const std::vector<Utf8> arguments = {
        "run", "--os", "linux", "--workspace", Utf8(directory.path()), "--workspace-module", "artifact_transitive_consumer",
        "--num-cores", "3", "--no-log-color"};
    return runCompiler(arguments, ExitCode::Success, "transitive shared artifact passed");
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_LinuxPublishedSharedModulesSurviveRelocation)
{
    LinkerTestDirectory directory("published_shared_library");
    SWC_RESULT(copyWorkspaceModules(directory.path(), {"artifact_shared_provider", "artifact_shared_consumer"}));
    const fs::path setupPath = directory.path() / "modules" / "artifact_shared_consumer" / "module.swg";
    std::string setup;
    FileSystem::IoErrorInfo ioError;
    SWC_RESULT(FileSystem::readTextFile(setupPath, setup, ioError));
    const std::string_view setting = "cfg.publishDependencies = false";
    const size_t settingOffset = setup.find(setting);
    if (settingOffset == std::string::npos)
        return Result::Error;
    std::string publishedSetup = setup;
    publishedSetup.replace(settingOffset, setting.size(), "cfg.publishDependencies = true");
    SWC_RESULT(directory.write("modules/artifact_shared_consumer/module.swg", publishedSetup));
    const std::vector<Utf8> arguments = {
        "run", "--os", "linux", "--workspace", Utf8(directory.path()), "--workspace-module", "artifact_shared_consumer",
        "--num-cores", "3", "--no-log-color"};
    SWC_RESULT(runCompiler(arguments, ExitCode::Success, "shared provider dropped"));
    const fs::path artifactDirectory = directory.path() / ".output" / "artifact_shared_consumer" / "executable" / "devmode" / "x86_64";
    const fs::path publishedLibrary = artifactDirectory / "artifact_shared_provider.so";
    std::error_code error;
    if (!fs::is_regular_file(publishedLibrary, error) || error)
        return Result::Error;
    const fs::path relocated = directory.path() / "relocated";
    fs::copy(artifactDirectory, relocated, fs::copy_options::recursive, error);
    if (error)
        return Result::Error;

    // Turning publication off must retire the prior copy while the compiler's
    // launch still finds the original dependency through its child search path.
    SWC_RESULT(directory.write("modules/artifact_shared_consumer/module.swg", setup));
    SWC_RESULT(runCompiler(arguments, ExitCode::Success, "shared provider dropped"));
    if (fs::exists(publishedLibrary, error) || error)
        return Result::Error;
    fs::rename(directory.path() / ".output", directory.path() / "old-output", error);
    if (error)
        return Result::Error;

    // A deployed executable has no compiler-provided paths or original workspace.
    std::string output;
    uint32_t exitCode = 0;
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 15000};
    const std::vector<Utf8> runArguments = {"", "two words", "a\"b", "tail\\", "café"};
    const auto result = Os::runProcess(exitCode, relocated / "artifact_shared_consumer", runArguments, relocated, &options);
    if (result != Os::ProcessRunResult::Ok || exitCode != 0 || output.find("shared artifact passed") == std::string::npos || output.find("shared provider dropped") == std::string::npos)
    {
        std::println(stderr, "[published-library-test] result={}, exit={}\n{}", static_cast<uint32_t>(result), exitCode, output);
        return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()
#endif

SWC_FILESYSTEM_TEST_BEGIN(Linker_CompilerConfigurationUsesHostContextForForeignTarget)
{
    const LinkerTestDirectory testDir("cross_target_context");
    constexpr std::string_view source = R"(#run
{
    let context = Swag.getContext()
    Swag.setContext(context)
    Swag.assert(Swag.getContext() == context)
    let cfg = unwrap Swag.compiler().getBuildCfg()
    cfg.resAppName = "host-context"
}
#main {}
)";
    SWC_RESULT(testDir.write("main.swg", source));
    const Utf8 target = hostTargetOs() == Runtime::TargetOs::Windows ? "linux" : "windows";
    const std::vector<Utf8> args = {"sema", "--os", target, "--artifact-kind", "executable", "-f", Utf8(testDir.path() / "main.swg"), "--out-dir", Utf8(testDir.path() / "output"), "--work-dir", Utf8(testDir.path() / "work"), "--num-cores", "3", "--no-log-color"};
    SWC_RESULT(runCompiler(args, ExitCode::Success, ""));
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_MissingResourceDrainsParallelReaders)
{
    const LinkerTestDirectory testDir("missing_resource");
    SWC_RESULT(testDir.write("module.swg", "#run\n{\n    let cfg = unwrap Swag.compiler().getBuildCfg()\n    cfg.backendKind = .Executable\n    cfg.resAppIcoFileName = \"missing.ico\"\n}\n"));
    SWC_RESULT(testDir.write("src/main.swg", "#main {}\n"));
    const std::vector<Utf8> args = {"build", "--os", "windows", "--module", Utf8(testDir.path()), "--build-cfg", "devmode", "--num-cores", std::to_string(Unittest::compilerWorkerCount(ctx)), "--no-log-color"};
    SWC_RESULT(runCompiler(args, ExitCode::CompileError, "cannot read resource"));
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_ParallelBuildsProduceIdenticalArtifacts)
{
    // Workers reserve global storage, intern strings and discover generic instances in
    // scheduling order. None of that order may reach the artifact: the same sources must build
    // to the same bytes. Without that, two builds of one program measure two different layouts.
    constexpr std::string_view source = R"(struct(T) Cell
{
    value: T
}

impl Cell
{
    func doubled(me)->T => .value + .value
}

var gTotal:  s64
var gScale = 3's64
var gLabel = "determinism"

func(T) typeName(value: T)->string? => #typeof(T).name

func(T) accumulate(value: T)
{
    let cell: Cell'T = {value: value}
    gTotal += cast(s64, cell.doubled()) * gScale
    Swag.print(typeName(value), " ", gLabel, "\n")
}

#main
{
    accumulate(1's8)
    accumulate(2's16)
    accumulate(3's32)
    accumulate(4's64)
    accumulate(5'u8)
    accumulate(6'u16)
    accumulate(7'u32)
    accumulate(8'u64)
    Swag.print(gTotal, "\n")
}
)";

    const LinkerTestDirectory testDir("parallel_determinism");
    SWC_RESULT(testDir.write("main.swg", source));

    struct ArtifactKind
    {
        std::string_view name;
        std::string_view extension;
    };

    // A static library also covers the archive members the constants are split into.
    const bool windows = hostTargetOs() == Runtime::TargetOs::Windows;
    for (const ArtifactKind kind : {ArtifactKind{"executable", windows ? ".exe" : ""}, ArtifactKind{"static-library", windows ? ".lib" : ".a"}})
    {
        ByteArray first;
        for (uint32_t round = 0; round < 3; ++round)
        {
            const fs::path          roundDir = testDir.path() / kind.name / std::to_string(round);
            const std::vector<Utf8> args     = {"build", "--os", Utf8(K_HOST_TARGET_ARGUMENT), "-f", Utf8(testDir.path() / "main.swg"), "-n", "determinism", "--artifact-kind", Utf8(kind.name), "--out-dir", Utf8(roundDir / "output"), "--work-dir", Utf8(roundDir / "work"), "--build-cfg", "devmode", "--num-cores", std::to_string(Unittest::compilerWorkerCount(ctx)), "--no-log-color"};
            SWC_RESULT(runCompiler(args, ExitCode::Success, ""));

            ByteArray               bytes;
            FileSystem::IoErrorInfo ioError;
            SWC_RESULT(FileSystem::readBinaryFile(roundDir / "output" / std::format("determinism{}", kind.extension), bytes, ioError));

            // PE carries a build timestamp. GNU ELF images and archives are deterministic as written.
            if (kind.extension == ".exe")
                bytes.writeLe32(bytes.readLe32(0x3c) + 8, 0);

            if (!round)
                first = std::move(bytes);
            else if (bytes.size() != first.size() || std::memcmp(bytes.data(), first.data(), bytes.size()) != 0)
            {
                std::println(stderr, "[linker-test] {} build {} differs from build 0", kind.name, round);
                return Result::Error;
            }
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(ELFObject_RejectsUnrepresentableSectionsAndRelocations)
{
    LinkImage image;
    LinkSection section;
    section.name = ".data";
    section.bytes.resize(8);
    image.sections.push_back(std::move(section));
    image.symbols.push_back({.name = "value", .sectionIndex = 0, .value = 0});
    ByteArray bytes;
    Diagnostic diagnostic;
    if (!buildElfObject(bytes, diagnostic, image))
        return Result::Error;
    image.sections[0].align = 3;
    if (buildElfObject(bytes, diagnostic, image) || !bytes.empty())
        return Result::Error;
    image.sections[0].align = 8;
    image.sections[0].relocs.push_back({.offset = 1, .kind = LinkRelocKind::Abs64, .symbolName = "value"});
    if (buildElfObject(bytes, diagnostic, image) || !bytes.empty())
        return Result::Error;
    image.sections[0].relocs[0].offset = 0;
    image.sections[0].relocs[0].kind = LinkRelocKind::Rva32;
    if (buildElfObject(bytes, diagnostic, image) || !bytes.empty())
        return Result::Error;
    image.sections[0].relocs.clear();
    image.symbols.push_back(image.symbols.front());
    if (buildElfObject(bytes, diagnostic, image) || !bytes.empty())
        return Result::Error;
    image.symbols.pop_back();
    image.exports.push_back({.name = "public_value", .symbolName = "absent"});
    if (buildElfObject(bytes, diagnostic, image) || !bytes.empty())
        return Result::Error;
}
SWC_TEST_END()

#if defined(__linux__) && defined(__x86_64__)
SWC_FILESYSTEM_TEST_BEGIN(Linker_LinuxRuntimeSymbolsResolveStaticAndSharedFrames)
{
    for (const bool shared : {false, true})
    {
        const LinkerTestDirectory directory(shared ? "runtime_symbols_shared" : "runtime_symbols_static");
        SWC_RESULT(directory.write("modules/symbols/module.swg", std::format("#run {{ let cfg = unwrap Swag.compiler().getBuildCfg(); cfg.moduleNamespace = \"NativeSymbols\"; cfg.backendKind = .{} }}\n", shared ? "SharedLibrary" : "StaticLibrary")));
        SWC_RESULT(directory.write("modules/symbols/src/leaf.swg", R"(#[Swag.NoInline, Swag.Optimize(false)]
public func leaf()
{
    Swag.panic("native-symbol-probe", #curlocation)
}
)"));
        SWC_RESULT(directory.write("modules/consumer/module.swg", std::format("#import(\"symbols\"{})\n#run {{ let cfg = unwrap Swag.compiler().getBuildCfg(); cfg.moduleNamespace = \"SymbolConsumer\"; cfg.backendKind = .Executable; cfg.publishDependencies = true }}\n", shared ? ", link: \"shared-library\"" : "")));
        SWC_RESULT(directory.write("modules/consumer/src/caller.swg", R"(#[Swag.NoInline, Swag.Optimize(false)]
func caller()
{
    NativeSymbols.leaf()
}
#main { caller() }
)"));
        const std::vector<Utf8> arguments = {"build", "--workspace", Utf8(directory.path()), "--workspace-module", "consumer", "--num-cores", "3", "--rebuild", "--no-log-color"};
        SWC_RESULT(runCompiler(arguments, ExitCode::Success, ""));
        const fs::path              artifacts  = directory.path() / ".output/consumer/executable/devmode/x86_64";
        const fs::path              executable = artifacts / "consumer";
        const fs::path              library    = artifacts / "symbols.so";
        std::string                 output;
        uint32_t                    exitCode = 0;
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 15000};
        if (Os::runProcess(exitCode, executable, {}, artifacts, &options) != Os::ProcessRunResult::Ok || exitCode != 102)
            return Result::Error;
        const auto leaf   = output.find("NativeSymbols.leaf --> ");
        const auto caller = output.find("SymbolConsumer.caller --> ");
        if (leaf == std::string::npos || caller == std::string::npos || leaf >= caller || output.find("leaf.swg:3", leaf) == std::string::npos || output.find("caller.swg:4", caller) == std::string::npos)
        {
            std::println(stderr, "[ELF runtime symbols] {}", output);
            return Result::Error;
        }

        // Runtime tables are file metadata: they must not create loaded segments or
        // text relocations. Removing them leaves ordinary panic reporting usable.
        for (const fs::path& artifact : shared ? std::vector<fs::path>{executable, library} : std::vector<fs::path>{executable})
        {
            output.clear();
            const std::vector<Utf8> inspect = {"-lW", "-d", Utf8(artifact)};
            if (Os::runProcess(exitCode, "readelf", inspect, artifacts, &options) != Os::ProcessRunResult::Ok || exitCode || output.find("TEXTREL") != std::string::npos || output.find(".swagdbg") != std::string::npos)
                return Result::Error;
            output.clear();
            const std::vector<Utf8> strip = {"--remove-section=.swagdbg", Utf8(artifact)};
            if (Os::runProcess(exitCode, "objcopy", strip, artifacts, &options) != Os::ProcessRunResult::Ok || exitCode)
                return Result::Error;
        }
        output.clear();
        if (Os::runProcess(exitCode, executable, {}, artifacts, &options) != Os::ProcessRunResult::Ok || exitCode != 102 || output.find("native-symbol-probe") == std::string::npos || output.find("runtime trace") != std::string::npos)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_LinuxDwarfResolvesSourceAcrossObjectContributions)
{
    const LinkerTestDirectory directory("dwarf_source");
    // Inspect stable stack homes while the second function exercises optimized line mappings.
    SWC_RESULT(directory.write("first.swg", R"(#[Swag.NoInline, Swag.Optimize(false)]
public func first(value: s64)->s64
{
    var adjusted = value + 1
    adjusted += 2
    return adjusted
}
)"));
    SWC_RESULT(directory.write("second.swg", R"(#[Swag.NoInline]
public func second(value: s64)->s64
{
    return first(value) + 1
}
)"));
    SWC_RESULT(directory.write("main.swg", "#main { Swag.assert(second(1) == 5) }\n"));
    for (const bool shared : {false, true})
    {
        const Utf8        outputDirectory = Utf8(directory.path() / (shared ? "shared" : "executable"));
        std::vector<Utf8> args            = {"build", "--os", "linux", "--artifact-kind", shared ? "shared-library" : "executable", "--debug", "-f", Utf8(directory.path() / "first.swg"), "-f", Utf8(directory.path() / "second.swg"), "-n", "dwarf", "--out-dir", outputDirectory, "--work-dir", Utf8(directory.path() / (shared ? "work-shared" : "work-executable")), "--num-cores", std::to_string(Unittest::compilerWorkerCount(ctx)), "--rebuild", "--no-log-color"};
        if (!shared)
        {
            args.emplace_back("-f");
            args.emplace_back(directory.path() / "main.swg");
        }
        SWC_RESULT(runCompiler(args, ExitCode::Success, ""));
        const Utf8                  artifact = Utf8(fs::path(outputDirectory.c_str()) / (shared ? "dwarf.so" : "dwarf"));
        std::string                 output;
        uint32_t                    exitCode = 0;
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 15000};
        const std::vector<Utf8>     debugInfo = {"--debug-dump=info", "--debug-dump=loc", "--debug-dump=decodedline", artifact};
        if (Os::runProcess(exitCode, "readelf", debugInfo, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode || output.find("DW_TAG_formal_parameter") == std::string::npos || output.find("adjusted") == std::string::npos || output.find("DW_OP_bregx") == std::string::npos || output.find("first.swg") == std::string::npos || output.find("second.swg") == std::string::npos || output.find("Warning:") != std::string::npos)
        {
            std::println(stderr, "[DWARF records] {}", output);
            return Result::Error;
        }
        const auto firstUnit = output.find("Compilation Unit @ offset");
        if (firstUnit == std::string::npos || output.find("Compilation Unit @ offset", firstUnit + 1) == std::string::npos)
            return Result::Error;
        output.clear();
        const std::vector<Utf8> segments = {"-lW", artifact};
        if (Os::runProcess(exitCode, "readelf", segments, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode || output.find(".debug_") != std::string::npos)
            return Result::Error;
        if (!shared)
        {
            output.clear();
            if (Os::runProcess(exitCode, artifact.c_str(), {}, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode)
                return Result::Error;
            continue;
        }
        output.clear();
        const std::vector<Utf8> dynamic = {"-d", artifact};
        if (Os::runProcess(exitCode, "readelf", dynamic, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode || output.find("TEXTREL") != std::string::npos)
            return Result::Error;
        output.clear();
        const std::vector<Utf8> symbols = {"--defined-only", artifact};
        if (Os::runProcess(exitCode, "nm", symbols, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode)
            return Result::Error;
        const std::string symbolTable = output;
        for (const std::string_view name : {"first", "second"})
        {
            const auto found = symbolTable.find(std::format(" __swc_api_6477617266__{}", name));
            if (found == std::string::npos)
                return Result::Error;
            const auto              preceding = symbolTable.rfind('\n', found);
            const auto              start     = preceding == std::string::npos ? 0 : preceding + 1;
            const auto              end       = symbolTable.find(' ', start);
            const Utf8              address   = symbolTable.substr(start, end - start);
            const std::vector<Utf8> resolve   = {"-f", "-e", artifact, address};
            output.clear();
            if (Os::runProcess(exitCode, "addr2line", resolve, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode || output.find(std::format("{}.swg:", name)) == std::string::npos || output.find("??") != std::string::npos)
            {
                std::println(stderr, "[DWARF address lookup] {}", output);
                return Result::Error;
            }
        }
    }
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_LinuxSharedFunctionPointersPreserveIdentityWithoutTextRelocations)
{
    const LinkerTestDirectory directory("pic_functions");
    SWC_RESULT(directory.write("functions.swg", R"(#[Swag.Foreign(module: "libc.so.6", function: "labs", link: "c", callconv: .C)]
func foreignAbs(value: s64)->s64
#[Swag.CallingConvention(.C)]
alias AbsFunction = func(s64)->s64
public func localValue(value: u64)->u64 => value + 1
#[Swag.NoInline]
public func localPointer()->func(u64)->u64 => &localValue
#[Swag.NoInline]
public func foreignPointer()->AbsFunction => &foreignAbs
#test
{
    let local = localPointer()
    let foreign = foreignPointer()
    Swag.assert(local == localPointer() and local(41) == 42)
    Swag.assert(foreign == foreignPointer() and foreign(-17) == 17)
}
)"));
    const std::vector<Utf8> common = {"--os", "linux", "-f", Utf8(directory.path() / "functions.swg"), "-n", "pic", "--out-dir", Utf8(directory.path() / "output"), "--work-dir", Utf8(directory.path() / "work"), "--num-cores", std::to_string(Unittest::compilerWorkerCount(ctx)), "--rebuild", "--no-log-color"};
    std::vector<Utf8>       args   = {"test", "--artifact-kind", "executable", "--no-test-native"};
    args.insert(args.end(), common.begin(), common.end());
    SWC_RESULT(runCompiler(args, ExitCode::Success, "1 passed"));
    args = {"build", "--artifact-kind", "shared-library"};
    args.insert(args.end(), common.begin(), common.end());
    SWC_RESULT(runCompiler(args, ExitCode::Success, ""));
    SWC_RESULT(directory.write("consumer.cpp", R"(#include <cstdint>
#include <dlfcn.h>
using Local = uint64_t (__attribute__((ms_abi)) *)(uint64_t);
using GetLocal = Local (__attribute__((ms_abi)) *)();
using Foreign = long (*)(long);
using GetForeign = Foreign (__attribute__((ms_abi)) *)();
int main()
{
    void* library = dlopen("./output/pic.so", RTLD_NOW | RTLD_LOCAL);
    if (!library) return 1;
    auto local = reinterpret_cast<GetLocal>(dlsym(library, "__swc_api_706963__local_pointer"));
    auto foreign = reinterpret_cast<GetForeign>(dlsym(library, "__swc_api_706963__foreign_pointer"));
    if (!local || !foreign) return 2;
    const bool valid = reinterpret_cast<void*>(local()) == dlsym(library, "__swc_api_706963__local_value") &&
        local()(41) == 42 && reinterpret_cast<void*>(foreign()) == dlsym(RTLD_DEFAULT, "labs") && foreign()(-17) == 17;
    return dlclose(library) == 0 && valid ? 0 : 3;
}
)"));
    std::string                 output;
    uint32_t                    exitCode = 0;
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 15000};
    const std::vector<Utf8>     inspect = {"-d", "output/pic.so"};
    if (Os::runProcess(exitCode, "readelf", inspect, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0 || output.find("TEXTREL") != std::string::npos)
        return Result::Error;
    const std::vector<Utf8> compile = {"consumer.cpp", "-ldl", "-o", "consumer"};
    if (Os::runProcess(exitCode, "c++", compile, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
        return Result::Error;
    if (Os::runProcess(exitCode, directory.path() / "consumer", {}, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ELFObject_RelocatedConstantsBecomeReadOnlyAfterLoading)
{
    const LinkerTestDirectory directory("elf_relro");
    LinkImage                 image;
    LinkSection               pointer;
    pointer.name  = ".rdata";
    pointer.align = 64;
    pointer.flags = LinkSectionFlagsE::Read;
    pointer.bytes.appendLe64(0);
    pointer.relocs.push_back({.offset = 0, .kind = LinkRelocKind::Abs64, .symbolName = "literal"});
    image.sections.push_back(std::move(pointer));
    LinkSection literal;
    literal.name  = ".rdata";
    literal.flags = LinkSectionFlagsE::Read;
    literal.bytes.appendLe64(42);
    image.sections.push_back(std::move(literal));
    image.symbols = {{.name = "pointer", .sectionIndex = 0}, {.name = "literal", .sectionIndex = 1}};
    ByteArray  bytes;
    Diagnostic diagnostic;
    if (!buildElfObject(bytes, diagnostic, image))
        return Result::Error;
    SWC_RESULT(directory.write("generated.o", {reinterpret_cast<const char*>(bytes.data()), bytes.size()}));
    SWC_RESULT(directory.write("consumer.cpp", R"(#include <cstdint>
#include <cstdio>
#include <dlfcn.h>
bool readOnly(const void* address)
{
    auto* maps = std::fopen("/proc/self/maps", "r");
    if (!maps) return false;
    char line[1024];
    bool result = false;
    while (std::fgets(line, sizeof(line), maps))
    {
        unsigned long start = 0, end = 0;
        char permissions[5]{};
        if (std::sscanf(line, "%lx-%lx %4s", &start, &end, permissions) == 3 &&
            reinterpret_cast<uintptr_t>(address) >= start && reinterpret_cast<uintptr_t>(address) < end)
        {
            result = permissions[0] == 'r' && permissions[1] == '-' && permissions[2] == '-';
            break;
        }
    }
    std::fclose(maps);
    return result;
}
int main()
{
    void* library = dlopen("./generated.so", RTLD_NOW | RTLD_LOCAL);
    if (!library) return 1;
    auto* pointer = static_cast<const uint64_t* const*>(dlsym(library, "pointer"));
    auto* literal = static_cast<const uint64_t*>(dlsym(library, "literal"));
    const bool valid = pointer && literal && *pointer == literal && *literal == 42 &&
        reinterpret_cast<uintptr_t>(pointer) % 64 == 0 && readOnly(pointer) && readOnly(literal);
    return dlclose(library) == 0 && valid ? 0 : 2;
}
)"));
    std::string                 output;
    uint32_t                    exitCode = 0;
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 15000};
    // -z text rejects a dynamic relocation in read-only storage; RELRO must then restore
    // read-only permissions after the loader has resolved the pointer.
    const std::vector<Utf8> libraryArguments = {"-shared", "-Wl,-z,text,-z,relro,-z,now", "generated.o", "-o", "generated.so"};
    if (Os::runProcess(exitCode, "c++", libraryArguments, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
    {
        std::println(stderr, "[ELF relocated constants] {}", output);
        return Result::Error;
    }
    const std::vector<Utf8> consumerArguments = {"consumer.cpp", "-ldl", "-o", "consumer"};
    if (Os::runProcess(exitCode, "c++", consumerArguments, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
        return Result::Error;
    if (Os::runProcess(exitCode, directory.path() / "consumer", {}, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ELFObject_GnuLinkerResolvesCodeDataBssAndImports)
{
    const LinkerTestDirectory directory("elf_object");
    LinkImage image;
    LinkSection code;
    code.name = ".text";
    code.align = 16;
    code.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
    NativeTest::emit(code.bytes, {0x48, 0x83, 0xec, 8, 0xe8}); // sub rsp,8; call helper
    code.relocs.push_back({.offset = static_cast<uint32_t>(code.bytes.size()), .kind = LinkRelocKind::Rel32, .symbolName = "helper"});
    code.bytes.appendLe32(0);
    NativeTest::emit(code.bytes, {0x48, 0xb9}); // movabs rcx,values+8
    code.relocs.push_back({.offset = static_cast<uint32_t>(code.bytes.size()), .kind = LinkRelocKind::Abs64, .symbolName = "values", .addend = -8});
    code.bytes.appendLe64(16);
    NativeTest::emit(code.bytes, {0x03, 0x01, 0x8b, 0x0d}); // add eax,[rcx]; mov ecx,[rip+values+8]
    code.relocs.push_back({.offset = static_cast<uint32_t>(code.bytes.size()), .kind = LinkRelocKind::Rel32, .symbolName = "values", .addend = -4});
    code.bytes.appendLe32(12);
    NativeTest::emit(code.bytes, {0x01, 0xc8, 0x48, 0xba}); // add eax,ecx; movabs rdx,counter
    code.relocs.push_back({.offset = static_cast<uint32_t>(code.bytes.size()), .kind = LinkRelocKind::Abs64, .symbolName = "counter"});
    code.bytes.appendLe64(0);
    NativeTest::emit(code.bytes, {0x03, 0x02, 0x89, 0x02, 0x48, 0x83, 0xc4, 8, 0xc3});
    image.sections.push_back(std::move(code));
    LinkSection data;
    data.name = ".data";
    data.align = 8;
    data.flags = LinkSectionFlagsE::Read | LinkSectionFlagsE::Write;
    data.bytes.appendLe32(7);
    data.bytes.appendLe32(8);
    data.bytes.appendLe32(22);
    image.sections.push_back(std::move(data));
    LinkSection bss;
    bss.name = ".bss";
    bss.align = 64;
    bss.bssSize = 4;
    bss.flags = LinkSectionFlagsE::Read | LinkSectionFlagsE::Write | LinkSectionFlagsE::Uninit;
    image.sections.push_back(std::move(bss));
    X64DwarfFrame frame;
    frame.advance(4);
    frame.defineCfa(7, 16);
    frame.advance(47);
    frame.defineCfa(7, 8);
    ByteArray frameBytes;
    frame.build(frameBytes, 48);
    LinkSection unwind;
    unwind.name = ".eh_frame";
    unwind.align = 8;
    unwind.flags = LinkSectionFlagsE::Read;
    uint32_t addressOffset = 0;
    if (!X64DwarfFrame::appendObjectFrame(unwind.bytes, addressOffset, frameBytes, 48))
        return Result::Error;
    unwind.bytes.appendLe32(0);
    unwind.relocs.push_back({.offset = addressOffset, .kind = LinkRelocKind::Rel32, .symbolName = "calculate", .addend = 4});
    image.sections.push_back(std::move(unwind));
    image.symbols = {{.name = "calculate", .sectionIndex = 0}, {.name = "values", .sectionIndex = 1}, {.name = "counter", .sectionIndex = 2}};
    image.exports.push_back({.name = "answer", .symbolName = "calculate"});
    ByteArray bytes;
    Diagnostic diagnostic;
    if (!buildElfObject(bytes, diagnostic, image))
        return Result::Error;
    SWC_RESULT(directory.write("generated.o", {reinterpret_cast<const char*>(bytes.data()), bytes.size()}));
    SWC_RESULT(directory.write("caller.cpp", R"(#include <unwind.h>
#include <cstdint>
extern "C" int answer();
extern "C" int counter;
struct Trace { bool generated = false; unsigned callers = 0; };
_Unwind_Reason_Code trace(_Unwind_Context* context, void* raw)
{
    auto& seen = *static_cast<Trace*>(raw);
    const auto address = _Unwind_GetIP(context);
    const auto start = reinterpret_cast<uintptr_t>(&answer);
    if (seen.generated) ++seen.callers;
    if (address >= start && address < start + 48) seen.generated = true;
    return _URC_NO_REASON;
}
extern "C" int helper()
{
    Trace seen;
    _Unwind_Backtrace(trace, &seen);
    return seen.generated && seen.callers ? 20 : 99;
}
int main()
{
    return reinterpret_cast<uintptr_t>(&counter) % 64 == 0 && answer() == 64 && answer() == 128 ? 0 : 1;
}
)"));
    std::string output;
    uint32_t exitCode = 0;
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false, .timeoutMs = 15000};
    const std::vector<Utf8> arguments = {"-no-pie", "-Wl,--build-id=none", "caller.cpp", "generated.o", "-o", "consumer"};
    if (Os::runProcess(exitCode, "c++", arguments, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
    {
        std::println(stderr, "[ELF object consumer] {}", output);
        return Result::Error;
    }
    if (Os::runProcess(exitCode, directory.path() / "consumer", {}, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
        return Result::Error;
}
SWC_TEST_END()
#endif

SWC_END_NAMESPACE();

#endif
