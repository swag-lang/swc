#pragma once
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE()

class SymbolAttribute;

enum class AttributeFlagsE : uint64_t
{
    Zero      = 0,
    EnumFlags = 1 << 0,
};
using AttributeFlags = EnumFlags<AttributeFlagsE>;

// One attribute
struct AttributeInstance
{
    const SymbolAttribute* symbol = nullptr;
};

// A list of attributes
struct AttributeList
{
    SmallVector<AttributeInstance, 4> attributes;
    AttributeFlags                    flags = AttributeFlagsE::Zero;

    bool hasFlag(AttributeFlagsE fl) const { return flags.has(fl); }
    void addFlag(AttributeFlags fl) { flags.add(fl); }
};

SWC_END_NAMESPACE()
