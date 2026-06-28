#pragma once
#include "Support/Core/ByteArray.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

// Self-contained debug information threaded from the linker front-end (PELinker::prepareLink, which can
// read compiler state) to the background image writer (PEWriter, which cannot). Everything here is plain
// data: names are already resolved, source line tables are already collected and types are already
// lowered into CodeView byte blobs. The writer only needs to map each referenced symbol to its final
// section:offset / RVA once the image layout is known, then assemble the PDB streams.

// One contiguous run of line records that all belong to the same source file, relative to the start of
// the owning function's machine code.
struct LinkDebugLineBlock
{
    uint32_t              fileIndex = 0; // index into LinkDebugInfo::files
    std::vector<uint32_t> codeOffsets;   // offset from function start, parallel to lines
    std::vector<uint32_t> lines;         // 1-based source line, parallel to codeOffsets
};

// A local variable or parameter, addressed relative to a frame register.
struct LinkDebugLocal
{
    Utf8     name;
    uint32_t typeIndex   = 0; // CodeView TPI type index (0 = T_NOTYPE)
    int32_t  frameOffset = 0;
    uint16_t cvRegister  = 0; // CodeView register enum for the frame base
    bool     isParam     = false;
};

// A function with code in the image. The writer resolves symbolName to its final address.
struct LinkDebugFunction
{
    Utf8                            symbolName; // defined symbol to resolve to section:offset
    Utf8                            displayName;
    uint32_t                        objIndex         = 0; // index into LinkDebugInfo::objectNames (the owning compiland)
    uint32_t                        primaryFileIndex = std::numeric_limits<uint32_t>::max();
    uint32_t                        codeSize         = 0;
    uint32_t                        funcIdIndex      = 0; // CodeView IPI LF_FUNC_ID index (0 = none)
    uint32_t                        procTypeIndex    = 0; // CodeView TPI LF_PROCEDURE index (0 = T_NOTYPE)
    uint32_t                        frameSize        = 0;
    uint32_t                        frameProcFlags   = 0;
    uint16_t                        frameToCodeReg   = 0; // CodeView register used to address locals/params
    std::vector<LinkDebugLineBlock> lineBlocks;
    std::vector<LinkDebugLocal>     locals;
};

// A global/static data symbol, addressed by its containing section plus an offset (the writer maps the
// section to its final segment/RVA).
struct LinkDebugGlobal
{
    Utf8     sectionName;       // ".data" / ".bss"
    uint32_t sectionOffset = 0; // byte offset within that section
    Utf8     displayName;
    uint32_t typeIndex = 0;
    bool     isPublic  = false;
};

// A user-defined type name to surface via S_UDT in the global symbol stream.
struct LinkDebugUdt
{
    Utf8     name;
    uint32_t typeIndex = 0;
};

// A source file referenced by line tables, with an optional content checksum so debuggers/profilers can
// locate and verify the matching source. checksumKind is the CodeView kind (0 = none, 1 = MD5, 3 = SHA-256).
struct LinkDebugFile
{
    Utf8                 path;
    std::vector<uint8_t> checksum; // empty when checksumKind == 0
    uint8_t              checksumKind = 0;
};

struct LinkDebugInfo
{
    bool enabled = false;

    // Pre-lowered CodeView type/id records, ready to drop into the PDB TPI/IPI streams verbatim. Indices
    // run from 0x1000 to the matching *End value. The two streams have independent index spaces.
    ByteArray              tpiRecords;
    ByteArray              ipiRecords;
    uint32_t               tpiIndexEnd    = 0x1000;
    uint32_t               ipiIndexEnd    = 0x1000;
    uint32_t               buildInfoIndex = 0;

    std::vector<LinkDebugFile>     files;       // source files, referenced by LinkDebugLineBlock::fileIndex
    std::vector<Utf8>              objectNames; // synthetic compiland (object file) names, indexed by LinkDebugFunction::objIndex
    std::vector<LinkDebugFunction> functions;
    std::vector<LinkDebugGlobal>   globals;
    std::vector<LinkDebugUdt>      udts;

    Utf8 compilerVersion; // S_COMPILE3 version string

    bool empty() const { return functions.empty() && globals.empty(); }
};

SWC_END_NAMESPACE();
