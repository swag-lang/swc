#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Linker/PeWriter.h"
#include "Support/Core/ByteUtils.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void emit(std::vector<std::byte>& out, std::initializer_list<int> bytes)
    {
        for (const int b : bytes)
            out.push_back(static_cast<std::byte>(b));
    }

    bool containsBytes(ByteSpan bytes, ByteSpan needle)
    {
        if (needle.empty())
            return true;
        if (needle.size() > bytes.size())
            return false;

        for (size_t offset = 0; offset <= bytes.size() - needle.size(); ++offset)
        {
            if (std::equal(needle.begin(), needle.end(), bytes.begin() + offset))
                return true;
        }

        return false;
    }

    bool containsUtf16Le(ByteSpan bytes, std::string_view text)
    {
        std::vector<std::byte> needle;
        needle.reserve(text.size() * sizeof(char16_t));
        for (const char ch : text)
        {
            ByteUtils::appendLe16(needle, static_cast<uint8_t>(ch));
        }

        return containsBytes(bytes, asByteSpan(needle));
    }

    uint16_t peSubsystem(ByteSpan bytes)
    {
        if (!ByteUtils::containsRange(bytes, 0x3C, sizeof(uint32_t)))
            return 0;

        const uint32_t peOffset = ByteUtils::readLe32(bytes, 0x3C);
        if (!ByteUtils::containsRange(bytes, peOffset, sizeof(uint32_t) + sizeof(IMAGE_FILE_HEADER) + sizeof(IMAGE_OPTIONAL_HEADER64)))
            return 0;
        if (ByteUtils::readLe32(bytes, peOffset) != IMAGE_NT_SIGNATURE)
            return 0;

        const size_t optionalOffset = peOffset + sizeof(uint32_t) + sizeof(IMAGE_FILE_HEADER);
        return ByteUtils::readLe16(bytes, optionalOffset + offsetof(IMAGE_OPTIONAL_HEADER64, Subsystem));
    }

    std::vector<std::byte> makeSingleImageIcon(ByteSpan image)
    {
        std::vector<std::byte> bytes;
        ByteUtils::appendLe16(bytes, 0);
        ByteUtils::appendLe16(bytes, 1);
        ByteUtils::appendLe16(bytes, 1);
        bytes.push_back(std::byte{16});
        bytes.push_back(std::byte{16});
        bytes.push_back(std::byte{0});
        bytes.push_back(std::byte{0});
        ByteUtils::appendLe16(bytes, 1);
        ByteUtils::appendLe16(bytes, 32);
        ByteUtils::appendLe32(bytes, static_cast<uint32_t>(image.size()));
        ByteUtils::appendLe32(bytes, 22);
        ByteUtils::appendBytes(bytes, image);
        return bytes;
    }
}

// Hand-builds the smallest meaningful program -- one that calls kernel32!ExitProcess(42) through an
// imported thunk -- writes it to a PE with the internal writer, runs it, and checks the exit code.
// This exercises section layout, the import table/IAT/thunk path, an absolute (Abs64) relocation and
// the matching base relocation end to end, independently of the rest of the compiler.
SWC_FILESYSTEM_TEST_BEGIN(PeWriter_MinimalExecutableCallsExitProcess)
{
    SWC_UNUSED(ctx);

    std::vector<std::byte> text;
    emit(text, {0x48, 0x83, 0xEC, 0x28});       // sub rsp, 0x28
    emit(text, {0xB9, 0x2A, 0x00, 0x00, 0x00}); // mov ecx, 42
    emit(text, {0x48, 0xB8});                   // movabs rax, <ExitProcess thunk>
    const uint32_t relocOffset = static_cast<uint32_t>(text.size());
    emit(text, {0, 0, 0, 0, 0, 0, 0, 0}); // imm64 (addend 0, patched by the linker)
    emit(text, {0xFF, 0xD0});             // call rax
    emit(text, {0xC3});                   // ret

    LinkSection textSection;
    textSection.name  = ".text";
    textSection.bytes = std::move(text);
    textSection.align = 16;
    textSection.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Execute | LinkSectionFlagsE::Read;
    textSection.relocs.push_back({.sectionIndex = 0, .offset = relocOffset, .symbolName = "ExitProcess", .addend = 0, .kind = LinkRelocKind::Abs64});

    LinkImage image;
    image.sections.push_back(std::move(textSection));
    image.symbols.push_back({.name = "entry", .sectionIndex = 0, .value = 0});
    image.imports.push_back({.dll = "kernel32", .importName = "ExitProcess", .symbolName = "ExitProcess", .isData = false});
    image.entrySymbol  = "entry";
    image.kind         = LinkImageKind::Executable;
    image.imageBase    = 0x140000000ull;
    image.stackReserve = 0x100000;

    std::vector<std::byte> peBytes;
    std::vector<std::byte> pdbBytes;
    Diagnostic             diag;
    PEWriter               writer;
    const LinkDebugInfo    noDebugInfo;
    if (!writer.writeImage(peBytes, pdbBytes, diag, image, noDebugInfo, fs::path{}))
    {
        const std::string_view reason = diag.elements().empty() ? std::string_view{"unknown error"} : diag.elements().front()->idName();
        std::println(stderr, "PeWriter test: writeImage failed: {}", reason);
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
        std::println(stderr, "PeWriter test: process did not run (result={})", static_cast<int>(runResult));
        return Result::Error;
    }
    if (exitCode != 42)
    {
        std::println(stderr, "PeWriter test: unexpected exit code {} (expected 42)", exitCode);
        return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(PeWriter_Win32ApplicationResourcesUseConfig)
{
    std::vector<std::byte> text;
    emit(text, {0xC3});

    LinkSection textSection;
    textSection.name  = ".text";
    textSection.bytes = std::move(text);
    textSection.align = 16;
    textSection.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Execute | LinkSectionFlagsE::Read;

    std::vector<std::byte> iconPayload;
    emit(iconPayload, {0x11, 0x22, 0x33, 0x44, 0x55});

    LinkImage image;
    image.sections.push_back(std::move(textSection));
    image.symbols.push_back({.name = "entry", .sectionIndex = 0, .value = 0});
    image.entrySymbol            = "entry";
    image.kind                   = LinkImageKind::Executable;
    image.imageBase              = 0x140000000ull;
    image.stackReserve           = 0x100000;
    image.moduleName             = "patchapp.exe";
    image.win32.subsystem        = LinkWin32Subsystem::Windows;
    image.win32.appName          = "Patch App";
    image.win32.appDescription   = "Patch Description";
    image.win32.appCompany       = "Patch Company";
    image.win32.appCopyright     = "Patch Copyright";
    image.win32.version          = 1;
    image.win32.revision         = 2;
    image.win32.buildNum         = 3;
    image.win32.iconPath         = "patch.ico";
    image.win32.iconBytes        = makeSingleImageIcon(asByteSpan(iconPayload));

    std::vector<std::byte> peBytes;
    std::vector<std::byte> pdbBytes;
    Diagnostic             diag;
    PEWriter               writer;
    const LinkDebugInfo    noDebugInfo;
    if (!writer.writeImage(peBytes, pdbBytes, diag, image, noDebugInfo, fs::path{}))
    {
        const std::string_view reason = diag.elements().empty() ? std::string_view{"unknown error"} : diag.elements().front()->idName();
        std::println(stderr, "PeWriter resource test: writeImage failed: {}", reason);
        return Result::Error;
    }

    const ByteSpan pe = asByteSpan(peBytes);
    if (peSubsystem(pe) != IMAGE_SUBSYSTEM_WINDOWS_GUI)
        return Result::Error;
    if (!containsUtf16Le(pe, "Patch App"))
        return Result::Error;
    if (!containsUtf16Le(pe, "Patch Description"))
        return Result::Error;
    if (!containsUtf16Le(pe, "Patch Company"))
        return Result::Error;
    if (!containsUtf16Le(pe, "Patch Copyright"))
        return Result::Error;
    if (!containsUtf16Le(pe, "1.2.3.0"))
        return Result::Error;
    if (!containsBytes(pe, asByteSpan(iconPayload)))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
