#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Linker/PeWriter.h"
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

    uint32_t                   exitCode = 0;
    const std::vector<Utf8>    args;
    const Os::ProcessRunResult runResult = Os::runProcess(exitCode, exePath, args, dir, nullptr);

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

SWC_END_NAMESPACE();

#endif
