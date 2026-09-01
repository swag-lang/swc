#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Linker/Linker.h"
#include "Backend/Linker/PeWriter.h"
#include "Support/Math/Helpers.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using RtlDecompressBufferFn = LONG(WINAPI*)(USHORT compressionFormat, PUCHAR uncompressedBuffer, ULONG uncompressedBufferSize, PUCHAR compressedBuffer, ULONG compressedBufferSize, ULONG* finalUncompressedSize);

    void emit(ByteArray& out, std::initializer_list<int> bytes)
    {
        for (const int b : bytes)
            out.pushBack(static_cast<std::byte>(b));
    }

    uint16_t peSubsystem(const ByteArray& bytes)
    {
        if (!bytes.containsRange(0x3C, sizeof(uint32_t)))
            return 0;

        const uint32_t peOffset = bytes.readLe32(0x3C);
        if (!bytes.containsRange(peOffset, sizeof(uint32_t) + sizeof(IMAGE_FILE_HEADER) + sizeof(IMAGE_OPTIONAL_HEADER64)))
            return 0;
        if (bytes.readLe32(peOffset) != IMAGE_NT_SIGNATURE)
            return 0;

        const size_t optionalOffset = peOffset + sizeof(uint32_t) + sizeof(IMAGE_FILE_HEADER);
        return bytes.readLe16(optionalOffset + offsetof(IMAGE_OPTIONAL_HEADER64, Subsystem));
    }

    struct PeSectionView
    {
        uint32_t virtualSize = 0;
        uint32_t rva         = 0;
        uint32_t rawSize     = 0;
        uint32_t rawOffset   = 0;
    };

    bool findPeSection(PeSectionView& outSection, const ByteArray& bytes, const std::string_view name)
    {
        outSection = {};
        if (!bytes.containsRange(0x3C, sizeof(uint32_t)))
            return false;

        const uint32_t peOffset         = bytes.readLe32(0x3C);
        const size_t   fileHeaderOffset = peOffset + sizeof(uint32_t);
        if (!bytes.containsRange(fileHeaderOffset, sizeof(IMAGE_FILE_HEADER)))
            return false;

        IMAGE_FILE_HEADER fileHeader;
        std::memcpy(&fileHeader, bytes.data() + fileHeaderOffset, sizeof(fileHeader));
        const size_t sectionTableOffset = fileHeaderOffset + sizeof(fileHeader) + fileHeader.SizeOfOptionalHeader;
        if (!bytes.containsRange(sectionTableOffset, static_cast<size_t>(fileHeader.NumberOfSections) * sizeof(IMAGE_SECTION_HEADER)))
            return false;

        for (uint32_t i = 0; i < fileHeader.NumberOfSections; ++i)
        {
            IMAGE_SECTION_HEADER header;
            std::memcpy(&header, bytes.data() + sectionTableOffset + static_cast<size_t>(i) * sizeof(header), sizeof(header));
            size_t nameLength = 0;
            while (nameLength < IMAGE_SIZEOF_SHORT_NAME && header.Name[nameLength])
                ++nameLength;
            if (std::string_view{reinterpret_cast<const char*>(header.Name), nameLength} != name)
                continue;

            outSection.virtualSize = header.Misc.VirtualSize;
            outSection.rva         = header.VirtualAddress;
            outSection.rawSize     = header.SizeOfRawData;
            outSection.rawOffset   = header.PointerToRawData;
            return true;
        }

        return false;
    }

    bool decompressLznt1(ByteArray& outBytes, const std::span<const std::byte> compressedBytes, const uint32_t uncompressedSize)
    {
        const HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
        if (!ntdll)
            return false;

        const auto decompressBuffer = reinterpret_cast<RtlDecompressBufferFn>(GetProcAddress(ntdll, "RtlDecompressBuffer"));
        if (!decompressBuffer)
            return false;

        outBytes.resize(uncompressedSize);
        ULONG finalSize = 0;
        if (decompressBuffer(0x0002, reinterpret_cast<PUCHAR>(outBytes.data()), uncompressedSize, reinterpret_cast<PUCHAR>(const_cast<std::byte*>(compressedBytes.data())), static_cast<ULONG>(compressedBytes.size()), &finalSize) < 0)
            return false;
        return finalSize == uncompressedSize;
    }

    ByteArray makeSingleImageIcon(const ByteArray& image)
    {
        ByteArray bytes;
        bytes.appendLe16(0);
        bytes.appendLe16(1);
        bytes.appendLe16(1);
        bytes.pushBack(std::byte{16});
        bytes.pushBack(std::byte{16});
        bytes.pushBack(std::byte{0});
        bytes.pushBack(std::byte{0});
        bytes.appendLe16(1);
        bytes.appendLe16(32);
        bytes.appendLe32(static_cast<uint32_t>(image.size()));
        bytes.appendLe32(22);
        bytes.append(image);
        return bytes;
    }
}

SWC_TEST_BEGIN(PeWriter_CompressesEmbeddedDebugTable)
{
    ByteArray text;
    emit(text, {0xC3});

    LinkSection textSection;
    textSection.name  = ".text";
    textSection.bytes = std::move(text);
    textSection.align = 16;
    textSection.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Execute | LinkSectionFlagsE::Read;

    ByteArray debugBytes;
    debugBytes.appendLe32(0x42445753u);
    debugBytes.appendLe32(1);
    debugBytes.appendLe32(0);
    debugBytes.appendLe32(16);
    debugBytes.resize(200'000, std::byte{'A'});
    const uint32_t  originalDebugSize  = static_cast<uint32_t>(debugBytes.size());
    const ByteArray originalDebugBytes = debugBytes;

    LinkSection debugSection;
    debugSection.name  = ".swagdbg";
    debugSection.bytes = std::move(debugBytes);
    debugSection.align = 4;

    LinkSection dataSection;
    dataSection.name = ".data";
    dataSection.bytes.resize(64, std::byte{0x5A});

    LinkImage image;
    image.sections.push_back(std::move(textSection));
    image.sections.push_back(std::move(debugSection));
    image.sections.push_back(std::move(dataSection));
    image.symbols.push_back({.name = "entry", .sectionIndex = 0, .value = 0});
    image.entrySymbol  = "entry";
    image.kind         = LinkImageKind::Executable;
    image.imageBase    = 0x140000000ull;
    image.stackReserve = 0x100000;

    ByteArray           peBytes;
    ByteArray           pdbBytes;
    Diagnostic          diag;
    PEWriter            writer;
    const LinkDebugInfo noDebugInfo;
    if (!writer.writeImage(peBytes, pdbBytes, diag, image, noDebugInfo, fs::path{}))
        return Result::Error;

    PeSectionView debugView;
    PeSectionView dataView;
    if (!findPeSection(debugView, peBytes, ".swagdbg") || !findPeSection(dataView, peBytes, ".data"))
        return Result::Error;
    if (debugView.virtualSize != originalDebugSize || debugView.rawSize >= Math::alignUpU32(originalDebugSize, 0x200))
        return Result::Error;
    if (dataView.rawOffset <= debugView.rawOffset || dataView.rawOffset >= debugView.rawOffset + Math::alignUpU32(originalDebugSize, 0x200))
        return Result::Error;
    if (!peBytes.containsRange(debugView.rawOffset, 16))
        return Result::Error;
    if (peBytes.readLe32(debugView.rawOffset) != 0x42445753u || peBytes.readLe32(debugView.rawOffset + 4) != 2)
        return Result::Error;
    if (peBytes.readLe32(debugView.rawOffset + 8) != originalDebugSize)
        return Result::Error;
    const uint32_t compressedSize = peBytes.readLe32(debugView.rawOffset + 12);
    if (compressedSize + 16 > debugView.rawSize)
        return Result::Error;

    ByteArray decompressedBytes;
    if (!decompressLznt1(decompressedBytes, {peBytes.data() + debugView.rawOffset + 16, compressedSize}, originalDebugSize))
        return Result::Error;
    if (decompressedBytes != originalDebugBytes)
        return Result::Error;
}
SWC_TEST_END()

// Hand-builds the smallest meaningful program -- one that calls kernel32!ExitProcess(42) through an
// imported thunk -- writes it to a PE with the internal writer, runs it, and checks the exit code.
// This exercises section layout and the import table/IAT/thunk path with a direct relative call,
// independently of the rest of the compiler.
SWC_FILESYSTEM_TEST_BEGIN(PeWriter_MinimalExecutableCallsExitProcess)
{
    SWC_UNUSED(ctx);

    ByteArray text;
    emit(text, {0x48, 0x83, 0xEC, 0x28});       // sub rsp, 0x28
    emit(text, {0xB9, 0x2A, 0x00, 0x00, 0x00}); // mov ecx, 42
    emit(text, {0xE8});                         // call <ExitProcess thunk>
    const uint32_t relocOffset = static_cast<uint32_t>(text.size());
    emit(text, {0, 0, 0, 0}); // rel32 (addend 0, patched by the linker)
    emit(text, {0xC3});       // ret

    LinkSection textSection;
    textSection.name  = ".text";
    textSection.bytes = std::move(text);
    textSection.align = 16;
    textSection.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Execute | LinkSectionFlagsE::Read;
    textSection.relocs.push_back({.sectionIndex = 0, .offset = relocOffset, .symbolName = "ExitProcess", .addend = 0, .kind = LinkRelocKind::Rel32});

    LinkImage image;
    image.sections.push_back(std::move(textSection));
    image.symbols.push_back({.name = "entry", .sectionIndex = 0, .value = 0});
    image.imports.push_back({.dll = "kernel32", .importName = "ExitProcess", .symbolName = "ExitProcess", .isData = false});
    image.entrySymbol  = "entry";
    image.kind         = LinkImageKind::Executable;
    image.imageBase    = 0x140000000ull;
    image.stackReserve = 0x100000;

    ByteArray           peBytes;
    ByteArray           pdbBytes;
    Diagnostic          diag;
    PEWriter            writer;
    const LinkDebugInfo noDebugInfo;
    if (!writer.writeImage(peBytes, pdbBytes, diag, image, noDebugInfo, fs::path{}))
    {
        const std::string_view reason = diag.elements().empty() ? std::string_view{"unknown error"} : diag.elements().front()->idName();
        std::println(stderr, "[pe-writer] cannot write image: {}", reason);
        return Result::Error;
    }

    const fs::path  dir = fs::temp_directory_path() / "swc_pewriter_test";
    std::error_code ec;
    fs::create_directories(dir, ec);
    const fs::path exePath = dir / "pewriter_minimal.exe";

    {
        std::ofstream file(exePath, std::ios::binary | std::ios::trunc);
        if (!file.is_open())
            return Result::Error;
        file.write(reinterpret_cast<const char*>(peBytes.data()), static_cast<std::streamsize>(peBytes.size()));
        if (!file.good())
            return Result::Error;
    }

    uint32_t                    exitCode = 0;
    constexpr std::vector<Utf8> args;
    const Os::ProcessRunResult  runResult = Os::runProcess(exitCode, exePath, args, dir, nullptr);

    fs::remove(exePath, ec);

    if (runResult != Os::ProcessRunResult::Ok)
    {
        std::println(stderr, "[pe-writer] generated process did not run (result {})", static_cast<int>(runResult));
        return Result::Error;
    }
    if (exitCode != 42)
    {
        std::println(stderr, "[pe-writer] generated process exited with code {}, expected 42", exitCode);
        return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(PeWriter_FoldsIdenticalUnwindInfo)
{
    ByteArray text;
    emit(text, {0xC3, 0xC3, 0xC3});

    LinkSection textSection;
    textSection.name  = ".text";
    textSection.bytes = std::move(text);
    textSection.align = 16;
    textSection.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Execute | LinkSectionFlagsE::Read;

    ByteArray xdata;
    emit(xdata, {1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 0});

    LinkSection xdataSection;
    xdataSection.name  = ".xdata";
    xdataSection.bytes = std::move(xdata);
    xdataSection.align = 4;
    xdataSection.flags = LinkSectionFlagsE::Read;

    LinkSection pdataSection;
    pdataSection.name  = ".pdata";
    pdataSection.align = 4;
    pdataSection.flags = LinkSectionFlagsE::Read | LinkSectionFlagsE::Exception;
    pdataSection.bytes.resize(36, std::byte{0});
    for (uint32_t i = 0; i < 3; ++i)
    {
        const uint32_t offset       = i * 12;
        const Utf8     functionName = std::format("function{}", i);
        const Utf8     unwindName   = std::format("unwind{}", i);
        pdataSection.relocs.push_back({.sectionIndex = 2, .offset = offset, .symbolName = functionName, .kind = LinkRelocKind::Rva32});
        pdataSection.relocs.push_back({.sectionIndex = 2, .offset = offset + 4, .symbolName = functionName, .addend = 1, .kind = LinkRelocKind::Rva32});
        pdataSection.relocs.push_back({.sectionIndex = 2, .offset = offset + 8, .symbolName = unwindName, .kind = LinkRelocKind::Rva32});
    }

    LinkImage image;
    image.sections.push_back(std::move(textSection));
    image.sections.push_back(std::move(xdataSection));
    image.sections.push_back(std::move(pdataSection));
    image.symbols.push_back({.name = "function0", .sectionIndex = 0, .value = 0});
    image.symbols.push_back({.name = "function1", .sectionIndex = 0, .value = 1});
    image.symbols.push_back({.name = "function2", .sectionIndex = 0, .value = 2});
    image.symbols.push_back({.name = "unwind0", .sectionIndex = 1, .value = 0});
    image.symbols.push_back({.name = "unwind1", .sectionIndex = 1, .value = 4});
    image.symbols.push_back({.name = "unwind2", .sectionIndex = 1, .value = 8});
    image.entrySymbol  = "function0";
    image.kind         = LinkImageKind::Executable;
    image.imageBase    = 0x140000000ull;
    image.stackReserve = 0x100000;

    ByteArray           peBytes;
    ByteArray           pdbBytes;
    Diagnostic          diag;
    PEWriter            writer;
    const LinkDebugInfo noDebugInfo;
    if (!writer.writeImage(peBytes, pdbBytes, diag, image, noDebugInfo, fs::path{}))
        return Result::Error;

    PeSectionView emittedXdata;
    PeSectionView emittedPdata;
    if (!findPeSection(emittedXdata, peBytes, ".xdata") || !findPeSection(emittedPdata, peBytes, ".pdata"))
        return Result::Error;
    if (emittedXdata.virtualSize != 8 || emittedPdata.virtualSize != 36)
        return Result::Error;

    const uint32_t firstUnwind  = peBytes.readLe32(emittedPdata.rawOffset + 8);
    const uint32_t secondUnwind = peBytes.readLe32(emittedPdata.rawOffset + 20);
    const uint32_t thirdUnwind  = peBytes.readLe32(emittedPdata.rawOffset + 32);
    if (firstUnwind != emittedXdata.rva || secondUnwind != firstUnwind || thirdUnwind != emittedXdata.rva + 4)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Linker_NonDebugImageRemovesStalePdb)
{
    SWC_UNUSED(ctx);

    ByteArray text;
    emit(text, {0xC3});

    LinkSection textSection;
    textSection.name  = ".text";
    textSection.bytes = std::move(text);
    textSection.align = 16;
    textSection.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Execute | LinkSectionFlagsE::Read;

    const fs::path  dir = fs::temp_directory_path() / "swc_linker_no_debug_test" / std::to_string(Os::currentProcessId());
    std::error_code ec;
    fs::create_directories(dir, ec);
    if (ec)
        return Result::Error;

    LinkJob job;
    job.outputPath = dir / "no_debug.exe";
    job.output     = LinkJob::Output::Executable;
    job.targetOs   = Runtime::TargetOs::Windows;
    job.image.sections.push_back(std::move(textSection));
    job.image.symbols.push_back({.name = "entry", .sectionIndex = 0, .value = 0});
    job.image.entrySymbol  = "entry";
    job.image.kind         = LinkImageKind::Executable;
    job.image.imageBase    = 0x140000000ull;
    job.image.stackReserve = 0x100000;

    fs::path stalePdbPath = job.outputPath;
    stalePdbPath.replace_extension(".pdb");
    {
        std::ofstream stalePdb(stalePdbPath, std::ios::binary | std::ios::trunc);
        if (!stalePdb.is_open())
            return Result::Error;
        stalePdb << "stale";
    }

    Linker::executeLink(job);
    const bool passed = job.ok && fs::exists(job.outputPath, ec) && !ec && !fs::exists(stalePdbPath, ec) && !ec;

    fs::remove(job.outputPath, ec);
    fs::remove(stalePdbPath, ec);
    fs::remove(dir, ec);
    if (!passed)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PeWriter_Win32ApplicationResourcesUseConfig)
{
    ByteArray text;
    emit(text, {0xC3});

    LinkSection textSection;
    textSection.name  = ".text";
    textSection.bytes = std::move(text);
    textSection.align = 16;
    textSection.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Execute | LinkSectionFlagsE::Read;

    ByteArray iconPayload;
    emit(iconPayload, {0x11, 0x22, 0x33, 0x44, 0x55});

    LinkImage image;
    image.sections.push_back(std::move(textSection));
    image.symbols.push_back({.name = "entry", .sectionIndex = 0, .value = 0});
    image.entrySymbol          = "entry";
    image.kind                 = LinkImageKind::Executable;
    image.imageBase            = 0x140000000ull;
    image.stackReserve         = 0x100000;
    image.moduleName           = "patchapp.exe";
    image.win32.subsystem      = LinkWin32Subsystem::Windows;
    image.win32.appName        = "Patch App";
    image.win32.appDescription = "Patch Description";
    image.win32.appCompany     = "Patch Company";
    image.win32.appCopyright   = "Patch Copyright";
    image.win32.version        = 1;
    image.win32.revision       = 2;
    image.win32.buildNum       = 3;
    image.win32.iconPath       = "patch.ico";
    image.win32.iconBytes      = makeSingleImageIcon(iconPayload);

    ByteArray           peBytes;
    ByteArray           pdbBytes;
    Diagnostic          diag;
    PEWriter            writer;
    const LinkDebugInfo noDebugInfo;
    if (!writer.writeImage(peBytes, pdbBytes, diag, image, noDebugInfo, fs::path{}))
    {
        const std::string_view reason = diag.elements().empty() ? std::string_view{"unknown error"} : diag.elements().front()->idName();
        std::println(stderr, "[pe-writer-resource] cannot write image: {}", reason);
        return Result::Error;
    }

    if (peSubsystem(peBytes) != IMAGE_SUBSYSTEM_WINDOWS_GUI)
        return Result::Error;
    if (!peBytes.containsUtf16Le("Patch App"))
        return Result::Error;
    if (!peBytes.containsUtf16Le("Patch Description"))
        return Result::Error;
    if (!peBytes.containsUtf16Le("Patch Company"))
        return Result::Error;
    if (!peBytes.containsUtf16Le("Patch Copyright"))
        return Result::Error;
    if (!peBytes.containsUtf16Le("1.2.3.0"))
        return Result::Error;
    if (!peBytes.contains(iconPayload))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
