#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolFunction;
class SymbolVariable;
struct CodeGenNodePayload;

namespace CodeGenHelpers
{
    struct FunctionParameterInfo
    {
        uint32_t    slotIndex     = 0;
        MicroOpBits opBits        = MicroOpBits::Zero;
        bool        isFloat       = false;
        bool        isIndirect    = false;
        bool        isRegisterArg = false;
    };

    FunctionParameterInfo functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar);
    void                  emitLoadFunctionParameterToReg(CodeGen& codeGen, const SymbolFunction& symbolFunc, const FunctionParameterInfo& paramInfo, MicroReg dstReg);
    CodeGenNodePayload    materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar);

    void emitMemCopy(CodeGen& codeGen, MicroReg dstReg, MicroReg srcAddressReg, uint32_t sizeInBytes);
}

SWC_END_NAMESPACE();
