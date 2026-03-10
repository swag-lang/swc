#pragma once
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Native/NativeObjFileWriter.h"

SWC_BEGIN_NAMESPACE();

class NativeObjFileWriterCoff final : public NativeObjFileWriter
{
public:
    explicit NativeObjFileWriterCoff(NativeBackendBuilder& builder);

    Result writeObjectFile(const NativeObjDescription& description) override;

private:
    struct CoffSymbolRecord
    {
        Utf8     name;
        int16_t  sectionNumber = 0;
        uint32_t value         = 0;
        uint16_t type          = 0;
        uint8_t  storageClass  = 0;
        uint8_t  numAuxSymbols = 0;
    };

    struct CoffSectionBuild
    {
        NativeSectionData                    data;
        std::vector<NativeSectionRelocation> relocations;
        uint16_t                             sectionNumber        = 0;
        uint32_t                             pointerToRawData     = 0;
        uint32_t                             pointerToRelocations = 0;
        uint16_t                             numberOfRelocations  = 0;
        uint32_t                             sizeOfRawData        = 0;
    };

    struct CoffStringTable
    {
        uint32_t add(const Utf8& name)
        {
            if (name.size() <= IMAGE_SIZEOF_SHORT_NAME)
                return 0;
            if (const auto it = offsets.find(name); it != offsets.end())
                return it->second;

            const uint32_t offset = size;
            offsets.emplace(name, offset);
            entries.push_back(name);
            size += static_cast<uint32_t>(name.size()) + 1;
            return offset;
        }

        uint32_t                           size = 4;
        std::unordered_map<Utf8, uint32_t> offsets;
        std::vector<Utf8>                  entries;
    };

    Result        buildTextSection(const NativeObjDescription& description, CoffSectionBuild& textSection) const;
    Result        appendCodeRelocations(const NativeStartupInfo& startup, const MachineCode& code, CoffSectionBuild& textSection, bool allowUnresolvedSymbols) const;
    Result        appendCodeRelocations(const NativeFunctionInfo& owner, const MachineCode& code, CoffSectionBuild& textSection, bool allowUnresolvedSymbols) const;
    Result        appendSingleCodeRelocation(uint32_t functionOffset, const MicroRelocation& relocation, CoffSectionBuild& textSection, bool allowUnresolvedSymbols) const;
    static Result applySectionRelocations(CoffSectionBuild& section);
    static void   writeU16(std::vector<std::byte>& bytes, uint32_t offset, uint16_t value);
    static void   writeU32(std::vector<std::byte>& bytes, uint32_t offset, uint32_t value);
    static void   writeU64(std::vector<std::byte>& bytes, uint32_t offset, uint64_t value);
    static void   addDefinedSymbols(const NativeObjDescription& description, const std::vector<CoffSectionBuild>& sections, const std::vector<DebugInfoDefinedSymbol>& extraSymbols, std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices);
    static void   addUndefinedSymbols(const std::vector<CoffSectionBuild>& sections, std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices);
    Result        flushCoffFile(const fs::path& objPath, std::vector<CoffSectionBuild>& sections, const std::vector<CoffSymbolRecord>& symbols, const std::unordered_map<Utf8, uint32_t>& symbolIndices) const;

    NativeBackendBuilder& builder_;
};

SWC_END_NAMESPACE();
