#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroOpBits plusOpBits(const TypeInfo& resultType)
    {
        if (resultType.isFloat())
            return microOpBitsFromBitWidth(resultType.payloadFloatBits());

        if (resultType.isInt())
        {
            const uint32_t intBits = resultType.payloadIntBits() ? resultType.payloadIntBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        return MicroOpBits::Zero;
    }

    void materializeBinaryOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef resultTypeRef, MicroOpBits opBits)
    {
        MicroBuilder& builder = codeGen.builder();
        outReg                = codeGen.nextVirtualRegisterForType(resultTypeRef);

        if (operandPayload.storageKind == CodeGenNodePayload::StorageKind::Address)
        {
            builder.encodeLoadRegMem(outReg, operandPayload.reg, 0, opBits);
            return;
        }

        builder.encodeLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    Result codeGenBinaryPlus(CodeGen& codeGen, const AstBinaryExpr& node)
    {
        const SemaNodeView nodeView = codeGen.curNodeView();
        SWC_ASSERT(nodeView.type);
        const TypeInfo& resultType = *nodeView.type;

        if (!resultType.isInt() && !resultType.isFloat())
            return Result::Continue;

        const CodeGenNodePayload* leftPayload  = codeGen.payload(node.nodeLeftRef);
        const CodeGenNodePayload* rightPayload = codeGen.payload(node.nodeRightRef);
        SWC_ASSERT(leftPayload != nullptr);
        SWC_ASSERT(rightPayload != nullptr);

        const MicroOpBits opBits = plusOpBits(resultType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayload(codeGen.curNodeRef(), nodeView.typeRef);
        nodePayload.reg                 = codeGen.nextVirtualRegisterForType(nodeView.typeRef);
        nodePayload.storageKind         = CodeGenNodePayload::StorageKind::Value;

        MicroReg rightReg = MicroReg::invalid();
        materializeBinaryOperand(nodePayload.reg, codeGen, *leftPayload, nodeView.typeRef, opBits);
        materializeBinaryOperand(rightReg, codeGen, *rightPayload, nodeView.typeRef, opBits);

        MicroBuilder& builder = codeGen.builder();
        if (resultType.isFloat())
            builder.encodeOpBinaryRegReg(nodePayload.reg, rightReg, MicroOp::FloatAdd, opBits);
        else
            builder.encodeOpBinaryRegReg(nodePayload.reg, rightReg, MicroOp::Add, opBits);

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
