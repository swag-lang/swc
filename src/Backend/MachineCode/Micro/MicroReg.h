#pragma once

SWC_BEGIN_NAMESPACE();

enum class MicroRegKind : uint8_t
{
    Invalid,
    Int,
    Float,
    Special,
    Virtual,
};

enum class MicroRegSpecial : uint8_t
{
    InstructionPointer,
    NoBase,
};

struct MicroReg
{
    static constexpr uint32_t K_KIND_SHIFT = 24;
    static constexpr uint32_t K_INDEX_MASK = 0x00FFFFFFu;

    uint32_t packed = 0;

    constexpr MicroReg() = default;
    constexpr MicroReg(MicroRegKind kind, uint32_t index) :
        packed((static_cast<uint32_t>(kind) << K_KIND_SHIFT) | (index & K_INDEX_MASK))
    {
    }

    constexpr MicroRegKind kind() const { return static_cast<MicroRegKind>((packed >> K_KIND_SHIFT) & 0xFF); }
    constexpr uint32_t     index() const { return packed & K_INDEX_MASK; }

    constexpr bool isValid() const { return kind() != MicroRegKind::Invalid; }
    constexpr bool isInt() const { return kind() == MicroRegKind::Int; }
    constexpr bool isFloat() const { return kind() == MicroRegKind::Float; }
    constexpr bool isVirtual() const { return kind() == MicroRegKind::Virtual; }

    constexpr bool isSpecial() const { return kind() == MicroRegKind::Special; }
    constexpr bool isInstructionPointer() const { return isSpecial() && index() == static_cast<uint32_t>(MicroRegSpecial::InstructionPointer); }
    constexpr bool isNoBase() const { return isSpecial() && index() == static_cast<uint32_t>(MicroRegSpecial::NoBase); }

    static constexpr MicroReg invalid() { return MicroReg(MicroRegKind::Invalid, 0); }
    static constexpr MicroReg intReg(uint32_t index) { return MicroReg(MicroRegKind::Int, index); }
    static constexpr MicroReg floatReg(uint32_t index) { return MicroReg(MicroRegKind::Float, index); }
    static constexpr MicroReg virtualReg(uint32_t index) { return MicroReg(MicroRegKind::Virtual, index); }
    static constexpr MicroReg instructionPointer() { return MicroReg(MicroRegKind::Special, static_cast<uint32_t>(MicroRegSpecial::InstructionPointer)); }
    static constexpr MicroReg noBase() { return MicroReg(MicroRegKind::Special, static_cast<uint32_t>(MicroRegSpecial::NoBase)); }

    constexpr bool operator==(const MicroReg& other) const { return packed == other.packed; }
    constexpr bool operator!=(const MicroReg& other) const { return packed != other.packed; }
};

SWC_END_NAMESPACE();
