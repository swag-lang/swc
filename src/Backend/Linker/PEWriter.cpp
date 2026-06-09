#include "pch.h"
#include "Backend/Linker/PEWriter.h"
#include "Support/Core/ByteUtils.h"
#include "Support/Math/Helpers.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t SECTION_ALIGNMENT = 0x1000;
    constexpr uint32_t FILE_ALIGNMENT    = 0x200;

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

    struct OutSection
    {
        Utf8                   name;
        std::vector<std::byte> bytes;
        uint32_t               virtualSize = 0;
        bool                   isBss       = false;
        uint32_t               align       = 16;
        uint32_t               rva         = 0;
        uint32_t               fileOffset  = 0;
        uint32_t               rawSize     = 0;
    };

    struct SectionLayoutLess
    {
        const std::vector<OutSection>* sections = nullptr;

        bool operator()(uint32_t left, uint32_t right) const
        {
            SWC_ASSERT(sections != nullptr);
            return sectionLayoutRank((*sections)[left].name.view()) < sectionLayoutRank((*sections)[right].name.view());
        }
    };

    struct SectionRvaLess
    {
        const std::vector<OutSection>* sections = nullptr;

        bool operator()(uint32_t left, uint32_t right) const
        {
            SWC_ASSERT(sections != nullptr);
            return (*sections)[left].rva < (*sections)[right].rva;
        }
    };

    struct ImportThunk
    {
        Utf8     symbolName;
        uint32_t textOffset     = 0; // offset of the 6-byte thunk within .text
        uint32_t iatSlotInIdata = 0; // offset of the IAT slot within .idata
    };

    class PEWriter
    {
    public:
        explicit PEWriter(const LinkImage& image) :
            image_(image)
        {
        }

        bool write(std::vector<std::byte>& outBytes, Diagnostic& outDiag);

    private:
        uint32_t resolveSymbolRva(bool& outFound, const Utf8& name) const;
        bool     buildImports(Diagnostic& outDiag);
        void     buildExports();
        void     assignLayout();
        bool     applyRelocations(Diagnostic& outDiag);
        void     buildBaseRelocations();
        bool     emit(std::vector<std::byte>& outBytes, Diagnostic& outDiag);

        const LinkImage&                       image_;
        std::vector<OutSection>                sections_;
        std::vector<uint32_t>                  imageToOut_;    // image.sections index -> sections_ index
        std::unordered_map<Utf8, uint32_t>     symbolSection_; // name -> sections_ index
        std::unordered_map<Utf8, uint32_t>     symbolValue_;   // name -> offset within section
        std::vector<ImportThunk>               thunks_;
        std::vector<uint32_t>                  idataRvaFixups_; // positions in .idata holding idata-relative offsets
        std::vector<uint32_t>                  baseRelocSites_; // RVAs needing IMAGE_REL_BASED_DIR64
        uint32_t                               headersSize_ = 0;
        int32_t                                textIndex_   = -1;
        int32_t                                idataIndex_  = -1;
        int32_t                                edataIndex_  = -1;
        int32_t                                relocIndex_  = -1;
        std::vector<uint32_t>                  edataRvaFixups_;  // edata-relative offsets to relocate by edata.rva
        std::vector<std::pair<uint32_t, Utf8>> eatSymbolFixups_; // export address table entries -> symbol RVA
        uint32_t                               importDirRva_  = 0;
        uint32_t                               importDirSize_ = 0;
        uint32_t                               iatRva_        = 0;
        uint32_t                               iatSize_       = 0;
    };

    bool exportNameLess(const LinkExport* left, const LinkExport* right)
    {
        return left->name.view() < right->name.view();
    }

    uint32_t PEWriter::resolveSymbolRva(bool& outFound, const Utf8& name) const
    {
        const auto sectionIt = symbolSection_.find(name);
        if (sectionIt == symbolSection_.end())
        {
            outFound = false;
            return 0;
        }
        outFound             = true;
        const uint32_t value = symbolValue_.at(name);
        return sections_[sectionIt->second].rva + value;
    }

    bool PEWriter::buildImports(Diagnostic& outDiag)
    {
        if (image_.imports.empty())
            return true;

        // Group imports by DLL, preserving first-seen order.
        std::vector<Utf8>                                        dllOrder;
        std::unordered_map<Utf8, std::vector<const LinkImport*>> byDll;
        for (const LinkImport& imp : image_.imports)
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
                thunk.symbolName = imp->symbolName;
                thunk.textOffset = static_cast<uint32_t>(text.bytes.size());
                text.bytes.insert(text.bytes.end(), 6, std::byte{0}); // FF 25 <disp32>, filled after layout
                thunks_.push_back(thunk);

                symbolSection_[imp->symbolName] = static_cast<uint32_t>(textIndex_);
                symbolValue_[imp->symbolName]   = thunk.textOffset;
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
                ByteUtils::appendLE16(idata, 0); // hint
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
                    ByteUtils::writeLE64(idata, iltCursor, entry);
                    ByteUtils::writeLE64(idata, iatCursor, entry);
                }
                else
                {
                    ByteUtils::writeLE64(idata, iltCursor, hintNameOffset[imp]);
                    idataRvaFixups_.push_back(iltCursor);
                    ByteUtils::writeLE64(idata, iatCursor, hintNameOffset[imp]);
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
            ByteUtils::writeLE32(idata, base + 0, dllLayouts[d].iltOffset); // OriginalFirstThunk
            idataRvaFixups_.push_back(base + 0);
            ByteUtils::writeLE32(idata, base + 12, dllNameOffset[dllOrder[d]]); // Name
            idataRvaFixups_.push_back(base + 12);
            ByteUtils::writeLE32(idata, base + 16, dllLayouts[d].iatOffset); // FirstThunk
            idataRvaFixups_.push_back(base + 16);
        }

        // Record the IAT slot offset each thunk references.
        for (ImportThunk& thunk : thunks_)
        {
            const LinkImport* match = nullptr;
            for (const LinkImport& imp : image_.imports)
            {
                if (imp.symbolName == thunk.symbolName)
                {
                    match = &imp;
                    break;
                }
            }
            if (!match)
            {
                outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_missing_import_thunk);
                outDiag.addArgument(Diagnostic::ARG_SYM, thunk.symbolName);
                return false;
            }
            thunk.iatSlotInIdata = iatEntryOffset[match];
        }

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
        return true;
    }

    void PEWriter::buildExports()
    {
        if (image_.kind != LinkImageKind::SharedLibrary || image_.exports.empty())
            return;

        // Export names must be sorted for the name-pointer table (the loader binary-searches it).
        std::vector<const LinkExport*> sorted;
        sorted.reserve(image_.exports.size());
        for (const LinkExport& e : image_.exports)
            sorted.push_back(&e);
        std::ranges::sort(sorted, exportNameLess);

        const uint32_t count = static_cast<uint32_t>(sorted.size());

        std::vector<std::byte> edata;
        edata.resize(40, std::byte{0}); // IMAGE_EXPORT_DIRECTORY

        const uint32_t eatOffset = static_cast<uint32_t>(edata.size());
        for (uint32_t i = 0; i < count; ++i)
        {
            eatSymbolFixups_.emplace_back(static_cast<uint32_t>(edata.size()), sorted[i]->symbolName);
            ByteUtils::appendLE32(edata, 0); // filled with the exported symbol RVA after layout
        }

        const uint32_t nptOffset = static_cast<uint32_t>(edata.size());
        edata.resize(edata.size() + static_cast<size_t>(count) * sizeof(uint32_t), std::byte{0});

        const uint32_t ordinalOffset = static_cast<uint32_t>(edata.size());
        for (uint32_t i = 0; i < count; ++i)
            ByteUtils::appendLE16(edata, static_cast<uint16_t>(i));

        // Name strings, then the module name.
        std::vector<uint32_t> nameOffsets(count);
        for (uint32_t i = 0; i < count; ++i)
        {
            nameOffsets[i] = static_cast<uint32_t>(edata.size());
            ByteUtils::appendCString(edata, sorted[i]->name.view());
        }
        const uint32_t         dllNameOffset = static_cast<uint32_t>(edata.size());
        const std::string_view exportModule  = image_.moduleName.empty() ? std::string_view{"module.dll"} : image_.moduleName.view();
        ByteUtils::appendCString(edata, exportModule);

        // Fill the name-pointer table with RVAs of the name strings (relocated after layout).
        for (uint32_t i = 0; i < count; ++i)
        {
            const uint32_t pos = nptOffset + i * sizeof(uint32_t);
            ByteUtils::writeLE32(edata, pos, nameOffsets[i]);
            edataRvaFixups_.push_back(pos);
        }

        // Fill IMAGE_EXPORT_DIRECTORY.
        ByteUtils::writeLE32(edata, 12, dllNameOffset);
        edataRvaFixups_.push_back(12);
        ByteUtils::writeLE32(edata, 16, 1);     // Base ordinal
        ByteUtils::writeLE32(edata, 20, count); // NumberOfFunctions
        ByteUtils::writeLE32(edata, 24, count); // NumberOfNames
        ByteUtils::writeLE32(edata, 28, eatOffset);
        edataRvaFixups_.push_back(28);
        ByteUtils::writeLE32(edata, 32, nptOffset);
        edataRvaFixups_.push_back(32);
        ByteUtils::writeLE32(edata, 36, ordinalOffset);
        edataRvaFixups_.push_back(36);

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
        for (const LinkSection& src : image_.sections)
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
        std::ranges::stable_sort(order, SectionLayoutLess{&sections_});

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
        for (size_t imageIdx = 0; imageIdx < image_.sections.size(); ++imageIdx)
        {
            const LinkSection& src = image_.sections[imageIdx];
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
                        const uint64_t inPlace = ByteUtils::readLE64(asByteSpan(out.bytes), reloc.offset);
                        const uint64_t value   = image_.imageBase + targetRva + inPlace + static_cast<uint64_t>(reloc.addend);
                        ByteUtils::writeLE64(out.bytes, reloc.offset, value);
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
                        const uint32_t inPlace = ByteUtils::readLE32(asByteSpan(out.bytes), reloc.offset);
                        const uint32_t value   = targetRva + inPlace + static_cast<uint32_t>(reloc.addend);
                        ByteUtils::writeLE32(out.bytes, reloc.offset, value);
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
            for (const uint32_t fixup : idataRvaFixups_)
            {
                const uint32_t rel = ByteUtils::readLE32(asByteSpan(sections_[idataIndex_].bytes), fixup);
                ByteUtils::writeLE32(sections_[idataIndex_].bytes, fixup, rel + idata.rva);
            }

            importDirRva_ += idata.rva;
            iatRva_ += idata.rva;
        }

        // Fix up the export directory: edata-internal RVAs and export-address-table symbol RVAs.
        if (edataIndex_ >= 0)
        {
            const OutSection& edata = sections_[edataIndex_];
            for (const uint32_t fixup : edataRvaFixups_)
            {
                const uint32_t rel = ByteUtils::readLE32(asByteSpan(edata.bytes), fixup);
                ByteUtils::writeLE32(sections_[edataIndex_].bytes, fixup, rel + edata.rva);
            }
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
                ByteUtils::writeLE32(sections_[edataIndex_].bytes, offset, targetRva);
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

            ByteUtils::appendLE32(reloc, pageRva);
            ByteUtils::appendLE32(reloc, blockSize);
            for (size_t k = i; k < j; ++k)
            {
                const uint16_t entry = static_cast<uint16_t>((IMAGE_REL_BASED_DIR64 << 12) | (baseRelocSites_[k] & 0xFFF));
                ByteUtils::appendLE16(reloc, entry);
            }
            if (pad)
                ByteUtils::appendLE16(reloc, 0);

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
        const bool isDll = image_.kind == LinkImageKind::SharedLibrary;

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

        // Compute SizeOfImage and the entry point.
        uint32_t sizeOfImage = headersSize;
        for (const OutSection& section : sections_)
            sizeOfImage = std::max(sizeOfImage, section.rva + Math::alignUpU32(section.virtualSize, SECTION_ALIGNMENT));
        sizeOfImage = Math::alignUpU32(sizeOfImage, SECTION_ALIGNMENT);

        uint32_t entryRva = 0;
        if (!isDll)
        {
            bool found = false;
            entryRva   = resolveSymbolRva(found, image_.entrySymbol);
            if (!found)
            {
                outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_entry_point_not_found);
                outDiag.addArgument(Diagnostic::ARG_SYM, image_.entrySymbol);
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
        opt.AddressOfEntryPoint         = entryRva;
        opt.ImageBase                   = image_.imageBase;
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
        opt.SizeOfStackReserve  = image_.stackReserve ? image_.stackReserve : 0x100000;
        opt.SizeOfStackCommit   = image_.stackCommit ? image_.stackCommit : 0x1000;
        opt.SizeOfHeapReserve   = 0x100000;
        opt.SizeOfHeapCommit    = 0x1000;
        opt.NumberOfRvaAndSizes = IMAGE_NUMBEROF_DIRECTORY_ENTRIES;

        // Compute sizes of code/initialized/uninitialized data for completeness.
        for (const OutSection& section : sections_)
        {
            const uint32_t vsize = Math::alignUpU32(section.virtualSize, SECTION_ALIGNMENT);
            if (section.name == ".text")
                opt.SizeOfCode += section.rawSize, opt.BaseOfCode = opt.BaseOfCode ? opt.BaseOfCode : section.rva;
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

        std::memcpy(file.data() + cursor, &opt, sizeof(opt));
        cursor += sizeof(opt);

        // Section table. The PE spec requires the section headers to be sorted by ascending virtual
        // address; the working set is kept in resolution order, so emit a virtual-address-sorted view.
        std::vector<uint32_t> headerOrder(sections_.size());
        std::ranges::iota(headerOrder, 0u);
        std::ranges::sort(headerOrder, SectionRvaLess{&sections_});
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

    bool PEWriter::write(std::vector<std::byte>& outBytes, Diagnostic& outDiag)
    {
        // Copy image sections into the working set, recording the index map and special sections.
        sections_.reserve(image_.sections.size() + 4);
        imageToOut_.resize(image_.sections.size());
        for (size_t i = 0; i < image_.sections.size(); ++i)
        {
            const LinkSection& src = image_.sections[i];
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

            // Record defined symbols' section/value (RVA resolved after layout).
        }

        for (const LinkSymbol& symbol : image_.symbols)
        {
            symbolSection_[symbol.name] = imageToOut_[symbol.sectionIndex];
            symbolValue_[symbol.name]   = symbol.value;
        }

        if (textIndex_ < 0)
        {
            outDiag = Diagnostic::get(DiagnosticId::cmd_err_link_no_text_section);
            return false;
        }

        if (!buildImports(outDiag))
            return false;

        buildExports();

        assignLayout();

        // Recompute thunk symbol values after imports were appended (already set in buildImports).
        if (!applyRelocations(outDiag))
            return false;

        buildBaseRelocations();

        return emit(outBytes, outDiag);
    }
}

bool writePeImage(std::vector<std::byte>& outBytes, Diagnostic& outDiag, const LinkImage& image)
{
    PEWriter writer(image);
    return writer.write(outBytes, outDiag);
}

SWC_END_NAMESPACE();
