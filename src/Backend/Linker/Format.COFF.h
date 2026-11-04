#pragma once

// COFF records shared by object files and PE images.
namespace swc::PE
{
    constexpr uint16_t FILE_MACHINE_I386 = 0x014c;
    constexpr uint16_t FILE_MACHINE_AMD64 = 0x8664;
    constexpr uint16_t FILE_RELOCS_STRIPPED = 0x0001;
    constexpr size_t SIZEOF_SHORT_NAME = 8;

    constexpr uint32_t SCN_CNT_CODE = 0x00000020;
    constexpr uint32_t SCN_CNT_INITIALIZED_DATA = 0x00000040;
    constexpr uint32_t SCN_CNT_UNINITIALIZED_DATA = 0x00000080;
    constexpr uint32_t SCN_LNK_INFO = 0x00000200;
    constexpr uint32_t SCN_LNK_REMOVE = 0x00000800;
    constexpr uint32_t SCN_ALIGN_1BYTES = 0x00100000;
    constexpr uint32_t SCN_ALIGN_4BYTES = 0x00300000;
    constexpr uint32_t SCN_ALIGN_8BYTES = 0x00400000;
    constexpr uint32_t SCN_ALIGN_16BYTES = 0x00500000;
    constexpr uint32_t SCN_ALIGN_32BYTES = 0x00600000;
    constexpr uint32_t SCN_LNK_NRELOC_OVFL = 0x01000000;
    constexpr uint32_t SCN_MEM_DISCARDABLE = 0x02000000;
    constexpr uint32_t SCN_MEM_EXECUTE = 0x20000000;
    constexpr uint32_t SCN_MEM_READ = 0x40000000;
    constexpr uint32_t SCN_MEM_WRITE = 0x80000000;

    constexpr uint16_t REL_AMD64_ADDR64 = 0x0001;
    constexpr uint16_t REL_AMD64_ADDR32NB = 0x0003;
    constexpr uint16_t REL_AMD64_REL32 = 0x0004;
    constexpr uint16_t REL_AMD64_SECTION = 0x000a;
    constexpr uint16_t REL_AMD64_SECREL = 0x000b;
    constexpr uint8_t SYM_CLASS_EXTERNAL = 2;
    constexpr uint8_t SYM_CLASS_STATIC = 3;
    constexpr uint16_t SYM_DTYPE_FUNCTION = 2;

#pragma pack(push, 1)
    struct FileHeader
    {
        uint16_t Machine;
        uint16_t NumberOfSections;
        uint32_t TimeDateStamp;
        uint32_t PointerToSymbolTable;
        uint32_t NumberOfSymbols;
        uint16_t SizeOfOptionalHeader;
        uint16_t Characteristics;
    };

    struct SectionHeader
    {
        uint8_t Name[SIZEOF_SHORT_NAME];
        union
        {
            uint32_t PhysicalAddress;
            uint32_t VirtualSize;
        } Misc;
        uint32_t VirtualAddress;
        uint32_t SizeOfRawData;
        uint32_t PointerToRawData;
        uint32_t PointerToRelocations;
        uint32_t PointerToLinenumbers;
        uint16_t NumberOfRelocations;
        uint16_t NumberOfLinenumbers;
        uint32_t Characteristics;
    };

    struct Symbol
    {
        union
        {
            uint8_t ShortName[SIZEOF_SHORT_NAME];
            struct
            {
                uint32_t Short;
                uint32_t Long;
            } Name;
        } N;
        uint32_t Value;
        int16_t SectionNumber;
        uint16_t Type;
        uint8_t StorageClass;
        uint8_t NumberOfAuxSymbols;
    };

    struct Relocation
    {
        union
        {
            uint32_t VirtualAddress;
            uint32_t RelocCount;
        };
        uint32_t SymbolTableIndex;
        uint16_t Type;
    };
#pragma pack(pop)

    static_assert(std::endian::native == std::endian::little, "PE records require little-endian serialization");
    static_assert(sizeof(FileHeader) == 20 && offsetof(FileHeader, PointerToSymbolTable) == 8);
    static_assert(sizeof(SectionHeader) == 40 && offsetof(SectionHeader, Characteristics) == 36);
    static_assert(sizeof(Symbol) == 18 && offsetof(Symbol, NumberOfAuxSymbols) == 17);
    static_assert(sizeof(Relocation) == 10 && offsetof(Relocation, Type) == 8);
}
