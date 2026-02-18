#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class BinaryOperandKind : uint8_t
    {
        IntLike,
        Float,
        Other,
    };

    BinaryOperandKind operandKind(const TypeInfo& type)
    {
        if (type.isIntLike())
            return BinaryOperandKind::IntLike;

        if (type.isFloat())
            return BinaryOperandKind::Float;

        return BinaryOperandKind::Other;
    }

    MicroOpBits arithmeticOpBits(const TypeInfo& type, BinaryOperandKind kind)
    {
        if (kind == BinaryOperandKind::Float)
        {
            const uint32_t floatBits = type.payloadFloatBits() ? type.payloadFloatBits() : 64;
            return microOpBitsFromBitWidth(floatBits);
        }

        if (kind == BinaryOperandKind::IntLike)
        {
            const uint32_t intBits = type.payloadIntLikeBits() ? type.payloadIntLikeBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        return MicroOpBits::Zero;
    }

    void materializeBinaryOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        MicroBuilder& builder = codeGen.builder();
        outReg                = codeGen.nextVirtualRegisterForType(operandTypeRef);
        if (operandPayload.storageKind == CodeGenNodePayload::StorageKind::Address)
            builder.encodeLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.encodeLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    Result emitPlusIntLikeIntLike(CodeGen& codeGen, const AstBinaryExpr& node, const SemaNodeView& leftView, const SemaNodeView& rightView)
    {
        SWC_ASSERT(leftView.type && rightView.type);
        const CodeGenNodePayload* leftPayload  = codeGen.payload(node.nodeLeftRef);
        const CodeGenNodePayload* rightPayload = codeGen.payload(node.nodeRightRef);
        SWC_ASSERT(leftPayload != nullptr);
        SWC_ASSERT(rightPayload != nullptr);

        constexpr auto    operandTypeKind = BinaryOperandKind::IntLike;
        const MicroOpBits opBits          = arithmeticOpBits(*leftView.type, operandTypeKind);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);

        MicroReg rightReg = MicroReg::invalid();
        materializeBinaryOperand(nodePayload.reg, codeGen, *leftPayload, leftView.typeRef, opBits);
        if (codeGen.canUseOperandRegDirect(*rightPayload))
            rightReg = rightPayload->reg;
        else
            materializeBinaryOperand(rightReg, codeGen, *rightPayload, rightView.typeRef, opBits);

        codeGen.builder().encodeOpBinaryRegReg(nodePayload.reg, rightReg, MicroOp::Add, opBits);
        return Result::Continue;
    }

    Result emitPlusFloatFloat(CodeGen& codeGen, const AstBinaryExpr& node, const SemaNodeView& leftView, const SemaNodeView& rightView)
    {
        SWC_ASSERT(leftView.type && rightView.type);
        const CodeGenNodePayload* leftPayload  = codeGen.payload(node.nodeLeftRef);
        const CodeGenNodePayload* rightPayload = codeGen.payload(node.nodeRightRef);
        SWC_ASSERT(leftPayload != nullptr);
        SWC_ASSERT(rightPayload != nullptr);

        constexpr auto    operandTypeKind = BinaryOperandKind::Float;
        const MicroOpBits opBits          = arithmeticOpBits(*leftView.type, operandTypeKind);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);

        MicroReg rightReg = MicroReg::invalid();
        materializeBinaryOperand(nodePayload.reg, codeGen, *leftPayload, leftView.typeRef, opBits);
        if (codeGen.canUseOperandRegDirect(*rightPayload))
            rightReg = rightPayload->reg;
        else
            materializeBinaryOperand(rightReg, codeGen, *rightPayload, rightView.typeRef, opBits);

        codeGen.builder().encodeOpBinaryRegReg(nodePayload.reg, rightReg, MicroOp::FloatAdd, opBits);
        return Result::Continue;
    }

    Result codeGenBinaryPlus(CodeGen& codeGen, const AstBinaryExpr& node)
    {
        const SemaNodeView leftView  = codeGen.nodeView(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.nodeView(node.nodeRightRef);
        SWC_ASSERT(leftView.type && rightView.type);

        const BinaryOperandKind leftKind  = operandKind(*leftView.type);
        const BinaryOperandKind rightKind = operandKind(*rightView.type);

        if (leftKind == BinaryOperandKind::IntLike && rightKind == BinaryOperandKind::IntLike)
            return emitPlusIntLikeIntLike(codeGen, node, leftView, rightView);
        if (leftKind == BinaryOperandKind::Float && rightKind == BinaryOperandKind::Float)
            return emitPlusFloatFloat(codeGen, node, leftView, rightView);

        return Result::Continue;
    }
}

Result AstBinaryExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::SymPlus:
            return codeGenBinaryPlus(codeGen, *this);

        default:
            // TODO
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
