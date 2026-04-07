#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TokenId canonicalBinaryToken(TokenId tokId)
    {
        switch (tokId)
        {
            case TokenId::SymPlusEqual:
            case TokenId::SymMinusEqual:
            case TokenId::SymAsteriskEqual:
            case TokenId::SymSlashEqual:
            case TokenId::SymAmpersandEqual:
            case TokenId::SymPipeEqual:
            case TokenId::SymCircumflexEqual:
            case TokenId::SymPercentEqual:
            case TokenId::SymLowerLowerEqual:
            case TokenId::SymGreaterGreaterEqual:
                return Token::assignToBinary(tokId);

            default:
                break;
        }

        return tokId;
    }

    enum class BinaryEncodingKind : uint8_t
    {
        IntLike,
        Float,
        PointerOffset,
        PointerDiff,
    };

    struct BinaryEncodeContext
    {
        const CodeGenNodePayload* leftPayload         = nullptr;
        const CodeGenNodePayload* rightPayload        = nullptr;
        TypeRef                   leftOperandTypeRef  = TypeRef::invalid();
        TypeRef                   rightOperandTypeRef = TypeRef::invalid();
        TypeRef                   resultTypeRef       = TypeRef::invalid();
        TypeRef                   operationTypeRef    = TypeRef::invalid();
        BinaryEncodingKind        encodingKind        = BinaryEncodingKind::IntLike;
        uint64_t                  pointerStride       = 0;
    };

    uint64_t pointerStrideSize(CodeGen& codeGen, TypeRef pointerTypeRef)
    {
        const TypeInfo& pointerType = codeGen.typeMgr().get(pointerTypeRef);
        return CodeGenTypeHelpers::blockPointerStride(codeGen.ctx(), pointerType);
    }

    BinaryEncodingKind resolveBinaryEncodingKind(TokenId tokId, const TypeInfo& leftType, const TypeInfo& rightType)
    {
        switch (tokId)
        {
            case TokenId::SymPlus:
                if ((leftType.isBlockPointer() && rightType.isScalarNumeric()) ||
                    (leftType.isScalarNumeric() && rightType.isBlockPointer()))
                    return BinaryEncodingKind::PointerOffset;
                break;

            case TokenId::SymMinus:
                if (leftType.isBlockPointer() && rightType.isScalarNumeric())
                    return BinaryEncodingKind::PointerOffset;
                if (leftType.isBlockPointer() && rightType.isBlockPointer())
                    return BinaryEncodingKind::PointerDiff;
                break;

            default:
                break;
        }

        if (leftType.isFloat())
            return BinaryEncodingKind::Float;

        if (leftType.isIntLike())
            return BinaryEncodingKind::IntLike;

        SWC_UNREACHABLE();
    }

    TypeRef resolveBinaryOperandSourceTypeRef(CodeGen& codeGen, AstNodeRef operandRef, const SemaNodeView& operandView, const CodeGenNodePayload& operandPayload)
    {
        const AstNode& operand = codeGen.node(operandRef);
        if (operand.is(AstNodeId::CastExpr))
        {
            const auto& castNode = operand.cast<AstCastExpr>();
            if (!castNode.hasFlag(AstCastExprFlagsE::Explicit) && castNode.nodeExprRef.isValid())
            {
                const TypeRef storedSourceTypeRef = codeGen.sema().viewStored(castNode.nodeExprRef, SemaNodeViewPartE::Type).typeRef();
                if (storedSourceTypeRef.isValid())
                    return storedSourceTypeRef;
            }

            if (operandPayload.typeRef.isValid())
                return operandPayload.typeRef;
        }
        else if (operand.is(AstNodeId::AutoCastExpr))
        {
            const auto& autoCastNode = operand.cast<AstAutoCastExpr>();
            if (autoCastNode.nodeExprRef.isValid())
            {
                const TypeRef storedSourceTypeRef = codeGen.sema().viewStored(autoCastNode.nodeExprRef, SemaNodeViewPartE::Type).typeRef();
                if (storedSourceTypeRef.isValid())
                    return storedSourceTypeRef;
            }

            if (operandPayload.typeRef.isValid())
                return operandPayload.typeRef;
        }
        else if (operand.is(AstNodeId::AsCastExpr) && operandPayload.typeRef.isValid())
        {
            return operandPayload.typeRef;
        }

        const TypeRef storedTypeRef = codeGen.sema().viewStored(operandRef, SemaNodeViewPartE::Type).typeRef();
        if (storedTypeRef.isValid())
        {
            return storedTypeRef;
        }

        if (operandPayload.typeRef.isValid())
            return operandPayload.typeRef;

        return operandView.typeRef();
    }

    BinaryEncodeContext buildBinaryEncodeContext(CodeGen& codeGen, const AstBinaryExpr& node, TokenId tokId)
    {
        BinaryEncodeContext ctx;

        const SemaNodeView leftView  = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);
        SWC_ASSERT(leftView.type() && rightView.type());

        ctx.leftPayload         = &codeGen.payload(node.nodeLeftRef);
        ctx.rightPayload        = &codeGen.payload(node.nodeRightRef);
        ctx.leftOperandTypeRef  = resolveBinaryOperandSourceTypeRef(codeGen, node.nodeLeftRef, leftView, *ctx.leftPayload);
        ctx.rightOperandTypeRef = resolveBinaryOperandSourceTypeRef(codeGen, node.nodeRightRef, rightView, *ctx.rightPayload);
        ctx.leftOperandTypeRef  = codeGen.typeMgr().get(ctx.leftOperandTypeRef).unwrapAliasEnum(codeGen.ctx(), ctx.leftOperandTypeRef);
        ctx.rightOperandTypeRef = codeGen.typeMgr().get(ctx.rightOperandTypeRef).unwrapAliasEnum(codeGen.ctx(), ctx.rightOperandTypeRef);
        ctx.resultTypeRef       = codeGen.curViewType().typeRef();
        ctx.operationTypeRef    = codeGen.typeMgr().get(leftView.typeRef()).unwrapAliasEnum(codeGen.ctx(), leftView.typeRef());
        if (!ctx.operationTypeRef.isValid())
            ctx.operationTypeRef = ctx.leftOperandTypeRef;
        SWC_ASSERT(ctx.leftOperandTypeRef.isValid());
        SWC_ASSERT(ctx.rightOperandTypeRef.isValid());
        SWC_ASSERT(ctx.resultTypeRef.isValid());
        SWC_ASSERT(ctx.operationTypeRef.isValid());

        TypeRef leftSemanticTypeRef  = codeGen.typeMgr().get(leftView.typeRef()).unwrapAliasEnum(codeGen.ctx(), leftView.typeRef());
        TypeRef rightSemanticTypeRef = codeGen.typeMgr().get(rightView.typeRef()).unwrapAliasEnum(codeGen.ctx(), rightView.typeRef());
        if (!leftSemanticTypeRef.isValid())
            leftSemanticTypeRef = ctx.leftOperandTypeRef;
        if (!rightSemanticTypeRef.isValid())
            rightSemanticTypeRef = ctx.rightOperandTypeRef;

        const TypeInfo& leftSemanticType  = codeGen.typeMgr().get(leftSemanticTypeRef);
        const TypeInfo& rightSemanticType = codeGen.typeMgr().get(rightSemanticTypeRef);
        ctx.encodingKind                  = resolveBinaryEncodingKind(tokId, leftSemanticType, rightSemanticType);
        // Pointer arithmetic is expressed in element units, so capture the stride once and reuse it in
        // both offset and difference lowering.
        if (ctx.encodingKind == BinaryEncodingKind::PointerOffset)
        {
            const TypeRef pointerTypeRef = leftSemanticType.isBlockPointer() ? leftSemanticTypeRef : rightSemanticTypeRef;
            ctx.pointerStride            = pointerStrideSize(codeGen, pointerTypeRef);
        }
        else if (ctx.encodingKind == BinaryEncodingKind::PointerDiff)
        {
            ctx.pointerStride = pointerStrideSize(codeGen, leftSemanticTypeRef);
        }

        return ctx;
    }

    void materializeBinaryOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        MicroBuilder& builder = codeGen.builder();
        outReg                = codeGen.nextVirtualRegisterForType(operandTypeRef);
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    bool isFloatRegClass(const MicroReg reg)
    {
        return reg.isFloat() || reg.isVirtualFloat();
    }

    bool isIntRegClass(const MicroReg reg)
    {
        return reg.isInt() || reg.isVirtualInt();
    }

    TypeRef resolveArithmeticOperandPhysicalTypeRef(CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef sourceTypeRef)
    {
        sourceTypeRef = codeGen.typeMgr().get(sourceTypeRef).unwrapAliasEnum(codeGen.ctx(), sourceTypeRef);
        if (!operandPayload.isValue() || !operandPayload.typeRef.isValid())
            return sourceTypeRef;

        TypeRef payloadTypeRef = codeGen.typeMgr().get(operandPayload.typeRef).unwrapAliasEnum(codeGen.ctx(), operandPayload.typeRef);
        if (!payloadTypeRef.isValid())
            payloadTypeRef = operandPayload.typeRef;
        if (!payloadTypeRef.isValid())
            return sourceTypeRef;

        const TypeInfo& sourceType  = codeGen.typeMgr().get(sourceTypeRef);
        const TypeInfo& payloadType = codeGen.typeMgr().get(payloadTypeRef);
        if (payloadType.isFloat() && isFloatRegClass(operandPayload.reg) && !sourceType.isFloat())
            return payloadTypeRef;
        if ((payloadType.isIntLike() || payloadType.isBool()) && isIntRegClass(operandPayload.reg) && sourceType.isFloat())
            return payloadTypeRef;

        return sourceTypeRef;
    }

    void convertArithmeticOperand(MicroReg& outReg, CodeGen& codeGen, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (srcTypeRef == dstTypeRef)
            return;

        srcTypeRef                = codeGen.typeMgr().get(srcTypeRef).unwrapAliasEnum(codeGen.ctx(), srcTypeRef);
        dstTypeRef                = codeGen.typeMgr().get(dstTypeRef).unwrapAliasEnum(codeGen.ctx(), dstTypeRef);
        const TypeInfo&   srcType = codeGen.typeMgr().get(srcTypeRef);
        const TypeInfo&   dstType = codeGen.typeMgr().get(dstTypeRef);
        const MicroOpBits srcBits = CodeGenTypeHelpers::numericOrBoolBits(srcType);
        const MicroOpBits dstBits = CodeGenTypeHelpers::numericOrBoolBits(dstType);
        SWC_ASSERT(srcBits != MicroOpBits::Zero);
        SWC_ASSERT(dstBits != MicroOpBits::Zero);

        MicroBuilder& builder         = codeGen.builder();
        const auto    isIntLikeOrBool = [](const TypeInfo& typeInfo) {
            return typeInfo.isIntLike() || typeInfo.isBool();
        };

        const auto isUnsignedLike = [](const TypeInfo& typeInfo) {
            return typeInfo.isBool() || typeInfo.isIntLikeUnsigned();
        };

        if (isIntLikeOrBool(srcType) && isIntLikeOrBool(dstType))
        {
            if (srcBits == dstBits)
                return;

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            if (getNumBits(srcBits) > getNumBits(dstBits))
            {
                builder.emitLoadRegReg(dstReg, outReg, dstBits);
                outReg = dstReg;
                return;
            }

            if (isUnsignedLike(srcType))
                builder.emitLoadZeroExtendRegReg(dstReg, outReg, dstBits, srcBits);
            else
                builder.emitLoadSignedExtendRegReg(dstReg, outReg, dstBits, srcBits);
            outReg = dstReg;
            return;
        }

        if (isIntLikeOrBool(srcType) && dstType.isFloat())
        {
            MicroReg srcReg = outReg;
            if (getNumBits(srcBits) < 32 || (dstBits == MicroOpBits::B64 && getNumBits(srcBits) == 32))
            {
                srcReg                        = codeGen.nextVirtualIntRegister();
                const MicroOpBits widenedBits = dstBits == MicroOpBits::B64 ? MicroOpBits::B64 : MicroOpBits::B32;
                if (!isUnsignedLike(srcType))
                    builder.emitLoadSignedExtendRegReg(srcReg, outReg, widenedBits, srcBits);
                else
                    builder.emitLoadZeroExtendRegReg(srcReg, outReg, widenedBits, srcBits);
            }

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertIntToFloat, dstBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isFloat() && dstType.isFloat())
        {
            if (srcBits == dstBits)
                return;

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, outReg, MicroOp::ConvertFloatToFloat, srcBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isFloat() && isIntLikeOrBool(dstType))
        {
            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, outReg, MicroOp::ConvertFloatToInt, srcBits);
            outReg = dstReg;
            return;
        }

        SWC_UNREACHABLE();
    }

    void materializeArithmeticOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        srcTypeRef                = resolveArithmeticOperandPhysicalTypeRef(codeGen, operandPayload, srcTypeRef);
        const TypeInfo&   srcType = codeGen.typeMgr().get(srcTypeRef);
        const MicroOpBits srcBits = CodeGenTypeHelpers::numericOrBoolBits(srcType);
        SWC_ASSERT(srcBits != MicroOpBits::Zero);

        materializeBinaryOperand(outReg, codeGen, operandPayload, srcTypeRef, srcBits);
        convertArithmeticOperand(outReg, codeGen, srcTypeRef, dstTypeRef);
    }

    MicroReg materializePointerValue(CodeGen& codeGen, const CodeGenNodePayload& operandPayload)
    {
        if (operandPayload.isValue())
            return operandPayload.reg;

        const MicroReg resultReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegMem(resultReg, operandPayload.reg, 0, MicroOpBits::B64);
        return resultReg;
    }

    MicroReg materializePointerIndexReg(CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        const TypeInfo&   operandType = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits srcBits     = CodeGenTypeHelpers::numericBits(operandType);
        SWC_ASSERT(operandType.isIntLike());
        SWC_ASSERT(srcBits != MicroOpBits::Zero);

        const MicroReg resultReg = codeGen.nextVirtualIntRegister();
        MicroBuilder&  builder   = codeGen.builder();
        if (operandPayload.isAddress())
        {
            if (srcBits == MicroOpBits::B64)
                builder.emitLoadRegMem(resultReg, operandPayload.reg, 0, MicroOpBits::B64);
            else if (operandType.isIntLikeUnsigned())
                builder.emitLoadZeroExtendRegMem(resultReg, operandPayload.reg, 0, MicroOpBits::B64, srcBits);
            else
                builder.emitLoadSignedExtendRegMem(resultReg, operandPayload.reg, 0, MicroOpBits::B64, srcBits);
        }
        else
        {
            if (srcBits == MicroOpBits::B64)
                builder.emitLoadRegReg(resultReg, operandPayload.reg, MicroOpBits::B64);
            else if (operandType.isIntLikeUnsigned())
                builder.emitLoadZeroExtendRegReg(resultReg, operandPayload.reg, MicroOpBits::B64, srcBits);
            else
                builder.emitLoadSignedExtendRegReg(resultReg, operandPayload.reg, MicroOpBits::B64, srcBits);
        }

        return resultReg;
    }

    MicroOp intBinaryMicroOp(TokenId tokId, bool isSigned)
    {
        switch (tokId)
        {
            case TokenId::SymPlus:
                return MicroOp::Add;
            case TokenId::SymMinus:
                return MicroOp::Subtract;
            case TokenId::SymAsterisk:
                return isSigned ? MicroOp::MultiplySigned : MicroOp::MultiplyUnsigned;
            case TokenId::SymSlash:
                return isSigned ? MicroOp::DivideSigned : MicroOp::DivideUnsigned;
            case TokenId::SymPercent:
                return isSigned ? MicroOp::ModuloSigned : MicroOp::ModuloUnsigned;
            case TokenId::SymAmpersand:
                return MicroOp::And;
            case TokenId::SymPipe:
                return MicroOp::Or;
            case TokenId::SymCircumflex:
                return MicroOp::Xor;
            case TokenId::SymLowerLower:
                return MicroOp::ShiftLeft;
            case TokenId::SymGreaterGreater:
                return isSigned ? MicroOp::ShiftArithmeticRight : MicroOp::ShiftRight;

            default:
                SWC_UNREACHABLE();
        }
    }

    MicroOp floatBinaryMicroOp(TokenId tokId)
    {
        switch (tokId)
        {
            case TokenId::SymPlus:
                return MicroOp::FloatAdd;
            case TokenId::SymMinus:
                return MicroOp::FloatSubtract;
            case TokenId::SymAsterisk:
                return MicroOp::FloatMultiply;
            case TokenId::SymSlash:
                return MicroOp::FloatDivide;

            default:
                SWC_UNREACHABLE();
        }
    }

    uint64_t opBitWidth(MicroOpBits opBits)
    {
        return getNumBits(opBits);
    }

    MicroReg widenIntRegTo64(CodeGen& codeGen, MicroReg srcReg, const TypeInfo& srcType, MicroOpBits srcBits)
    {
        if (srcBits == MicroOpBits::B64)
            return srcReg;

        MicroBuilder&  builder = codeGen.builder();
        const MicroReg dstReg  = codeGen.nextVirtualIntRegister();
        if (srcType.isIntLikeUnsigned())
            builder.emitLoadZeroExtendRegReg(dstReg, srcReg, MicroOpBits::B64, srcBits);
        else
            builder.emitLoadSignedExtendRegReg(dstReg, srcReg, MicroOpBits::B64, srcBits);
        return dstReg;
    }

    ApInt minSignedImmediate(const MicroOpBits opBits)
    {
        const uint32_t bits = getNumBits(opBits);
        SWC_ASSERT(bits > 0 && bits <= 64);
        const uint64_t value = bits == 64 ? (1ull << 63) : (1ull << (bits - 1));
        return ApInt(value, 64);
    }

    Result emitShiftBinaryIntLike(CodeGen&             codeGen,
                                  const AstBinaryExpr& node,
                                  CodeGenNodePayload&  nodePayload,
                                  const MicroReg       originalLeftReg,
                                  const MicroReg       rightReg,
                                  const TypeInfo&      operationType,
                                  const MicroOpBits    opBits,
                                  const TokenId        tokId)
    {
        const bool          isLeftShift   = tokId == TokenId::SymLowerLower;
        const bool          isSigned      = operationType.isIntLike() && !operationType.isIntLikeUnsigned();
        const bool          hasSafety     = CodeGenSafety::hasOverflowRuntimeSafety(codeGen);
        const bool          allowWrap     = node.modifierFlags.has(AstModifierFlagsE::Wrap);
        const bool          checkOverflow = isLeftShift && hasSafety && !allowWrap;
        MicroBuilder&       builder       = codeGen.builder();
        const MicroOp       shiftOp       = intBinaryMicroOp(tokId, isSigned);
        const uint64_t      bitWidth      = opBitWidth(opBits);
        const MicroReg      countReg64    = widenIntRegTo64(codeGen, rightReg, operationType, opBits);
        const MicroLabelRef nonNegative   = builder.createLabel();
        const MicroLabelRef normalLabel   = builder.createLabel();
        const MicroLabelRef largeLabel    = builder.createLabel();
        const MicroLabelRef doneLabel     = builder.createLabel();

        if (isSigned)
        {
            builder.emitCmpRegImm(rightReg, ApInt(0, 64), opBits);
            builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B32, nonNegative);
            if (hasSafety)
                SWC_RESULT(CodeGenSafety::emitNegativeShiftCheck(codeGen, node));
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, normalLabel);
            builder.placeLabel(nonNegative);
        }

        builder.emitCmpRegImm(countReg64, ApInt(bitWidth, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, largeLabel);

        builder.placeLabel(normalLabel);
        builder.emitOpBinaryRegReg(nodePayload.reg, rightReg, shiftOp, opBits);
        if (checkOverflow)
        {
            const MicroReg reverseReg = codeGen.nextVirtualRegisterForType(nodePayload.typeRef);
            builder.emitLoadRegReg(reverseReg, nodePayload.reg, opBits);
            builder.emitOpBinaryRegReg(reverseReg, rightReg, isSigned ? MicroOp::ShiftArithmeticRight : MicroOp::ShiftRight, opBits);
            builder.emitCmpRegReg(reverseReg, originalLeftReg, opBits);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
            SWC_RESULT(CodeGenSafety::emitOverflowCheck(codeGen, node));
        }

        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
        builder.placeLabel(largeLabel);

        if (isLeftShift)
        {
            if (checkOverflow)
            {
                const MicroLabelRef zeroLabel = builder.createLabel();
                builder.emitCmpRegImm(originalLeftReg, ApInt(0, 64), opBits);
                builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, zeroLabel);
                SWC_RESULT(CodeGenSafety::emitOverflowCheck(codeGen, node));
                builder.placeLabel(zeroLabel);
            }

            builder.emitClearReg(nodePayload.reg, opBits);
        }
        else if (isSigned)
        {
            const MicroLabelRef negativeLabel = builder.createLabel();
            builder.emitCmpRegImm(originalLeftReg, ApInt(0, 64), opBits);
            builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B32, negativeLabel);
            builder.emitClearReg(nodePayload.reg, opBits);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
            builder.placeLabel(negativeLabel);
            builder.emitLoadRegImm(nodePayload.reg, ApInt(std::numeric_limits<uint64_t>::max(), 64), opBits);
        }
        else
        {
            builder.emitClearReg(nodePayload.reg, opBits);
        }

        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result emitBinaryIntLike(CodeGen& codeGen, const BinaryEncodeContext& encodeCtx, TokenId tokId)
    {
        SWC_ASSERT(encodeCtx.leftPayload);
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.leftOperandTypeRef.isValid());
        SWC_ASSERT(encodeCtx.rightOperandTypeRef.isValid());
        SWC_ASSERT(encodeCtx.resultTypeRef.isValid());
        SWC_ASSERT(encodeCtx.operationTypeRef.isValid());

        const auto&       node          = codeGen.node(codeGen.curNodeRef()).cast<AstBinaryExpr>();
        const TypeInfo&   operationType = codeGen.typeMgr().get(encodeCtx.operationTypeRef);
        const MicroOp     op            = intBinaryMicroOp(tokId, !operationType.isIntLikeUnsigned());
        const MicroOpBits opBits        = CodeGenTypeHelpers::numericBits(operationType);
        const bool        isSigned      = operationType.isIntLike() && !operationType.isIntLikeUnsigned();
        const bool        hasSafety     = CodeGenSafety::hasOverflowRuntimeSafety(codeGen);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), encodeCtx.resultTypeRef);
        materializeArithmeticOperand(nodePayload.reg, codeGen, *encodeCtx.leftPayload, encodeCtx.leftOperandTypeRef, encodeCtx.operationTypeRef);

        auto finalizeIntLikeResult = [&]() {
            convertArithmeticOperand(nodePayload.reg, codeGen, encodeCtx.operationTypeRef, encodeCtx.resultTypeRef);
            return Result::Continue;
        };

        MicroReg rightReg;
        materializeArithmeticOperand(rightReg, codeGen, *encodeCtx.rightPayload, encodeCtx.rightOperandTypeRef, encodeCtx.operationTypeRef);

        if (tokId == TokenId::SymLowerLower || tokId == TokenId::SymGreaterGreater)
        {
            const MicroReg stableLeftReg = codeGen.nextVirtualRegisterForType(encodeCtx.resultTypeRef);
            codeGen.builder().emitLoadRegReg(stableLeftReg, nodePayload.reg, opBits);
            SWC_RESULT(emitShiftBinaryIntLike(codeGen, node, nodePayload, stableLeftReg, rightReg, operationType, opBits, tokId));
            return finalizeIntLikeResult();
        }

        if (isSigned && (tokId == TokenId::SymSlash || tokId == TokenId::SymPercent))
        {
            MicroBuilder&       builder   = codeGen.builder();
            const MicroLabelRef doOpLabel = builder.createLabel();
            const MicroLabelRef doneLabel = builder.createLabel();
            builder.emitCmpRegImm(rightReg, ApInt(std::numeric_limits<uint64_t>::max(), 64), opBits);
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, doOpLabel);
            builder.emitCmpRegImm(nodePayload.reg, minSignedImmediate(opBits), opBits);
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, doOpLabel);
            if (hasSafety)
                SWC_RESULT(CodeGenSafety::emitOverflowCheck(codeGen, node));
            if (tokId == TokenId::SymPercent)
                builder.emitClearReg(nodePayload.reg, opBits);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
            builder.placeLabel(doOpLabel);
            builder.emitOpBinaryRegReg(nodePayload.reg, rightReg, op, opBits);
            builder.placeLabel(doneLabel);
            return finalizeIntLikeResult();
        }

        codeGen.builder().emitOpBinaryRegReg(nodePayload.reg, rightReg, op, opBits);

        if (hasSafety)
        {
            MicroBuilder&       builder         = codeGen.builder();
            const MicroLabelRef noOverflowLabel = builder.createLabel();
            switch (tokId)
            {
                case TokenId::SymPlus:
                case TokenId::SymMinus:
                    builder.emitJumpToLabel(isSigned ? MicroCond::NotOverflow : MicroCond::AboveOrEqual, MicroOpBits::B32, noOverflowLabel);
                    SWC_RESULT(CodeGenSafety::emitOverflowCheck(codeGen, node));
                    builder.placeLabel(noOverflowLabel);
                    break;

                case TokenId::SymAsterisk:
                    builder.emitJumpToLabel(MicroCond::NotOverflow, MicroOpBits::B32, noOverflowLabel);
                    SWC_RESULT(CodeGenSafety::emitOverflowCheck(codeGen, node));
                    builder.placeLabel(noOverflowLabel);
                    break;

                default:
                    break;
            }
        }

        return finalizeIntLikeResult();
    }

    Result emitBinaryFloat(CodeGen& codeGen, const BinaryEncodeContext& encodeCtx, TokenId tokId)
    {
        SWC_ASSERT(encodeCtx.leftPayload);
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.leftOperandTypeRef.isValid());
        SWC_ASSERT(encodeCtx.rightOperandTypeRef.isValid());
        SWC_ASSERT(encodeCtx.resultTypeRef.isValid());
        SWC_ASSERT(encodeCtx.operationTypeRef.isValid());

        const TypeInfo&   operationType = codeGen.typeMgr().get(encodeCtx.operationTypeRef);
        const MicroOp     op            = floatBinaryMicroOp(tokId);
        const MicroOpBits opBits        = CodeGenTypeHelpers::numericBits(operationType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), encodeCtx.resultTypeRef);

        materializeArithmeticOperand(nodePayload.reg, codeGen, *encodeCtx.leftPayload, encodeCtx.leftOperandTypeRef, encodeCtx.operationTypeRef);
        MicroReg rightReg;
        materializeArithmeticOperand(rightReg, codeGen, *encodeCtx.rightPayload, encodeCtx.rightOperandTypeRef, encodeCtx.operationTypeRef);

        codeGen.builder().emitOpBinaryRegReg(nodePayload.reg, rightReg, op, opBits);
        return Result::Continue;
    }

    Result emitPointerOffset(CodeGen& codeGen, const BinaryEncodeContext& encodeCtx, TokenId tokId)
    {
        SWC_ASSERT(encodeCtx.leftPayload);
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.leftOperandTypeRef.isValid());
        SWC_ASSERT(encodeCtx.rightOperandTypeRef.isValid());
        SWC_ASSERT(encodeCtx.resultTypeRef.isValid());
        SWC_ASSERT(encodeCtx.pointerStride > 0);

        const TypeInfo& leftType = codeGen.typeMgr().get(encodeCtx.leftOperandTypeRef);
        const bool      leftPtr  = leftType.isBlockPointer();

        const CodeGenNodePayload& pointerPayload = leftPtr ? *encodeCtx.leftPayload : *encodeCtx.rightPayload;
        const CodeGenNodePayload& indexPayload   = leftPtr ? *encodeCtx.rightPayload : *encodeCtx.leftPayload;
        const TypeRef             indexTypeRef   = leftPtr ? encodeCtx.rightOperandTypeRef : encodeCtx.leftOperandTypeRef;

        const MicroReg baseReg  = materializePointerValue(codeGen, pointerPayload);
        const MicroReg indexReg = materializePointerIndexReg(codeGen, indexPayload, indexTypeRef);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), encodeCtx.resultTypeRef);
        MicroBuilder&             builder       = codeGen.builder();
        builder.emitLoadRegReg(resultPayload.reg, baseReg, MicroOpBits::B64);

        if (encodeCtx.pointerStride == 1)
        {
            const MicroOp op = tokId == TokenId::SymMinus ? MicroOp::Subtract : MicroOp::Add;
            builder.emitOpBinaryRegReg(resultPayload.reg, indexReg, op, MicroOpBits::B64);
            return Result::Continue;
        }

        if (tokId == TokenId::SymMinus)
        {
            const MicroReg negIndexReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(negIndexReg, indexReg, MicroOpBits::B64);
            builder.emitOpUnaryReg(negIndexReg, MicroOp::Negate, MicroOpBits::B64);
            builder.emitLoadAddressAmcRegMem(resultPayload.reg, MicroOpBits::B64, baseReg, negIndexReg, encodeCtx.pointerStride, 0, MicroOpBits::B64);
            return Result::Continue;
        }

        builder.emitLoadAddressAmcRegMem(resultPayload.reg, MicroOpBits::B64, baseReg, indexReg, encodeCtx.pointerStride, 0, MicroOpBits::B64);
        return Result::Continue;
    }

    Result emitPointerDifference(CodeGen& codeGen, const BinaryEncodeContext& encodeCtx)
    {
        SWC_ASSERT(encodeCtx.leftPayload);
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.resultTypeRef.isValid());
        SWC_ASSERT(encodeCtx.pointerStride > 0);

        const MicroReg leftReg  = materializePointerValue(codeGen, *encodeCtx.leftPayload);
        const MicroReg rightReg = materializePointerValue(codeGen, *encodeCtx.rightPayload);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), encodeCtx.resultTypeRef);
        MicroBuilder&             builder       = codeGen.builder();
        builder.emitLoadRegReg(resultPayload.reg, leftReg, MicroOpBits::B64);
        builder.emitOpBinaryRegReg(resultPayload.reg, rightReg, MicroOp::Subtract, MicroOpBits::B64);
        // Pointer subtraction produces a byte delta first; normalize it back to an element count for the
        // language-level result.
        if (encodeCtx.pointerStride != 1)
            builder.emitOpBinaryRegImm(resultPayload.reg, ApInt(encodeCtx.pointerStride, 64), MicroOp::DivideSigned, MicroOpBits::B64);
        return Result::Continue;
    }
}

Result AstBinaryExpr::codeGenPostNode(CodeGen& codeGen) const
{
    SmallVector<ResolvedCallArgument> resolvedArgs;
    codeGen.appendResolvedCallArguments(codeGen.curNodeRef(), resolvedArgs);

    const SemaNodeView specialOpView = codeGen.curViewSymbol();
    if (!resolvedArgs.empty() && specialOpView.sym() && specialOpView.sym()->isFunction())
    {
        const auto& calledFn = specialOpView.sym()->cast<SymbolFunction>();
        if (calledFn.specOpKind() == SpecOpKind::OpBinary)
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid());
    }

    const TokenId             tokId     = canonicalBinaryToken(codeGen.token(codeRef()).id);
    const BinaryEncodeContext encodeCtx = buildBinaryEncodeContext(codeGen, *this, tokId);
    switch (encodeCtx.encodingKind)
    {
        case BinaryEncodingKind::IntLike:
            return emitBinaryIntLike(codeGen, encodeCtx, tokId);
        case BinaryEncodingKind::Float:
            return emitBinaryFloat(codeGen, encodeCtx, tokId);
        case BinaryEncodingKind::PointerOffset:
            return emitPointerOffset(codeGen, encodeCtx, tokId);
        case BinaryEncodingKind::PointerDiff:
            return emitPointerDifference(codeGen, encodeCtx);
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
