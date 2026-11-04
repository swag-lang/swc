#pragma once
#include "Backend/Linker/Format.COFF.h"

// PE image records layered on the COFF file and section format.
namespace swc::PE
{
    constexpr uint16_t FILE_EXECUTABLE_IMAGE = 0x0002;
    constexpr uint16_t FILE_LARGE_ADDRESS_AWARE = 0x0020;
    constexpr uint16_t FILE_DLL = 0x2000;
    constexpr uint16_t DOS_SIGNATURE = 0x5a4d;
    constexpr uint32_t NT_SIGNATURE = 0x00004550;
    constexpr uint16_t NT_OPTIONAL_HDR64_MAGIC = 0x020b;
    constexpr size_t NUMBEROF_DIRECTORY_ENTRIES = 16;
    constexpr uint16_t REL_BASED_DIR64 = 10;

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

    static_assert(sizeof(DosHeader) == 64 && offsetof(DosHeader, e_lfanew) == 60);
    static_assert(sizeof(OptionalHeader64) == 240 && offsetof(OptionalHeader64, DataDirectory) == 112);
    static_assert(sizeof(ImportDescriptor) == 20 && offsetof(ImportDescriptor, FirstThunk) == 16);
}
