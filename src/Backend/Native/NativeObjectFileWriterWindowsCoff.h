#pragma once

#include "Backend/Native/NativeObjectFileWriter.h"

SWC_BEGIN_NAMESPACE();

class NativeObjectFileWriterWindowsCoff final : public NativeObjectFileWriter
{
public:
    explicit NativeObjectFileWriterWindowsCoff(NativeBackendBuilder& builder);

    bool writeObjectFile(const NativeObjDescription& description) override;

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

    bool        buildTextSection(const NativeObjDescription& description, CoffSectionBuild& textSection);
    bool        appendCodeRelocations(const NativeStartupInfo& startup, const MachineCode& code, CoffSectionBuild& textSection);
    bool        appendCodeRelocations(const NativeFunctionInfo& owner, const MachineCode& code, CoffSectionBuild& textSection);
    bool        appendSingleCodeRelocation(uint32_t functionOffset, const MicroRelocation& relocation, CoffSectionBuild& textSection);
    bool        buildDataRelocations(CoffSectionBuild& section) const;
    static void writeU64(std::vector<std::byte>& bytes, uint32_t offset, uint64_t value);
    static void addDefinedSymbols(const NativeObjDescription&          description,
                                  const std::vector<CoffSectionBuild>& sections,
                                  std::vector<CoffSymbolRecord>&       symbols,
                                  std::unordered_map<Utf8, uint32_t>&  symbolIndices);
    static void addUndefinedSymbols(const std::vector<CoffSectionBuild>& sections,
                                    std::vector<CoffSymbolRecord>&       symbols,
                                    std::unordered_map<Utf8, uint32_t>&  symbolIndices);
    bool        flushCoffFile(const fs::path&                           objPath,
                              std::vector<CoffSectionBuild>&            sections,
                              const std::vector<CoffSymbolRecord>&      symbols,
                              const std::unordered_map<Utf8, uint32_t>& symbolIndices) const;

    NativeBackendBuilder& builder_;
};

SWC_END_NAMESPACE();
