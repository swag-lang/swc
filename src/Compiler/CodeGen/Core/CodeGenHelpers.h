#pragma once
#include "Backend/CodeGen/Micro/MicroReg.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;

namespace CodeGenHelpers
{
    void emitMemCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes);
}

SWC_END_NAMESPACE();
