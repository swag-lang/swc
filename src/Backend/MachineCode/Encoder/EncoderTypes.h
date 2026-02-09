#pragma once
#include "Backend/MachineCode/Micro/MicroTypes.h"

SWC_BEGIN_NAMESPACE();

enum class EncoderSymbolKind
{
    Function,
    Extern,
    Custom,
    Constant,
};

struct EncoderJumpLabel
{
    uint32_t  ipDest = 0;
    MicroJump jump{};
};

struct EncoderSymbol
{
    IdentifierRef     name;
    EncoderSymbolKind kind  = EncoderSymbolKind::Custom;
    uint32_t          value = 0;
    uint32_t          index = 0;
};

struct EncoderFunction
{
    uint32_t                      symbolIndex  = 0;
    uint32_t                      startAddress = 0;
    std::vector<EncoderJumpLabel> labelsToSolve;
};

inline uint32_t getEncoderNumBits(MicroOpBits opBits)
{
    switch (opBits)
    {
        case MicroOpBits::B8: return 8;
        case MicroOpBits::B16: return 16;
        case MicroOpBits::B32: return 32;
        case MicroOpBits::B64: return 64;
        default: return 0;
    }
}

SWC_END_NAMESPACE();
