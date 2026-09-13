#pragma once
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Native/NativeObjFileWriter.h"
#include "Backend/Native/NativeSection.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

struct MachineCode;
struct MicroRelocation;
struct NativeFunctionInfo;
struct NativeObjDescription;
struct NativeStartupInfo;

class NativeObjFileWriterCoff final : public NativeObjFileWriter
{
public:
    explicit NativeObjFileWriterCoff(NativeBackendBuilder& builder);

    Result buildObjectFile(ByteArray& outBytes, const NativeObjDescription& description) override;
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
        uint16_t                             sectionNumber         = 0;
        uint32_t                             pointerToRawData      = 0;
        uint32_t                             pointerToRelocations  = 0;
        uint16_t                             numberOfRelocations   = 0;
        uint32_t                             sizeOfRawData         = 0;
        bool                                 hasRelocationOverflow = false;
    };

    struct CoffStringTable
    {
        uint32_t add(const std::string_view name)
        {
            if (name.size() <= K_COFF_SHORT_NAME_SIZE)
                return 0;
            const auto [it, inserted] = offsets.try_emplace(name, size);
            if (!inserted)
                return it->second;

            const uint32_t offset = size;
            entries.push_back(name);
            size += static_cast<uint32_t>(name.size()) + 1;
            return offset;
        }

        // buildCoffFile owns this table inside the lifetime of its immutable symbol vector.
        // Names remain stable until both their offsets and bytes have been emitted.
        uint32_t                                      size = 4;
        std::unordered_map<std::string_view, uint32_t> offsets;
        std::vector<std::string_view>                  entries;
    };

    Result        buildTextSection(const NativeObjDescription& description, CoffSectionBuild& textSection) const;
    Result        buildRDataAllocationSection(CoffSectionBuild& section, const NativeObjDescription& description) const;
    static void   appendAlignedCodeBytes(CoffSectionBuild& textSection, uint32_t& outOffset, const ByteArray& bytes);
    Result        appendCodeRelocations(const NativeStartupInfo& startup, const MachineCode& code, CoffSectionBuild& textSection, bool allowUnresolvedSymbols, bool splitRDataReferences) const;
    Result        appendCodeRelocations(const NativeFunctionInfo& owner, const MachineCode& code, CoffSectionBuild& textSection, bool allowUnresolvedSymbols, bool splitRDataReferences) const;
    Result        appendSingleCodeRelocation(uint32_t functionOffset, const Utf8& ownerName, const MicroRelocation& relocation, CoffSectionBuild& textSection, bool allowUnresolvedSymbols, bool splitRDataReferences) const;
    static Result applySectionRelocations(CoffSectionBuild& section);
    static void   writeU16(ByteArray& bytes, uint32_t offset, uint16_t value);
    static void   writeU32(ByteArray& bytes, uint32_t offset, uint32_t value);
    static void   writeU64(ByteArray& bytes, uint32_t offset, uint64_t value);
    void          addDefinedSymbols(const NativeObjDescription& description, const std::vector<CoffSectionBuild>& sections, const std::vector<DebugInfoDefinedSymbol>& extraSymbols, std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices) const;
    static void   addSymbolRecord(std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices, CoffSymbolRecord record);
    static void   addUndefinedSymbols(const std::vector<CoffSectionBuild>& sections, std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices);
    static Result buildCoffFile(ByteArray& outBytes, std::vector<CoffSectionBuild>& sections, const std::vector<CoffSymbolRecord>& symbols, const std::unordered_map<Utf8, uint32_t>& symbolIndices);

    NativeBackendBuilder* builder_ = nullptr;
};

SWC_END_NAMESPACE();
