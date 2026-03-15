#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
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

    TypeRef resolveOperandTypeRef(const CodeGenNodePayload& payload, TypeRef fallbackTypeRef)
    {
        if (payload.typeRef.isValid())
            return payload.typeRef;
        return fallbackTypeRef;
    }

    MicroOpBits arithmeticOpBits(const TypeInfo& type)
    {
        if (type.isFloat())
        {
            const uint32_t floatBits = type.payloadFloatBitsOr(64);
            return microOpBitsFromBitWidth(floatBits);
        }

        if (type.isIntLike())
        {
            const uint32_t intBits = type.payloadIntLikeBitsOr(64);
            return microOpBitsFromBitWidth(intBits);
        }

        return MicroOpBits::Zero;
    }

    TypeRef normalizeArithmeticTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return typeRef;

        const TypeInfo& typeInfo      = codeGen.typeMgr().get(typeRef);
        const TypeRef   normalizedRef = typeInfo.unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (normalizedRef.isValid())
            return normalizedRef;
        return typeRef;
    }

    uint64_t pointerStrideSize(CodeGen& codeGen, TypeRef pointerTypeRef)
    {
        const TypeInfo& pointerType = codeGen.typeMgr().get(pointerTypeRef);
        SWC_ASSERT(pointerType.isBlockPointer());
        const uint64_t stride = codeGen.typeMgr().get(pointerType.payloadTypeRef()).sizeOf(codeGen.ctx());
        SWC_ASSERT(stride > 0);
        return stride;
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

    BinaryEncodeContext buildBinaryEncodeContext(CodeGen& codeGen, const AstBinaryExpr& node, TokenId tokId)
    {
        BinaryEncodeContext ctx;

        const SemaNodeView leftView  = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);
        SWC_ASSERT(leftView.type() && rightView.type());

        ctx.leftPayload         = &codeGen.payload(node.nodeLeftRef);
        ctx.rightPayload        = &codeGen.payload(node.nodeRightRef);
        ctx.leftOperandTypeRef  = resolveOperandTypeRef(*ctx.leftPayload, leftView.typeRef());
        ctx.rightOperandTypeRef = resolveOperandTypeRef(*ctx.rightPayload, rightView.typeRef());
        ctx.leftOperandTypeRef  = normalizeArithmeticTypeRef(codeGen, ctx.leftOperandTypeRef);
        ctx.rightOperandTypeRef = normalizeArithmeticTypeRef(codeGen, ctx.rightOperandTypeRef);
        ctx.resultTypeRef       = codeGen.curViewType().typeRef();
        ctx.operationTypeRef    = ctx.leftOperandTypeRef;
        SWC_ASSERT(ctx.leftOperandTypeRef.isValid());
        SWC_ASSERT(ctx.rightOperandTypeRef.isValid());
        SWC_ASSERT(ctx.resultTypeRef.isValid());
        SWC_ASSERT(ctx.operationTypeRef.isValid());

        const TypeInfo& leftOperandType  = codeGen.typeMgr().get(ctx.leftOperandTypeRef);
        const TypeInfo& rightOperandType = codeGen.typeMgr().get(ctx.rightOperandTypeRef);
        ctx.encodingKind                 = resolveBinaryEncodingKind(tokId, leftOperandType, rightOperandType);
        if (ctx.encodingKind == BinaryEncodingKind::PointerOffset)
        {
            const TypeRef pointerTypeRef = leftOperandType.isBlockPointer() ? ctx.leftOperandTypeRef : ctx.rightOperandTypeRef;
            ctx.pointerStride            = pointerStrideSize(codeGen, pointerTypeRef);
        }
        else if (ctx.encodingKind == BinaryEncodingKind::PointerDiff)
        {
            ctx.pointerStride = pointerStrideSize(codeGen, ctx.leftOperandTypeRef);
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

    void convertArithmeticOperand(MicroReg& outReg, CodeGen& codeGen, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (srcTypeRef == dstTypeRef)
            return;

        const TypeInfo&   srcType = codeGen.typeMgr().get(srcTypeRef);
        const TypeInfo&   dstType = codeGen.typeMgr().get(dstTypeRef);
        const MicroOpBits srcBits = arithmeticOpBits(srcType);
        const MicroOpBits dstBits = arithmeticOpBits(dstType);
        SWC_ASSERT(srcBits != MicroOpBits::Zero);
        SWC_ASSERT(dstBits != MicroOpBits::Zero);

        MicroBuilder& builder = codeGen.builder();
        if (srcType.isIntLike() && dstType.isIntLike())
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

            if (srcType.isIntLikeUnsigned())
                builder.emitLoadZeroExtendRegReg(dstReg, outReg, dstBits, srcBits);
            else
                builder.emitLoadSignedExtendRegReg(dstReg, outReg, dstBits, srcBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isIntLike() && dstType.isFloat())
        {
            MicroReg srcReg = outReg;
            if (getNumBits(srcBits) < 32)
            {
                srcReg = codeGen.nextVirtualIntRegister();
                if (srcType.isIntSigned())
                    builder.emitLoadSignedExtendRegReg(srcReg, outReg, MicroOpBits::B32, srcBits);
                else
                    builder.emitLoadZeroExtendRegReg(srcReg, outReg, MicroOpBits::B32, srcBits);
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

        if (srcType.isFloat() && dstType.isIntLike())
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
        const TypeInfo&   srcType = codeGen.typeMgr().get(srcTypeRef);
        const MicroOpBits srcBits = arithmeticOpBits(srcType);
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
        const MicroOpBits srcBits     = arithmeticOpBits(operandType);
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
                return MicroOp::MultiplySigned;
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

    Result emitBinaryIntLike(CodeGen& codeGen, const BinaryEncodeContext& encodeCtx, TokenId tokId)
    {
        SWC_ASSERT(encodeCtx.leftPayload);
        SWC_ASSERT(encodeCtx.rightPayload);
        SWC_ASSERT(encodeCtx.leftOperandTypeRef.isValid());
        SWC_ASSERT(encodeCtx.rightOperandTypeRef.isValid());
        SWC_ASSERT(encodeCtx.resultTypeRef.isValid());
        SWC_ASSERT(encodeCtx.operationTypeRef.isValid());

        const TypeInfo&   operationType = codeGen.typeMgr().get(encodeCtx.operationTypeRef);
        const MicroOp     op            = intBinaryMicroOp(tokId, !operationType.isIntLikeUnsigned());
        const MicroOpBits opBits        = arithmeticOpBits(operationType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), encodeCtx.resultTypeRef);
        materializeArithmeticOperand(nodePayload.reg, codeGen, *encodeCtx.leftPayload, encodeCtx.leftOperandTypeRef, encodeCtx.operationTypeRef);

        MicroReg rightReg;
        materializeArithmeticOperand(rightReg, codeGen, *encodeCtx.rightPayload, encodeCtx.rightOperandTypeRef, encodeCtx.operationTypeRef);

        codeGen.builder().emitOpBinaryRegReg(nodePayload.reg, rightReg, op, opBits);
        return Result::Continue;
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
        const MicroOpBits opBits        = arithmeticOpBits(operationType);
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
        if (encodeCtx.pointerStride != 1)
            builder.emitOpBinaryRegImm(resultPayload.reg, ApInt(encodeCtx.pointerStride, 64), MicroOp::DivideSigned, MicroOpBits::B64);
        return Result::Continue;
    }
}

Result AstBinaryExpr::codeGenPostNode(CodeGen& codeGen) const
{
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
