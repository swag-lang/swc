#pragma once
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

// A CodeView local or parameter, addressed relative to a frame register.
struct DebugPdbLocal
{
    Utf8     name;
    uint32_t typeIndex   = 0; // CodeView TPI type index (0 = T_NOTYPE)
    int32_t  frameOffset = 0;
    uint16_t cvRegister  = 0; // CodeView register that addresses the frame
    bool     isParam     = false;
};

SWC_END_NAMESPACE();
