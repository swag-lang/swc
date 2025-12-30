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
    AttributeFlagsE                   flags = AttributeFlagsE::Zero;
};

SWC_END_NAMESPACE()
