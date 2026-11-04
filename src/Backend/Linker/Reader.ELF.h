#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/ByteView.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

namespace ELF
{
    inline constexpr uint32_t SHT_PROGBITS = 1;
    inline constexpr uint32_t SHT_SYMTAB = 2;
    inline constexpr uint32_t SHT_STRTAB = 3;
    inline constexpr uint32_t SHT_RELA = 4;
    inline constexpr uint32_t SHT_DYNAMIC = 6;
    inline constexpr uint32_t SHT_NOBITS = 8;
    inline constexpr uint32_t SHT_DYNSYM = 11;
    inline constexpr uint32_t SHT_INIT_ARRAY = 14;
    inline constexpr uint32_t SHT_FINI_ARRAY = 15;
    inline constexpr uint32_t SHT_PREINIT_ARRAY = 16;
    inline constexpr uint64_t SHF_WRITE = 1;
    inline constexpr uint64_t SHF_ALLOC = 2;
    inline constexpr uint64_t SHF_EXEC = 4;
    inline constexpr uint64_t SHF_TLS = 0x400;
    inline constexpr uint16_t SHN_ABS = 0xfff1;
    inline constexpr uint16_t SHN_COMMON = 0xfff2;
    inline constexpr uint32_t R_ABS64 = 1;
    inline constexpr uint32_t R_PC32 = 2;
    inline constexpr uint32_t R_PLT32 = 4;
    inline constexpr uint32_t R_COPY = 5;
    inline constexpr uint32_t R_GLOB_DAT = 6;
    inline constexpr uint32_t R_RELATIVE = 8;
    inline constexpr uint32_t R_GOTPCREL = 9;
    inline constexpr uint32_t R_32 = 10;
    inline constexpr uint32_t R_32S = 11;
    inline constexpr uint32_t R_PC64 = 24;
    inline constexpr uint32_t R_GOTPCRELX = 41;
    inline constexpr uint32_t R_REX_GOTPCRELX = 42;

    struct Section
    {
        std::string name;
        uint32_t type = 0;
        uint32_t link = 0;
        uint32_t info = 0;
        uint64_t flags = 0;
        uint64_t address = 0;
        uint64_t offset = 0;
        uint64_t size = 0;
        uint64_t align = 1;
        uint64_t entrySize = 0;
        size_t output = 0;
        uint64_t contribution = 0;
    };

    struct Symbol
    {
        std::string name;
        std::string version;
        uint8_t info = 0;
        uint8_t visibility = 0;
        uint16_t section = 0;
        uint64_t value = 0;
        uint64_t size = 0;
        bool hiddenVersion = false;
        size_t target = SIZE_MAX;
        uint8_t binding() const { return info >> 4; }
        uint8_t type() const { return info & 15; }
    };

    struct Relocation
    {
        uint32_t section = 0;
        uint32_t symbol = 0;
        uint32_t type = 0;
        uint64_t address = 0;
        uint64_t offset = 0;
        int64_t addend = 0;
    };

    // Views borrow the immutable bytes for the entire link. File inputs own their buffer;
    // prepared objects and extracted archive members borrow their existing backing storage.
    struct File
    {
        Utf8 name;
        ByteArray owned;
        ByteView bytes;
        bool shared = false;
        std::vector<Section> sections;
        std::vector<Symbol> symbols;
        std::vector<Relocation> relocations;
        std::vector<std::string> needed;
        std::string soname;

        bool read(Utf8& error, std::span<const std::byte> input);
        bool string(std::string& out, Utf8& error, const Section& strings, uint64_t offset) const;
    };

    uint32_t hash(std::string_view name);
}

SWC_END_NAMESPACE();
