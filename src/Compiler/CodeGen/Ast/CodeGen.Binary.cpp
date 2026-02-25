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
    };

    struct BinaryEncodeContext
    {
        const CodeGenNodePayload* leftPayload         = nullptr;
        const CodeGenNodePayload* rightPayload        = nullptr;
        TypeRef                   leftOperandTypeRef  = TypeRef::invalid();
        TypeRef                   rightOperandTypeRef = TypeRef::invalid();
        TypeRef                   resultTypeRef       = TypeRef::invalid();
        BinaryEncodingKind        encodingKind        = BinaryEncodingKind::IntLike;
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
            const uint32_t floatBits = type.payloadFloatBits() ? type.payloadFloatBits() : 64;
            return microOpBitsFromBitWidth(floatBits);
        }

        if (type.isIntLike())
        {
            const uint32_t intBits = type.payloadIntLikeBits() ? type.payloadIntLikeBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        return MicroOpBits::Zero;
    }

    BinaryEncodingKind resolveBinaryEncodingKind(const TypeInfo& leftType, const TypeInfo& rightType)
    {
        if (leftType.isIntLike() && rightType.isIntLike())
            return BinaryEncodingKind::IntLike;

        if (leftType.isFloat() && rightType.isFloat())
            return BinaryEncodingKind::Float;

        SWC_UNREACHABLE();
    }

    BinaryEncodeContext buildBinaryEncodeContext(CodeGen& codeGen, const AstBinaryExpr& node)
    {
        BinaryEncodeContext ctx;

        const SemaNodeView leftView  = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);
        SWC_ASSERT(leftView.type() && rightView.type());

        ctx.leftPayload         = &codeGen.payload(node.nodeLeftRef);
        ctx.rightPayload        = &codeGen.payload(node.nodeRightRef);
        ctx.leftOperandTypeRef  = resolveOperandTypeRef(*ctx.leftPayload, leftView.typeRef());
        ctx.rightOperandTypeRef = resolveOperandTypeRef(*ctx.rightPayload, rightView.typeRef());
        ctx.resultTypeRef       = codeGen.curViewType().typeRef();
        ctx.encodingKind        = resolveBinaryEncodingKind(*leftView.type(), *rightView.type());
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

        const TypeInfo&   leftType = codeGen.typeMgr().get(encodeCtx.leftOperandTypeRef);
        const MicroOp     op       = intBinaryMicroOp(tokId, !leftType.isIntLikeUnsigned());
        const MicroOpBits opBits   = arithmeticOpBits(leftType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), encodeCtx.resultTypeRef);
        materializeBinaryOperand(nodePayload.reg, codeGen, *encodeCtx.leftPayload, encodeCtx.leftOperandTypeRef, opBits);

        MicroReg rightReg;
        materializeBinaryOperand(rightReg, codeGen, *encodeCtx.rightPayload, encodeCtx.rightOperandTypeRef, opBits);

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

        const TypeInfo&   leftType = codeGen.typeMgr().get(encodeCtx.leftOperandTypeRef);
        const MicroOp     op       = floatBinaryMicroOp(tokId);
        const MicroOpBits opBits   = arithmeticOpBits(leftType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), encodeCtx.resultTypeRef);

        materializeBinaryOperand(nodePayload.reg, codeGen, *encodeCtx.leftPayload, encodeCtx.leftOperandTypeRef, opBits);
        MicroReg rightReg;
        materializeBinaryOperand(rightReg, codeGen, *encodeCtx.rightPayload, encodeCtx.rightOperandTypeRef, opBits);

        codeGen.builder().emitOpBinaryRegReg(nodePayload.reg, rightReg, op, opBits);
        return Result::Continue;
    }
}

Result AstBinaryExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const TokenId             tokId     = canonicalBinaryToken(codeGen.token(codeRef()).id);
    const BinaryEncodeContext encodeCtx = buildBinaryEncodeContext(codeGen, *this);
    switch (encodeCtx.encodingKind)
    {
        case BinaryEncodingKind::IntLike:
            return emitBinaryIntLike(codeGen, encodeCtx, tokId);
        case BinaryEncodingKind::Float:
            return emitBinaryFloat(codeGen, encodeCtx, tokId);
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
