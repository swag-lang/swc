#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Support/Core/Result.h"
#include "Support/Math/Fold.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolFunction;
class TypeInfo;
struct AstIntrinsicCallExpr;
struct CodeGenNodePayload;

namespace CodeGenSafety
{
    using LoadNumericOperandFn        = void (*)(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef);
    using MaterializeNumericOperandFn = void (*)(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, TypeRef resultTypeRef);

    bool hasMathRuntimeSafety(const CodeGen& codeGen);

    Result emitBoundCheck(CodeGen& codeGen, AstNodeRef indexRef, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload, MicroReg indexReg);
    Result emitSwitchCheck(CodeGen& codeGen, const AstNode& node, SymbolFunction* panicFunction);
    Result emitMathCheck(CodeGen& codeGen, const AstNode& node);
    Result emitUnaryMathDomainCheck(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& floatType, Math::FoldIntrinsicUnaryFloatOp op, MicroLabelRef failLabel);
    Result emitFloatNanCheck(CodeGen& codeGen, const AstNode& node, MicroReg valueReg, const TypeInfo& floatType);
    Result emiUnaryMathIntrinsicCall(CodeGen& codeGen, const AstIntrinsicCallExpr& node, Math::FoldIntrinsicUnaryFloatOp op, MaterializeNumericOperandFn materializeOperandFn);
    Result emitPowIntrinsicCall(CodeGen& codeGen, const AstIntrinsicCallExpr& node, LoadNumericOperandFn loadOperandFn);
    Result emitUnreachableCheck(CodeGen& codeGen, const AstNode& node);
}

SWC_END_NAMESPACE();
