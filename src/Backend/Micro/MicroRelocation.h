#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class Symbol;

struct MicroRelocation
{
    static constexpr uint64_t K_SELF_ADDRESS = std::numeric_limits<uint64_t>::max();
    static constexpr uint32_t K_INVALID_SOURCE = std::numeric_limits<uint32_t>::max();

    enum class Kind : uint8_t
    {
        ForeignFunctionAddress,
        ConstantAddress,
        LocalFunctionAddress,
        CompilerAddress,
        GlobalZeroAddress,
        GlobalInitAddress,
    };

    // How the patch is written into the code stream. Absolute64 stores the
    // target address itself, in a trailing eight-byte immediate. Relative32
    // stores the signed distance from the end of the instruction to the target,
    // in a trailing four-byte displacement - which is what x64 RIP-relative
    // addressing reads, and what lets a constant be reached without first
    // materializing its address in a register.
    enum class Form : uint8_t
    {
        Absolute64,
        Relative32,
    };

    Kind     kind       = Kind::ConstantAddress;
    Form     form       = Form::Absolute64;
    uint32_t codeOffset = 0;
    // End of the instruction the displacement belongs to, which is where a
    // Relative32 distance is measured from. Unused by Absolute64.
    uint32_t      relativeEndOffset = 0;
    MicroInstrRef instructionRef    = MicroInstrRef::invalid();
    uint64_t      targetAddress     = 0;
    Symbol*       targetSymbol      = nullptr;
    ConstantRef   constantRef       = ConstantRef::invalid();
    uint32_t      constantShard     = K_INVALID_SOURCE;
    uint32_t      constantOffset    = K_INVALID_SOURCE;

    bool hasConstantSource() const noexcept { return constantShard != K_INVALID_SOURCE && constantOffset != K_INVALID_SOURCE; }
};

SWC_END_NAMESPACE();
