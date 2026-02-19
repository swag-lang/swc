#pragma once
#include "Backend/Micro/MicroTypes.h"

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

SWC_END_NAMESPACE();
