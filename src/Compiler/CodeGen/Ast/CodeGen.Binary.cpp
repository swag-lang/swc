#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t X64_RAX = 0;
    constexpr uint32_t X64_RCX = 2;
    constexpr uint32_t X64_RDX = 3;

    const CodeGenNodePayload& ensureOperandPayload(const CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return *SWC_CHECK_NOT_NULL(codeGen.payload(nodeRef));
    }

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

    void materializeBinaryOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        MicroBuilder& builder = codeGen.builder();
        outReg                = codeGen.nextVirtualRegisterForType(operandTypeRef);
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    void materializeBinaryOperandInReg(MicroReg outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, MicroOpBits opBits)
    {
        MicroBuilder& builder = codeGen.builder();
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

    Result emitIntBinaryGeneral(CodeGen&                  codeGen,
                                TokenId                   tokId,
                                const CodeGenNodePayload& leftPayload,
                                const CodeGenNodePayload& rightPayload,
                                TypeRef                   leftOperandTypeRef,
                                TypeRef                   rightOperandTypeRef,
                                TypeRef                   resultTypeRef)
    {
        const TypeInfo&   leftType = codeGen.typeMgr().get(leftOperandTypeRef);
        const MicroOp     op       = intBinaryMicroOp(tokId, !leftType.isIntLikeUnsigned());
        const MicroOpBits opBits   = arithmeticOpBits(leftType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        materializeBinaryOperand(nodePayload.reg, codeGen, leftPayload, leftOperandTypeRef, opBits);

        MicroReg rightReg = MicroReg::invalid();
        materializeBinaryOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, opBits);

        codeGen.builder().emitOpBinaryRegReg(nodePayload.reg, rightReg, op, opBits);
        return Result::Continue;
    }

    Result emitIntBinaryShift(CodeGen&                  codeGen,
                              TokenId                   tokId,
                              const CodeGenNodePayload& leftPayload,
                              const CodeGenNodePayload& rightPayload,
                              TypeRef                   leftOperandTypeRef,
                              TypeRef                   resultTypeRef)
    {
        const TypeInfo&   leftType = codeGen.typeMgr().get(leftOperandTypeRef);
        const MicroOpBits opBits   = arithmeticOpBits(leftType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        constexpr MicroReg  rcxReg      = MicroReg::intReg(X64_RCX);
        codeGen.builder().addVirtualRegForbiddenPhysReg(nodePayload.reg, rcxReg);

        materializeBinaryOperand(nodePayload.reg, codeGen, leftPayload, leftOperandTypeRef, opBits);
        materializeBinaryOperandInReg(rcxReg, codeGen, rightPayload, opBits);

        const MicroOp op = intBinaryMicroOp(tokId, !leftType.isIntLikeUnsigned());
        codeGen.builder().emitOpBinaryRegReg(nodePayload.reg, rcxReg, op, opBits);
        return Result::Continue;
    }

    Result emitIntBinaryDivMod(CodeGen&                  codeGen,
                               TokenId                   tokId,
                               const CodeGenNodePayload& leftPayload,
                               const CodeGenNodePayload& rightPayload,
                               TypeRef                   leftOperandTypeRef,
                               TypeRef                   rightOperandTypeRef,
                               TypeRef                   resultTypeRef)
    {
        const TypeInfo&   leftType = codeGen.typeMgr().get(leftOperandTypeRef);
        const MicroOp     op       = intBinaryMicroOp(tokId, !leftType.isIntLikeUnsigned());
        const MicroOpBits opBits   = arithmeticOpBits(leftType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        constexpr MicroReg raxReg = MicroReg::intReg(X64_RAX);
        constexpr MicroReg rdxReg = MicroReg::intReg(X64_RDX);

        materializeBinaryOperandInReg(raxReg, codeGen, leftPayload, opBits);
        MicroReg rightReg = MicroReg::invalid();
        materializeBinaryOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, opBits);
        codeGen.builder().addVirtualRegForbiddenPhysReg(rightReg, raxReg);
        codeGen.builder().addVirtualRegForbiddenPhysReg(rightReg, rdxReg);

        codeGen.builder().emitOpBinaryRegReg(raxReg, rightReg, op, opBits);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        codeGen.builder().emitLoadRegReg(nodePayload.reg, raxReg, opBits);
        return Result::Continue;
    }

    Result emitFloatBinary(CodeGen&                  codeGen,
                           TokenId                   tokId,
                           const CodeGenNodePayload& leftPayload,
                           const CodeGenNodePayload& rightPayload,
                           TypeRef                   leftOperandTypeRef,
                           TypeRef                   rightOperandTypeRef,
                           TypeRef                   resultTypeRef)
    {
        const TypeInfo&   leftType = codeGen.typeMgr().get(leftOperandTypeRef);
        const MicroOp     op       = floatBinaryMicroOp(tokId);
        const MicroOpBits opBits   = arithmeticOpBits(leftType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        CodeGenNodePayload& nodePayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);

        materializeBinaryOperand(nodePayload.reg, codeGen, leftPayload, leftOperandTypeRef, opBits);
        MicroReg rightReg = MicroReg::invalid();
        materializeBinaryOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, opBits);

        codeGen.builder().emitOpBinaryRegReg(nodePayload.reg, rightReg, op, opBits);
        return Result::Continue;
    }

    Result codeGenBinaryNumeric(CodeGen& codeGen, const AstBinaryExpr& node, TokenId tokId)
    {
        const SemaNodeView leftView  = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);
        SWC_ASSERT(leftView.type() && rightView.type());

        const CodeGenNodePayload& leftPayload         = ensureOperandPayload(codeGen, node.nodeLeftRef);
        const CodeGenNodePayload& rightPayload        = ensureOperandPayload(codeGen, node.nodeRightRef);
        const TypeRef             leftOperandTypeRef  = resolveOperandTypeRef(leftPayload, leftView.typeRef());
        const TypeRef             rightOperandTypeRef = resolveOperandTypeRef(rightPayload, rightView.typeRef());
        const TypeRef             resultTypeRef       = codeGen.curViewType().typeRef();

        if (leftView.type()->isIntLike() && rightView.type()->isIntLike())
        {
            if (tokId == TokenId::SymSlash || tokId == TokenId::SymPercent)
                return emitIntBinaryDivMod(codeGen, tokId, leftPayload, rightPayload, leftOperandTypeRef, rightOperandTypeRef, resultTypeRef);
            if (tokId == TokenId::SymLowerLower || tokId == TokenId::SymGreaterGreater)
                return emitIntBinaryShift(codeGen, tokId, leftPayload, rightPayload, leftOperandTypeRef, resultTypeRef);

            return emitIntBinaryGeneral(codeGen, tokId, leftPayload, rightPayload, leftOperandTypeRef, rightOperandTypeRef, resultTypeRef);
        }

        if (leftView.type()->isFloat() && rightView.type()->isFloat())
            return emitFloatBinary(codeGen, tokId, leftPayload, rightPayload, leftOperandTypeRef, rightOperandTypeRef, resultTypeRef);

        return Result::Continue;
    }
}

Result AstBinaryExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymAsterisk:
        case TokenId::SymSlash:
        case TokenId::SymPercent:
        case TokenId::SymAmpersand:
        case TokenId::SymPipe:
        case TokenId::SymCircumflex:
        case TokenId::SymGreaterGreater:
        case TokenId::SymLowerLower:
            return codeGenBinaryNumeric(codeGen, *this, tok.id);

        default:
            // TODO
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
