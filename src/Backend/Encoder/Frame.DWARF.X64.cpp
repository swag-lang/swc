#include "pch.h"
#include "Backend/Encoder/Frame.DWARF.X64.h"
#include "Backend/DwarfEncoding.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Version 1, zR augmentation, code alignment 1, data alignment -8,
    // return address in RIP (16), absolute 64-bit FDE addresses.
    // Initial rule: CFA = rsp + 8; saved RIP = *(CFA - 8).
    constexpr std::array<uint8_t, 24> K_CIE        = {20, 0, 0, 0, 0, 0, 0, 0, 1, 'z', 'R', 0, 1, 0x78, 16, 1, 0, 0x0c, 7, 8, 0x90, 1, 0, 0};
    constexpr auto                    K_OBJECT_CIE = [] {
        auto bytes = K_CIE;
        bytes[16]  = 0x1b; // DW_EH_PE_pcrel | DW_EH_PE_sdata4.
        return bytes;
    }();
    constexpr uint32_t K_FDE_OFFSET          = static_cast<uint32_t>(K_CIE.size());
    constexpr uint32_t K_CODE_ADDRESS_OFFSET = K_FDE_OFFSET + 8;
    constexpr uint32_t K_CODE_SIZE_OFFSET    = K_CODE_ADDRESS_OFFSET + 8;

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
    codeOffset_  = 0;
    savedCfa_.clear();
    cfaReg_    = 7;
    cfaOffset_ = 8;
}

void X64DwarfFrame::advance(const uint32_t codeOffset)
{
    SWC_ASSERT(codeOffset >= codeOffset_);
    const uint32_t delta = codeOffset - codeOffset_;
    if (!delta)
        return;
    appendAdvance(instructions_, delta);
    codeOffset_ = codeOffset;
}

void X64DwarfFrame::appendAdvance(ByteArray& instructions, const uint32_t delta)
{
    if (!delta)
        return;
    if (delta < 64)
        instructions.pushBack(std::byte{static_cast<uint8_t>(0x40 | delta)});
    else if (delta <= UINT8_MAX)
    {
        instructions.pushBack(std::byte{0x02}); // DW_CFA_advance_loc1
        instructions.pushBack(static_cast<std::byte>(delta));
    }
    else if (delta <= UINT16_MAX)
    {
        instructions.pushBack(std::byte{0x03}); // DW_CFA_advance_loc2
        instructions.appendLe16(static_cast<uint16_t>(delta));
    }
    else
    {
        instructions.pushBack(std::byte{0x04}); // DW_CFA_advance_loc4
        instructions.appendLe32(delta);
    }
}

void X64DwarfFrame::defineCfa(const uint32_t reg, const uint32_t offset)
{
    if (reg == cfaReg_)
        instructions_.pushBack(std::byte{0x0e}); // DW_CFA_def_cfa_offset
    else if (offset == cfaOffset_)
    {
        instructions_.pushBack(std::byte{0x0d}); // DW_CFA_def_cfa_register
        Dwarf::appendUnsignedLeb128(instructions_, reg);
        cfaReg_ = reg;
        return;
    }
    else
    {
        instructions_.pushBack(std::byte{0x0c}); // DW_CFA_def_cfa
        Dwarf::appendUnsignedLeb128(instructions_, reg);
    }
    Dwarf::appendUnsignedLeb128(instructions_, offset);
    cfaReg_    = reg;
    cfaOffset_ = offset;
}

void X64DwarfFrame::saveRegister(const uint32_t reg, const int32_t cfaOffset)
{
    SWC_ASSERT(cfaOffset <= 0 && cfaOffset % 8 == 0);
    if (reg < 64)
        instructions_.pushBack(static_cast<std::byte>(0x80 | reg)); // DW_CFA_offset
    else
    {
        instructions_.pushBack(std::byte{0x05}); // DW_CFA_offset_extended
        Dwarf::appendUnsignedLeb128(instructions_, reg);
    }
    Dwarf::appendUnsignedLeb128(instructions_, static_cast<uint32_t>(-static_cast<int64_t>(cfaOffset) / 8));
}

void X64DwarfFrame::restoreRegister(const uint32_t reg)
{
    // Same-value is explicit: the CIE has no saved-register rules beyond RIP.
    instructions_.pushBack(std::byte{0x08}); // DW_CFA_same_value
    Dwarf::appendUnsignedLeb128(instructions_, reg);
}

void X64DwarfFrame::rememberState()
{
    instructions_.pushBack(std::byte{0x0a});
    savedCfa_.emplace_back(cfaReg_, cfaOffset_);
}

void X64DwarfFrame::restoreState()
{
    SWC_ASSERT(!savedCfa_.empty());
    instructions_.pushBack(std::byte{0x0b});
    std::tie(cfaReg_, cfaOffset_) = savedCfa_.back();
    savedCfa_.pop_back();
}

void X64DwarfFrame::build(ByteArray& outFrame, const uint32_t codeSize) const
{
    SWC_ASSERT(codeSize && codeOffset_ <= codeSize && savedCfa_.empty());
    outFrame.clear();
    outFrame.append(std::as_bytes(std::span{K_CIE}));
    outFrame.appendLe32(0);                // FDE length, patched after padding
    outFrame.appendLe32(K_FDE_OFFSET + 4); // Backward distance to the CIE
    outFrame.appendLe64(0);                // Relocated only once the executable address is known
    outFrame.appendLe64(codeSize);
    outFrame.pushBack(std::byte{0}); // Empty FDE augmentation
    outFrame.append(instructions_);
    outFrame.align(8); // DW_CFA_nop padding also aligns the following record
    outFrame.writeLe32(K_FDE_OFFSET, static_cast<uint32_t>(outFrame.size() - K_FDE_OFFSET - 4));
    outFrame.appendLe32(0); // .eh_frame terminator
}

bool X64DwarfFrame::isObjectCie(const std::span<const std::byte> bytes)
{
    return bytes.size() == K_OBJECT_CIE.size() && std::memcmp(bytes.data(), K_OBJECT_CIE.data(), K_OBJECT_CIE.size()) == 0;
}

bool X64DwarfFrame::trimObjectInstructions(std::span<const std::byte>& instructions, uint32_t& endPc, const uint32_t codeSize)
{
    uint64_t pc     = 0;
    size_t   cursor = 0;
    size_t   used   = 0;
    size_t   saved  = 0;
    while (cursor < instructions.size())
    {
        const uint8_t op = std::to_integer<uint8_t>(instructions[cursor++]);
        if (!op) // DW_CFA_nop also pads the FDE.
            continue;
        size_t operands = 0;
        if ((op & 0xc0) == 0x40)
            pc += op & 0x3f;
        else if ((op & 0xc0) == 0x80)
            operands = 1;
        else if (op >= 2 && op <= 4)
        {
            const uint32_t width = 1u << (op - 2);
            if (width > instructions.size() - cursor)
                return false;
            for (uint32_t i = 0; i < width; ++i)
                pc += uint64_t{std::to_integer<uint8_t>(instructions[cursor++])} << (8 * i);
        }
        else if (op == 0x05 || op == 0x0c) // offset_extended, def_cfa
            operands = 2;
        else if (op == 0x08 || op == 0x0d || op == 0x0e) // same_value, def_cfa_register, def_cfa_offset
            operands = 1;
        else if (op == 0x0a) // remember_state
            ++saved;
        else if (op == 0x0b && saved) // restore_state
            --saved;
        else
            return false;

        for (size_t operand = 0; operand < operands; ++operand)
        {
            while (cursor < instructions.size() && (instructions[cursor] & std::byte{0x80}) != std::byte{0})
                ++cursor;
            if (cursor == instructions.size())
                return false;
            ++cursor;
        }
        if (pc > codeSize)
            return false;
        used = cursor;
    }
    if (saved)
        return false;
    instructions = instructions.first(used);
    endPc        = static_cast<uint32_t>(pc);
    return true;
}

bool X64DwarfFrame::appendObjectFrame(ByteArray& frames, uint32_t& addressOffset, const ByteArray& frame, const uint32_t codeSize)
{
    if (!validFrame(frame, codeSize) || frame.size() > UINT32_MAX - 7 || frames.size() > UINT32_MAX - frame.size() - 7)
        return false;
    frames.align(8);
    const uint32_t base = static_cast<uint32_t>(frames.size());
    addressOffset       = base + K_CODE_ADDRESS_OFFSET;
    frames.append(std::as_bytes(std::span{K_OBJECT_CIE}));
    // Object frames use DW_EH_PE_pcrel | DW_EH_PE_sdata4, so the loader never
    // needs to modify read-only unwind records. JIT frames retain absolute addresses.
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
