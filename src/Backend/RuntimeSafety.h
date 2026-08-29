#pragma once

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    enum class SafetyWhat : uint16_t
    {
        BoundCheck  = 0x0001,
        Overflow    = 0x0002,
        Math        = 0x0004,
        DynCast     = 0x0008,
        Switch      = 0x0010,
        Bool        = 0x0020,
        NaN         = 0x0040,
        Unreachable = 0x0080,
        Null        = 0x0100,
        Memory      = 0x0200,
        Expect      = 0x0400,
        Lifecycle   = 0x0800,
        None        = 0x0000,
        All         = 0xFFFF,
    };
}

SWC_END_NAMESPACE();
