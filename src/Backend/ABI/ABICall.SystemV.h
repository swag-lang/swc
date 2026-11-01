#pragma once
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/SystemVAbi.h"

SWC_BEGIN_NAMESPACE();

namespace ABICall
{
    // The packed-address bridge keeps aggregate storage whole until the System V
    // allocator has committed every eightbyte of the argument to registers or stack.
    PreparedCall prepareSystemVStorageArgs(MicroBuilder& builder, CallConvKind callConvKind, std::span<const PreparedArg> args);
    void storeSystemVReturn(MicroBuilder& builder, const Return& ret);
    void storeSystemVReturn(MicroBuilder& builder, MicroReg destination, const SystemVAbi::Classification& type);
    void storeSystemVArgument(MicroBuilder& builder, MicroReg destination, const SystemVAbi::Classification& type, const SystemVAbi::ArgumentLocation& location);
    void loadSystemVReturn(MicroBuilder& builder, MicroReg source, const SystemVAbi::Classification& type);
    void callSystemVAddress(MicroBuilder& builder, CallConvKind callConvKind, uint64_t targetAddress, std::span<const Arg> args, const Return& ret);
}

SWC_END_NAMESPACE();
