#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolFunction;
class SymbolVariable;
class Sema;
class TypeInfo;
enum class CallConvKind : uint8_t;
struct CallConv;
struct CodeGenNodePayload;

namespace CodeGenFunctionHelpers
{
    struct FunctionParameterInfo
    {
        uint32_t    slotIndex         = 0;
        uint64_t    stackOffset       = 0;
        MicroOpBits opBits            = MicroOpBits::Zero;
        bool        isFloat           = false;
        bool        isSigned          = false;
        bool        isIndirect        = false;
        bool        needsIndirectCopy = false;
        bool        isRegisterArg     = false;
        uint8_t     numBits           = 0;
    };

    // The parameter symbol the function itself declares for 'symVar', when 'symVar' is a
    // clone that carries the same slot or name. Null when 'symVar' already is the canonical one.
    const SymbolVariable* resolveCanonicalParameter(const SymbolFunction& symbolFunc, const SymbolVariable& symVar);

    // Opens the local stack frame: reserves it on the stack and pins its base in a virtual
    // register constrained to a callee-saved one, so the base survives every call the body makes.
    void emitLocalStackFramePrologue(CodeGen& codeGen, CallConvKind callConvKind);

    bool                  functionUsesIndirectReturnStorage(CodeGen& codeGen, const SymbolFunction& symbolFunc);
    bool                  usesCallerReturnStorage(CodeGen& codeGen, const SymbolVariable& symVar);
    CodeGenNodePayload    resolveCallerReturnStoragePayload(CodeGen& codeGen, const SymbolVariable& symVar);
    CodeGenNodePayload    resolveClosureCapturePayload(CodeGen& codeGen, const SymbolVariable& symVar);
    CodeGenNodePayload    resolveStoredVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar);
    FunctionParameterInfo functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, bool hasIndirectReturnArg, bool hasClosureContextArg);
    FunctionParameterInfo functionParameterInfo(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar);
    bool                  canUseIncomingIndirectParameterAsAddressableParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar);
    bool                  isBorrowedIndirectParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar);
    bool                  isByValueAggregateParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar);
    void                  emitLoadFunctionParameterToReg(CodeGen& codeGen, const SymbolFunction& symbolFunc, const FunctionParameterInfo& paramInfo, MicroReg dstReg);
    CodeGenNodePayload    materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const FunctionParameterInfo& paramInfo);
    CodeGenNodePayload    materializeFunctionParameter(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar);
    uint32_t              checkedTypeSizeInBytes(CodeGen& codeGen, const TypeInfo& typeInfo);
    bool                  shouldMaterializeAddressBackedValue(CodeGen& codeGen, const TypeInfo& typeInfo, bool isIndirect, bool isFloat, uint8_t numBits);
    Result                emitTypeDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg);
    Result                emitTypeDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg, uint32_t count);
    Result                emitTypeDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg, MicroReg countReg);
    Result                emitStructDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg);
    Result                emitStructDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg, uint32_t count);
    Result                emitStructDefaultValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstAddressReg, MicroReg countReg);
    void                  emitStackPointerSubtract(CodeGen& codeGen, const CallConv& callConv, uint64_t sizeInBytes, MicroReg scratchReg);
    bool                  tryUseDirectVarInitStorage(CodeGen& codeGen, AstNodeRef nodeRef, TypeRef typeRef, MicroReg& outStorageReg, SymbolVariable*& outStorageSym);
    bool                  tryUseDirectReturnStorage(CodeGen& codeGen, AstNodeRef nodeRef, TypeRef typeRef, MicroReg& outStorageReg, SymbolVariable*& outStorageSym);
    bool                  needsPersistentCompilerRunReturn(const Sema& sema, TypeRef typeRef);
    void                  emitPersistCompilerRunValue(CodeGen& codeGen, TypeRef typeRef, MicroReg dstStorageReg, MicroReg srcStorageReg, MicroReg localStackBaseReg, uint32_t localStackSize);
    Result                emitFallibleWrapperPreNode(CodeGen& codeGen, AstNodeRef nodeRef);
    Result                emitFallibleWrapperPostNode(CodeGen& codeGen, AstNodeRef nodeRef);
}

SWC_END_NAMESPACE();
