#pragma once
#include "Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class SymbolAttribute;

// Some runtime attributes have their own flag
enum class SwagAttributeFlagsE : uint64_t
{
    Zero         = 0,
    EnumFlags    = 1 << 0,
    Strict       = 1 << 1,
    Complete     = 1 << 2,
    Incomplete   = 1 << 3,
    AttrMulti    = 1 << 4,
    ConstExpr    = 1 << 5,
    PrintBc      = 1 << 6,
    PrintBcGen   = 1 << 7,
    PrintAsm     = 1 << 8,
    Compiler     = 1 << 9,
    Inline       = 1 << 10,
    NoInline     = 1 << 11,
    PlaceHolder  = 1 << 12,
    NoPrint      = 1 << 13,
    Macro        = 1 << 14,
    Mixin        = 1 << 15,
    Implicit     = 1 << 16,
    Overload     = 1 << 17,
    CalleeReturn = 1 << 18,
    Discardable  = 1 << 19,
    NotGeneric   = 1 << 20,
    Tls          = 1 << 21,
    NoCopy       = 1 << 22,
    Opaque       = 1 << 23,
    EnumIndex    = 1 << 24,
    NoDuplicate  = 1 << 25,
    NoDoc        = 1 << 26,
    Global       = 1 << 27,
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
