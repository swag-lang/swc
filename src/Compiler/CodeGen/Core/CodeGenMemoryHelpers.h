#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolVariable;
class TypeInfo;
struct CodeGenNodePayload;

namespace CodeGenMemoryHelpers
{
    void     emitGlobalVariableAddress(CodeGen& codeGen, MicroReg reg, const SymbolVariable& symVar);
    void     emitConvertFloatToInt(CodeGen& codeGen, MicroReg dstReg, MicroReg srcReg, const TypeInfo& srcType, const TypeInfo& dstType);
    void     loadOperandToRegister(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& payload, TypeRef regTypeRef, MicroOpBits opBits);
    MicroReg materializeScalarPayloadForStore(CodeGen& codeGen, const CodeGenNodePayload& srcPayload, TypeRef srcTypeRef, TypeRef targetTypeRef);
    void     storePayloadToAddress(CodeGen& codeGen, MicroReg dstReg, const CodeGenNodePayload& srcPayload, uint32_t copySize);
    void     emitMemCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes, const SourceCodeRef& sourceCodeRef = SourceCodeRef::invalid(), const SourceCodeRef& destinationCodeRef = SourceCodeRef::invalid());
    void     emitMemFill(CodeGen& codeGen, MicroReg dstReg, MicroReg fillValueReg, uint32_t elementSizeInBytes, uint32_t elementCount);
    void     emitMemRepeatCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t elementSizeInBytes, uint32_t elementCount);
    void     emitMemSet(CodeGen& codeGen, MicroReg dstReg, MicroReg fillValueReg, uint32_t sizeInBytes);
    void     emitMemZero(CodeGen& codeGen, MicroReg dstReg, uint32_t sizeInBytes);
    void     emitMemMove(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes);
    void     emitMemCompare(CodeGen& codeGen, MicroReg outResultReg, MicroReg leftAddressReg, MicroReg rightAddressReg, uint32_t sizeInBytes);
    void     emitCStringCountReg(CodeGen& codeGen, MicroReg countReg, MicroReg cstrReg);
}

SWC_END_NAMESPACE();
