#pragma once
#include "Backend/ABI/ABICall.h"

SWC_BEGIN_NAMESPACE();

namespace ABICall
{
    // The packed-address bridge keeps aggregate storage whole until the System V
    // allocator has committed every eightbyte of the argument to registers or stack.
    void callSystemVAddress(MicroBuilder& builder, CallConvKind callConvKind, uint64_t targetAddress, std::span<const Arg> args, const Return& ret);
}

SWC_END_NAMESPACE();
