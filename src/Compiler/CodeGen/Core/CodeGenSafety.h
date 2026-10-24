#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroTypes.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Math/Fold.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolFunction;
class SymbolVariable;
class TypeInfo;
struct AstIntrinsicCallExpr;
struct CodeGenNodePayload;

namespace CodeGenSafety
{
    struct ShiftIntLikeContext
    {
        AstNodeRef countOperandRef;
        MicroReg   valueReg;
        MicroReg   countReg;

        const TypeInfo* valueType = nullptr;
        const TypeInfo* countType = nullptr;

        MicroOpBits valueBits = MicroOpBits::Zero;
        MicroOpBits countBits = MicroOpBits::Zero;
        TokenId     op        = TokenId::Invalid;
    };

    using LoadNumericOperandFn        = void (*)(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef);
    using MaterializeNumericOperandFn = void (*)(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, TypeRef resultTypeRef);

    void   configureValueBorrowSites(CodeGen& codeGen, AstNodeRef bodyRef, uint64_t& frameSize);
    void   initializeValueBorrowSites(CodeGen& codeGen);
    Result emitValueBorrowSite(CodeGen& codeGen, AstNodeRef homeRef);

    bool isBorrowedValueType(CodeGen& codeGen, TypeRef typeRef);
    bool hasValueBorrowSafety(const CodeGen& codeGen);
    bool isUnborrowableLocalWrite(CodeGen& codeGen, AstNodeRef targetRef);

    Result prepareValueBorrowSafety(CodeGen& codeGen);
    Result emitValueBorrowBegin(CodeGen& codeGen, uint32_t recordOffset, MicroReg address, uint64_t size);
    Result emitValueBorrowEnd(CodeGen& codeGen, uint32_t recordOffset);
    Result emitValueBorrowWrite(CodeGen& codeGen, MicroReg address, uint64_t size);
    Result emitValueBorrowWrite(CodeGen& codeGen, MicroReg address, MicroReg size);
    Result emitValueBorrowWriteElements(CodeGen& codeGen, MicroReg address, MicroReg count, uint64_t elementSize);

    bool hasMathRuntimeSafety(const CodeGen& codeGen);
    bool hasOverflowRuntimeSafety(const CodeGen& codeGen);
    bool hasLifecycleRuntimeSafety(const CodeGen& codeGen);
    bool hasLifecycleSanity(const CodeGen& codeGen);
    bool hasLifecycleInvalidate(const CodeGen& codeGen);

    Result emitLifecyclePoison(CodeGen& codeGen, MicroReg addrReg, uint64_t sizeInBytes);
    Result emitLifecyclePoisonLoop(CodeGen& codeGen, MicroReg addrReg, MicroReg countReg, uint64_t elementSizeInBytes);
    Result emitLifecycleInvalidate(CodeGen& codeGen, MicroReg addrReg, TypeRef typeRef, AstNodeRef sourceRef);

    Result emitBoundCheck(CodeGen& codeGen, AstNodeRef indexRef, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload, MicroReg indexReg);
    Result emitLoopBoundCheck(CodeGen& codeGen, AstNodeRef nodeRef, MicroReg lowerReg, MicroReg upperReg, const TypeInfo& indexType);
    Result emitSliceRangeCheck(CodeGen& codeGen, AstNodeRef nodeRef, MicroReg lowReg, MicroReg endExclusiveReg, MicroReg sourceCountReg);
    Result emitSwitchCheck(CodeGen& codeGen, const AstNode& node, SymbolFunction* panicFunction);

    Result emitOverflowCheck(CodeGen& codeGen, const AstNode& node);
    Result emitOverflowTrapOnFailure(CodeGen& codeGen, const AstNode& node, MicroCond successCond);
    Result emitIntArithmeticOverflowCheck(CodeGen& codeGen, const AstNode& node, TokenId binaryTokId, bool isSigned);
    Result emitShiftIntLike(CodeGen& codeGen, const AstNode& node, const ShiftIntLikeContext& shiftCtx);
    Result emitDivOrModIntLike(CodeGen& codeGen, const AstNode& node, MicroReg leftReg, MicroReg rightReg, MicroOp op, MicroOpBits opBits, bool isSigned, bool zeroOnOverflow);

    Result emitIntLikeCastOverflowCheck(CodeGen& codeGen, const AstNode& node, MicroReg srcReg, const TypeInfo& srcType, const TypeInfo& dstType);
    Result emitFloatToIntCastOverflowCheck(CodeGen& codeGen, const AstNode& node, MicroReg srcReg, const TypeInfo& srcType, const TypeInfo& dstType);
    Result emitShiftAmountCheck(CodeGen& codeGen, const AstNode& node);
    Result emitMathCheck(CodeGen& codeGen, const AstNode& node);

    Result emitNotNullCheck(CodeGen& codeGen, const AstNode& node);
    Result emitNotNullGuard(CodeGen& codeGen, AstNodeRef ownerRef, AstNodeRef valueRef, std::string_view what);
    Result emitNullExtractCheck(CodeGen& codeGen, const AstNode& node, MicroReg valueReg, bool valueIsAddress, TypeRef resultTypeRef);
    Result emitLateReadCheck(CodeGen& codeGen, const AstNode& node, MicroReg addrReg, TypeRef lateTypeRef);
    Result emitTaggedCaseCheck(CodeGen& codeGen, const AstNode& node, MicroReg unionAddressReg, const SymbolVariable& member);

    Result emitUnaryMathDomainCheck(CodeGen& codeGen, MicroReg valueReg, const TypeInfo& floatType, Math::FoldIntrinsicUnaryFloatOp op, MicroLabelRef failLabel);
    Result emitFloatNanCheck(CodeGen& codeGen, const AstNode& node, MicroReg valueReg, const TypeInfo& floatType);
    Result emitUnaryMathIntrinsicCall(CodeGen& codeGen, const AstIntrinsicCallExpr& node, Math::FoldIntrinsicUnaryFloatOp op, MaterializeNumericOperandFn materializeOperandFn);
    Result emitPowIntrinsicCall(CodeGen& codeGen, const AstIntrinsicCallExpr& node, LoadNumericOperandFn loadOperandFn);

    Result emitDynCastCheck(CodeGen& codeGen, SymbolFunction& panicFunction, const AstNode& node);
    Result emitUnreachableCheck(CodeGen& codeGen, const AstNode& node);
}

SWC_END_NAMESPACE();
