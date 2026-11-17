#include "pch.h"
#include "Backend/Linker/Format.COFF.h"

#if SWC_HAS_UNITTEST

#include "Backend/Debug/SymbolTable.h"
#include "Backend/Encoder/Frame.DWARF.X64.h"
#include "Backend/Linker/Archive.COFF.h"
#include "Backend/Linker/ImageWriter.ELF.h"
#include "Backend/Linker/LinkJob.h"
#include "Backend/Linker/Linker.PE.h"
#include "Backend/Linker/ObjectWriter.ELF.h"
#include "Backend/Linker/Reader.COFF.h"
#include "Backend/Linker/Reader.ELF.h"
#include "Backend/Linker/SymbolTable.ELF.h"
#include "Backend/RuntimeName.h"
#include "Main/ExitCodes.h"
#include "Main/FileSystem.h"
#include "Support/Core/ByteView.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include "Unittest/Native/NativeTestBytes.h"
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

    CoffObject makeReadOnlyAllocation(const std::string_view name, const uint64_t value, const Utf8& target = {})
    {
        CoffObject       object;
        CoffInputSection section;
        section.name            = ".rdata";
        section.characteristics = PE::SCN_CNT_INITIALIZED_DATA | PE::SCN_MEM_READ | PE::SCN_ALIGN_8BYTES;
        section.bytes.appendLe64(0);
        section.bytes.appendLe64(value);
        if (!target.empty())
            section.relocs.push_back({.offset = 0, .type = PE::REL_AMD64_ADDR64, .symbolName = target});
        object.sections.push_back(std::move(section));
        object.definedSymbols.push_back({.name = Utf8(name)});
        return object;
    }

    // The production reader accepts link inputs, while these tests inspect ET_EXEC.
    std::optional<ELF::Section> elfImageSection(const ByteArray& bytes, const std::string_view wanted)
    {
        if (!bytes.containsRange(0, 64))
            return {};
        const uint64_t headers    = bytes.readLe64(40);
        const uint16_t count      = bytes.readLe16(60);
        const uint16_t namesIndex = bytes.readLe16(62);
        if (namesIndex >= count || !bytes.containsRange(headers, uint64_t{count} * 64))
            return {};
        const uint64_t namesHeader = headers + uint64_t{namesIndex} * 64;
        const uint64_t strings     = bytes.readLe64(namesHeader + 24);
        const uint64_t stringsSize = bytes.readLe64(namesHeader + 32);
        if (!bytes.containsRange(strings, stringsSize))
            return {};
        for (uint16_t index = 1; index < count; ++index)
        {
            const uint64_t header     = headers + uint64_t{index} * 64;
            const uint32_t nameOffset = bytes.readLe32(header);
            if (nameOffset >= stringsSize)
                return {};
            const auto* name = reinterpret_cast<const char*>(bytes.data() + strings + nameOffset);
            const auto* end  = static_cast<const char*>(std::memchr(name, 0, stringsSize - nameOffset));
            if (!end)
                return {};
            if (std::string_view(name, end) == wanted)
                return ELF::Section{.type = bytes.readLe32(header + 4), .link = bytes.readLe32(header + 40), .address = bytes.readLe64(header + 16), .offset = bytes.readLe64(header + 24), .size = bytes.readLe64(header + 32)};
        }
        return {};
    }

    bool readElfImageSymbols(std::map<std::string, ELF::Symbol>& symbols, const ByteArray& bytes)
    {
        symbols.clear();
        const auto table = elfImageSection(bytes, ".symtab");
        if (!table || table->size % 24 || !bytes.containsRange(table->offset, table->size))
            return false;
        const uint64_t headers = bytes.readLe64(40);
        if (table->link >= bytes.readLe16(60))
            return false;
        const uint64_t namesHeader = headers + uint64_t{table->link} * 64;
        const uint64_t names       = bytes.readLe64(namesHeader + 24);
        const uint64_t namesSize   = bytes.readLe64(namesHeader + 32);
        if (!bytes.containsRange(names, namesSize))
            return false;
        for (uint64_t entry = table->offset + 24; entry < table->offset + table->size; entry += 24)
        {
            const uint32_t offset = bytes.readLe32(entry);
            if (offset >= namesSize)
                return false;
            const auto* name = reinterpret_cast<const char*>(bytes.data() + names + offset);
            const auto* end  = static_cast<const char*>(std::memchr(name, 0, namesSize - offset));
            if (!end)
                return false;
            symbols.emplace(std::string(name, end), ELF::Symbol{.section = bytes.readLe16(entry + 6), .value = bytes.readLe64(entry + 8)});
        }
        return true;
    }

    CoffObject makeFoldableFunction(const std::string_view name, const Utf8& target = {})
    {
        CoffObject       object;
        CoffInputSection code;
        code.name            = ".text";
        code.characteristics = PE::SCN_CNT_CODE | PE::SCN_MEM_READ | PE::SCN_MEM_EXECUTE | PE::SCN_ALIGN_16BYTES;
        if (target.empty())
            NativeTest::emit(code.bytes, {0xb8, 42, 0, 0, 0, 0xc3});
        else
        {
            NativeTest::emit(code.bytes, {0xe8, 0, 0, 0, 0, 0xc3});
            code.relocs.push_back({.offset = 1, .type = PE::REL_AMD64_REL32, .symbolName = target});
        }
        object.sections.push_back(std::move(code));
        object.definedSymbols.push_back({.name = Utf8(name)});
        return object;
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

    Result copyWorkspaceModules(const fs::path& destination, const std::initializer_list<std::string_view> modules)
    {
        const fs::path sourceModules = Os::getExeFullName().parent_path() / "unittests" / "workspace" / "modules";
        for (const std::string_view module : modules)
        {
            std::error_code error;
            const fs::path  moduleDirectory = destination / "modules" / module;
            fs::create_directories(moduleDirectory, error);
            if (error)
                return Result::Error;
            fs::copy(sourceModules / module, moduleDirectory, fs::copy_options::recursive, error);
            if (error)
                return Result::Error;
        }
        return Result::Continue;
    }

    Result runCompiler(const std::vector<Utf8>& args, const ExitCode expectedExit, const std::string_view expectedOutput)
    {
        uint32_t                    exitCode = 0;
        std::string                 output;
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
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
            if (!offset || archive.memberOffsetForSymbol("__imp_" + name) != offset || !tryReadCoffImport(imported, diag, archive, offset) ||
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
    if (!tryReadCoffImport(imported, diag, assigned, firstOffset) || imported.importName != symbol || imported.dll != "archive-test.dll")
        return Result::Error;
    const std::span<const std::byte> importData = assigned.memberData(diag, firstOffset);
    ArchiveImport                    importedFromBytes;
    if (importData.empty() || !tryReadCoffImport(importedFromBytes, importData))
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
    if (!tryReadCoffImport(imported, diag, assigned, offset) || imported.dll != "old.dll" || imported.importName != "original")
        return Result::Error;
    if (assigned.memberOffsetForSymbol("replacement") || original.memberOffsetForSymbol("original"))
        return Result::Error;
    const uint32_t replacementOffset = original.memberOffsetForSymbol("replacement");
    if (!replacementOffset || !tryReadCoffImport(imported, diag, original, replacementOffset) || imported.dll != "new.dll")
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

#endif

SWC_FILESYSTEM_TEST_BEGIN(Linker_TransitiveSharedModulesExecuteDuringCompilation)
{
    LinkerTestDirectory directory("transitive_shared_library_jit");
    SWC_RESULT(copyWorkspaceModules(directory.path(), {"artifact_transitive_leaf", "artifact_transitive_middle", "artifact_transitive_consumer"}));
    // Build providers in a separate process so their earlier compilation cannot preload them.
    const std::vector<Utf8> dependencies = {
        "build", "--os", Utf8(K_HOST_TARGET_ARGUMENT), "--workspace", Utf8(directory.path()), "--workspace-module", "artifact_transitive_middle",
        "--num-cores", "3", "--no-log-color"};
    SWC_RESULT(runCompiler(dependencies, ExitCode::Success, ""));
    const std::vector<Utf8> arguments = {
        "run", "--os", Utf8(K_HOST_TARGET_ARGUMENT), "--workspace", Utf8(directory.path()), "--workspace-module", "artifact_transitive_consumer",
        "--num-cores", "3", "--no-log-color"};
    SWC_RESULT(runCompiler(arguments, ExitCode::Success, "transitive shared artifact passed"));
    return runCompiler(arguments, ExitCode::Success, "transitive shared artifact passed");
}
SWC_TEST_END()

#ifdef __linux__
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
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
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

SWC_TEST_BEGIN(PeLinker_FoldsReadOnlyDependenciesRegardlessOfDiscoveryOrder)
{
    constexpr size_t depth = 32;
    for (const bool reverse : {false, true})
    {
        std::vector<CoffObject> objects;
        for (size_t level = 0; level < depth; ++level)
        {
            for (const char branch : {'a', 'b'})
            {
                const Utf8 name   = std::format("__swc_rdata_{}{}", branch, level);
                const Utf8 target = level + 1 < depth ? Utf8(std::format("__swc_rdata_{}{}", branch, level + 1)) : Utf8{};
                objects.push_back(makeReadOnlyAllocation(name, level, target));
            }
        }
        if (reverse)
            std::ranges::reverse(objects);
        std::unordered_map<Utf8, Utf8> aliases;
        PELinker::foldReadOnlyData(objects, aliases);
        if (aliases.size() != depth || objects.size() != depth * 2 ||
            std::ranges::count_if(objects, [](const CoffObject& object) { return !object.sections.empty(); }) != depth)
            return Result::Error;
        for (size_t level = 0; level < depth; ++level)
        {
            const Utf8 a     = std::format("__swc_rdata_a{}", level);
            const Utf8 b     = std::format("__swc_rdata_b{}", level);
            const auto first = aliases.find(a), second = aliases.find(b);
            if ((first == aliases.end()) == (second == aliases.end()))
                return Result::Error;
            const Utf8& target = first == aliases.end() ? second->second : first->second;
            if (target != (first == aliases.end() ? a : b) || aliases.contains(target))
                return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(PeLinker_ReadOnlyAliasesResolveToFinalSurvivors)
{
    std::vector<CoffObject> objects = {
        makeReadOnlyAllocation("__swc_rdata_wrapper_a", 20, "__swc_rdata_parent_alias"),
        makeReadOnlyAllocation("__swc_rdata_wrapper_b", 20, "__swc_rdata_parent_b"),
        makeReadOnlyAllocation("__swc_rdata_parent_a", 10, "__swc_rdata_leaf_a"),
        makeReadOnlyAllocation("__swc_rdata_parent_alias", 10, "__swc_rdata_leaf_a"),
        makeReadOnlyAllocation("__swc_rdata_parent_b", 10, "__swc_rdata_leaf_b"),
        makeReadOnlyAllocation("__swc_rdata_leaf_b", 1),
        makeReadOnlyAllocation("__swc_rdata_leaf_a", 1),
    };
    std::unordered_map<Utf8, Utf8> aliases;
    PELinker::foldReadOnlyData(objects, aliases);
    if (aliases.size() != 4 || aliases.at("__swc_rdata_parent_a") != "__swc_rdata_parent_b" ||
        aliases.at("__swc_rdata_parent_alias") != "__swc_rdata_parent_b" || aliases.at("__swc_rdata_wrapper_a") != "__swc_rdata_wrapper_b")
        return Result::Error;
    for (const auto& [_, target] : aliases)
        if (aliases.contains(target))
            return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PeLinker_PreservesDistinctDataAndRelocationSemantics)
{
    std::vector<CoffObject> objects;
    objects.push_back(makeReadOnlyAllocation("__swc_rdata_base", 42));
    objects.push_back(makeReadOnlyAllocation("__swc_rdata_value", 43));
    objects.push_back(makeReadOnlyAllocation("__swc_rdata_aligned", 42));
    objects.back().sections[0].characteristics ^= PE::SCN_ALIGN_8BYTES | PE::SCN_ALIGN_16BYTES;
    for (const char suffix : {'a', 'b'})
    {
        objects.push_back(makeReadOnlyAllocation(std::format("__swc_rdata_write{}", suffix), 42));
        objects.back().sections[0].characteristics |= PE::SCN_MEM_WRITE;
        objects.push_back(makeReadOnlyAllocation(std::format("public{}", suffix), 42));
        objects.push_back(makeReadOnlyAllocation(std::format("__swc_rdata_extra{}", suffix), 42));
        objects.back().definedSymbols.push_back({.name = std::format("interior{}", suffix), .value = 8});
    }
    objects.push_back(makeReadOnlyAllocation("__swc_rdata_first", 42, "external_a"));
    objects.push_back(makeReadOnlyAllocation("__swc_rdata_second", 42, "external_b"));
    objects.push_back(makeReadOnlyAllocation("__swc_rdata_addend", 42, "external_a"));
    objects.back().sections[0].bytes.writeLe64(0, 8);
    objects.push_back(makeReadOnlyAllocation("__swc_rdata_kind", 42, "external_a"));
    objects.back().sections[0].relocs[0].type = PE::REL_AMD64_ADDR32NB;
    std::unordered_map<Utf8, Utf8> aliases;
    PELinker::foldReadOnlyData(objects, aliases);
    if (!aliases.empty() || std::ranges::any_of(objects, [](const CoffObject& object) { return object.sections.empty(); }))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PeLinker_FoldsReadOnlyZeroFillAndItsReaders)
{
    std::vector<CoffObject> objects;
    for (const auto name : {"__swc_rdata_zero_a", "__swc_rdata_zero_b", "__swc_rdata_mutable_a", "__swc_rdata_mutable_b", "__swc_rdata_smaller", "__swc_rdata_aligned"})
    {
        CoffObject       object;
        CoffInputSection section;
        section.name            = ".rbss";
        section.isBss           = true;
        section.bssSize         = 64;
        section.characteristics = PE::SCN_CNT_UNINITIALIZED_DATA | PE::SCN_MEM_READ | PE::SCN_ALIGN_8BYTES;
        object.sections.push_back(std::move(section));
        object.definedSymbols.push_back({.name = name});
        objects.push_back(std::move(object));
    }
    objects[2].sections[0].characteristics |= PE::SCN_MEM_WRITE;
    objects[3].sections[0].characteristics |= PE::SCN_MEM_WRITE;
    objects[4].sections[0].bssSize = 32;
    objects[5].sections[0].characteristics ^= PE::SCN_ALIGN_8BYTES | PE::SCN_ALIGN_16BYTES;
    objects.insert(objects.begin(), makeReadOnlyAllocation("__swc_rdata_parent_b", 1, "__swc_rdata_zero_b"));
    objects.insert(objects.begin(), makeReadOnlyAllocation("__swc_rdata_parent_a", 1, "__swc_rdata_zero_a"));
    std::unordered_map<Utf8, Utf8> aliases;
    PELinker::foldReadOnlyData(objects, aliases);
    if (aliases.size() != 2 || aliases.at("__swc_rdata_zero_b") != "__swc_rdata_zero_a")
        return Result::Error;
    for (size_t i = 4; i < objects.size(); ++i)
        if (objects[i].sections.empty())
            return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PeLinker_FoldsSelfReferencesWithoutConflatingDistinctCycles)
{
    std::vector<CoffObject> objects = {
        makeReadOnlyAllocation("__swc_rdata_self_a", 1, "__swc_rdata_self_a"),
        makeReadOnlyAllocation("__swc_rdata_self_b", 1, "__swc_rdata_self_b"),
        makeReadOnlyAllocation("__swc_rdata_self_c", 1, "__swc_rdata_self_c"),
        makeReadOnlyAllocation("__swc_rdata_cycle_a", 2, "__swc_rdata_cycle_b"),
        makeReadOnlyAllocation("__swc_rdata_cycle_b", 2, "__swc_rdata_cycle_a"),
    };
    std::unordered_map<Utf8, Utf8> aliases;
    PELinker::foldReadOnlyData(objects, aliases);
    if (aliases.size() != 2 || objects[3].sections.empty() || objects[4].sections.empty())
        return Result::Error;
    for (const auto& [_, target] : aliases)
        if (aliases.contains(target))
            return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PeLinker_FunctionGraphsKeepObservedAddressesDistinct)
{
    std::vector<CoffObject> objects = {
        makeFoldableFunction("__swc_fn_caller_a", "__swc_fn_observed_a"),
        makeFoldableFunction("__swc_fn_caller_b", "__swc_fn_observed_b"),
        makeFoldableFunction("__swc_fn_unobserved"),
        makeFoldableFunction("__swc_fn_observed_a"),
        makeFoldableFunction("__swc_fn_observed_b"),
    };
    LinkImage   image;
    LinkSection data;
    data.name = ".rdata";
    data.bytes.resize(16);
    data.relocs = {{.offset = 0, .kind = LinkRelocKind::Abs64, .symbolName = "__swc_fn_observed_a"}, {.offset = 8, .kind = LinkRelocKind::Abs64, .symbolName = "__swc_fn_observed_b"}};
    image.sections.push_back(std::move(data));
    std::unordered_map<Utf8, Utf8> aliases;
    PELinker::foldIdenticalFunctionsForTest(objects, aliases, image);
    if (objects.size() != 4 || aliases.size() != 1 || !aliases.contains("__swc_fn_unobserved") || aliases.contains("__swc_fn_observed_a") || aliases.contains("__swc_fn_observed_b"))
        return Result::Error;
    if (aliases.at("__swc_fn_unobserved") != "__swc_fn_observed_a" && aliases.at("__swc_fn_unobserved") != "__swc_fn_observed_b")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PeLinker_FunctionSelfKeysCannotCollideWithForeignSymbols)
{
    std::vector<CoffObject> objects = {
        makeFoldableFunction("__swc_fn_recursive", "__swc_fn_recursive"),
        makeFoldableFunction("__swc_fn_foreign", "$self"),
    };
    std::unordered_map<Utf8, Utf8> aliases;
    PELinker::foldIdenticalFunctionsForTest(objects, aliases, {});
    if (objects.size() != 2 || !aliases.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PeLinker_FunctionGraphsKeepOtherStorageAndPublicDefinitions)
{
    std::vector<CoffObject> objects = {
        makeFoldableFunction("__swc_fn_mutable"),
        makeFoldableFunction("__swc_fn_multiple_definitions"),
        makeFoldableFunction("external_function"),
        makeFoldableFunction("__swc_fn_plain"),
    };
    CoffInputSection data;
    data.name            = ".data";
    data.characteristics = PE::SCN_CNT_INITIALIZED_DATA | PE::SCN_MEM_READ | PE::SCN_MEM_WRITE;
    data.bytes.appendLe64(1);
    objects[0].sections.push_back(std::move(data));
    objects[0].definedSymbols.push_back({.name = "mutable", .sectionIndex = 1});
    objects[1].definedSymbols.push_back({.name = "inner_entry", .value = 1});
    std::unordered_map<Utf8, Utf8> aliases;
    PELinker::foldIdenticalFunctionsForTest(objects, aliases, {});
    if (objects.size() != 4 || !aliases.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ELFImage_WritesProtectedSegmentsAndRejectsUnresolvedInputs)
{
    LinkImage image;
    LinkSection code;
    code.name = ".text";
    code.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
    NativeTest::emit(code.bytes, {0xb8, 42, 0, 0, 0, 0xc3});
    image.sections.push_back(std::move(code));
    image.symbols.push_back({.name = "answer"});
    LinkJob job;
    job.output = LinkJob::Output::SharedLibrary;
    job.outputPath = "internal.so";
    job.archiveMembers.resize(1);
    Diagnostic diagnostic;
    if (!buildElfObject(job.archiveMembers[0].bytes, diagnostic, image))
        return Result::Error;
    ByteArray bytes;
    Utf8 error;
    if (!buildElfImage(bytes, error, job))
        return Result::Error;
    ELF::File file;
    if (!file.read(error, bytes.span()) || !file.shared || file.soname != "internal.so")
        return Result::Error;
    bool stack = false, relro = false;
    for (uint32_t index = 0; index < bytes.readLe16(56); ++index)
    {
        const uint64_t header = bytes.readLe64(32) + uint64_t{index} * 56;
        const uint32_t type = bytes.readLe32(header), flags = bytes.readLe32(header + 4);
        if (type == 1 && (flags & 3) == 3)
            return Result::Error;
        if (type == 0x6474e551)
            stack = flags == 6;
        if (type == 0x6474e552)
            relro = bytes.readLe64(header + 40) != 0;
    }
    if (!stack || !relro)
        return Result::Error;
    const ByteArray original = job.archiveMembers[0].bytes;
    ELF::File object;
    if (!object.read(error, original.span()))
        return Result::Error;
    for (const ELF::Section& section : object.sections)
        if (section.type == ELF::SHT_SYMTAB)
            job.archiveMembers[0].bytes[section.offset + 24 + 4] = std::byte{0x1a};
    if (buildElfImage(bytes, error, job) || !error.view().contains("IFUNC"))
        return Result::Error;
    job.archiveMembers[0].bytes = original;
    image.sections[0].bytes.resize(8);
    image.sections[0].relocs.push_back({.offset = 0, .kind = LinkRelocKind::Abs64, .symbolName = "missing_import"});
    if (!buildElfObject(job.archiveMembers[0].bytes, diagnostic, image) || buildElfImage(bytes, error, job) || !error.view().contains("missing_import"))
        return Result::Error;
    job.archiveMembers[0].bytes.writeLe64(40, UINT64_MAX);
    if (buildElfImage(bytes, error, job) || !bytes.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ELFImage_StripsStaticSymbolsWithoutChangingLoadedBytes)
{
    LinkImage   image;
    LinkSection code;
    code.name  = ".text";
    code.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
    NativeTest::emit(code.bytes, {0xb8, 42, 0, 0, 0, 0xc3});
    image.sections.push_back(std::move(code));
    image.symbols.push_back({.name = "answer"});
    const SymbolTable::Entry entry{.symbolName = "answer", .name = "Answer", .file = "answer.swg", .line = 3, .size = 6};
    ELFSymbolTable::appendObject(image, std::span(&entry, 1));

    LinkJob job;
    job.output     = LinkJob::Output::SharedLibrary;
    job.outputPath = "symbols.so";
    job.archiveMembers.resize(1);
    Diagnostic diagnostic;
    if (!buildElfObject(job.archiveMembers[0].bytes, diagnostic, image))
        return Result::Error;

    ByteArray original, stripped;
    Utf8      error;
    if (!buildElfImage(original, error, job) || !ELFSymbolTable::finalizeImage(original, error))
        return Result::Error;
    job.elfStripSymbols = true;
    if (!buildElfImage(stripped, error, job) || !ELFSymbolTable::finalizeImage(stripped, error) || stripped.size() >= original.size())
        return Result::Error;

    ELF::File before, after;
    if (!before.read(error, original.span()) || !after.read(error, stripped.span()))
        return Result::Error;
    if (std::ranges::none_of(before.sections, [](const ELF::Section& section) { return section.type == ELF::SHT_SYMTAB; }) ||
        std::ranges::any_of(after.sections, [](const ELF::Section& section) { return section.type == ELF::SHT_SYMTAB || section.name == ".strtab"; }))
        return Result::Error;

    // Dynamic exports, unwind data and runtime frame names survive independently of .symtab.
    for (const ELF::Section& section : before.sections)
    {
        if (!(section.flags & ELF::SHF_ALLOC) && section.name != SymbolTable::IMAGE_SECTION)
            continue;
        const auto retained = std::ranges::find(after.sections, section.name, &ELF::Section::name);
        if (retained == after.sections.end() || retained->address != section.address || retained->size != section.size || retained->flags != section.flags)
            return Result::Error;
        if (section.type != ELF::SHT_NOBITS && !std::ranges::equal(original.span().subspan(section.offset, section.size), stripped.span().subspan(retained->offset, retained->size)))
            return Result::Error;
    }
    const uint64_t programs    = original.readLe64(32);
    const uint64_t programSize = uint64_t{original.readLe16(54)} * original.readLe16(56);
    if (stripped.readLe64(32) != programs || !std::ranges::equal(original.span().subspan(programs, programSize), stripped.span().subspan(programs, programSize)))
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ELFImage_FoldsPrivateImmutableGraphsAfterTheirTargets)
{
    LinkJob job;
    job.outputPath   = "folded";
    job.elfLibraries = {"c"};
    Diagnostic diagnostic;
    const auto appendObject = [&](const LinkImage& image) {
        LinkArchiveMember member;
        if (!buildElfObject(member.bytes, diagnostic, image))
            return false;
        job.archiveMembers.push_back(std::move(member));
        return true;
    };
    LinkImage   main;
    LinkSection code;
    code.name  = ".text";
    code.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
    NativeTest::emit(code.bytes, {0x31, 0xc0, 0xc3});
    main.sections.push_back(std::move(code));
    main.symbols.push_back({.name = "main"});
    if (!appendObject(main))
        return Result::Error;
    for (const size_t index : {size_t{0}, size_t{1}, size_t{2}, size_t{3}, size_t{4}, size_t{5}, size_t{6}, size_t{7}, size_t{8}})
    {
        LinkImage   image;
        LinkSection data;
        data.name  = index < 4 ? ".rdata" : ".rbss";
        data.flags = LinkSectionFlagsE::Read;
        data.align = index == 7 ? 16 : 8;
        if (index < 4)
        {
            data.bytes.appendLe64(index < 2 ? 0 : 42);
            if (index < 2)
                data.relocs.push_back({.offset = 0, .kind = LinkRelocKind::Abs64, .symbolName = index ? "__swc_rdata_leaf_b" : "__swc_rdata_leaf_a"});
        }
        else
        {
            data.flags.add(LinkSectionFlagsE::Uninit);
            data.bssSize = index == 6 ? 32 : 64;
        }
        if (index == 5)
            data.flags.add(LinkSectionFlagsE::Write);
        image.sections.push_back(std::move(data));
        const Utf8 name = index < 2 ? (index ? "__swc_rdata_reader_b" : "__swc_rdata_reader_a") : index < 4 ? (index == 3 ? "__swc_rdata_leaf_b" : "__swc_rdata_leaf_a")
                                                                                                            : Utf8{std::format("__swc_rdata_zero_{}", index)};
        image.symbols.push_back({.name = name});
        if (!appendObject(image))
            return Result::Error;
    }
    // Zero-filled and initialized definitions of different sizes/alignment, and
    // writable definitions, must not acquire another allocation's storage.
    ByteArray bytes;
    Utf8      error;
    if (!buildElfImage(bytes, error, job))
    {
        std::println(stderr, "[ELF constant fold] {}", error);
        return Result::Error;
    }
    const LinkerTestDirectory directory("internal_elf_fold");
    SWC_RESULT(directory.write("folded", {reinterpret_cast<const char*>(bytes.data()), bytes.size()}));
    const uint64_t                     headers = bytes.readLe64(40);
    std::map<std::string, ELF::Symbol> symbols;
    if (!readElfImageSymbols(symbols, bytes))
        return Result::Error;
    const auto symbol = [&](const std::string_view name) -> const ELF::Symbol* {
        const auto found = symbols.find(std::string(name));
        return found == symbols.end() ? nullptr : &found->second;
    };
    const auto* readerA = symbol("__swc_rdata_reader_a");
    const auto* readerB = symbol("__swc_rdata_reader_b");
    const auto* leafA   = symbol("__swc_rdata_leaf_a");
    const auto* leafB   = symbol("__swc_rdata_leaf_b");
    if (!readerA || !readerB || !leafA || !leafB || readerA->value != readerB->value || leafA->value != leafB->value || readerA->value == leafA->value)
    {
        for (const auto& [name, value] : symbols)
            std::println(stderr, "[ELF constant fold] {} = {} (section {})", name, value.value, value.section);
        return Result::Error;
    }
    const uint64_t data = headers + uint64_t{readerA->section} * 64;
    if (bytes.readLe64(bytes.readLe64(data + 24) + readerA->value - bytes.readLe64(data + 16)) != leafA->value)
        return Result::Error;
    for (size_t left = 4; left < 8; ++left)
        for (size_t right = left + 1; right < 8; ++right)
        {
            const auto* a = symbol(std::format("__swc_rdata_zero_{}", left));
            const auto* b = symbol(std::format("__swc_rdata_zero_{}", right));
            if (!a || !b || a->value == b->value)
                return Result::Error;
        }
    const auto* zeroA = symbol("__swc_rdata_zero_4");
    const auto* zeroB = symbol("__swc_rdata_zero_8");
    if (!zeroA || !zeroB || zeroA->value != zeroB->value)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ELFImage_FoldsSelfReferentialConstantsWithoutConflatingForeignNamesOrCycles)
{
    LinkJob job;
    job.outputPath   = "folded_self";
    job.elfLibraries = {"c"};
    Diagnostic diagnostic;
    const auto appendObject = [&](const LinkImage& image) {
        LinkArchiveMember member;
        if (!buildElfObject(member.bytes, diagnostic, image))
            return false;
        job.archiveMembers.push_back(std::move(member));
        return true;
    };
    LinkImage   main;
    LinkSection code;
    code.name  = ".text";
    code.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
    NativeTest::emit(code.bytes, {0x31, 0xc0, 0xc3});
    main.sections.push_back(std::move(code));
    main.symbols.push_back({.name = "main"});
    if (!appendObject(main))
        return Result::Error;
    const std::array<std::pair<const char*, const char*>, 8> definitions = {{
        {"__swc_rdata_self_a", "__swc_rdata_self_a"},
        {"__swc_rdata_self_b", "__swc_rdata_self_b"},
        {"__swc_rdata_foreign", "$self"},
        {"$self", "$self"},
        {"__swc_rdata_cycle_a", "__swc_rdata_cycle_b"},
        {"__swc_rdata_cycle_b", "__swc_rdata_cycle_a"},
        {"__swc_rdata_cycle_c", "__swc_rdata_cycle_d"},
        {"__swc_rdata_cycle_d", "__swc_rdata_cycle_c"},
    }};
    for (const auto& [name, target] : definitions)
    {
        LinkImage   image;
        LinkSection data;
        data.name  = ".rdata";
        data.flags = LinkSectionFlagsE::Read;
        data.align = 8;
        data.bytes.appendLe64(0);
        data.relocs.push_back({.offset = 0, .kind = LinkRelocKind::Abs64, .symbolName = target});
        image.sections.push_back(std::move(data));
        image.symbols.push_back({.name = name});
        if (!appendObject(image))
            return Result::Error;
    }
    ByteArray bytes;
    Utf8      error;
    if (!buildElfImage(bytes, error, job))
        return Result::Error;
    std::map<std::string, ELF::Symbol> symbols;
    if (!readElfImageSymbols(symbols, bytes))
        return Result::Error;
    const auto address = [&](const char* name) {
        return symbols.at(name).value;
    };
    if (address("__swc_rdata_self_a") != address("__swc_rdata_self_b") ||
        address("__swc_rdata_self_a") == address("__swc_rdata_foreign"))
        return Result::Error;
    for (size_t left = 4; left < definitions.size(); ++left)
        for (size_t right = left + 1; right < definitions.size(); ++right)
            if (address(definitions[left].first) == address(definitions[right].first))
                return Result::Error;
    const uint64_t headers = bytes.readLe64(40);
    for (const auto& [name, target] : definitions)
    {
        const auto&    symbol  = symbols.at(name);
        const uint64_t section = headers + uint64_t{symbol.section} * 64;
        const uint64_t offset  = bytes.readLe64(section + 24) + symbol.value - bytes.readLe64(section + 16);
        if (bytes.readLe64(offset) != address(target))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ELFImage_FoldsCallGraphsWithTheirUnwindAndRuntimeNames)
{
    constexpr size_t depth = 16;
    LinkJob          job;
    job.outputPath   = "folded-functions";
    job.elfLibraries = {"c"};
    Diagnostic diagnostic;
    const auto append = [&](const LinkImage& image) {
        LinkArchiveMember object;
        if (!buildElfObject(object.bytes, diagnostic, image))
            return false;
        job.archiveMembers.push_back(std::move(object));
        return true;
    };
    LinkImage   main;
    LinkSection entry;
    entry.name  = ".text";
    entry.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
    NativeTest::emit(entry.bytes, {0x31, 0xc0, 0xc3});
    main.sections.push_back(std::move(entry));
    main.symbols.push_back({.name = "main"});
    if (!append(main))
        return Result::Error;
    for (size_t level = 0; level < depth; ++level)
        for (const char branch : {'a', 'b'})
        {
            LinkImage   image;
            LinkSection code;
            code.name  = ".text";
            code.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
            if (level + 1 < depth)
            {
                NativeTest::emit(code.bytes, {0xe8, 0, 0, 0, 0, 0xc3});
                code.relocs.push_back({.offset = 1, .kind = LinkRelocKind::Rel32, .symbolName = std::format("__swc_fn_{}{}", branch, level + 1)});
            }
            else
                NativeTest::emit(code.bytes, {0xb8, 42, 0, 0, 0, 0xc3});
            const Utf8 name{std::format("__swc_fn_{}{}", branch, level)};
            image.sections.push_back(std::move(code));
            image.symbols.push_back({.name = name});
            X64DwarfFrame frame;
            ByteArray     frameBytes;
            frame.build(frameBytes, 6);
            LinkSection unwind;
            unwind.name            = ".eh_frame";
            unwind.flags           = LinkSectionFlagsE::Read;
            unwind.align           = 8;
            uint32_t addressOffset = 0;
            if (!X64DwarfFrame::appendObjectFrame(unwind.bytes, addressOffset, frameBytes, 6))
                return Result::Error;
            unwind.bytes.appendLe32(0);
            unwind.relocs.push_back({.offset = addressOffset, .kind = LinkRelocKind::Rel32, .symbolName = name, .addend = 4});
            image.sections.push_back(std::move(unwind));
            const SymbolTable::Entry source{.symbolName = name, .name = name, .file = "folded.swg", .line = 1, .size = 6};
            ELFSymbolTable::appendObject(image, std::span(&source, 1));
            if (!append(image))
                return Result::Error;
        }
    ByteArray bytes;
    Utf8      error;
    if (!buildElfImage(bytes, error, job) || !ELFSymbolTable::finalizeImage(bytes, error))
    {
        std::println(stderr, "[ELF function fold] {}", error);
        return Result::Error;
    }
    std::map<std::string, ELF::Symbol> symbols;
    if (!readElfImageSymbols(symbols, bytes))
        return Result::Error;
    for (size_t level = 0; level < depth; ++level)
    {
        const auto a = symbols.find(std::format("__swc_fn_a{}", level));
        const auto b = symbols.find(std::format("__swc_fn_b{}", level));
        if (a == symbols.end() || b == symbols.end() || a->second.value != b->second.value)
            return Result::Error;
        if (level + 1 == depth)
            continue;
        const auto child = symbols.find(std::format("__swc_fn_a{}", level + 1));
        const auto text  = elfImageSection(bytes, ".text");
        if (child == symbols.end() || !text || a->second.value + 5 + static_cast<int32_t>(bytes.readLe32(text->offset + a->second.value - text->address + 1)) != child->second.value)
            return Result::Error;
    }
    const auto names  = elfImageSection(bytes, SymbolTable::IMAGE_SECTION);
    const auto unwind = elfImageSection(bytes, ".eh_frame_hdr");
    if (!names || !unwind || bytes.readLe32(names->offset + 8) != depth || bytes.readLe32(unwind->offset + 8) != depth)
        return Result::Error;
    const auto rules = elfImageSection(bytes, ".eh_frame");
    if (!rules)
        return Result::Error;
    uint32_t cieCount = 0, frameCount = 0;
    for (uint64_t offset = 0; offset + 4 <= rules->size;)
    {
        const uint32_t length = bytes.readLe32(rules->offset + offset);
        if (!length)
            break;
        const uint32_t cie = bytes.readLe32(rules->offset + offset + 4);
        if (!cie)
            ++cieCount;
        else
        {
            if (offset + 4 != cie)
                return Result::Error;
            ++frameCount;
        }
        offset += length + 4;
    }
    if (cieCount != 1 || frameCount != depth)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ELFImage_FunctionFoldingPreservesAddressesStorageAndUnwindRules)
{
    LinkJob job;
    job.outputPath   = "observed-functions";
    job.elfLibraries = {"c"};
    Diagnostic diagnostic;
    const auto append = [&](const LinkImage& image) {
        LinkArchiveMember object;
        if (!buildElfObject(object.bytes, diagnostic, image))
            return false;
        job.archiveMembers.push_back(std::move(object));
        return true;
    };
    for (const auto name : {"main", "__swc_fn_observed_a", "__swc_fn_observed_b", "__swc_fn_unobserved", "__swc_fn_mutable", "__swc_fn_public", "__swc_fn_rules_a", "__swc_fn_rules_b", "__swc_fn_recursive", "__swc_fn_foreign", "$self"})
    {
        LinkImage   image;
        LinkSection code;
        code.name  = ".text";
        code.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
        const std::string_view function(name);
        if (function == "__swc_fn_recursive" || function == "__swc_fn_foreign")
        {
            NativeTest::emit(code.bytes, {0xe8, 0, 0, 0, 0, 0xc3});
            code.relocs.push_back({.offset = 1, .kind = LinkRelocKind::Rel32, .symbolName = function == "__swc_fn_recursive" ? name : "$self"});
        }
        else
            NativeTest::emit(code.bytes, {0xb8, function.starts_with("__swc_fn_rules") ? 99 : 42, 0, 0, 0, 0xc3});
        image.sections.push_back(std::move(code));
        image.symbols.push_back({.name = name});
        if (function == "main" || function == "__swc_fn_mutable")
        {
            LinkSection data;
            data.name  = ".data";
            data.flags = LinkSectionFlagsE::Read | LinkSectionFlagsE::Write;
            data.bytes.resize(16);
            if (function == "main")
                data.relocs = {{.offset = 0, .kind = LinkRelocKind::Abs64, .symbolName = "__swc_fn_observed_a"}, {.offset = 8, .kind = LinkRelocKind::Abs64, .symbolName = "__swc_fn_observed_b"}};
            image.sections.push_back(std::move(data));
        }
        if (function == "__swc_fn_public")
            image.symbols.push_back({.name = "public_entry"});
        if (function.starts_with("__swc_fn_rules"))
        {
            X64DwarfFrame frame;
            if (function == "__swc_fn_rules_b")
            {
                frame.rememberState();
                frame.restoreState();
            }
            ByteArray frameBytes;
            frame.build(frameBytes, 6);
            LinkSection unwind;
            unwind.name            = ".eh_frame";
            unwind.flags           = LinkSectionFlagsE::Read;
            unwind.align           = 8;
            uint32_t addressOffset = 0;
            if (!X64DwarfFrame::appendObjectFrame(unwind.bytes, addressOffset, frameBytes, 6))
                return Result::Error;
            unwind.bytes.appendLe32(0);
            unwind.relocs.push_back({.offset = addressOffset, .kind = LinkRelocKind::Rel32, .symbolName = name, .addend = 4});
            image.sections.push_back(std::move(unwind));
        }
        if (!append(image))
            return Result::Error;
    }
    ByteArray bytes;
    Utf8      error;
    if (!buildElfImage(bytes, error, job))
        return Result::Error;
    std::map<std::string, ELF::Symbol> symbols;
    if (!readElfImageSymbols(symbols, bytes))
        return Result::Error;
    const auto address = [&](const char* name) {
        return symbols.at(name).value;
    };
    const uint64_t first = address("__swc_fn_observed_a"), second = address("__swc_fn_observed_b");
    if (first == second || (address("__swc_fn_unobserved") != first && address("__swc_fn_unobserved") != second))
        return Result::Error;
    for (const auto name : {"__swc_fn_mutable", "__swc_fn_public"})
        if (address(name) == first || address(name) == second)
            return Result::Error;
    if (address("__swc_fn_rules_a") == address("__swc_fn_rules_b") || address("__swc_fn_recursive") == address("__swc_fn_foreign"))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ELFImage_ResolvesWeakCommonAndStrongDefinitions)
{
    LinkImage image;
    LinkSection data;
    data.name = ".data";
    data.flags = LinkSectionFlagsE::Read | LinkSectionFlagsE::Write;
    data.bytes.appendLe64(17);
    image.sections.push_back(std::move(data));
    image.symbols.push_back({.name = "value"});
    ByteArray original;
    Diagnostic diagnostic;
    if (!buildElfObject(original, diagnostic, image))
        return Result::Error;
    ELF::File object;
    Utf8 error;
    if (!object.read(error, original.span()))
        return Result::Error;
    uint64_t symbolOffset = 0, dataOffset = 0;
    for (const ELF::Section& section : object.sections)
    {
        if (section.type == ELF::SHT_SYMTAB)
            symbolOffset = section.offset + 24;
        if (section.name == ".data")
            dataOffset = section.offset;
    }
    std::vector<LinkArchiveMember> members(5);
    for (LinkArchiveMember& member : members)
    {
        member.bytes = original;
        member.bytes.writeLe64(symbolOffset + 16, 8);
    }
    for (const size_t index : {size_t{0}, size_t{4}})
    {
        members[index].bytes.writeLe16(symbolOffset + 6, ELF::SHN_COMMON);
        members[index].bytes.writeLe64(symbolOffset + 8, index ? 64 : 32);
        members[index].bytes.writeLe64(symbolOffset + 16, index ? 16 : 8);
    }
    members[1].bytes[symbolOffset + 4] = std::byte{0x21};
    members[2].bytes[symbolOffset + 4] = std::byte{0x21};
    members[2].bytes.writeLe64(dataOffset, 99);
    members[3].bytes.writeLe64(dataOffset, 42);
    for (size_t scenario = 0; scenario < 3; ++scenario)
    {
        LinkJob job;
        job.output = LinkJob::Output::SharedLibrary;
        job.outputPath = "symbols.so";
        job.archiveMembers = scenario == 0 ? std::vector<LinkArchiveMember>{members[0], members[1], members[4]} : scenario == 1 ? std::vector<LinkArchiveMember>{members[1], members[2]} : members;
        ByteArray bytes;
        if (!buildElfImage(bytes, error, job))
            return Result::Error;
        ELF::File linked;
        if (!linked.read(error, bytes.span()))
            return Result::Error;
        const auto value = std::ranges::find(linked.symbols, std::string("value"), &ELF::Symbol::name);
        if (value == linked.symbols.end() || !value->section || value->section >= linked.sections.size())
            return Result::Error;
        const ELF::Section& section = linked.sections[value->section];
        if (!scenario)
        {
            if (section.type != ELF::SHT_NOBITS || value->size != 16 || value->value % 64)
                return Result::Error;
        }
        else if (value->binding() != (scenario == 1 ? 2 : 1) || value->size != 8 || section.type != ELF::SHT_PROGBITS ||
                 bytes.readLe64(section.offset + value->value - section.address) != (scenario == 1 ? 17 : 42))
            return Result::Error;
    }
}
SWC_TEST_END()

#if defined(__linux__) && defined(__x86_64__)
SWC_FILESYSTEM_TEST_BEGIN(ELFImage_ExecutesProcessEntryAndEagerLibcImports)
{
    const LinkerTestDirectory directory("internal_elf_entry");
    LinkImage image;
    LinkSection code;
    code.name = ".text";
    code.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
    NativeTest::emit(code.bytes, {0x48, 0x83, 0xec, 8, 0x48, 0x8d, 0x3d, 0, 0, 0, 0, 0xe8, 0, 0, 0, 0, 0x31, 0xc0, 0x48, 0x83, 0xc4, 8, 0xc3});
    code.relocs = {{.offset = 7, .kind = LinkRelocKind::Rel32, .symbolName = "message"}, {.offset = 12, .kind = LinkRelocKind::Rel32, .symbolName = "puts"}};
    image.sections.push_back(std::move(code));
    LinkSection message;
    message.name = ".rdata";
    message.flags = LinkSectionFlagsE::Read;
    message.bytes.append("internal ELF link");
    message.bytes.pushBack(std::byte{0});
    image.sections.push_back(std::move(message));
    image.symbols = {{.name = "main"}, {.name = "message", .sectionIndex = 1}};
    LinkJob job;
    job.outputPath = directory.path() / "program";
    job.elfLibraries = {"c"};
    job.archiveMembers.resize(1);
    Diagnostic diagnostic;
    if (!buildElfObject(job.archiveMembers[0].bytes, diagnostic, image))
        return Result::Error;
    ByteArray bytes;
    Utf8 error;
    if (!buildElfImage(bytes, error, job))
    {
        std::println(stderr, "[internal ELF] {}", error);
        return Result::Error;
    }
    SWC_RESULT(directory.write("program", {reinterpret_cast<const char*>(bytes.data()), bytes.size()}));
    std::error_code permissions;
    fs::permissions(job.outputPath, fs::perms::owner_exec, fs::perm_options::add, permissions);
    if (permissions)
        return Result::Error;
    uint32_t exitCode = 0;
    std::string output;
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
    if (Os::runProcess(exitCode, job.outputPath, {}, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode || output != "internal ELF link\n")
    {
        std::println(stderr, "[internal ELF] exit={}, output={}", exitCode, output);
        return Result::Error;
    }
}
SWC_TEST_END()
SWC_FILESYSTEM_TEST_BEGIN(ELFImage_CopyRelocationsShareStorageWithGotReferences)
{
    const LinkerTestDirectory directory("internal_elf_copy");
    LinkImage image;
    LinkSection code;
    code.name = ".text";
    code.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
    // Update libc's optind through a direct reference, then observe the same storage
    // through the GOT. A copy relocation must not leave one access in the original DSO.
    NativeTest::emit(code.bytes, {0x8b, 0x05, 0, 0, 0, 0, 0x83, 0xc0, 1, 0x89, 0x05, 0, 0, 0, 0, 0x48, 0x8b, 0x0d, 0, 0, 0, 0, 0x2b, 0x01, 0xc3});
    code.relocs = {{.offset = 2, .kind = LinkRelocKind::Rel32, .symbolName = "optind"}, {.offset = 11, .kind = LinkRelocKind::Rel32, .symbolName = "optind"}, {.offset = 18, .kind = LinkRelocKind::GotRel32, .symbolName = "optind"}};
    image.sections.push_back(std::move(code));
    image.symbols.push_back({.name = "main"});
    image.imports.push_back({.symbolName = "optind", .isData = true});
    LinkJob job;
    job.outputPath = directory.path() / "program";
    job.elfLibraries = {"c"};
    job.archiveMembers.resize(1);
    Diagnostic diagnostic;
    if (!buildElfObject(job.archiveMembers[0].bytes, diagnostic, image))
        return Result::Error;
    ByteArray bytes;
    Utf8 error;
    if (!buildElfImage(bytes, error, job))
    {
        std::println(stderr, "[ELF copy relocation] {}", error);
        return Result::Error;
    }
    SWC_RESULT(directory.write("program", {reinterpret_cast<const char*>(bytes.data()), bytes.size()}));
    std::error_code permissions;
    fs::permissions(job.outputPath, fs::perms::owner_exec, fs::perm_options::add, permissions);
    if (permissions)
        return Result::Error;
    uint32_t exitCode = 0;
    std::string output;
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
    if (Os::runProcess(exitCode, job.outputPath, {}, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode)
        return Result::Error;
    for (LinkReloc& relocation : image.sections[0].relocs)
        relocation.symbolName = "errno";
    image.imports[0].symbolName = "errno";
    if (!buildElfObject(job.archiveMembers[0].bytes, diagnostic, image) || buildElfImage(bytes, error, job) || !error.view().contains("TLS"))
        return Result::Error;
}
SWC_TEST_END()
SWC_FILESYSTEM_TEST_BEGIN(ELFImage_ArchiveDefinitionsOverrideCommonDeclarations)
{
    const LinkerTestDirectory directory("internal_elf_archive_common");
    SWC_RESULT(directory.write("main.c", "int value; int main(void) { return value != 42; }\n"));
    SWC_RESULT(directory.write("weak.c", "__attribute__((weak)) int value = 7;\n"));
    SWC_RESULT(directory.write("strong.c", "int value = 42;\n"));
    uint32_t exitCode = 0;
    std::string output;
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
    for (const char* name : {"main", "weak", "strong"})
    {
        const std::vector<Utf8> arguments = {"-x", "c", "-fcommon", "-c", std::format("{}.c", name), "-o", std::format("{}.o", name)};
        if (Os::runProcess(exitCode, "c++", arguments, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode)
            return Result::Error;
    }
    FileSystem::IoErrorInfo io;
    std::vector<LinkArchiveMember> members(2);
    SWC_RESULT(FileSystem::readBinaryFile(directory.path() / "weak.o", members[0].bytes, io));
    SWC_RESULT(FileSystem::readBinaryFile(directory.path() / "strong.o", members[1].bytes, io));
    ByteArray bytes;
    Diagnostic diagnostic;
    if (!buildElfStaticArchive(bytes, diagnostic, members))
        return Result::Error;
    SWC_RESULT(directory.write("library.a", {reinterpret_cast<const char*>(bytes.data()), bytes.size()}));
    LinkJob job;
    job.outputPath = directory.path() / "program";
    job.archiveMembers.resize(1);
    job.elfLibraries = {directory.path() / "library.a", "c"};
    SWC_RESULT(FileSystem::readBinaryFile(directory.path() / "main.o", job.archiveMembers[0].bytes, io));
    Utf8 error;
    if (!buildElfImage(bytes, error, job))
    {
        std::println(stderr, "[ELF common archive] {}", error);
        return Result::Error;
    }
    SWC_RESULT(directory.write("program", {reinterpret_cast<const char*>(bytes.data()), bytes.size()}));
    std::error_code permissions;
    fs::permissions(job.outputPath, fs::perms::owner_exec, fs::perm_options::add, permissions);
    if (permissions || Os::runProcess(exitCode, job.outputPath, {}, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(ELFImage_LoadsNativeConstructorsAndPreservesArrayMetadata)
{
    const LinkerTestDirectory directory("internal_elf_constructor");
    constexpr std::string_view source = R"(extern "C" {
__attribute__((visibility("protected"))) int initialized;
__attribute__((constructor(200))) static void second() { initialized = initialized * 10 + 2; }
__attribute__((constructor(101))) static void first() { initialized = initialized * 10 + 1; }
__attribute__((constructor)) static void last() { initialized = initialized * 10 + 3; }
}
)";
    SWC_RESULT(directory.write("constructor.cpp", source));
    uint32_t exitCode = 0;
    std::string output;
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
    const std::vector<Utf8> compile = {"-c", "-fPIC", "constructor.cpp", "-o", "constructor.o"};
    if (Os::runProcess(exitCode, "c++", compile, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode)
        return Result::Error;
    LinkJob job;
    job.output = LinkJob::Output::SharedLibrary;
    job.outputPath = directory.path() / "constructor.so";
    job.archiveMembers.resize(1);
    FileSystem::IoErrorInfo io;
    SWC_RESULT(FileSystem::readBinaryFile(directory.path() / "constructor.o", job.archiveMembers[0].bytes, io));
    ByteArray bytes;
    Utf8 error;
    if (!buildElfImage(bytes, error, job))
    {
        std::println(stderr, "[ELF constructor] {}", error);
        return Result::Error;
    }
    SWC_RESULT(directory.write("constructor.so", {reinterpret_cast<const char*>(bytes.data()), bytes.size()}));
    const std::vector<Utf8> inspect = {"--dump-section", ".init_array=array.bin", "constructor.so", "inspected.so"};
    if (Os::runProcess(exitCode, "objcopy", inspect, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode)
        return Result::Error;
    void* module = nullptr;
    void* initialized = nullptr;
    if (!Os::loadExternalModule(module, job.outputPath.string()) || !Os::getExternalSymbolAddress(initialized, module, "initialized") || *static_cast<const int*>(initialized) != 123)
        return Result::Error;
    LinkImage image;
    LinkSection code;
    code.name = ".text";
    code.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Read | LinkSectionFlagsE::Execute;
    NativeTest::emit(code.bytes, {0x48, 0x8b, 0x0d, 0, 0, 0, 0, 0x8b, 0x01, 0x83, 0xe8, 123, 0xc3});
    code.relocs.push_back({.offset = 3, .kind = LinkRelocKind::GotRel32, .symbolName = "initialized"});
    image.sections.push_back(std::move(code));
    image.symbols.push_back({.name = "main"});
    LinkJob program;
    program.outputPath = directory.path() / "program";
    program.elfLibraries = {job.outputPath, "c"};
    program.archiveMembers.resize(1);
    Diagnostic diagnostic;
    if (!buildElfObject(program.archiveMembers[0].bytes, diagnostic, image) || !buildElfImage(bytes, error, program))
        return Result::Error;
    SWC_RESULT(directory.write("program", {reinterpret_cast<const char*>(bytes.data()), bytes.size()}));
    std::error_code permissions;
    fs::permissions(program.outputPath, fs::perms::owner_exec, fs::perm_options::add, permissions);
    if (permissions || Os::runProcess(exitCode, program.outputPath, {}, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode)
        return Result::Error;
    image.sections[0].relocs[0].kind = LinkRelocKind::Rel32;
    image.imports.push_back({.symbolName = "initialized", .isData = true});
    if (!buildElfObject(program.archiveMembers[0].bytes, diagnostic, image) || buildElfImage(bytes, error, program) || !error.view().contains("protected"))
        return Result::Error;
}
SWC_TEST_END()
#endif

SWC_TEST_BEGIN(ELFArchive_IndexesDefinitionsAndPreservesMembers)
{
    LinkImage image;
    LinkSection section;
    section.name = ".data";
    section.bytes.append("odd");
    image.sections.push_back(std::move(section));
    image.symbols.push_back({.name = "first", .sectionIndex = 0});
    image.symbols.push_back({.name = "second", .sectionIndex = 0});
    image.sections[0].relocs.push_back({.offset = 0, .kind = LinkRelocKind::Abs64, .symbolName = "undefined"});
    image.sections[0].bytes.resize(9);
    std::vector<LinkArchiveMember> members(2);
    Diagnostic diagnostic;
    if (!buildElfObject(members[0].bytes, diagnostic, image))
        return Result::Error;
    members[0].bytes.append("x"); // Odd member sizes need an external padding byte.
    image.symbols = {{.name = "third", .sectionIndex = 0}};
    if (!buildElfObject(members[1].bytes, diagnostic, image))
        return Result::Error;
    ByteArray bytes;
    if (!buildElfStaticArchive(bytes, diagnostic, members))
        return Result::Error;
    const ByteView view(bytes.span());
    if (std::memcmp(bytes.data(), "!<arch>\n", 8) || view.readBe32(68) != 3)
        return Result::Error;
    const uint32_t first = view.readBe32(72);
    const uint32_t second = view.readBe32(80);
    if (view.readBe32(76) != first || first % 2 || second % 2 ||
        std::memcmp(bytes.data() + 84, "first\0second\0third\0", 19) ||
        second != first + 60 + members[0].bytes.size() + (members[0].bytes.size() & 1) ||
        !std::ranges::equal(bytes.span().subspan(first + 60, members[0].bytes.size()), members[0].bytes.span()) ||
        !std::ranges::equal(bytes.span().subspan(second + 60, members[1].bytes.size()), members[1].bytes.span()))
        return Result::Error;
    ByteArray repeated;
    if (!buildElfStaticArchive(repeated, diagnostic, members) || repeated != bytes)
        return Result::Error;
    ByteArray oversizedMemberSize = bytes;
    std::memcpy(oversizedMemberSize.data() + 8 + 48, "4294967331", 10);
    Archive rejectsWrappedMemberSize;
    if (rejectsWrappedMemberSize.load(diagnostic, std::move(oversizedMemberSize)))
        return Result::Error;

    const ByteArray original = members[1].bytes;
    members[1].bytes.writeLe64(40, UINT64_MAX);
    if (buildElfStaticArchive(bytes, diagnostic, members) || !bytes.empty())
        return Result::Error;
    members[1].bytes = original;
    members[1].bytes.resize(63);
    if (buildElfStaticArchive(bytes, diagnostic, members) || !bytes.empty())
        return Result::Error;
    members.clear();
    if (!buildElfStaticArchive(bytes, diagnostic, members) || bytes.size() != 72 || ByteView(bytes.span()).readBe32(68))
        return Result::Error;
    std::memcpy(bytes.data() + 8, "/SYM64/", 7);
    Archive unsupported;
    if (unsupported.load(diagnostic, std::move(bytes)))
        return Result::Error;
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
SWC_FILESYSTEM_TEST_BEGIN(Linker_LinuxRelinksChangedStaticDependenciesAndRecoversDamagedCache)
{
    const LinkerTestDirectory directory("elf_module_relink");
    SWC_RESULT(directory.write("modules/provider/module.swg", "#run { let cfg = unwrap Swag.compiler().getBuildCfg(); cfg.moduleNamespace = \"Provider\"; cfg.backendKind = .StaticLibrary }\n"));
    SWC_RESULT(directory.write("modules/consumer/module.swg", "#import(\"provider\")\n#run { let cfg = unwrap Swag.compiler().getBuildCfg(); cfg.moduleNamespace = \"Consumer\"; cfg.backendKind = .Executable }\n"));
    std::string main = "#main\n{\n    switch Provider.value()\n    {\n";
    for (uint32_t phase = 1; phase <= 7; ++phase)
        main += std::format("    case {}: Swag.print(\"value-{}\\n\")\n", phase, phase);
    main += "    default: Swag.panic(\"unexpected provider value\", #curlocation)\n    }\n}\n";
    SWC_RESULT(directory.write("modules/consumer/src/main.swg", main));
    const std::vector<Utf8> arguments = {"run", "--workspace", Utf8(directory.path()), "--workspace-module", "consumer", "--num-cores", std::to_string(Unittest::compilerWorkerCount(ctx)), "--no-log-color"};
    fs::path                cachePath;
    for (uint32_t phase = 1; phase <= 7; ++phase)
    {
        std::string provider = std::format("#[Swag.NoInline]\npublic func value()->s32 {{ return {} }}\n", phase);
        provider += "#init { Swag.print(\"provider-init\\n\") }\n#drop { Swag.print(\"provider-drop\\n\") }\n";
        // An API change requires compilation even when an older object cache is intact.
        if (phase == 7)
            provider += "public func added()->s32 { return 1 }\n";
        SWC_RESULT(directory.write("modules/provider/src/value.swg", provider));
        std::error_code error;
        if (phase == 3)
        {
            const auto originalTime = fs::last_write_time(cachePath, error);
            if (error)
                return Result::Error;
            ByteArray               bytes;
            FileSystem::IoErrorInfo ioError;
            SWC_RESULT(FileSystem::readBinaryFile(cachePath, bytes, ioError));
            if (bytes.empty())
                return Result::Error;
            bytes[bytes.size() - 1] ^= std::byte{1};
            SWC_RESULT(FileSystem::writeBinaryFile(cachePath, bytes.data(), bytes.size(), ioError));
            // Reach the cache integrity check, not just manifest mtime invalidation.
            fs::last_write_time(cachePath, originalTime, error);
            if (error)
                return Result::Error;
        }
        if (phase == 5 && (!fs::remove(cachePath, error) || error))
            return Result::Error;
        std::string                 output;
        uint32_t                    exitCode = 0;
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
        const auto                  status      = Os::runProcess(exitCode, Os::getExeFullName(), arguments, directory.path(), &options);
        const auto                  initialized = output.find("provider-init");
        const auto                  value       = output.find(std::format("value-{}", phase));
        const auto                  dropped     = output.find("provider-drop");
        const bool                  reused      = phase == 2 || phase == 4 || phase == 6;
        if (status != Os::ProcessRunResult::Ok || exitCode || initialized == std::string::npos || value == std::string::npos || dropped == std::string::npos ||
            initialized >= value || value >= dropped || (output.find("relinked") != std::string::npos) != reused)
        {
            std::println(stderr, "[ELF module relink phase {}] result={}, exit={}\n{}", phase, static_cast<uint32_t>(status), exitCode, output);
            return Result::Error;
        }
        if (phase == 1)
        {
            for (fs::recursive_directory_iterator it(directory.path(), error), end; it != end && !error; it.increment(error))
                if (it->path().filename().string().ends_with(".relink.elfcache"))
                    cachePath = it->path();
            if (error || cachePath.empty())
                return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_LinuxFunctionCacheReusesAndInvalidatesNativeObjects)
{
    const LinkerTestDirectory directory("elf_function_cache");
    const auto                writeProgram = [&](const uint64_t seed, const uint32_t blankLines, const uint32_t marker) -> Result {
        std::string source(blankLines, '\n');
        source += "#[Swag.NoInline]\nfunc cachedLeaf(value: u64)->u64\n{\n    var result = value\n";
        uint64_t expected = 7;
        for (uint64_t step = 0; step < 32; ++step)
        {
            source += std::format("    result = ((result << 3) ^ (result >> 2)) ^ {}'u64\n", seed + step);
            expected = ((expected << 3) ^ (expected >> 2)) ^ (seed + step);
        }
        source += "    return result\n}\n";
        uint64_t second = expected;
        for (uint64_t step = 0; step < 32; ++step)
            second = ((second << 3) ^ (second >> 2)) ^ (seed + step);
        source += std::format("#main {{ let first = cachedLeaf(7); let second = cachedLeaf(first); Swag.assert(first == {}'u64 and second == {}'u64); Swag.print(\"cache-ok-{}\\n\") }}\n", expected, second, marker);
        return directory.write("program.swg", source);
    };
    const std::vector<Utf8> arguments = {
        "run", "--file", Utf8(directory.path() / "program.swg"), "--artifact-name", "cache-probe", "--num-cores", std::to_string(Unittest::compilerWorkerCount(ctx)), "--no-log-color",
        "--out-dir", Utf8(directory.path() / "output"), "--work-dir", Utf8(directory.path() / "work")};
    const auto run = [&](const bool reused, const uint32_t marker) -> Result {
        std::string                 output;
        uint32_t                    exitCode = 0;
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
        const auto                  status = Os::runProcess(exitCode, Os::getExeFullName(), arguments, directory.path(), &options);
        if (status != Os::ProcessRunResult::Ok || exitCode || output.find(std::format("cache-ok-{}", marker)) == std::string::npos ||
            (output.find("unchanged function") != std::string::npos) != reused)
        {
            std::println(stderr, "[ELF function cache marker {}] result={}, exit={}\n{}", marker, static_cast<uint32_t>(status), exitCode, output);
            return Result::Error;
        }
        return Result::Continue;
    };
    const auto checkSourceLine = [&](const uint32_t expected) -> Result {
        const fs::path              table = directory.path() / "symbols.bin";
        const std::vector<Utf8>     dump  = {"--dump-section", ".swagdbg=" + Utf8(table), Utf8(directory.path() / "output/cache-probe"), Utf8(directory.path() / "inspected-elf")};
        std::string                 output;
        uint32_t                    exitCode = 0;
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
        if (Os::runProcess(exitCode, "objcopy", dump, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode)
            return Result::Error;
        ByteArray               bytes;
        FileSystem::IoErrorInfo error;
        SWC_RESULT(FileSystem::readBinaryFile(table, bytes, error));
        // An image table contains resolved addresses, not the object relocations
        // required by SymbolTable::read. Inspect its runtime layout directly.
        if (!bytes.containsRange(0, SymbolTable::HEADER_SIZE) || bytes.readLe32(0) != SymbolTable::MAGIC || bytes.readLe32(4) != SymbolTable::VERSION_PLAIN)
            return Result::Error;
        const uint32_t count   = bytes.readLe32(8);
        const uint32_t strings = bytes.readLe32(12);
        if (strings < SymbolTable::HEADER_SIZE + static_cast<uint64_t>(count) * SymbolTable::ENTRY_SIZE || strings > bytes.size())
            return Result::Error;
        const auto readString = [&](const uint32_t offset) -> std::string_view {
            if (offset < strings || offset >= bytes.size())
                return {};
            const char* begin = reinterpret_cast<const char*>(bytes.data() + offset);
            const char* end   = static_cast<const char*>(std::memchr(begin, 0, bytes.size() - offset));
            return end ? std::string_view(begin, end) : std::string_view{};
        };
        for (uint32_t index = 0; index < count; ++index)
        {
            const uint64_t entry = SymbolTable::HEADER_SIZE + static_cast<uint64_t>(index) * SymbolTable::ENTRY_SIZE;
            if (readString(bytes.readLe32(entry + 8)).ends_with(".cachedLeaf"))
                return bytes.readLe32(entry + 16) == expected && readString(bytes.readLe32(entry + 12)).ends_with("/program.swg") ? Result::Continue : Result::Error;
        }
        return Result::Error;
    };
    SWC_RESULT(writeProgram(11, 0, 1));
    SWC_RESULT(run(false, 1));
    SWC_RESULT(checkSourceLine(5));
    SWC_RESULT(writeProgram(11, 0, 2));
    SWC_RESULT(run(true, 2));
    SWC_RESULT(checkSourceLine(5));

    fs::path        cachePath;
    std::error_code error;
    for (fs::recursive_directory_iterator it(directory.path(), error), end; it != end && !error; it.increment(error))
        if (it->path().extension() == ".elfcache")
            cachePath = it->path();
    if (error || cachePath.empty())
        return Result::Error;
    SWC_RESULT(writeProgram(12, 0, 3));
    SWC_RESULT(run(false, 3));
    SWC_RESULT(writeProgram(12, 0, 4));
    SWC_RESULT(run(true, 4));

    // Token indices and generated symbol names survive blank lines; recorded source lines do not.
    SWC_RESULT(writeProgram(12, 3, 5));
    SWC_RESULT(run(false, 5));
    SWC_RESULT(writeProgram(12, 3, 6));
    SWC_RESULT(run(true, 6));
    SWC_RESULT(checkSourceLine(8));
    FileSystem::IoErrorInfo ioError;
    const std::array        corrupt = {std::byte{0}, std::byte{1}};
    SWC_RESULT(FileSystem::writeBinaryFile(cachePath, corrupt.data(), corrupt.size(), ioError));
    SWC_RESULT(writeProgram(12, 3, 7));
    SWC_RESULT(run(false, 7));
    SWC_RESULT(writeProgram(12, 3, 8));
    SWC_RESULT(run(true, 8));
}
SWC_TEST_END()

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
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
        if (Os::runProcess(exitCode, executable, {}, artifacts, &options) != Os::ProcessRunResult::Ok || exitCode != 102)
            return Result::Error;
        const auto leaf   = output.find("NativeSymbols.leaf --> ");
        const auto caller = output.find("SymbolConsumer.caller --> ");
        if (leaf == std::string::npos || caller == std::string::npos || leaf >= caller || output.find("leaf.swg:3", leaf) == std::string::npos || output.find("caller.swg:4", caller) == std::string::npos)
        {
            std::println(stderr, "[ELF runtime symbols] {}", output);
            return Result::Error;
        }

        std::vector<fs::path> artifactPaths = {executable};
        if (shared)
            artifactPaths.push_back(library);
        std::vector<uint64_t> defaultSizes;
        for (const fs::path& artifact : artifactPaths)
            defaultSizes.push_back(fs::file_size(artifact));

        std::vector<Utf8> omitSymbolsArguments = arguments;
        std::erase(omitSymbolsArguments, Utf8("--rebuild"));
        omitSymbolsArguments.push_back("--no-runtime-symbols");
        SWC_RESULT(runCompiler(omitSymbolsArguments, ExitCode::Success, ""));

        // Omitting the runtime table makes the images smaller, but leaves the
        // panic message itself available to callers.
        for (size_t index = 0; index < artifactPaths.size(); ++index)
        {
            const fs::path& artifact = artifactPaths[index];
            if (fs::file_size(artifact) >= defaultSizes[index])
                return Result::Error;
            output.clear();
            const std::vector<Utf8> inspect = {"-lW", "-d", "-SW", Utf8(artifact)};
            if (Os::runProcess(exitCode, "readelf", inspect, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode || output.find("TEXTREL") != std::string::npos || output.find(".swagdbg") != std::string::npos)
                return Result::Error;
        }
        output.clear();
        if (Os::runProcess(exitCode, executable, {}, artifacts, &options) != Os::ProcessRunResult::Ok || exitCode != 102 || output.find("native-symbol-probe") == std::string::npos || output.find("runtime trace") != std::string::npos)
            return Result::Error;

        // Switching back without --rebuild must restore the table from cached object/archive
        // contributions, including the dependency's static-library frames.
        std::vector<Utf8> restoreSymbolsArguments = omitSymbolsArguments;
        std::erase(restoreSymbolsArguments, Utf8("--no-runtime-symbols"));
        SWC_RESULT(runCompiler(restoreSymbolsArguments, ExitCode::Success, ""));
        for (size_t index = 0; index < artifactPaths.size(); ++index)
        {
            const fs::path& artifact = artifactPaths[index];
            if (fs::file_size(artifact) != defaultSizes[index])
                return Result::Error;
            output.clear();
            const std::vector<Utf8> inspect = {"-lW", "-d", "-SW", Utf8(artifact)};
            if (Os::runProcess(exitCode, "readelf", inspect, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode || output.find(".swagdbg") == std::string::npos)
                return Result::Error;
        }
        output.clear();
        if (Os::runProcess(exitCode, executable, {}, artifacts, &options) != Os::ProcessRunResult::Ok || exitCode != 102 || output.find("NativeSymbols.leaf --> ") == std::string::npos || output.find("SymbolConsumer.caller --> ") == std::string::npos)
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
        const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
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
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
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

SWC_FILESYSTEM_TEST_BEGIN(ELFImage_RelocatedConstantsBecomeReadOnlyAfterLoading)
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
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
    LinkJob job;
    job.output = LinkJob::Output::SharedLibrary;
    job.outputPath = directory.path() / "generated.so";
    job.archiveMembers.push_back({.name = "generated.o", .bytes = std::move(bytes)});
    Utf8 error;
    if (!buildElfImage(bytes, error, job))
    {
        std::println(stderr, "[ELF relocated constants] {}", error);
        return Result::Error;
    }
    SWC_RESULT(directory.write("generated.so", {reinterpret_cast<const char*>(bytes.data()), bytes.size()}));
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
    const Os::ProcessRunOptions options{.capturedOutput = &output, .forwardOutput = false};
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
