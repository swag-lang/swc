#include "pch.h"
#include "Backend/Encoder/DwarfFrame.x64.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Version 1, zR augmentation, code alignment 1, data alignment -8,
    // return address in RIP (16), absolute 64-bit FDE addresses.
    // Initial rule: CFA = rsp + 8; saved RIP = *(CFA - 8).
    constexpr std::array<uint8_t, 24> K_CIE = {20, 0, 0, 0, 0, 0, 0, 0, 1, 'z', 'R', 0, 1, 0x78, 16, 1, 0, 0x0c, 7, 8, 0x90, 1, 0, 0};
    constexpr uint32_t K_FDE_OFFSET = static_cast<uint32_t>(K_CIE.size());
    constexpr uint32_t K_CODE_ADDRESS_OFFSET = K_FDE_OFFSET + 8;
    constexpr uint32_t K_CODE_SIZE_OFFSET = K_CODE_ADDRESS_OFFSET + 8;

    bool validFrame(const ByteArray& frame, const uint32_t codeSize)
    {
        if (!codeSize || frame.size() < 60)
            return false;
        if (std::memcmp(frame.data(), K_CIE.data(), K_CIE.size()) != 0 || frame.readLe32(K_FDE_OFFSET + 4) != K_FDE_OFFSET + 4)
            return false;
        if (frame.readLe32(K_FDE_OFFSET) != frame.size() - K_FDE_OFFSET - 8 || frame.readLe32(frame.size() - 4) != 0)
            return false;
        return frame.readLe64(K_CODE_SIZE_OFFSET) == codeSize && frame[K_CODE_SIZE_OFFSET + 8] == std::byte{0};
    }

    void appendUleb(ByteArray& bytes, uint32_t value)
    {
        do
        {
            const uint8_t part = value & 0x7f;
            value >>= 7;
            bytes.pushBack(std::byte{static_cast<uint8_t>(part | (value ? 0x80 : 0))});
        } while (value);
    }
}

uint32_t X64DwarfFrame::registerNumber(const MicroReg reg)
{
    SWC_ASSERT((reg.isInt() || reg.isFloat()) && reg.index() < 16);
    constexpr uint8_t integers[] = {0, 3, 2, 1, 7, 6, 4, 5, 8, 9, 10, 11, 12, 13, 14, 15};
    return reg.isFloat() ? reg.index() + 17 : integers[reg.index()];
}

void X64DwarfFrame::reset()
{
    instructions_.clear();
    codeOffset_ = 0;
    savedStates_ = 0;
}

void X64DwarfFrame::advance(const uint32_t codeOffset)
{
    SWC_ASSERT(codeOffset >= codeOffset_);
    const uint32_t delta = codeOffset - codeOffset_;
    if (!delta)
        return;
    if (delta < 64)
        instructions_.pushBack(std::byte{static_cast<uint8_t>(0x40 | delta)});
    else
    {
        instructions_.pushBack(std::byte{0x04}); // DW_CFA_advance_loc4
        instructions_.appendLe32(delta);
    }
    codeOffset_ = codeOffset;
}

void X64DwarfFrame::defineCfa(const uint32_t reg, const uint32_t offset)
{
    instructions_.pushBack(std::byte{0x0c}); // DW_CFA_def_cfa
    appendUleb(instructions_, reg);
    appendUleb(instructions_, offset);
}

void X64DwarfFrame::saveRegister(const uint32_t reg, const int32_t cfaOffset)
{
    SWC_ASSERT(cfaOffset <= 0 && cfaOffset % 8 == 0);
    instructions_.pushBack(std::byte{0x05}); // DW_CFA_offset_extended
    appendUleb(instructions_, reg);
    appendUleb(instructions_, static_cast<uint32_t>(-static_cast<int64_t>(cfaOffset) / 8));
}

void X64DwarfFrame::restoreRegister(const uint32_t reg)
{
    // Same-value is explicit: the CIE has no saved-register rules beyond RIP.
    instructions_.pushBack(std::byte{0x08}); // DW_CFA_same_value
    appendUleb(instructions_, reg);
}

void X64DwarfFrame::rememberState()
{
    instructions_.pushBack(std::byte{0x0a});
    ++savedStates_;
}

void X64DwarfFrame::restoreState()
{
    SWC_ASSERT(savedStates_);
    instructions_.pushBack(std::byte{0x0b});
    --savedStates_;
}

void X64DwarfFrame::build(ByteArray& outFrame, const uint32_t codeSize) const
{
    SWC_ASSERT(codeSize && codeOffset_ <= codeSize && !savedStates_);
    outFrame.clear();
    outFrame.append(std::as_bytes(std::span{K_CIE}));
    outFrame.appendLe32(0); // FDE length, patched after padding
    outFrame.appendLe32(K_FDE_OFFSET + 4); // Backward distance to the CIE
    outFrame.appendLe64(0); // Relocated only once the executable address is known
    outFrame.appendLe64(codeSize);
    outFrame.pushBack(std::byte{0}); // Empty FDE augmentation
    outFrame.append(instructions_);
    outFrame.align(8); // DW_CFA_nop padding also aligns the following record
    outFrame.writeLe32(K_FDE_OFFSET, static_cast<uint32_t>(outFrame.size() - K_FDE_OFFSET - 4));
    outFrame.appendLe32(0); // .eh_frame terminator
}

bool X64DwarfFrame::appendObjectFrame(ByteArray& frames, uint32_t& addressOffset, const ByteArray& frame, const uint32_t codeSize)
{
    if (!validFrame(frame, codeSize) || frame.size() > UINT32_MAX - 7 || frames.size() > UINT32_MAX - frame.size() - 7)
        return false;
    frames.align(8);
    const uint32_t base = static_cast<uint32_t>(frames.size());
    addressOffset       = base + K_CODE_ADDRESS_OFFSET;
    frames.append(frame.span().first(K_CIE.size()));
    // Object frames use DW_EH_PE_pcrel | DW_EH_PE_sdata4, so the loader never
    // needs to modify read-only unwind records. JIT frames retain absolute addresses.
    frames[base + 16] = std::byte{0x1b};
    frames.appendLe32(frame.readLe32(K_FDE_OFFSET) - 8);
    frames.appendLe32(K_FDE_OFFSET + 4);
    frames.appendLe32(0);
    frames.appendLe32(codeSize);
    constexpr uint32_t instructionsOffset = K_CODE_SIZE_OFFSET + 8;
    frames.append(frame.span().subspan(instructionsOffset, frame.size() - instructionsOffset - 4));
    return true;
}

bool X64DwarfFrame::relocate(ByteArray& frame, const uintptr_t codeAddress, const uint32_t codeSize)
{
    if (!codeAddress || codeAddress > UINTPTR_MAX - codeSize || !validFrame(frame, codeSize))
        return false;
    frame.writeLe64(K_CODE_ADDRESS_OFFSET, codeAddress);
    return true;
}

SWC_END_NAMESPACE();
