#pragma once
#include "Backend/Micro/MicroReg.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;

namespace CodeGenMemoryHelpers
{
    void emitMemCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes);
    void emitMemSet(CodeGen& codeGen, MicroReg dstReg, MicroReg fillValueReg, uint32_t sizeInBytes);
    void emitMemZero(CodeGen& codeGen, MicroReg dstReg, uint32_t sizeInBytes);
    void emitMemMove(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes);
    void emitMemCompare(CodeGen& codeGen, MicroReg outResultReg, MicroReg leftAddressReg, MicroReg rightAddressReg, uint32_t sizeInBytes);
}

SWC_END_NAMESPACE();
