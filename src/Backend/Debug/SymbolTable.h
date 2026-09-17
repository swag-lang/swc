#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
struct NativeFunctionInfo;

// The table the runtime reads to name the functions a stack trace goes through, without a PDB.
//
// A linked image carries one in its '.swagdbg' section. An object in a static archive carries the part
// that describes its own functions in '.swagsym', and the linker folds that part into the image's
// table when it pulls the object in: without it, a program that takes a library's code in would print
// traces that skip every frame of that library.
//
// Both sections share one layout: a 16-byte header (magic, version, entry count, offset of the
// strings), then 20-byte entries (image-relative start, size, name, file, line), then the strings.
// String offsets count from the start of the table, and 0 stands for no string. A start address is
// relocated against the entry's symbol.
namespace SymbolTable
{
    inline constexpr std::string_view IMAGE_SECTION   = ".swagdbg";
    inline constexpr std::string_view OBJECT_SECTION  = ".swagsym";
    inline constexpr uint32_t         MAGIC           = 0x42445753u; // 'SWDB'
    inline constexpr uint32_t         VERSION_PLAIN   = 1;
    inline constexpr uint32_t         VERSION_PACKED  = 2; // an image's table, LZNT1-compressed by the PE writer
    inline constexpr uint32_t         HEADER_SIZE     = 16;
    inline constexpr uint32_t         ENTRY_SIZE      = 20;
    inline constexpr uint32_t         ENTRY_START_RVA = 0;

    struct Entry
    {
        Utf8     symbolName;
        Utf8     name;
        Utf8     file;
        uint32_t line = 0;
        uint32_t size = 0;
    };

    struct Relocation
    {
        uint32_t offset = 0;
        Utf8     symbolName;
    };

    // Describes one generated function. Returns false for a function without code.
    bool makeEntry(Entry& outEntry, const TaskContext& ctx, const NativeFunctionInfo& info);

    // Lays the entries out as a table, and names the symbol each start address is relocated against.
    void build(ByteArray& outBytes, std::vector<Relocation>& outRelocations, std::span<const Entry> entries);

    // Appends the entries of a table, given the symbol each start address is relocated against.
    // Returns false, and appends nothing, when the bytes are not such a table.
    bool read(std::vector<Entry>& outEntries, std::span<const std::byte> bytes, std::span<const Relocation> relocations);
}

SWC_END_NAMESPACE();
