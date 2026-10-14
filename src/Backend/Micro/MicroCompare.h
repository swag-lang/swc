#pragma once
#include "Backend/Micro/MicroTypes.h"

SWC_BEGIN_NAMESPACE();

// Snapshot integer comparison outcomes without retaining the source registers.
// Two bytes also fit the sanitizer state's existing tail padding.
struct MicroCompare
{
    int8_t unsignedOrder = 2;
    int8_t signedOrder   = 2;

    bool operator==(const MicroCompare&) const = default;
    bool isKnown() const { return unsignedOrder != 2; }

    static MicroCompare evaluate(uint64_t left, uint64_t right, MicroOpBits bits)
    {
        const uint64_t mask = getBitsMask(bits);
        if (!mask)
            return {};
        left &= mask;
        right &= mask;
        const int8_t   unsignedOrder = static_cast<int8_t>((left > right) - (left < right));
        const uint64_t sign          = (mask >> 1) + 1;
        left ^= sign;
        right ^= sign;
        return {unsignedOrder, static_cast<int8_t>((left > right) - (left < right))};
    }

    bool tryCondition(bool& outTaken, MicroCond condition) const
    {
        if (!isKnown())
            return false;
        switch (condition)
        {
            case MicroCond::Equal:
            case MicroCond::Zero: outTaken = unsignedOrder == 0; break;
            case MicroCond::NotEqual:
            case MicroCond::NotZero: outTaken = unsignedOrder != 0; break;
            case MicroCond::Above: outTaken = unsignedOrder > 0; break;
            case MicroCond::AboveOrEqual: outTaken = unsignedOrder >= 0; break;
            case MicroCond::Below: outTaken = unsignedOrder < 0; break;
            case MicroCond::BelowOrEqual:
            case MicroCond::NotAbove: outTaken = unsignedOrder <= 0; break;
            case MicroCond::Greater: outTaken = signedOrder > 0; break;
            case MicroCond::GreaterOrEqual: outTaken = signedOrder >= 0; break;
            case MicroCond::Less: outTaken = signedOrder < 0; break;
            case MicroCond::LessOrEqual: outTaken = signedOrder <= 0; break;
            case MicroCond::Unconditional: outTaken = true; break;
            default: return false;
        }
        return true;
    }
};

SWC_END_NAMESPACE();
