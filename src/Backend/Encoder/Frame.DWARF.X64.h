#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

// One x86-64 .eh_frame CIE/FDE pair. Register numbers are DWARF numbers,
// not encoder register indices. Rules take effect after the named instruction.
class X64DwarfFrame
{
public:
    static uint32_t registerNumber(MicroReg reg);

    void reset();
    void advance(uint32_t codeOffset);
    static void appendAdvance(ByteArray& instructions, uint32_t delta);
    void defineCfa(uint32_t reg, uint32_t offset);
    void saveRegister(uint32_t reg, int32_t cfaOffset);
    void restoreRegister(uint32_t reg);
    void rememberState();
    void restoreState();
    void build(ByteArray& outFrame, uint32_t codeSize) const;

    // Recognizes the compiler's relocation-free, PC-relative CIE record.
    static bool isObjectCie(std::span<const std::byte> bytes);
    static bool trimObjectInstructions(std::span<const std::byte>& instructions, uint32_t& endPc, uint32_t codeSize);

    // Append one PC-relative CIE/FDE pair without its terminator. The address needs
    // a Rel32 relocation with addend 4 (DWARF measures from the field's first byte).
    // The object writer adds one final zero record after all functions have been appended.
    static bool appendObjectFrame(ByteArray& frames, uint32_t& addressOffset, const ByteArray& frame, uint32_t codeSize);

    // Patch a private, writable copy before registering it with the host unwinder.
    static bool relocate(ByteArray& frame, uintptr_t codeAddress, uint32_t codeSize);

private:
    ByteArray instructions_;
    SmallVector<std::pair<uint32_t, uint32_t>, 2> savedCfa_;
    uint32_t                                      codeOffset_ = 0;
    uint32_t                                      cfaReg_     = 7;
    uint32_t                                      cfaOffset_  = 8;
};

SWC_END_NAMESPACE();
