#include "pch.h"
#include "Backend/Linker/PEWriter.h"
#include "Backend/Linker/Archive.h"
#include "Backend/Linker/PdbWriter.h"
#include "Main/Version.h"
#include "Support/Core/ByteUtils.h"
#include "Support/Math/Helpers.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t SECTION_ALIGNMENT = 0x1000;
    constexpr uint32_t FILE_ALIGNMENT    = 0x200;

    // The PDB path is embedded both in the exe's RSDS debug-directory record and in the PDB header.
    // Emit it with native (backslash) separators like link.exe does: a forward-slash path built from a
    // forward-slash workspace argument can stop Visual Studio from loading the module's symbols.
    // (Utf8(fs::path) goes through generic_string(), which forces forward slashes, so convert here.)
    Utf8 nativePdbPathString(const fs::path& pdbPath)
    {
        auto result = Utf8(pdbPath);
        std::ranges::replace(result, '/', '\\');
        return result;
    }

    uint32_t sectionCharacteristics(std::string_view name)
    {
        if (name == ".text")
            return IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_READ;
        if (name == ".data")
            return IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE;
        if (name == ".bss")
            return IMAGE_SCN_CNT_UNINITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE;
        if (name == ".reloc")
            return IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_DISCARDABLE;
        return IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ;
    }

    uint32_t peHeadersSize(uint32_t sectionCount)
    {
        const size_t headersSize = sizeof(IMAGE_DOS_HEADER) + sizeof(uint32_t) + sizeof(IMAGE_FILE_HEADER) + sizeof(IMAGE_OPTIONAL_HEADER64) + sectionCount * sizeof(IMAGE_SECTION_HEADER);
        return Math::alignUpU32(static_cast<uint32_t>(headersSize), FILE_ALIGNMENT);
    }

    int sectionLayoutRank(std::string_view name)
    {
        if (name == ".text")
            return 0;
        if (name == ".data")
            return 3;
        if (name == ".bss")
            return 4;
        if (name == ".reloc")
            return 5;
        return 2;
    }

    Utf8 normalizedDllName(const Utf8& dll)
    {
        if (dll.view().find('.') != std::string_view::npos)
            return dll;
        Utf8 out = dll;
        out += ".dll";
        return out;
    }

    bool exportNameLess(const LinkExport* left, const LinkExport* right)
    {
        return left->name.view() < right->name.view();
    }

    // Writes a section-relative RVA placeholder and records its position so applyRelocations can rebase
    // it to an image RVA once the owning section's RVA is known.
    void writeRvaFixup(std::vector<std::byte>& bytes, std::vector<uint32_t>& fixups, uint32_t offset, uint32_t value)
    {
        ByteUtils::writeLe32(bytes, offset, value);
        fixups.push_back(offset);
    }

    // Adds the section RVA to every recorded fixup site, turning section-relative offsets into image RVAs.
    void rebaseRvaFixups(std::vector<std::byte>& bytes, const std::vector<uint32_t>& fixups, uint32_t rva)
    {
        for (const uint32_t fixup : fixups)
            ByteUtils::writeLe32(bytes, fixup, ByteUtils::readLe32(asByteSpan(bytes), fixup) + rva);
    }
}

uint32_t PEWriter::resolveSymbolRva(bool& outFound, const Utf8& name) const
{
    const auto it = symbols_.find(name);
    if (it == symbols_.end())
    {
        outFound = false;
        return 0;
    }
    outFound = true;
    return sections_[it->second.sectionIndex].rva + it->second.value;
}

void PEWriter::buildImports()
{
    if (image_->imports.empty())
        return;

    // Group imports by DLL, preserving first-seen order.
    std::vector<Utf8>                                        dllOrder;
    std::unordered_map<Utf8, std::vector<const LinkImport*>> byDll;
    for (const LinkImport& imp : image_->imports)
    {
        const Utf8 dll = normalizedDllName(imp.dll);
        if (!byDll.contains(dll))
            dllOrder.push_back(dll);
        byDll[dll].push_back(&imp);
    }

    // Append a 6-byte indirect-jump thunk per imported function to .text. The referencing code
    // takes the address of the plain symbol, so it must resolve to this thunk.
    OutSection& text = sections_[textIndex_];
    for (const Utf8& dll : dllOrder)
    {
        for (const LinkImport* imp : byDll[dll])
        {
            if (text.bytes.size() % 16 != 0)
                text.bytes.resize(Math::alignUpU32(static_cast<uint32_t>(text.bytes.size()), 16), std::byte{0});

            ImportThunk thunk;
            thunk.import     = imp;
            thunk.textOffset = static_cast<uint32_t>(text.bytes.size());
            text.bytes.insert(text.bytes.end(), 6, std::byte{0}); // FF 25 <disp32>, filled after layout
            thunks_.push_back(thunk);

            symbols_[imp->symbolName] = {static_cast<uint32_t>(textIndex_), thunk.textOffset};
        }
    }

    // Build the .idata section: import descriptors, ILTs, IATs, hint/name table and DLL names.
    std::vector<std::byte> idata;
    const uint32_t         descCount = static_cast<uint32_t>(dllOrder.size());

    // Reserve the import directory table (+1 null terminator).
    constexpr uint32_t descTableOffset = 0;
    idata.resize(static_cast<size_t>(descCount + 1) * sizeof(IMAGE_IMPORT_DESCRIPTOR), std::byte{0});

    struct DllLayout
    {
        uint32_t iltOffset = 0;
        uint32_t iatOffset = 0;
    };
    std::vector<DllLayout> dllLayouts(descCount);

    // ILTs.
    for (uint32_t d = 0; d < descCount; ++d)
    {
        dllLayouts[d].iltOffset = static_cast<uint32_t>(idata.size());
        idata.resize(idata.size() + (byDll[dllOrder[d]].size() + 1) * sizeof(uint64_t), std::byte{0});
    }

    // IATs (the loader patches these in place; they start as a copy of the ILT contents).
    iatRva_                                                        = 0; // resolved to an RVA after layout
    const uint32_t                                  iatStartOffset = static_cast<uint32_t>(idata.size());
    std::unordered_map<const LinkImport*, uint32_t> iatEntryOffset;
    for (uint32_t d = 0; d < descCount; ++d)
    {
        dllLayouts[d].iatOffset = static_cast<uint32_t>(idata.size());
        for (const LinkImport* imp : byDll[dllOrder[d]])
        {
            iatEntryOffset[imp] = static_cast<uint32_t>(idata.size());
            idata.resize(idata.size() + sizeof(uint64_t), std::byte{0});
        }
        idata.resize(idata.size() + sizeof(uint64_t), std::byte{0}); // null terminator
    }
    const uint32_t iatEndOffset = static_cast<uint32_t>(idata.size());

    // Hint/name entries, shared by ILT and IAT.
    std::unordered_map<const LinkImport*, uint32_t> hintNameOffset;
    for (const Utf8& dll : dllOrder)
    {
        for (const LinkImport* imp : byDll[dll])
        {
            if (imp->byOrdinal)
                continue; // imported by ordinal: no hint/name entry
            hintNameOffset[imp] = static_cast<uint32_t>(idata.size());
            ByteUtils::appendLe16(idata, 0); // hint
            ByteUtils::appendCString(idata, imp->importName.view());
            if (idata.size() % 2 != 0)
                idata.push_back(std::byte{0});
        }
    }

    // DLL name strings.
    std::unordered_map<Utf8, uint32_t> dllNameOffset;
    for (const Utf8& dll : dllOrder)
    {
        dllNameOffset[dll] = static_cast<uint32_t>(idata.size());
        ByteUtils::appendCString(idata, dll.view());
        if (idata.size() % 2 != 0)
            idata.push_back(std::byte{0});
    }

    // Fill ILT and IAT entries (offsets to hint/name; fixed up to RVAs after layout).
    for (uint32_t d = 0; d < descCount; ++d)
    {
        uint32_t iltCursor = dllLayouts[d].iltOffset;
        uint32_t iatCursor = dllLayouts[d].iatOffset;
        for (const LinkImport* imp : byDll[dllOrder[d]])
        {
            if (imp->byOrdinal)
            {
                const uint64_t entry = 0x8000000000000000ull | imp->ordinal;
                ByteUtils::writeLe64(idata, iltCursor, entry);
                ByteUtils::writeLe64(idata, iatCursor, entry);
            }
            else
            {
                ByteUtils::writeLe64(idata, iltCursor, hintNameOffset[imp]);
                idataRvaFixups_.push_back(iltCursor);
                ByteUtils::writeLe64(idata, iatCursor, hintNameOffset[imp]);
                idataRvaFixups_.push_back(iatCursor);
            }
            iltCursor += sizeof(uint64_t);
            iatCursor += sizeof(uint64_t);
        }
    }

    // Fill the import descriptors.
    for (uint32_t d = 0; d < descCount; ++d)
    {
        const uint32_t base = descTableOffset + d * sizeof(IMAGE_IMPORT_DESCRIPTOR);
        writeRvaFixup(idata, idataRvaFixups_, base + 0, dllLayouts[d].iltOffset);     // OriginalFirstThunk
        writeRvaFixup(idata, idataRvaFixups_, base + 12, dllNameOffset[dllOrder[d]]); // Name
        writeRvaFixup(idata, idataRvaFixups_, base + 16, dllLayouts[d].iatOffset);    // FirstThunk
    }

    // Record the IAT slot offset each thunk references (the import was captured when the thunk was built).
    for (ImportThunk& thunk : thunks_)
        thunk.iatSlotInIdata = iatEntryOffset[thunk.import];

    OutSection idataSection;
    idataSection.name        = ".idata";
    idataSection.bytes       = std::move(idata);
    idataSection.virtualSize = static_cast<uint32_t>(idataSection.bytes.size());
    idataSection.align       = 4;
    idataIndex_              = static_cast<int32_t>(sections_.size());
    sections_.push_back(std::move(idataSection));

    importDirRva_  = 0; // resolved after layout
    importDirSize_ = (descCount + 1) * sizeof(IMAGE_IMPORT_DESCRIPTOR);
    iatSize_       = iatEndOffset - iatStartOffset;
    // iatStartOffset is the offset of the first IAT within .idata.
    iatRva_       = iatStartOffset; // becomes an RVA after layout (add idata rva)
    importDirRva_ = descTableOffset;
}

void PEWriter::buildExports()
{
    if (image_->kind != LinkImageKind::SharedLibrary || image_->exports.empty())
        return;

    // Export names must be sorted for the name-pointer table (the loader binary-searches it).
    std::vector<const LinkExport*> sorted;
    sorted.reserve(image_->exports.size());
    for (const LinkExport& e : image_->exports)
        sorted.push_back(&e);
    std::ranges::sort(sorted, exportNameLess);

    const uint32_t count = static_cast<uint32_t>(sorted.size());

    std::vector<std::byte> edata;
    edata.resize(40, std::byte{0}); // IMAGE_EXPORT_DIRECTORY

    const uint32_t eatOffset = static_cast<uint32_t>(edata.size());
    for (uint32_t i = 0; i < count; ++i)
    {
        eatSymbolFixups_.emplace_back(static_cast<uint32_t>(edata.size()), sorted[i]->symbolName);
        ByteUtils::appendLe32(edata, 0); // filled with the exported symbol RVA after layout
    }

    const uint32_t nptOffset = static_cast<uint32_t>(edata.size());
    edata.resize(edata.size() + static_cast<size_t>(count) * sizeof(uint32_t), std::byte{0});

    const uint32_t ordinalOffset = static_cast<uint32_t>(edata.size());
    for (uint32_t i = 0; i < count; ++i)
        ByteUtils::appendLe16(edata, static_cast<uint16_t>(i));

    // Name strings, then the module name.
    std::vector<uint32_t> nameOffsets(count);
    for (uint32_t i = 0; i < count; ++i)
    {
        nameOffsets[i] = static_cast<uint32_t>(edata.size());
        ByteUtils::appendCString(edata, sorted[i]->name.view());
    }
    const uint32_t         dllNameOffset = static_cast<uint32_t>(edata.size());
    const std::string_view exportModule  = image_->moduleName.empty() ? std::string_view{"module.dll"} : image_->moduleName.view();
    ByteUtils::appendCString(edata, exportModule);

    // Fill the name-pointer table with RVAs of the name strings (relocated after layout).
    for (uint32_t i = 0; i < count; ++i)
        writeRvaFixup(edata, edataRvaFixups_, nptOffset + i * sizeof(uint32_t), nameOffsets[i]);

    // Fill IMAGE_EXPORT_DIRECTORY.
    writeRvaFixup(edata, edataRvaFixups_, 12, dllNameOffset);
    ByteUtils::writeLe32(edata, 16, 1);     // Base ordinal
    ByteUtils::writeLe32(edata, 20, count); // NumberOfFunctions
    ByteUtils::writeLe32(edata, 24, count); // NumberOfNames
    writeRvaFixup(edata, edataRvaFixups_, 28, eatOffset);
    writeRvaFixup(edata, edataRvaFixups_, 32, nptOffset);
    writeRvaFixup(edata, edataRvaFixups_, 36, ordinalOffset);

    OutSection section;
    section.name        = ".edata";
    section.bytes       = std::move(edata);
    section.virtualSize = static_cast<uint32_t>(section.bytes.size());
    section.align       = 4;
    edataIndex_         = static_cast<int32_t>(sections_.size());
    sections_.push_back(std::move(section));
}

void PEWriter::assignLayout()
{
    // Non-bss sections grow up to here (e.g. .text gained import thunks); keep virtual sizes current.
    for (OutSection& section : sections_)
    {
        if (!section.isBss)
            section.virtualSize = static_cast<uint32_t>(section.bytes.size());
    }

    // A .reloc section is appended after this layout pass whenever absolute relocations exist; it
    // must be counted now so the header size (and therefore every section RVA) stays stable.
    bool willHaveReloc = false;
    for (const LinkSection& src : image_->sections)
    {
        for (const LinkReloc& reloc : src.relocs)
        {
            if (reloc.kind == LinkRelocKind::Abs64)
            {
                willHaveReloc = true;
                break;
            }
        }
        if (willHaveReloc)
            break;
    }

    // Header size (DOS header + PE signature + file header + optional header + section table).
    const uint32_t sectionCount = static_cast<uint32_t>(sections_.size()) + (willHaveReloc ? 1u : 0u);
    const uint32_t headersSize  = peHeadersSize(sectionCount);
    headersSize_                = headersSize;

    std::vector<uint32_t> order(sections_.size());
    std::ranges::iota(order, 0u);
    std::ranges::stable_sort(order, [this](uint32_t left, uint32_t right) {
        return sectionLayoutRank(sections_[left].name.view()) < sectionLayoutRank(sections_[right].name.view());
    });

    uint32_t rva        = Math::alignUpU32(headersSize, SECTION_ALIGNMENT);
    uint32_t fileOffset = headersSize;
    for (const uint32_t idx : order)
    {
        OutSection& section = sections_[idx];
        section.rva         = rva;
        if (section.isBss)
        {
            section.fileOffset = 0;
            section.rawSize    = 0;
        }
        else
        {
            section.fileOffset = fileOffset;
            section.rawSize    = Math::alignUpU32(static_cast<uint32_t>(section.bytes.size()), FILE_ALIGNMENT);
            fileOffset += section.rawSize;
        }
        rva += Math::alignUpU32(section.virtualSize, SECTION_ALIGNMENT);
    }
}

bool PEWriter::applyRelocations(Diagnostic& outDiag)
{
    for (size_t imageIdx = 0; imageIdx < image_->sections.size(); ++imageIdx)
    {
        const LinkSection& src = image_->sections[imageIdx];
        OutSection&        out = sections_[imageToOut_[imageIdx]];
        for (const LinkReloc& reloc : src.relocs)
        {
            bool           found     = false;
            const uint32_t targetRva = resolveSymbolRva(found, reloc.symbolName);
            if (!found)
            {
                outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_unresolved_symbol);
                outDiag.addArgument(Diagnostic::ARG_SYM, reloc.symbolName);
                return false;
            }

            switch (reloc.kind)
            {
                case LinkRelocKind::Abs64:
                {
                    if (reloc.offset + sizeof(uint64_t) > out.bytes.size())
                    {
                        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_reloc_out_of_bounds);
                        return false;
                    }
                    const uint64_t inPlace = ByteUtils::readLe64(asByteSpan(out.bytes), reloc.offset);
                    const uint64_t value   = image_->imageBase + targetRva + inPlace + static_cast<uint64_t>(reloc.addend);
                    ByteUtils::writeLe64(out.bytes, reloc.offset, value);
                    baseRelocSites_.push_back(out.rva + reloc.offset);
                    break;
                }
                case LinkRelocKind::Rva32:
                {
                    if (reloc.offset + sizeof(uint32_t) > out.bytes.size())
                    {
                        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_reloc_out_of_bounds);
                        return false;
                    }
                    const uint32_t inPlace = ByteUtils::readLe32(asByteSpan(out.bytes), reloc.offset);
                    const uint32_t value   = targetRva + inPlace + static_cast<uint32_t>(reloc.addend);
                    ByteUtils::writeLe32(out.bytes, reloc.offset, value);
                    break;
                }
            }
        }
    }

    // Patch the import thunks now that .text and .idata RVAs are known.
    if (idataIndex_ >= 0)
    {
        const OutSection& text  = sections_[textIndex_];
        const OutSection& idata = sections_[idataIndex_];
        for (const ImportThunk& thunk : thunks_)
        {
            const uint32_t iatRva                             = idata.rva + thunk.iatSlotInIdata;
            const uint32_t site                               = text.rva + thunk.textOffset;
            const int32_t  disp                               = static_cast<int32_t>(iatRva) - static_cast<int32_t>(site + 6);
            sections_[textIndex_].bytes[thunk.textOffset + 0] = std::byte{0xFF};
            sections_[textIndex_].bytes[thunk.textOffset + 1] = std::byte{0x25};
            std::memcpy(sections_[textIndex_].bytes.data() + thunk.textOffset + 2, &disp, sizeof(disp));
        }

        // Fix up .idata internal RVAs.
        rebaseRvaFixups(sections_[idataIndex_].bytes, idataRvaFixups_, idata.rva);

        importDirRva_ += idata.rva;
        iatRva_ += idata.rva;
    }

    // Fix up the export directory: edata-internal RVAs and export-address-table symbol RVAs.
    if (edataIndex_ >= 0)
    {
        const OutSection& edata = sections_[edataIndex_];
        rebaseRvaFixups(sections_[edataIndex_].bytes, edataRvaFixups_, edata.rva);
        for (const auto& [offset, symbolName] : eatSymbolFixups_)
        {
            bool           found     = false;
            const uint32_t targetRva = resolveSymbolRva(found, symbolName);
            if (!found)
            {
                outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_export_symbol_not_found);
                outDiag.addArgument(Diagnostic::ARG_SYM, symbolName);
                return false;
            }
            ByteUtils::writeLe32(sections_[edataIndex_].bytes, offset, targetRva);
        }
    }

    return true;
}

void PEWriter::buildBaseRelocations()
{
    if (baseRelocSites_.empty())
        return;

    std::ranges::sort(baseRelocSites_);

    std::vector<std::byte> reloc;
    size_t                 i = 0;
    while (i < baseRelocSites_.size())
    {
        const uint32_t pageRva = baseRelocSites_[i] & ~0xFFFu;
        size_t         j       = i;
        while (j < baseRelocSites_.size() && (baseRelocSites_[j] & ~0xFFFu) == pageRva)
            ++j;

        const uint32_t entryCount = static_cast<uint32_t>(j - i);
        const bool     pad        = (entryCount % 2) != 0;
        const uint32_t blockSize  = sizeof(uint32_t) * 2 + (entryCount + (pad ? 1 : 0)) * sizeof(uint16_t);

        ByteUtils::appendLe32(reloc, pageRva);
        ByteUtils::appendLe32(reloc, blockSize);
        for (size_t k = i; k < j; ++k)
        {
            const uint16_t entry = static_cast<uint16_t>((IMAGE_REL_BASED_DIR64 << 12) | (baseRelocSites_[k] & 0xFFF));
            ByteUtils::appendLe16(reloc, entry);
        }
        if (pad)
            ByteUtils::appendLe16(reloc, 0);

        i = j;
    }

    OutSection relocSection;
    relocSection.name        = ".reloc";
    relocSection.bytes       = std::move(reloc);
    relocSection.virtualSize = static_cast<uint32_t>(relocSection.bytes.size());
    relocSection.align       = 4;
    relocIndex_              = static_cast<int32_t>(sections_.size());
    sections_.push_back(std::move(relocSection));
}

bool PEWriter::emit(std::vector<std::byte>& outBytes, Diagnostic& outDiag)
{
    const bool isDll = image_->kind == LinkImageKind::SharedLibrary;

    // The .reloc section was appended after the initial layout; give it an RVA and file offset at
    // the very end of the image so it does not disturb the already-assigned sections. The header
    // size was reserved for it during assignLayout(), so RVAs remain stable.
    const uint32_t sectionCount = static_cast<uint32_t>(sections_.size());
    const uint32_t headersSize  = headersSize_;

    if (relocIndex_ >= 0)
    {
        uint32_t maxRvaEnd  = headersSize;
        uint32_t maxFileEnd = headersSize;
        for (int32_t i = 0; std::cmp_less(i, sections_.size()); ++i)
        {
            if (i == relocIndex_)
                continue;
            maxRvaEnd = std::max(maxRvaEnd, sections_[i].rva + Math::alignUpU32(sections_[i].virtualSize, SECTION_ALIGNMENT));
            if (!sections_[i].isBss)
                maxFileEnd = std::max(maxFileEnd, sections_[i].fileOffset + sections_[i].rawSize);
        }
        OutSection& relocSection = sections_[relocIndex_];
        relocSection.rva         = Math::alignUpU32(maxRvaEnd, SECTION_ALIGNMENT);
        relocSection.fileOffset  = maxFileEnd;
        relocSection.rawSize     = Math::alignUpU32(static_cast<uint32_t>(relocSection.bytes.size()), FILE_ALIGNMENT);
    }

    // Image timestamp = the actual build time (what a debugger shows and uses, with SizeOfImage, as the
    // module's runtime identity). A real wall-clock value, not 0 and not a content hash. Computed once and
    // shared by the PE file header and the debug-directory entry so they agree.
    timeDateStamp_ = static_cast<uint32_t>(std::time(nullptr));
    if (timeDateStamp_ == 0)
        timeDateStamp_ = 1;

    // Every section now has a final RVA/file offset: build the PDB and fill the debug-directory section.
    emitDebugInfo();

    // Patch the resource data entry's payload RVA now that the .rsrc section has an address.
    if (rsrcIndex_ >= 0)
    {
        OutSection& rs = sections_[rsrcIndex_];
        ByteUtils::writeLe32(rs.bytes, 72, rs.rva + 88); // IMAGE_RESOURCE_DATA_ENTRY.OffsetToData (RVA)
    }

    // Compute SizeOfImage and the entry point.
    uint32_t sizeOfImage = headersSize;
    for (const OutSection& section : sections_)
        sizeOfImage = std::max(sizeOfImage, section.rva + Math::alignUpU32(section.virtualSize, SECTION_ALIGNMENT));
    sizeOfImage = Math::alignUpU32(sizeOfImage, SECTION_ALIGNMENT);

    uint32_t entryRva = 0;
    if (!isDll)
    {
        bool found = false;
        entryRva   = resolveSymbolRva(found, image_->entrySymbol);
        if (!found)
        {
            outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_entry_point_not_found);
            outDiag.addArgument(Diagnostic::ARG_SYM, image_->entrySymbol);
            return false;
        }
    }

    // ---- Headers ----
    std::vector<std::byte> file;
    file.resize(headersSize, std::byte{0});

    IMAGE_DOS_HEADER dos{};
    dos.e_magic  = IMAGE_DOS_SIGNATURE;
    dos.e_lfanew = sizeof(IMAGE_DOS_HEADER);
    std::memcpy(file.data(), &dos, sizeof(dos));

    uint32_t           cursor      = sizeof(IMAGE_DOS_HEADER);
    constexpr uint32_t peSignature = IMAGE_NT_SIGNATURE;
    std::memcpy(file.data() + cursor, &peSignature, sizeof(peSignature));
    cursor += sizeof(peSignature);

    IMAGE_FILE_HEADER fileHeader{};
    fileHeader.Machine              = IMAGE_FILE_MACHINE_AMD64;
    fileHeader.NumberOfSections     = static_cast<WORD>(sectionCount);
    fileHeader.TimeDateStamp        = timeDateStamp_;
    fileHeader.SizeOfOptionalHeader = sizeof(IMAGE_OPTIONAL_HEADER64);
    fileHeader.Characteristics      = IMAGE_FILE_EXECUTABLE_IMAGE | IMAGE_FILE_LARGE_ADDRESS_AWARE;
    if (isDll)
        fileHeader.Characteristics |= IMAGE_FILE_DLL;
    if (baseRelocSites_.empty())
        fileHeader.Characteristics |= IMAGE_FILE_RELOCS_STRIPPED;
    std::memcpy(file.data() + cursor, &fileHeader, sizeof(fileHeader));
    cursor += sizeof(fileHeader);

    IMAGE_OPTIONAL_HEADER64 opt{};
    opt.Magic                       = IMAGE_NT_OPTIONAL_HDR64_MAGIC;
    opt.MajorLinkerVersion          = static_cast<uint8_t>(SWC_VERSION); // the PE "linker version" is the producer/compiler version
    opt.MinorLinkerVersion          = static_cast<uint8_t>(SWC_REVISION);
    opt.AddressOfEntryPoint         = entryRva;
    opt.ImageBase                   = image_->imageBase;
    opt.SectionAlignment            = SECTION_ALIGNMENT;
    opt.FileAlignment               = FILE_ALIGNMENT;
    opt.MajorOperatingSystemVersion = 6;
    opt.MajorSubsystemVersion       = 6;
    opt.SizeOfImage                 = sizeOfImage;
    opt.SizeOfHeaders               = headersSize;
    opt.Subsystem                   = IMAGE_SUBSYSTEM_WINDOWS_CUI;
    opt.DllCharacteristics          = IMAGE_DLLCHARACTERISTICS_HIGH_ENTROPY_VA | IMAGE_DLLCHARACTERISTICS_NX_COMPAT |
                             IMAGE_DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE;
    if (!baseRelocSites_.empty())
        opt.DllCharacteristics |= IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE;
    opt.SizeOfStackReserve  = image_->stackReserve ? image_->stackReserve : 0x100000;
    opt.SizeOfStackCommit   = image_->stackCommit ? image_->stackCommit : 0x1000;
    opt.SizeOfHeapReserve   = 0x100000;
    opt.SizeOfHeapCommit    = 0x1000;
    opt.NumberOfRvaAndSizes = IMAGE_NUMBEROF_DIRECTORY_ENTRIES;

    // Compute sizes of code/initialized/uninitialized data for completeness.
    for (const OutSection& section : sections_)
    {
        const uint32_t vsize = Math::alignUpU32(section.virtualSize, SECTION_ALIGNMENT);
        if (section.name == ".text")
        {
            opt.SizeOfCode += section.rawSize;
            if (!opt.BaseOfCode)
                opt.BaseOfCode = section.rva;
        }
        else if (section.isBss)
            opt.SizeOfUninitializedData += vsize;
        else
            opt.SizeOfInitializedData += section.rawSize;
    }

    // Data directories.
    if (idataIndex_ >= 0)
    {
        opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress = importDirRva_;
        opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].Size           = importDirSize_;
        opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_IAT].VirtualAddress    = iatRva_;
        opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_IAT].Size              = iatSize_;
    }
    for (const OutSection& section : sections_)
    {
        if (section.name == ".pdata")
        {
            opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXCEPTION].VirtualAddress = section.rva;
            opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXCEPTION].Size           = section.virtualSize;
        }
        else if (section.name == ".edata")
        {
            opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress = section.rva;
            opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].Size           = section.virtualSize;
        }
    }
    if (relocIndex_ >= 0)
    {
        opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC].VirtualAddress = sections_[relocIndex_].rva;
        opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC].Size           = sections_[relocIndex_].virtualSize;
    }
    if (debugDirSize_ > 0)
    {
        opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_DEBUG].VirtualAddress = debugDirRva_;
        opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_DEBUG].Size           = debugDirSize_;
    }
    if (rsrcIndex_ >= 0)
    {
        opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_RESOURCE].VirtualAddress = sections_[rsrcIndex_].rva;
        opt.DataDirectory[IMAGE_DIRECTORY_ENTRY_RESOURCE].Size           = sections_[rsrcIndex_].virtualSize;
    }

    std::memcpy(file.data() + cursor, &opt, sizeof(opt));
    cursor += sizeof(opt);

    // Section table. The PE spec requires the section headers to be sorted by ascending virtual
    // address; the working set is kept in resolution order, so emit a virtual-address-sorted view.
    std::vector<uint32_t> headerOrder(sections_.size());
    std::ranges::iota(headerOrder, 0u);
    std::ranges::sort(headerOrder, [this](uint32_t left, uint32_t right) {
        return sections_[left].rva < sections_[right].rva;
    });
    for (const uint32_t sectionIdx : headerOrder)
    {
        const OutSection&    section = sections_[sectionIdx];
        IMAGE_SECTION_HEADER header{};
        std::memcpy(header.Name, section.name.data(), std::min<size_t>(section.name.size(), IMAGE_SIZEOF_SHORT_NAME));
        header.Misc.VirtualSize = section.virtualSize;
        header.VirtualAddress   = section.rva;
        header.SizeOfRawData    = section.rawSize;
        header.PointerToRawData = section.isBss ? 0 : section.fileOffset;
        header.Characteristics  = sectionCharacteristics(section.name.view());
        std::memcpy(file.data() + cursor, &header, sizeof(header));
        cursor += sizeof(header);
    }

    // ---- Section bodies ----
    uint32_t imageEnd = headersSize;
    for (const OutSection& section : sections_)
    {
        if (section.isBss || section.bytes.empty())
            continue;
        imageEnd = std::max(imageEnd, section.fileOffset + section.rawSize);
    }
    file.resize(imageEnd, std::byte{0});
    for (const OutSection& section : sections_)
    {
        if (section.isBss || section.bytes.empty())
            continue;
        std::memcpy(file.data() + section.fileOffset, section.bytes.data(), section.bytes.size());
    }

    outBytes = std::move(file);
    return true;
}

bool PEWriter::debugInfoEnabled() const
{
    return debugInfo_ != nullptr && debugInfo_->enabled && !debugInfo_->empty() && !pdbPath_.empty();
}

// Reserves a section large enough to hold the debug directory entry plus its RSDS CodeView record. The
// bytes are filled in by emitDebugInfo() once the image layout (and therefore the record's own RVA) is
// known, but the section must exist before layout so it is assigned an address.
void PEWriter::reserveDebugDirectorySection()
{
    if (!debugInfoEnabled())
        return;

    const Utf8         pdbPathStr        = nativePdbPathString(pdbPath_);
    const uint32_t     rsdsSize          = 4 + 16 + 4 + static_cast<uint32_t>(pdbPathStr.size()) + 1;
    constexpr uint32_t debugDirEntrySize = 28; // sizeof(IMAGE_DEBUG_DIRECTORY)
    constexpr uint32_t featDataSize      = 20; // IMAGE_DEBUG_TYPE_VC_FEATURE payload (5 x u32 counts)

    // Two directory entries (CodeView + VC_FEATURE) followed by their data blobs, matching link.exe's layout.
    OutSection section;
    section.name = ".debug";
    section.bytes.assign(2 * debugDirEntrySize + rsdsSize + featDataSize, std::byte{0});
    section.virtualSize = static_cast<uint32_t>(section.bytes.size());
    section.align       = 4;
    debugDirIndex_      = static_cast<int32_t>(sections_.size());
    sections_.push_back(std::move(section));
}

// Embeds a standard application manifest as an RT_MANIFEST resource in a .rsrc section, matching the
// resource directory a conventional Windows linker (link.exe) emits. The single IMAGE_RESOURCE_DATA_ENTRY
// stores its payload by RVA, which is patched in emit() once the section's address is known.
void PEWriter::reserveResourceSection()
{
    static constexpr char manifest[] =
        "<?xml version='1.0' encoding='UTF-8' standalone='yes'?>\r\n"
        "<assembly xmlns='urn:schemas-microsoft-com:asm.v1' manifestVersion='1.0'>\r\n"
        "  <trustInfo xmlns=\"urn:schemas-microsoft-com:asm.v3\">\r\n"
        "    <security>\r\n"
        "      <requestedPrivileges>\r\n"
        "        <requestedExecutionLevel level='asInvoker' uiAccess='false' />\r\n"
        "      </requestedPrivileges>\r\n"
        "    </security>\r\n"
        "  </trustInfo>\r\n"
        "</assembly>\r\n";
    constexpr auto manifestLen = static_cast<uint32_t>(sizeof(manifest) - 1); // drop the trailing NUL

    // Three directory levels (type / id / language), each a 16-byte directory + one 8-byte entry, then a
    // 16-byte data entry, then the manifest bytes. Offsets below are relative to the section start.
    constexpr uint32_t K_RT_MANIFEST   = 24;
    constexpr uint32_t K_MANIFEST_ID   = 1; // CREATEPROCESS_MANIFEST_RESOURCE_ID
    constexpr uint32_t K_LANG_EN_US    = 0x0409;
    constexpr uint32_t K_SUBDIR_FLAG   = 0x80000000u;
    constexpr uint32_t dataEntryOffset = (16 + 8) * 3;         // 72
    constexpr uint32_t dataOffset      = dataEntryOffset + 16; // 88

    std::vector<std::byte> b;
    const auto             u16 = [&](uint16_t v) {
        ByteUtils::appendLe16(b, v);
    };
    const auto u32 = [&](uint32_t v) {
        ByteUtils::appendLe32(b, v);
    };
    const auto dir = [&] {
        u32(0);
        u32(0);
        u16(0);
        u16(0);
        u16(0);
        u16(1);
    }; // one id entry

    dir();
    u32(K_RT_MANIFEST);
    u32(K_SUBDIR_FLAG | 24); // root -> type dir at 24
    dir();
    u32(K_MANIFEST_ID);
    u32(K_SUBDIR_FLAG | 48); // type -> language dir at 48
    dir();
    u32(K_LANG_EN_US);
    u32(dataEntryOffset); // language -> data entry at 72
    u32(0 /*OffsetToData RVA, patched later*/);
    u32(manifestLen);
    u32(0);
    u32(0);
    for (uint32_t i = 0; i < manifestLen; ++i)
        b.push_back(static_cast<std::byte>(manifest[i]));

    OutSection section;
    section.name        = ".rsrc";
    section.bytes       = std::move(b);
    section.virtualSize = static_cast<uint32_t>(section.bytes.size());
    section.align       = 4;
    rsrcIndex_          = static_cast<int32_t>(sections_.size());
    sections_.push_back(std::move(section));
}

namespace
{
    // Looks up each symbol's final placement in a flat, pre-resolved address map; resolves global data by
    // its section name + offset.
    struct PeSymbolResolver final : PdbWriter::SymbolResolver
    {
        const std::unordered_map<Utf8, PdbSymbolAddress>* addresses = nullptr;
        const std::unordered_map<Utf8, PdbSymbolAddress>* sections  = nullptr;

        PdbSymbolAddress resolve(const Utf8& name) const override
        {
            const auto it = addresses->find(name);
            return it == addresses->end() ? PdbSymbolAddress{} : it->second;
        }

        PdbSymbolAddress resolveSection(const Utf8& sectionName, const uint32_t offset) const override
        {
            const auto it = sections->find(sectionName);
            if (it == sections->end())
                return {};
            PdbSymbolAddress addr = it->second;
            addr.offset += offset;
            addr.rva += offset;
            return addr;
        }
    };
}

void PEWriter::emitDebugInfo()
{
    if (!debugInfoEnabled() || debugDirIndex_ < 0)
        return;

    // Build the section -> 1-based segment map in the same RVA-sorted order the PE section table uses, and
    // the matching PdbSectionInfo list so the PDB's section headers match the image exactly.
    std::vector<uint32_t> order(sections_.size());
    std::ranges::iota(order, 0u);
    std::ranges::sort(order, [this](uint32_t left, uint32_t right) { return sections_[left].rva < sections_[right].rva; });

    std::vector<uint32_t>       segmentOf(sections_.size(), 0);
    std::vector<uint32_t>       sectionRva(sections_.size(), 0);
    std::vector<PdbSectionInfo> pdbSections;
    pdbSections.reserve(sections_.size());
    for (size_t pos = 0; pos < order.size(); ++pos)
    {
        const uint32_t    idx = order[pos];
        const OutSection& s   = sections_[idx];
        segmentOf[idx]        = static_cast<uint32_t>(pos + 1);
        sectionRva[idx]       = s.rva;

        PdbSectionInfo info;
        info.name            = s.name;
        info.rva             = s.rva;
        info.virtualSize     = s.virtualSize;
        info.rawSize         = s.rawSize;
        info.fileOffset      = s.isBss ? 0 : s.fileOffset;
        info.characteristics = sectionCharacteristics(s.name.view());
        pdbSections.push_back(std::move(info));
    }

    std::unordered_map<Utf8, PdbSymbolAddress> addresses;
    addresses.reserve(symbols_.size());
    for (const auto& [name, loc] : symbols_)
    {
        PdbSymbolAddress addr;
        addr.found   = true;
        addr.segment = static_cast<uint16_t>(segmentOf[loc.sectionIndex]);
        addr.offset  = loc.value;
        addr.rva     = sectionRva[loc.sectionIndex] + loc.value;
        addresses.emplace(name, addr);
    }

    std::unordered_map<Utf8, PdbSymbolAddress> sectionAddresses;
    for (size_t idx = 0; idx < sections_.size(); ++idx)
    {
        PdbSymbolAddress addr;
        addr.found   = true;
        addr.segment = static_cast<uint16_t>(segmentOf[idx]);
        addr.offset  = 0;
        addr.rva     = sectionRva[idx];
        sectionAddresses.emplace(sections_[idx].name, addr);
    }

    PeSymbolResolver resolver;
    resolver.addresses = &addresses;
    resolver.sections  = &sectionAddresses;

    std::array<uint8_t, 16> guid{};
    uint32_t                age        = 0;
    uint32_t                signature  = 0;
    const Utf8              pdbPathStr = nativePdbPathString(pdbPath_);
    PdbWriter::build(*outPdbBytes_, guid, age, signature, *debugInfo_, pdbSections, resolver, image_->moduleName, pdbPathStr);

    // Fill the reserved debug-directory section. Like link.exe, emit two entries — CodeView (the RSDS record
    // pointing at the PDB) and VC_FEATURE (feature counts) — followed by their data blobs in the same section.
    OutSection&        section    = sections_[debugDirIndex_];
    constexpr uint32_t entrySize  = 28;
    constexpr uint32_t entryCount = 2;
    constexpr uint32_t dirSize    = entrySize * entryCount;

    std::vector<std::byte> rsds;
    ByteUtils::appendLe32(rsds, 0x53445352u); // "RSDS"
    for (const uint8_t b : guid)
        rsds.push_back(static_cast<std::byte>(b));
    ByteUtils::appendLe32(rsds, age);
    for (const char ch : pdbPathStr.view())
        rsds.push_back(static_cast<std::byte>(ch));
    rsds.push_back(std::byte{0});

    // VC_FEATURE payload: Pre-VC++11 / C-C++ / GS / sdl / guardN counts. swc applies none of these
    // hardening passes, so the counts are zero — a valid, honest entry.
    constexpr uint32_t     featDataSize = 20;
    std::vector<std::byte> feat(featDataSize, std::byte{0});

    const uint32_t rsdsRva  = section.rva + dirSize;
    const uint32_t rsdsFile = section.fileOffset + dirSize;
    const uint32_t featRva  = rsdsRva + static_cast<uint32_t>(rsds.size());
    const uint32_t featFile = rsdsFile + static_cast<uint32_t>(rsds.size());

    constexpr uint32_t K_IMAGE_DEBUG_TYPE_VC_FEATURE = 12;

    const auto appendDirEntry = [&](std::vector<std::byte>& out, uint32_t type, uint32_t size, uint32_t rva, uint32_t fileOff) {
        ByteUtils::appendLe32(out, 0);              // Characteristics
        ByteUtils::appendLe32(out, timeDateStamp_); // TimeDateStamp (matches the PE file header)
        ByteUtils::appendLe16(out, 0);              // MajorVersion
        ByteUtils::appendLe16(out, 0);              // MinorVersion
        ByteUtils::appendLe32(out, type);
        ByteUtils::appendLe32(out, size);
        ByteUtils::appendLe32(out, rva);
        ByteUtils::appendLe32(out, fileOff);
    };

    std::vector<std::byte> dir;
    appendDirEntry(dir, IMAGE_DEBUG_TYPE_CODEVIEW, static_cast<uint32_t>(rsds.size()), rsdsRva, rsdsFile);
    appendDirEntry(dir, K_IMAGE_DEBUG_TYPE_VC_FEATURE, featDataSize, featRva, featFile);

    SWC_ASSERT(section.bytes.size() >= dirSize + rsds.size() + feat.size());
    std::memcpy(section.bytes.data(), dir.data(), dir.size());
    std::memcpy(section.bytes.data() + dirSize, rsds.data(), rsds.size());
    std::memcpy(section.bytes.data() + dirSize + rsds.size(), feat.data(), feat.size());

    debugDirRva_  = section.rva;
    debugDirSize_ = dirSize;
}

bool PEWriter::writeImage(std::vector<std::byte>& outBytes, std::vector<std::byte>& outPdbBytes, Diagnostic& outDiag, const LinkImage& image, const LinkDebugInfo& debugInfo, const fs::path& pdbPath)
{
    image_       = &image;
    debugInfo_   = &debugInfo;
    pdbPath_     = pdbPath;
    outPdbBytes_ = &outPdbBytes;

    // Copy image sections into the working set, recording the index map and special sections.
    sections_.reserve(image_->sections.size() + 4);
    imageToOut_.resize(image_->sections.size());
    for (size_t i = 0; i < image_->sections.size(); ++i)
    {
        const LinkSection& src = image_->sections[i];
        OutSection         out;
        out.name        = src.name;
        out.bytes       = src.bytes;
        out.isBss       = src.isUninit();
        out.virtualSize = src.virtualSize();
        out.align       = src.align;
        imageToOut_[i]  = static_cast<uint32_t>(sections_.size());
        if (src.name == ".text")
            textIndex_ = static_cast<int32_t>(sections_.size());
        sections_.push_back(std::move(out));
    }

    for (const LinkSymbol& symbol : image_->symbols)
        symbols_[symbol.name] = {imageToOut_[symbol.sectionIndex], symbol.value};

    if (textIndex_ < 0)
    {
        outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_no_text_section);
        return false;
    }

    buildImports();
    buildExports();
    reserveDebugDirectorySection();
    reserveResourceSection();
    assignLayout();

    if (!applyRelocations(outDiag))
        return false;

    buildBaseRelocations();

    return emit(outBytes, outDiag);
}

bool PEWriter::buildStaticArchive(std::vector<std::byte>& outBytes, Diagnostic& outDiag, const std::vector<LinkArchiveMember>& members)
{
    return buildCoffStaticArchive(outBytes, outDiag, members);
}

void PEWriter::buildImportLibrary(std::vector<std::byte>& outBytes, std::string_view dllFileName, const std::vector<Utf8>& exportNames)
{
    buildCoffImportLibrary(outBytes, dllFileName, exportNames);
}

SWC_END_NAMESPACE();
