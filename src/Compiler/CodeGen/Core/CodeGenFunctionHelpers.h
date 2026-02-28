#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolFunction;
class SymbolVariable;
struct CodeGenNodePayload;

namespace CodeGenFunctionHelpers
{
    struct FunctionParameterInfo
    {
        uint32_t    slotIndex     = 0;
        MicroOpBits opBits        = MicroOpBits::Zero;
        bool        isFloat       = false;
        bool        isIndirect    = false;
        bool        isRegisterArg = false;
    };

    FunctionParameterInfo functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, bool hasIndirectReturnArg);
    FunctionParameterInfo functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar);
    void                  emitLoadFunctionParameterToReg(CodeGen& codeGen, const SymbolFunction& symbolFunc, const FunctionParameterInfo& paramInfo, MicroReg dstReg);
    CodeGenNodePayload    materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const FunctionParameterInfo& paramInfo);
    CodeGenNodePayload    materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar);
    Result                codeGenCallExprCommon(CodeGen& codeGen, AstNodeRef calleeRef);
}

SWC_END_NAMESPACE();
