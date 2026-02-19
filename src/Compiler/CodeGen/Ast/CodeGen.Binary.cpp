#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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

    void materializeBinaryOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        MicroBuilder& builder = codeGen.builder();
        outReg                = codeGen.nextVirtualRegisterForType(operandTypeRef);
        if (operandPayload.storageKind == CodeGenNodePayload::StorageKind::Address)
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    bool shouldReuseLeftOperandAsDestination(CodeGen& codeGen, AstNodeRef leftNodeRef, const CodeGenNodePayload& leftPayload)
    {
        if (!codeGen.canUseOperandRegDirect(leftPayload))
            return false;

        // Identifier payloads alias variable storage. Keep copy semantics to avoid mutating that value.
        const AstNode& leftNode = codeGen.node(leftNodeRef);
        if (leftNode.is(AstNodeId::Identifier))
            return false;

        return leftPayload.reg.isVirtual();
    }

    Result emitPlusIntLikeIntLike(CodeGen& codeGen, const AstBinaryExpr& node, const SemaNodeView& leftView, const SemaNodeView& rightView)
    {
        SWC_ASSERT(leftView.type && rightView.type);
        const CodeGenNodePayload* leftPayload  = codeGen.payload(node.nodeLeftRef);
        const CodeGenNodePayload* rightPayload = codeGen.payload(node.nodeRightRef);
        SWC_ASSERT(leftPayload != nullptr);
        SWC_ASSERT(rightPayload != nullptr);

        const MicroOpBits opBits = arithmeticOpBits(*leftView.type);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curNodeViewType().typeRef);

        MicroReg rightReg = MicroReg::invalid();
        if (shouldReuseLeftOperandAsDestination(codeGen, node.nodeLeftRef, *leftPayload))
            nodePayload.reg = leftPayload->reg;
        else
            materializeBinaryOperand(nodePayload.reg, codeGen, *leftPayload, leftView.typeRef, opBits);

        if (codeGen.canUseOperandRegDirect(*rightPayload))
            rightReg = rightPayload->reg;
        else
            materializeBinaryOperand(rightReg, codeGen, *rightPayload, rightView.typeRef, opBits);

        codeGen.builder().emitOpBinaryRegReg(nodePayload.reg, rightReg, MicroOp::Add, opBits);
        return Result::Continue;
    }

    Result emitPlusFloatFloat(CodeGen& codeGen, const AstBinaryExpr& node, const SemaNodeView& leftView, const SemaNodeView& rightView)
    {
        SWC_ASSERT(leftView.type && rightView.type);
        const CodeGenNodePayload* leftPayload  = codeGen.payload(node.nodeLeftRef);
        const CodeGenNodePayload* rightPayload = codeGen.payload(node.nodeRightRef);
        SWC_ASSERT(leftPayload != nullptr);
        SWC_ASSERT(rightPayload != nullptr);

        const MicroOpBits opBits = arithmeticOpBits(*leftView.type);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curNodeViewType().typeRef);

        MicroReg rightReg = MicroReg::invalid();
        if (shouldReuseLeftOperandAsDestination(codeGen, node.nodeLeftRef, *leftPayload))
            nodePayload.reg = leftPayload->reg;
        else
            materializeBinaryOperand(nodePayload.reg, codeGen, *leftPayload, leftView.typeRef, opBits);

        if (codeGen.canUseOperandRegDirect(*rightPayload))
            rightReg = rightPayload->reg;
        else
            materializeBinaryOperand(rightReg, codeGen, *rightPayload, rightView.typeRef, opBits);

        codeGen.builder().emitOpBinaryRegReg(nodePayload.reg, rightReg, MicroOp::FloatAdd, opBits);
        return Result::Continue;
    }

    Result codeGenBinaryPlus(CodeGen& codeGen, const AstBinaryExpr& node)
    {
        const SemaNodeView leftView  = codeGen.nodeViewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.nodeViewType(node.nodeRightRef);
        SWC_ASSERT(leftView.type && rightView.type);

        if (leftView.type->isIntLike() && rightView.type->isIntLike())
            return emitPlusIntLikeIntLike(codeGen, node, leftView, rightView);
        if (leftView.type->isFloat() && rightView.type->isFloat())
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

