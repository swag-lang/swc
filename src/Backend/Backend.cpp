#include "pch.h"
#include "Backend/Backend.h"
#include "Backend/MachineCode/ABI/CallConv.h"

SWC_BEGIN_NAMESPACE();

namespace Backend
{
    void setup()
    {
        CallConv::setup();
    }
}

SWC_END_NAMESPACE();
