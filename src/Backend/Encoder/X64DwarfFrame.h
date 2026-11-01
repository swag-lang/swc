#pragma once
#include "Support/Core/ByteArray.h"

SWC_BEGIN_NAMESPACE();

// One x86-64 .eh_frame CIE/FDE pair. Register numbers are DWARF numbers,
// not encoder register indices. Rules take effect after the named instruction.
class X64DwarfFrame
{
public:
    void reset();
    void advance(uint32_t codeOffset);
    void defineCfa(uint32_t reg, uint32_t offset);
    void saveRegister(uint32_t reg, int32_t cfaOffset);
    void restoreRegister(uint32_t reg);
    void rememberState();
    void restoreState();
    void build(ByteArray& outFrame, uint32_t codeSize) const;

    // Patch a private, writable copy before registering it with the host unwinder.
    static bool relocate(ByteArray& frame, uintptr_t codeAddress, uint32_t codeSize);

private:
    ByteArray instructions_;
    uint32_t codeOffset_ = 0;
    uint32_t savedStates_ = 0;
};

SWC_END_NAMESPACE();
