#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"
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
    bool hasOverflowRuntimeSafety(const CodeGen& codeGen);

    Result emitBoundCheck(CodeGen& codeGen, AstNodeRef indexRef, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload, MicroReg indexReg);
    Result emitLoopBoundCheck(CodeGen& codeGen, AstNodeRef nodeRef, MicroReg lowerReg, MicroReg upperReg, const TypeInfo& indexType, bool inclusive);
    Result emitSwitchCheck(CodeGen& codeGen, const AstNode& node, SymbolFunction* panicFunction);
    Result emitOverflowCheck(CodeGen& codeGen, const AstNode& node);
    Result emitOverflowTrapOnFailure(CodeGen& codeGen, const AstNode& node, MicroCond successCond);
    Result emitIntArithmeticOverflowCheck(CodeGen& codeGen, const AstNode& node, TokenId binaryTokId, bool isSigned);
    Result emitShiftIntLike(CodeGen& codeGen, const AstNode& node, MicroReg valueReg, MicroReg rightReg, const TypeInfo& operationType, MicroOpBits opBits, TokenId shiftTokId, bool allowWrap);
    Result emitSignedDivOrModIntLike(CodeGen& codeGen, const AstNode& node, MicroReg leftReg, MicroReg rightReg, MicroOp op, MicroOpBits opBits, bool zeroOnOverflow);
    Result emitIntLikeCastOverflowCheck(CodeGen& codeGen, const AstNode& node, MicroReg srcReg, const TypeInfo& srcType, const TypeInfo& dstType);
    Result emitFloatToIntCastOverflowCheck(CodeGen& codeGen, const AstNode& node, MicroReg srcReg, const TypeInfo& srcType, const TypeInfo& dstType);
    Result emitNegativeShiftCheck(CodeGen& codeGen, const AstNode& node);
    Result emitMathCheck(CodeGen& codeGen, const AstNode& node);
    Result emitUnaryMathDomainCheck(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& floatType, Math::FoldIntrinsicUnaryFloatOp op, MicroLabelRef failLabel);
    Result emitFloatNanCheck(CodeGen& codeGen, const AstNode& node, MicroReg valueReg, const TypeInfo& floatType);
    Result emitUnaryMathIntrinsicCall(CodeGen& codeGen, const AstIntrinsicCallExpr& node, Math::FoldIntrinsicUnaryFloatOp op, MaterializeNumericOperandFn materializeOperandFn);
    Result emitPowIntrinsicCall(CodeGen& codeGen, const AstIntrinsicCallExpr& node, LoadNumericOperandFn loadOperandFn);
    Result emitDynCastCheck(CodeGen& codeGen, SymbolFunction& panicFunction, const AstNode& node);
    Result emitUnreachableCheck(CodeGen& codeGen, const AstNode& node);
}

SWC_END_NAMESPACE();
