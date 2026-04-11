#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
struct CodeGenNodePayload;

namespace CodeGenMemoryHelpers
{
    void loadOperandToRegister(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef regTypeRef, MicroOpBits opBits);
    void emitMemCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes);
    void emitMemFill(CodeGen& codeGen, MicroReg dstReg, MicroReg fillValueReg, uint32_t elementSizeInBytes, uint32_t elementCount);
    void emitMemRepeatCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t elementSizeInBytes, uint32_t elementCount);
    void emitMemSet(CodeGen& codeGen, MicroReg dstReg, MicroReg fillValueReg, uint32_t sizeInBytes);
    void emitMemZero(CodeGen& codeGen, MicroReg dstReg, uint32_t sizeInBytes);
    void emitMemMove(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes);
    void emitMemCompare(CodeGen& codeGen, MicroReg outResultReg, MicroReg leftAddressReg, MicroReg rightAddressReg, uint32_t sizeInBytes);
}

SWC_END_NAMESPACE();
