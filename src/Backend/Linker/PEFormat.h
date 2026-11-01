#pragma once

// PE/COFF on-disk records, independent of the compiler host and Windows SDK. Field names
// follow the format specification. These are serialized records, never native OS handles.
namespace swc::PE
{
    constexpr uint16_t FILE_MACHINE_I386 = 0x014c;
    constexpr uint16_t FILE_MACHINE_AMD64 = 0x8664;
    constexpr uint16_t FILE_RELOCS_STRIPPED = 0x0001;
    constexpr uint16_t FILE_EXECUTABLE_IMAGE = 0x0002;
    constexpr uint16_t FILE_LARGE_ADDRESS_AWARE = 0x0020;
    constexpr uint16_t FILE_DLL = 0x2000;
    constexpr uint16_t DOS_SIGNATURE = 0x5a4d;
    constexpr uint32_t NT_SIGNATURE = 0x00004550;
    constexpr uint16_t NT_OPTIONAL_HDR64_MAGIC = 0x020b;
    constexpr size_t SIZEOF_SHORT_NAME = 8;
    constexpr size_t NUMBEROF_DIRECTORY_ENTRIES = 16;

    constexpr uint32_t SCN_CNT_CODE = 0x00000020;
    constexpr uint32_t SCN_CNT_INITIALIZED_DATA = 0x00000040;
    constexpr uint32_t SCN_CNT_UNINITIALIZED_DATA = 0x00000080;
    constexpr uint32_t SCN_LNK_INFO = 0x00000200;
    constexpr uint32_t SCN_LNK_REMOVE = 0x00000800;
    constexpr uint32_t SCN_ALIGN_1BYTES = 0x00100000;
    constexpr uint32_t SCN_ALIGN_4BYTES = 0x00300000;
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
    constexpr uint16_t REL_BASED_DIR64 = 10;
    constexpr uint8_t SYM_CLASS_EXTERNAL = 2;
    constexpr uint8_t SYM_CLASS_STATIC = 3;
    constexpr uint16_t SYM_DTYPE_FUNCTION = 2;

    constexpr size_t DIRECTORY_ENTRY_EXPORT = 0;
    constexpr size_t DIRECTORY_ENTRY_IMPORT = 1;
    constexpr size_t DIRECTORY_ENTRY_RESOURCE = 2;
    constexpr size_t DIRECTORY_ENTRY_EXCEPTION = 3;
    constexpr size_t DIRECTORY_ENTRY_BASERELOC = 5;
    constexpr size_t DIRECTORY_ENTRY_DEBUG = 6;
    constexpr size_t DIRECTORY_ENTRY_IAT = 12;
    constexpr uint16_t SUBSYSTEM_WINDOWS_GUI = 2;
    constexpr uint16_t SUBSYSTEM_WINDOWS_CUI = 3;
    constexpr uint16_t DLLCHARACTERISTICS_HIGH_ENTROPY_VA = 0x0020;
    constexpr uint16_t DLLCHARACTERISTICS_DYNAMIC_BASE = 0x0040;
    constexpr uint16_t DLLCHARACTERISTICS_NX_COMPAT = 0x0100;
    constexpr uint16_t DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE = 0x8000;
    constexpr uint32_t DEBUG_TYPE_CODEVIEW = 2;

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

    struct DosHeader
    {
        uint16_t e_magic;
        uint16_t e_cblp;
        uint16_t e_cp;
        uint16_t e_crlc;
        uint16_t e_cparhdr;
        uint16_t e_minalloc;
        uint16_t e_maxalloc;
        uint16_t e_ss;
        uint16_t e_sp;
        uint16_t e_csum;
        uint16_t e_ip;
        uint16_t e_cs;
        uint16_t e_lfarlc;
        uint16_t e_ovno;
        uint16_t e_res[4];
        uint16_t e_oemid;
        uint16_t e_oeminfo;
        uint16_t e_res2[10];
        int32_t e_lfanew;
    };

    struct DataDirectory
    {
        uint32_t VirtualAddress;
        uint32_t Size;
    };

    struct OptionalHeader64
    {
        uint16_t Magic;
        uint8_t MajorLinkerVersion;
        uint8_t MinorLinkerVersion;
        uint32_t SizeOfCode;
        uint32_t SizeOfInitializedData;
        uint32_t SizeOfUninitializedData;
        uint32_t AddressOfEntryPoint;
        uint32_t BaseOfCode;
        uint64_t ImageBase;
        uint32_t SectionAlignment;
        uint32_t FileAlignment;
        uint16_t MajorOperatingSystemVersion;
        uint16_t MinorOperatingSystemVersion;
        uint16_t MajorImageVersion;
        uint16_t MinorImageVersion;
        uint16_t MajorSubsystemVersion;
        uint16_t MinorSubsystemVersion;
        uint32_t Win32VersionValue;
        uint32_t SizeOfImage;
        uint32_t SizeOfHeaders;
        uint32_t CheckSum;
        uint16_t Subsystem;
        uint16_t DllCharacteristics;
        uint64_t SizeOfStackReserve;
        uint64_t SizeOfStackCommit;
        uint64_t SizeOfHeapReserve;
        uint64_t SizeOfHeapCommit;
        uint32_t LoaderFlags;
        uint32_t NumberOfRvaAndSizes;
        PE::DataDirectory DataDirectory[NUMBEROF_DIRECTORY_ENTRIES];
    };

    struct ImportDescriptor
    {
        uint32_t OriginalFirstThunk;
        uint32_t TimeDateStamp;
        uint32_t ForwarderChain;
        uint32_t Name;
        uint32_t FirstThunk;
    };
#pragma pack(pop)

    static_assert(std::endian::native == std::endian::little, "PE records require little-endian serialization");
    static_assert(sizeof(FileHeader) == 20 && offsetof(FileHeader, PointerToSymbolTable) == 8);
    static_assert(sizeof(SectionHeader) == 40 && offsetof(SectionHeader, Characteristics) == 36);
    static_assert(sizeof(Symbol) == 18 && offsetof(Symbol, NumberOfAuxSymbols) == 17);
    static_assert(sizeof(Relocation) == 10 && offsetof(Relocation, Type) == 8);
    static_assert(sizeof(DosHeader) == 64 && offsetof(DosHeader, e_lfanew) == 60);
    static_assert(sizeof(OptionalHeader64) == 240 && offsetof(OptionalHeader64, DataDirectory) == 112);
    static_assert(sizeof(ImportDescriptor) == 20 && offsetof(ImportDescriptor, FirstThunk) == 16);
}
