#pragma once
#include "Backend/ABI/ABICall.h"
#include "Backend/Micro/MicroReg.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Support/Core/Result.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

struct CallConv;
class CodeGen;
struct CodeGenNodePayload;
struct ResolvedCallArgument;

namespace CodeGenCallHelpers
{
    Result codeGenCallExprCommon(CodeGen& codeGen, AstNodeRef calleeRef);
    Result emitCallWithResolvedArgsToReg(CodeGen& codeGen, AstNodeRef callRef, SymbolFunction& calledFunction, std::span<const ResolvedCallArgument> args, MicroReg resultReg);
    void   appendPreparedStringCompareArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, const CallConv& callConv, const CodeGenNodePayload& operandPayload, TypeRef argTypeRef);
    void   appendDirectPreparedArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, const CallConv& callConv, TypeRef argTypeRef, MicroReg srcReg);
    Result emitRuntimeCallWithDirectArgsToReg(CodeGen& codeGen, SymbolFunction& runtimeFunction, std::span<const MicroReg> argRegs, MicroReg resultReg);
}

SWC_END_NAMESPACE();
