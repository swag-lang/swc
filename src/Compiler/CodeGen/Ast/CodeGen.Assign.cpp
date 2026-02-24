#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct AssignLocalTarget
    {
        const CodeGenNodePayload* payload = nullptr;
        TypeRef                   typeRef = TypeRef::invalid();
    };

    const CodeGenNodePayload& ensureOperandPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return *SWC_CHECK_NOT_NULL(codeGen.payload(nodeRef));
    }

    TypeRef resolveOperandTypeRef(const CodeGenNodePayload& payload, TypeRef fallbackTypeRef)
    {
        if (payload.typeRef.isValid())
            return payload.typeRef;
        return fallbackTypeRef;
    }

    MicroOpBits scalarStoreOpBits(CodeGen& codeGen, const TypeInfo& typeInfo)
    {
        if (typeInfo.isFloat())
        {
            const uint32_t floatBits = typeInfo.payloadFloatBits() ? typeInfo.payloadFloatBits() : 64;
            return microOpBitsFromBitWidth(floatBits);
        }

        if (typeInfo.isBool())
            return MicroOpBits::B8;

        if (typeInfo.isIntLike())
        {
            const uint32_t intBits = typeInfo.payloadIntLikeBits() ? typeInfo.payloadIntLikeBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        if (typeInfo.isEnum() || typeInfo.isAnyPointer() || typeInfo.isFunction() || typeInfo.isCString() || typeInfo.isTypeInfo())
        {
            const uint64_t sizeOf = typeInfo.sizeOf(codeGen.ctx());
            if (sizeOf == 1 || sizeOf == 2 || sizeOf == 4 || sizeOf == 8)
                return microOpBitsFromChunkSize(static_cast<uint32_t>(sizeOf));
        }

        return MicroOpBits::Zero;
    }

    bool isScalarAssignmentType(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        return scalarStoreOpBits(codeGen, typeInfo) != MicroOpBits::Zero;
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

    MicroReg materializeAssignOperand(CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        const MicroReg operandReg = codeGen.nextVirtualRegisterForType(operandTypeRef);
        if (operandPayload.isAddress())
            codeGen.builder().emitLoadRegMem(operandReg, operandPayload.reg, 0, opBits);
        else
            codeGen.builder().emitLoadRegReg(operandReg, operandPayload.reg, opBits);

        return operandReg;
    }

    AssignLocalTarget resolveLocalAssignTarget(CodeGen& codeGen, AstNodeRef leftRef)
    {
        AssignLocalTarget target;
        target.payload = codeGen.payload(leftRef);
        if (!target.payload)
            return target;

        const SemaNodeView leftSymView = codeGen.viewSymbol(leftRef);
        if (!leftSymView.sym() || !leftSymView.sym()->isVariable())
            return target;

        const SymbolVariable& symVar = leftSymView.sym()->cast<SymbolVariable>();
        if (!codeGen.localStackSlot(symVar))
            return target;
        if (!target.payload->isAddress())
            return target;

        const SemaNodeView leftTypeView = codeGen.viewType(leftRef);
        const TypeRef      leftTypeRef  = resolveOperandTypeRef(*target.payload, leftTypeView.typeRef());
        if (!leftTypeRef.isValid())
            return target;

        const TypeInfo& leftTypeInfo = codeGen.typeMgr().get(leftTypeRef);
        if (leftTypeInfo.isReference())
            return target;

        target.typeRef = leftTypeRef;
        return target;
    }

    Result codeGenAssignToLocalScalar(CodeGen& codeGen, const AstAssignStmt& node, TokenId assignOp)
    {
        SWC_UNUSED(node.modifierFlags);

        const AssignLocalTarget target = resolveLocalAssignTarget(codeGen, node.nodeLeftRef);
        SWC_ASSERT(target.payload != nullptr);
        SWC_ASSERT(target.typeRef.isValid());

        if (!isScalarAssignmentType(codeGen, target.typeRef))
            SWC_UNREACHABLE();

        const TypeInfo&   targetType = codeGen.typeMgr().get(target.typeRef);
        const MicroOpBits opBits     = scalarStoreOpBits(codeGen, targetType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        const CodeGenNodePayload& rightPayload = ensureOperandPayload(codeGen, node.nodeRightRef);
        const SemaNodeView        rightView    = codeGen.viewType(node.nodeRightRef);
        TypeRef                   rightTypeRef = resolveOperandTypeRef(rightPayload, rightView.typeRef());
        if (!rightTypeRef.isValid())
            rightTypeRef = target.typeRef;

        MicroBuilder& builder = codeGen.builder();
        if (assignOp == TokenId::SymEqual)
        {
            const MicroReg rightReg = materializeAssignOperand(codeGen, rightPayload, rightTypeRef, opBits);
            builder.emitLoadMemReg(target.payload->reg, 0, rightReg, opBits);
            return Result::Continue;
        }

        if (!targetType.isIntLike() && !targetType.isFloat())
            SWC_UNREACHABLE();

        const TokenId  binaryOp = Token::assignToBinary(assignOp);
        const MicroReg leftReg  = codeGen.nextVirtualRegisterForType(target.typeRef);
        builder.emitLoadRegMem(leftReg, target.payload->reg, 0, opBits);

        const MicroReg rightReg = materializeAssignOperand(codeGen, rightPayload, rightTypeRef, opBits);
        if (targetType.isFloat())
        {
            const MicroOp op = floatBinaryMicroOp(binaryOp);
            builder.emitOpBinaryRegReg(leftReg, rightReg, op, opBits);
        }
        else
        {
            const MicroOp op = intBinaryMicroOp(binaryOp, !targetType.isIntLikeUnsigned());
            builder.emitOpBinaryRegReg(leftReg, rightReg, op, opBits);
        }

        builder.emitLoadMemReg(target.payload->reg, 0, leftReg, opBits);
        return Result::Continue;
    }
}

Result AstAssignStmt::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::SymEqual:
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
            return codeGenAssignToLocalScalar(codeGen, *this, tok.id);

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
