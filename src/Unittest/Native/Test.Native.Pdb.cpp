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
    constexpr uint16_t K_S_PROCREF        = 0x1125;
    constexpr uint16_t K_LF_POINTER       = 0x1002;
    constexpr uint16_t K_LF_FIELDLIST     = 0x1203;
    constexpr uint16_t K_LF_STRUCTURE     = 0x1505;
    constexpr uint16_t K_LF_MEMBER        = 0x150D;
    constexpr uint16_t K_CV_PROP_FORWARD  = 0x0080;
    constexpr uint16_t K_CV_ACCESS_PUBLIC = 0x0003;
    constexpr uint32_t K_CV_PTR_NEAR64    = 0x000C;
    constexpr uint32_t K_T_INT4           = 0x0074;
    constexpr uint32_t K_NODE_FORWARD     = 0x1000;
    constexpr uint32_t K_NODE_POINTER     = 0x1001;
    constexpr uint32_t K_NODE_FIELDS      = 0x1002;
    constexpr uint32_t K_TYPE_INDEX_END   = 0x1004;
    constexpr uint16_t K_NODE_SIZE        = 16;

    void emit(ByteArray& out, std::initializer_list<int> bytes)
    {
        for (const int b : bytes)
            out.pushBack(static_cast<std::byte>(b));
    }

    bool writeFile(const fs::path& path, const ByteArray& bytes)
    {
        std::ofstream file(path, std::ios::binary | std::ios::trunc);
        if (!file.is_open())
            return false;
        file.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
        return file.good();
    }

    uint16_t readU16(const ByteArray& bytes, const size_t offset)
    {
        return bytes.readLe16(offset);
    }

    // Appends one type record, padded to four bytes the way the CodeView writer pads it.
    void appendTypeRecord(ByteArray& records, const uint16_t kind, const ByteArray& payload)
    {
        const size_t start = records.size();
        records.appendLe16(0);
        records.appendLe16(kind);
        records.append(payload);
        for (size_t pad = (4 - (records.size() - start) % 4) % 4; pad > 0; --pad)
            records.pushBack(static_cast<std::byte>(0xF0 + pad));
        records.writeLe16(start, static_cast<uint16_t>(records.size() - start - sizeof(uint16_t)));
    }

    ByteArray structurePayload(const uint16_t memberCount, const uint16_t properties, const uint32_t fieldList, const uint16_t size, const std::string_view name)
    {
        ByteArray payload;
        payload.appendLe16(memberCount);
        payload.appendLe16(properties);
        payload.appendLe32(fieldList);
        payload.appendLe32(0); // derivation list
        payload.appendLe32(0); // vtable shape
        payload.appendLe16(size);
        payload.appendCString(name);
        return payload;
    }

    void appendMember(ByteArray& fields, const uint32_t typeIndex, const uint16_t offset, const std::string_view name)
    {
        fields.appendLe16(K_LF_MEMBER);
        fields.appendLe16(K_CV_ACCESS_PUBLIC);
        fields.appendLe32(typeIndex);
        fields.appendLe16(offset);
        fields.appendCString(name);
    }

    // A structure that points at itself names its own forward declaration. A debugger replaces that
    // declaration with the definition it finds in the bucket its name hashes to.
    ByteArray selfReferencingNodeTypes()
    {
        ByteArray records;
        appendTypeRecord(records, K_LF_STRUCTURE, structurePayload(0, K_CV_PROP_FORWARD, 0, 0, "Node"));

        ByteArray pointer;
        pointer.appendLe32(K_NODE_FORWARD);
        pointer.appendLe32(K_CV_PTR_NEAR64);
        appendTypeRecord(records, K_LF_POINTER, pointer);

        ByteArray fields;
        appendMember(fields, K_NODE_POINTER, 0, "next");
        appendMember(fields, K_T_INT4, 8, "value");
        appendTypeRecord(records, K_LF_FIELDLIST, fields);

        appendTypeRecord(records, K_LF_STRUCTURE, structurePayload(2, 0, K_NODE_FIELDS, K_NODE_SIZE, "Node"));
        return records;
    }

    bool pdbContainsSymbolRecord(const ByteArray& bytes, const uint16_t kind, const std::string_view name)
    {
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

            const std::string_view recordBytes{reinterpret_cast<const char*>(bytes.data() + offset), recordEnd - offset};
            if (recordBytes.contains(name))
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

    ByteArray text;
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
    dataSection.bytes = ByteArray(8, std::byte{0});
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

    constexpr uint16_t cvRegRsp = 335;

    const fs::path  dir = fs::temp_directory_path() / "swc_pdb_test";
    std::error_code ec;
    fs::create_directories(dir, ec);
    const fs::path exePath   = dir / "pdbtest.exe";
    const fs::path pdbPath   = dir / "pdbtest.pdb";
    const fs::path srcPath   = dir / "pdbtest.swg";
    const fs::path macroPath = dir / "pdbmacro.swg";

    LinkDebugInfo dbg;
    dbg.enabled     = true;
    dbg.tpiRecords  = selfReferencingNodeTypes();
    dbg.tpiIndexEnd = K_TYPE_INDEX_END;
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
    fn.locals.push_back({.name = "myLocal", .typeIndex = K_T_INT4, .frameOffset = 0x20, .cvRegister = cvRegRsp, .isParam = false});
    fn.locals.push_back({.name = "myNode", .typeIndex = K_NODE_POINTER, .frameOffset = 0x18, .cvRegister = cvRegRsp, .isParam = false});
    dbg.functions.push_back(std::move(fn));

    LinkDebugGlobal global;
    global.sectionName   = ".data";
    global.sectionOffset = 0;
    global.displayName   = "myGlobal";
    global.typeIndex     = K_T_INT4;
    global.isPublic      = true;
    dbg.globals.push_back(std::move(global));

    ByteArray  peBytes;
    ByteArray  pdbBytes;
    Diagnostic diag;
    PEWriter   writer;
    if (!writer.writeImage(peBytes, pdbBytes, diag, image, dbg, pdbPath))
    {
        std::println(stderr, "[pdb-test] image writer did not produce a PDB");
        return Result::Error;
    }
    if (pdbBytes.empty())
    {
        std::println(stderr, "[pdb-test] image writer produced no PDB bytes");
        return Result::Error;
    }
    if (!pdbContainsSymbolRecord(pdbBytes, K_S_PROCREF, "myFunc"))
    {
        std::println(stderr, "[pdb-test] function procedure reference is missing from globals");
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
        std::println(stderr, "[pdb-test] SymInitialize returned error {}", GetLastError());
        return Result::Error;
    }

    auto       result   = Result::Continue;
    const auto exePathU = Utf8(exePath);
    // Pass size 0 so dbghelp reads SizeOfImage (the virtual size) from the PE header rather than the
    // smaller on-disk byte count, which would exclude .text's virtual address from the module range.
    const DWORD64 modBase = SymLoadModuleEx(symHandle, nullptr, exePathU.c_str(), nullptr, imageBase, 0, nullptr, 0);

    const auto fail = [&](std::string_view msg) {
        std::println(stderr, "[pdb-test] {} (error {})", msg, GetLastError());
        result = Result::Error;
    };

    if (modBase == 0)
    {
        fail("SymLoadModuleEx returned an error");
    }
    else
    {
        alignas(SYMBOL_INFO) std::array<std::byte, sizeof(SYMBOL_INFO) + MAX_SYM_NAME> symBuffer{};
        auto*                                                                          symbol = reinterpret_cast<SYMBOL_INFO*>(symBuffer.data());
        symbol->SizeOfStruct                                                                  = sizeof(SYMBOL_INFO);
        symbol->MaxNameLen                                                                    = MAX_SYM_NAME;

        // Name -> address.
        if (result == Result::Continue && !SymFromName(symHandle, "myFunc", symbol))
            fail("SymFromName(myFunc) returned an error");

        const DWORD64 funcAddr = symbol->Address;

        // Address -> name.
        if (result == Result::Continue)
        {
            DWORD64 disp         = 0;
            symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
            symbol->MaxNameLen   = MAX_SYM_NAME;
            if (!SymFromAddr(symHandle, funcAddr, &disp, symbol))
                fail("SymFromAddr returned an error");
            else if (std::string_view{symbol->Name, symbol->NameLen} != "myFunc")
                fail("SymFromAddr returned a name that does not match myFunc");
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
                fail("SymGetLineFromAddr64 did not return the expected source file name");

            line              = {};
            line.SizeOfStruct = sizeof(line);
            if (result == Result::Continue && (!SymGetLineFromAddr64(symHandle, funcAddr + 4, &lineDisp, &line) || line.LineNumber != 20))
                fail("SymGetLineFromAddr64 at +4 did not return macro line 20");
            else if (result == Result::Continue && (line.FileName == nullptr || std::string_view{line.FileName} != Utf8(macroPath).view()))
                fail("SymGetLineFromAddr64 at +4 did not return the expected macro source file name");

            line              = {};
            line.SizeOfStruct = sizeof(line);
            if (result == Result::Continue && (!SymGetLineFromAddr64(symHandle, funcAddr + 8, &lineDisp, &line) || line.LineNumber != 11))
                fail("SymGetLineFromAddr64 at +8 did not return line 11");
            else if (result == Result::Continue && (line.FileName == nullptr || std::string_view{line.FileName} != Utf8(srcPath).view()))
                fail("SymGetLineFromAddr64 at +8 did not return the expected source file name");
        }

        // Global data symbol -> resolves by name (exercises the globals stream / GSI hash) with its type.
        if (result == Result::Continue)
        {
            symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
            symbol->MaxNameLen   = MAX_SYM_NAME;
            if (!SymFromName(symHandle, "myGlobal", symbol))
                fail("SymFromName(myGlobal) returned an error");
            else if (symbol->TypeIndex == 0)
                fail("myGlobal has no type index");
        }

        // Local variable -> enumerated in the function's scope (exercises S_REGREL32 + module stream).
        if (result == Result::Continue)
        {
            IMAGEHLP_STACK_FRAME frame{};
            frame.InstructionOffset = funcAddr;
            SymSetContext(symHandle, &frame, nullptr);

            struct ScopeLocals
            {
                bool  foundLocal = false;
                ULONG nodeTypeId = 0;
                bool  foundNode  = false;
            };

            ScopeLocals scope;
            const auto  localCb = [](PSYMBOL_INFO sym, ULONG, PVOID ctx1) -> BOOL {
                auto&                  found = *static_cast<ScopeLocals*>(ctx1);
                const std::string_view name{sym->Name, sym->NameLen};
                if (name == "myLocal")
                    found.foundLocal = true;
                if (name == "myNode")
                {
                    found.foundNode  = true;
                    found.nodeTypeId = sym->TypeIndex;
                }
                return TRUE;
            };
            SymEnumSymbols(symHandle, 0, "*", localCb, &scope);
            if (!scope.foundLocal)
                fail("local variable myLocal was not enumerated in scope");
            else if (!scope.foundNode)
                fail("local variable myNode was not enumerated in scope");

            // The pointer names the forward declaration; the debugger has to reach the definition.
            ULONG   pointee  = 0;
            DWORD   children = 0;
            ULONG64 length   = 0;
            if (result == Result::Continue && !SymGetTypeInfo(symHandle, modBase, scope.nodeTypeId, TI_GET_TYPEID, &pointee))
                fail("myNode has no pointee type");
            else if (result == Result::Continue && (!SymGetTypeInfo(symHandle, modBase, pointee, TI_GET_LENGTH, &length) || length != K_NODE_SIZE))
                fail("the forward declaration of Node did not resolve to its definition's size");
            else if (result == Result::Continue && (!SymGetTypeInfo(symHandle, modBase, pointee, TI_GET_CHILDRENCOUNT, &children) || children != 2))
                fail("the forward declaration of Node did not resolve to its definition's fields");
        }
    }

    SymCleanup(symHandle);
    cleanup();
    return result;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
