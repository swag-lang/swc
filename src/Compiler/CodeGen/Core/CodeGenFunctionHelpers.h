#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolFunction;
class SymbolVariable;
class Sema;
class TypeInfo;
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

    bool                  functionUsesIndirectReturnStorage(CodeGen& codeGen, const SymbolFunction& symbolFunc);
    bool                  usesCallerReturnStorage(CodeGen& codeGen, const SymbolVariable& symVar);
    CodeGenNodePayload    resolveCallerReturnStoragePayload(CodeGen& codeGen, const SymbolVariable& symVar);
    CodeGenNodePayload    resolveClosureCapturePayload(CodeGen& codeGen, const SymbolVariable& symVar);
    FunctionParameterInfo functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, bool hasIndirectReturnArg, bool hasClosureContextArg);
    FunctionParameterInfo functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar);
    void                  emitLoadFunctionParameterToReg(CodeGen& codeGen, const SymbolFunction& symbolFunc, const FunctionParameterInfo& paramInfo, MicroReg dstReg);
    CodeGenNodePayload    materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const FunctionParameterInfo& paramInfo);
    CodeGenNodePayload    materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar);
    uint32_t              checkedTypeSizeInBytes(CodeGen& codeGen, const TypeInfo& typeInfo);
    bool                  shouldMaterializeAddressBackedValue(CodeGen& codeGen, const TypeInfo& typeInfo, bool isIndirect, bool isFloat, uint8_t numBits);
    bool                  tryUseCurrentFunctionReturnStorageForDirectExpr(CodeGen& codeGen, AstNodeRef nodeRef, MicroReg& outStorageReg);
    bool                  needsPersistentCompilerRunReturn(const Sema& sema, TypeRef typeRef);
    void                  emitPersistCompilerRunValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstStorageReg, MicroReg srcStorageReg, MicroReg localStackBaseReg, uint32_t localStackSize);
}

SWC_END_NAMESPACE();
