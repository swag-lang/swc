#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Linker/PeWriter.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Unittest/Unittest.h"

#include <dbghelp.h>
#pragma comment(lib, "Dbghelp.lib")

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint16_t K_S_PROCREF = 0x1125;

    void emit(std::vector<std::byte>& out, std::initializer_list<int> bytes)
    {
        for (const int b : bytes)
            out.push_back(static_cast<std::byte>(b));
    }

    bool writeFile(const fs::path& path, const std::vector<std::byte>& bytes)
    {
        std::ofstream file(path, std::ios::binary | std::ios::trunc);
        if (!file.is_open())
            return false;
        file.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
        return file.good();
    }

    uint16_t readU16(const std::vector<std::byte>& bytes, const size_t offset)
    {
        uint16_t value = 0;
        std::memcpy(&value, bytes.data() + offset, sizeof(value));
        return value;
    }

    bool pdbContainsSymbolRecord(const std::vector<std::byte>& bytes, const uint16_t kind, const std::string_view name)
    {
        const ByteSpan needle = asByteSpan(name);
        for (size_t offset = 0; offset + sizeof(uint16_t) * 2 <= bytes.size(); ++offset)
        {
            const uint16_t recordSize = readU16(bytes, offset);
            if (recordSize < sizeof(uint16_t))
                continue;

            const size_t recordEnd = offset + sizeof(uint16_t) + recordSize;
            if (recordEnd > bytes.size())
                continue;
            if (readU16(bytes, offset + sizeof(uint16_t)) != kind)
                continue;

            const ByteSpan recordBytes{bytes.data() + offset, recordEnd - offset};
            if (containsBytes(recordBytes, needle))
                return true;
        }

        return false;
    }
}

// Builds a tiny executable plus its PDB through the internal writer, then loads them with dbghelp -- the
// same symbol API Visual Studio and external profilers (e.g. Superluminal) use -- and checks that a
// function resolves by name, that an address resolves back to that name, and that source line numbers are
// recovered. This validates the whole PDB container/stream layout end to end against a real consumer.
SWC_FILESYSTEM_TEST_BEGIN(Pdb_DbgHelpResolvesNamesAndLines)
{
    SWC_UNUSED(ctx);

    constexpr uint64_t imageBase = 0x140000000ull;

    std::vector<std::byte> text;
    emit(text, {0x48, 0x83, 0xEC, 0x28}); // sub rsp, 0x28   (line 10)
    emit(text, {0xB8, 0x2A, 0x00, 0x00}); // mov eax, ...    (macro line 20)
    emit(text, {0x90, 0x90, 0x90, 0x90}); //                 (line 11)
    emit(text, {0x48, 0x83, 0xC4, 0x28}); // add rsp, 0x28   (line 11)
    emit(text, {0xC3});                   // ret             (line 12)
    const auto codeSize = static_cast<uint32_t>(text.size());

    LinkSection textSection;
    textSection.name  = ".text";
    textSection.bytes = std::move(text);
    textSection.align = 16;
    textSection.flags = LinkSectionFlagsE::Code | LinkSectionFlagsE::Execute | LinkSectionFlagsE::Read;

    LinkSection dataSection;
    dataSection.name  = ".data";
    dataSection.bytes = std::vector(8, std::byte{0});
    dataSection.align = 8;
    dataSection.flags = LinkSectionFlagsE::Read | LinkSectionFlagsE::Write;

    LinkImage image;
    image.sections.push_back(std::move(textSection));
    image.sections.push_back(std::move(dataSection));
    image.symbols.push_back({.name = "myFunc", .sectionIndex = 0, .value = 0});
    image.entrySymbol  = "myFunc";
    image.kind         = LinkImageKind::Executable;
    image.imageBase    = imageBase;
    image.stackReserve = 0x100000;

    constexpr uint32_t tInt4    = 0x0074; // CodeView primitive: 32-bit signed int (no TPI record needed)
    constexpr uint16_t cvRegRsp = 335;

    const fs::path  dir = fs::temp_directory_path() / "swc_pdb_test";
    std::error_code ec;
    fs::create_directories(dir, ec);
    const fs::path exePath   = dir / "pdbtest.exe";
    const fs::path pdbPath   = dir / "pdbtest.pdb";
    const fs::path srcPath   = dir / "pdbtest.swg";
    const fs::path macroPath = dir / "pdbmacro.swg";

    LinkDebugInfo dbg;
    dbg.enabled = true;
    LinkDebugFile dbgFile;
    dbgFile.path         = Utf8(srcPath);
    dbgFile.checksumKind = 3; // SHA-256
    dbgFile.checksum.assign(32, 0xAB);
    dbg.files.push_back(std::move(dbgFile));
    LinkDebugFile macroFile;
    macroFile.path         = Utf8(macroPath);
    macroFile.checksumKind = 3; // SHA-256
    macroFile.checksum.assign(32, 0xCD);
    dbg.files.push_back(std::move(macroFile));
    LinkDebugFunction fn;
    fn.symbolName  = "myFunc";
    fn.displayName = "myFunc";
    fn.codeSize    = codeSize;
    LinkDebugLineBlock block;
    block.fileIndex   = 0;
    block.codeOffsets = {0};
    block.lines       = {10};
    fn.lineBlocks.push_back(std::move(block));
    LinkDebugLineBlock macroBlock;
    macroBlock.fileIndex   = 1;
    macroBlock.codeOffsets = {4};
    macroBlock.lines       = {20};
    fn.lineBlocks.push_back(std::move(macroBlock));
    LinkDebugLineBlock tailBlock;
    tailBlock.fileIndex   = 0;
    tailBlock.codeOffsets = {8, 16};
    tailBlock.lines       = {11, 12};
    fn.lineBlocks.push_back(std::move(tailBlock));
    fn.locals.push_back({.name = "myLocal", .typeIndex = tInt4, .frameOffset = 0x20, .cvRegister = cvRegRsp, .isParam = false});
    dbg.functions.push_back(std::move(fn));

    LinkDebugGlobal global;
    global.sectionName   = ".data";
    global.sectionOffset = 0;
    global.displayName   = "myGlobal";
    global.typeIndex     = tInt4;
    global.isPublic      = true;
    dbg.globals.push_back(std::move(global));

    std::vector<std::byte> peBytes;
    std::vector<std::byte> pdbBytes;
    Diagnostic             diag;
    PEWriter               writer;
    if (!writer.writeImage(peBytes, pdbBytes, diag, image, dbg, pdbPath))
    {
        std::println(stderr, "Pdb test: writeImage failed");
        return Result::Error;
    }
    if (pdbBytes.empty())
    {
        std::println(stderr, "Pdb test: no PDB bytes produced");
        return Result::Error;
    }
    if (!pdbContainsSymbolRecord(pdbBytes, K_S_PROCREF, "myFunc"))
    {
        std::println(stderr, "Pdb test: function procedure reference is missing from globals");
        return Result::Error;
    }

    const auto cleanup = [&] {
        fs::remove(exePath, ec);
        fs::remove(pdbPath, ec);
    };

    if (!writeFile(exePath, peBytes) || !writeFile(pdbPath, pdbBytes))
    {
        cleanup();
        return Result::Error;
    }

    // Load the image + PDB through dbghelp under a private symbol handle so we do not disturb the
    // process-wide handler the runtime installs.
    const auto symHandle = reinterpret_cast<HANDLE>(static_cast<uintptr_t>(0xC0FFEE));
    SymSetOptions(SYMOPT_LOAD_LINES | SYMOPT_UNDNAME);
    if (!SymInitialize(symHandle, nullptr, FALSE))
    {
        cleanup();
        std::println(stderr, "Pdb test: SymInitialize failed ({})", GetLastError());
        return Result::Error;
    }

    auto       result   = Result::Continue;
    const auto exePathU = Utf8(exePath);
    // Pass size 0 so dbghelp reads SizeOfImage (the virtual size) from the PE header rather than the
    // smaller on-disk byte count, which would exclude .text's virtual address from the module range.
    const DWORD64 modBase = SymLoadModuleEx(symHandle, nullptr, exePathU.c_str(), nullptr, imageBase, 0, nullptr, 0);

    const auto fail = [&](std::string_view msg) {
        std::println(stderr, "Pdb test: {} (err={})", msg, GetLastError());
        result = Result::Error;
    };

    if (modBase == 0)
    {
        fail("SymLoadModuleEx failed");
    }
    else
    {
        alignas(SYMBOL_INFO) std::array<std::byte, sizeof(SYMBOL_INFO) + MAX_SYM_NAME> symBuffer{};
        auto*                                                                          symbol = reinterpret_cast<SYMBOL_INFO*>(symBuffer.data());
        symbol->SizeOfStruct                                                                  = sizeof(SYMBOL_INFO);
        symbol->MaxNameLen                                                                    = MAX_SYM_NAME;

        // Name -> address.
        if (result == Result::Continue && !SymFromName(symHandle, "myFunc", symbol))
            fail("SymFromName(myFunc) failed");

        const DWORD64 funcAddr = symbol->Address;

        // Address -> name.
        if (result == Result::Continue)
        {
            DWORD64 disp         = 0;
            symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
            symbol->MaxNameLen   = MAX_SYM_NAME;
            if (!SymFromAddr(symHandle, funcAddr, &disp, symbol))
                fail("SymFromAddr failed");
            else if (std::string_view{symbol->Name, symbol->NameLen} != "myFunc")
                fail("SymFromAddr returned the wrong name");
        }

        // Address -> source line, including a repeated source file block after an interleaved macro file.
        if (result == Result::Continue)
        {
            IMAGEHLP_LINE64 line{};
            line.SizeOfStruct = sizeof(line);
            DWORD lineDisp    = 0;
            if (!SymGetLineFromAddr64(symHandle, funcAddr, &lineDisp, &line) || line.LineNumber != 10)
                fail("SymGetLineFromAddr64 at start did not return line 10");
            // The source file name must resolve too (regression guard: line numbers can resolve while the
            // file name comes back empty if the checksum/names wiring is broken, which hides source in
            // profilers like Superluminal).
            else if (line.FileName == nullptr || std::string_view{line.FileName} != Utf8(srcPath).view())
                fail("SymGetLineFromAddr64 returned the wrong/empty source file name");

            line              = {};
            line.SizeOfStruct = sizeof(line);
            if (result == Result::Continue && (!SymGetLineFromAddr64(symHandle, funcAddr + 4, &lineDisp, &line) || line.LineNumber != 20))
                fail("SymGetLineFromAddr64 at +4 did not return macro line 20");
            else if (result == Result::Continue && (line.FileName == nullptr || std::string_view{line.FileName} != Utf8(macroPath).view()))
                fail("SymGetLineFromAddr64 at +4 returned the wrong/empty macro source file name");

            line              = {};
            line.SizeOfStruct = sizeof(line);
            if (result == Result::Continue && (!SymGetLineFromAddr64(symHandle, funcAddr + 8, &lineDisp, &line) || line.LineNumber != 11))
                fail("SymGetLineFromAddr64 at +8 did not return line 11");
            else if (result == Result::Continue && (line.FileName == nullptr || std::string_view{line.FileName} != Utf8(srcPath).view()))
                fail("SymGetLineFromAddr64 at +8 returned the wrong/empty source file name");
        }

        // Global data symbol -> resolves by name (exercises the globals stream / GSI hash) with its type.
        if (result == Result::Continue)
        {
            symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
            symbol->MaxNameLen   = MAX_SYM_NAME;
            if (!SymFromName(symHandle, "myGlobal", symbol))
                fail("SymFromName(myGlobal) failed");
            else if (symbol->TypeIndex == 0)
                fail("myGlobal has no type index");
        }

        // Local variable -> enumerated in the function's scope (exercises S_REGREL32 + module stream).
        if (result == Result::Continue)
        {
            IMAGEHLP_STACK_FRAME frame{};
            frame.InstructionOffset = funcAddr;
            SymSetContext(symHandle, &frame, nullptr);

            bool       foundLocal = false;
            const auto localCb    = [](PSYMBOL_INFO sym, ULONG, PVOID ctx1) -> BOOL {
                if (std::string_view{sym->Name, sym->NameLen} == "myLocal")
                    *static_cast<bool*>(ctx1) = true;
                return TRUE;
            };
            SymEnumSymbols(symHandle, 0, "*", localCb, &foundLocal);
            if (!foundLocal)
                fail("local variable myLocal was not enumerated in scope");
        }
    }

    SymCleanup(symHandle);
    cleanup();
    return result;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
