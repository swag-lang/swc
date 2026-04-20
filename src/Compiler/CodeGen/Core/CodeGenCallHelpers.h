#pragma once
#include "Backend/ABI/ABICall.h"
#include "Backend/Micro/MicroReg.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Support/Core/Result.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

struct CallConv;
class CodeGen;
class SymbolFunction;
struct CodeGenNodePayload;
struct ResolvedCallArgument;

namespace CodeGenCallHelpers
{
    Result codeGenCallExprCommon(CodeGen& codeGen, AstNodeRef calleeRef);
    bool   materializeTypedConstantPayload(CodeGen& codeGen, CodeGenNodePayload& outPayload, TypeRef targetTypeRef, ConstantRef constantRef);
    Result emitCallWithResolvedArgs(CodeGen& codeGen, AstNodeRef callRef, SymbolFunction& calledFunction, std::span<const ResolvedCallArgument> args);
    Result emitCallWithResolvedArgsToReg(CodeGen& codeGen, AstNodeRef callRef, SymbolFunction& calledFunction, std::span<const ResolvedCallArgument> args, MicroReg resultReg);
    Result emitThrowableFailureJump(CodeGen& codeGen);
    Result emitThrowableFailureJumpIfHasError(CodeGen& codeGen);
    void   appendPreparedStringCompareArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, const CallConv& callConv, const CodeGenNodePayload& operandPayload, TypeRef argTypeRef);
    void   appendDirectPreparedArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, const CallConv& callConv, TypeRef argTypeRef, MicroReg srcReg);
    Result emitRuntimeCallWithDirectArgs(CodeGen& codeGen, SymbolFunction& runtimeFunction, std::span<const MicroReg> argRegs);
    Result emitRuntimeCallWithDirectArgsToReg(CodeGen& codeGen, SymbolFunction& runtimeFunction, std::span<const MicroReg> argRegs, MicroReg resultReg);
}

SWC_END_NAMESPACE();
