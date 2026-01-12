#pragma once
#include "Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class SymbolAttribute;

// Some runtime attributes have their own flag
enum class SwagAttributeFlagsE : uint64_t
{
    Zero      = 0,
    EnumFlags = 1 << 0,
    Strict    = 1 << 1,
};
using SwagAttributeFlags = EnumFlags<SwagAttributeFlagsE>;

// One attribute
struct AttributeInstance
{
    const SymbolAttribute* symbol = nullptr;
};

// A list of attributes
struct AttributeList
{
    SmallVector<AttributeInstance, 4> attributes;
    SwagAttributeFlags                swagFlags = SwagAttributeFlagsE::Zero;

    bool hasSwagFlag(SwagAttributeFlagsE fl) const { return swagFlags.has(fl); }
    void addSwagFlag(SwagAttributeFlags fl) { swagFlags.add(fl); }
};

SWC_END_NAMESPACE();
