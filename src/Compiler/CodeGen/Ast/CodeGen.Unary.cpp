#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef resolveOperandTypeRef(const CodeGenNodePayload& payload, TypeRef fallbackTypeRef)
    {
        if (payload.typeRef.isValid())
            return payload.typeRef;
        return fallbackTypeRef;
    }

    MicroOpBits unaryOpBits(const TypeInfo& typeInfo)
    {
        if (typeInfo.isFloat())
        {
            const uint32_t floatBits = typeInfo.payloadFloatBits() ? typeInfo.payloadFloatBits() : 64;
            return microOpBitsFromBitWidth(floatBits);
        }

        if (typeInfo.isIntLike())
        {
            const uint32_t intBits = typeInfo.payloadIntLikeBits() ? typeInfo.payloadIntLikeBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        if (typeInfo.isBool())
            return MicroOpBits::B8;

        return MicroOpBits::B64;
    }

    void materializeUnaryOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        MicroBuilder& builder = codeGen.builder();
        outReg                = codeGen.nextVirtualRegisterForType(operandTypeRef);
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    Result codeGenUnaryPlus(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        const CodeGenNodePayload* childPayload = codeGen.payload(nodeExprRef);
        SWC_ASSERT(childPayload != nullptr);

        const SemaNodeView childView       = codeGen.viewType(nodeExprRef);
        const TypeRef      operandTypeRef  = resolveOperandTypeRef(*childPayload, childView.typeRef());
        const TypeRef      resultTypeRef   = codeGen.curViewType().typeRef();
        const TypeInfo&    operandTypeInfo = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits  opBits          = unaryOpBits(operandTypeInfo);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        materializeUnaryOperand(resultPayload.reg, codeGen, *childPayload, operandTypeRef, opBits);
        return Result::Continue;
    }

    Result codeGenUnaryMinus(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        MicroBuilder&             builder      = codeGen.builder();
        const CodeGenNodePayload* childPayload = codeGen.payload(nodeExprRef);
        SWC_ASSERT(childPayload != nullptr);

        const SemaNodeView childView       = codeGen.viewType(nodeExprRef);
        const TypeRef      operandTypeRef  = resolveOperandTypeRef(*childPayload, childView.typeRef());
        const TypeRef      resultTypeRef   = codeGen.curViewType().typeRef();
        const TypeInfo&    operandTypeInfo = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits  opBits          = unaryOpBits(operandTypeInfo);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        materializeUnaryOperand(resultPayload.reg, codeGen, *childPayload, operandTypeRef, opBits);

        if (operandTypeInfo.isFloat())
        {
            const MicroReg valueReg = codeGen.nextVirtualRegisterForType(operandTypeRef);
            builder.emitLoadRegReg(valueReg, resultPayload.reg, opBits);
            const MicroReg zeroReg = codeGen.nextVirtualRegisterForType(operandTypeRef);
            builder.emitClearReg(zeroReg, opBits);
            builder.emitLoadRegReg(resultPayload.reg, zeroReg, opBits);
            builder.emitOpBinaryRegReg(resultPayload.reg, valueReg, MicroOp::FloatSubtract, opBits);
            return Result::Continue;
        }

        builder.emitOpUnaryReg(resultPayload.reg, MicroOp::Negate, opBits);
        return Result::Continue;
    }

    Result codeGenUnaryBang(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        const CodeGenNodePayload* childPayload = codeGen.payload(nodeExprRef);
        SWC_ASSERT(childPayload != nullptr);

        const SemaNodeView childView      = codeGen.viewType(nodeExprRef);
        const TypeRef      operandTypeRef = resolveOperandTypeRef(*childPayload, childView.typeRef());
        const TypeInfo&    operandType    = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits  opBits         = unaryOpBits(operandType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg operandReg = MicroReg::invalid();
        materializeUnaryOperand(operandReg, codeGen, *childPayload, operandTypeRef, opBits);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&             builder       = codeGen.builder();
        builder.emitCmpRegImm(operandReg, 0, opBits);
        builder.emitSetCondReg(resultPayload.reg, MicroCond::Equal);
        builder.emitLoadZeroExtendRegReg(resultPayload.reg, resultPayload.reg, MicroOpBits::B32, MicroOpBits::B8);
        return Result::Continue;
    }

    Result codeGenUnaryBitwiseNot(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        const CodeGenNodePayload* childPayload = codeGen.payload(nodeExprRef);
        SWC_ASSERT(childPayload != nullptr);

        const SemaNodeView childView       = codeGen.viewType(nodeExprRef);
        const TypeRef      operandTypeRef  = resolveOperandTypeRef(*childPayload, childView.typeRef());
        const TypeRef      resultTypeRef   = codeGen.curViewType().typeRef();
        const TypeInfo&    operandTypeInfo = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits  opBits          = unaryOpBits(operandTypeInfo);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        materializeUnaryOperand(resultPayload.reg, codeGen, *childPayload, operandTypeRef, opBits);
        codeGen.builder().emitOpUnaryReg(resultPayload.reg, MicroOp::BitwiseNot, opBits);
        return Result::Continue;
    }

    Result codeGenUnaryDeref(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        MicroBuilder&             builder      = codeGen.builder();
        const CodeGenNodePayload* childPayload = codeGen.payload(nodeExprRef);
        SWC_ASSERT(childPayload != nullptr);

        const SemaNodeView        view    = codeGen.curViewType();
        const CodeGenNodePayload& payload = codeGen.setPayloadAddress(codeGen.curNodeRef(), view.typeRef());
        builder.emitLoadRegReg(payload.reg, childPayload->reg, MicroOpBits::B64);
        return Result::Continue;
    }
}

Result AstUnaryExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::SymPlus:
            return codeGenUnaryPlus(codeGen, nodeExprRef);
        case TokenId::SymMinus:
            return codeGenUnaryMinus(codeGen, nodeExprRef);
        case TokenId::SymBang:
            return codeGenUnaryBang(codeGen, nodeExprRef);
        case TokenId::SymTilde:
            return codeGenUnaryBitwiseNot(codeGen, nodeExprRef);
        case TokenId::KwdDRef:
            return codeGenUnaryDeref(codeGen, nodeExprRef);

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
