#pragma once

SWC_BEGIN_NAMESPACE();

enum class MicroRegKind : uint8_t
{
    Invalid,
    Int,
    Float,
    Special,
};

enum class MicroRegSpecial : uint8_t
{
    InstructionPointer,
    NoBase,
};

struct MicroReg
{
    uint16_t packed = 0;

    constexpr MicroReg() = default;
    constexpr MicroReg(MicroRegKind kind, uint8_t index) :
        packed(static_cast<uint16_t>(static_cast<uint16_t>(kind) << 8 | index))
    {
    }

    constexpr MicroRegKind kind() const { return static_cast<MicroRegKind>((packed >> 8) & 0xFF); }
    constexpr uint8_t      index() const { return static_cast<uint8_t>(packed & 0xFF); }

    constexpr bool isValid() const { return kind() != MicroRegKind::Invalid; }
    constexpr bool isInt() const { return kind() == MicroRegKind::Int; }
    constexpr bool isFloat() const { return kind() == MicroRegKind::Float; }
    constexpr bool isSpecial() const { return kind() == MicroRegKind::Special; }

    constexpr bool isInstructionPointer() const { return isSpecial() && index() == static_cast<uint8_t>(MicroRegSpecial::InstructionPointer); }
    constexpr bool isNoBase() const { return isSpecial() && index() == static_cast<uint8_t>(MicroRegSpecial::NoBase); }

    static constexpr MicroReg invalid() { return MicroReg(MicroRegKind::Invalid, 0); }
    static constexpr MicroReg intReg(uint8_t index) { return MicroReg(MicroRegKind::Int, index); }
    static constexpr MicroReg floatReg(uint8_t index) { return MicroReg(MicroRegKind::Float, index); }
    static constexpr MicroReg instructionPointer() { return MicroReg(MicroRegKind::Special, static_cast<uint8_t>(MicroRegSpecial::InstructionPointer)); }
    static constexpr MicroReg noBase() { return MicroReg(MicroRegKind::Special, static_cast<uint8_t>(MicroRegSpecial::NoBase)); }

    constexpr bool operator==(const MicroReg& other) const { return packed == other.packed; }
    constexpr bool operator!=(const MicroReg& other) const { return packed != other.packed; }
};

SWC_END_NAMESPACE();
