#pragma once
#include "Backend/ABI/ABICall.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Support/Core/Result.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

struct CallConv;
class CodeGen;
struct CodeGenNodePayload;

namespace CodeGenCallHelpers
{
    Result codeGenCallExprCommon(CodeGen& codeGen, AstNodeRef calleeRef);
    void   appendPreparedStringCompareArg(SmallVector<ABICall::PreparedArg>& outArgs,
                                          CodeGen&                           codeGen,
                                          const CallConv&                    callConv,
                                          const CodeGenNodePayload&          operandPayload,
                                          TypeRef                            argTypeRef);
}

SWC_END_NAMESPACE();
