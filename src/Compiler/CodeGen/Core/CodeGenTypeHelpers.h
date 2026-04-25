#pragma once
#include "Backend/Micro/MicroTypes.h"
#include "Compiler/Lexer/Token.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenTypeHelpers
{
    inline MicroOpBits bitsFromStorageSize(uint64_t size)
    {
        if (size == 1 || size == 2 || size == 4 || size == 8)
            return microOpBitsFromChunkSize(static_cast<uint32_t>(size));
        return MicroOpBits::Zero;
    }

    inline MicroOpBits numericBits(const TypeInfo& typeInfo)
    {
        if (typeInfo.isFloat())
            return microOpBitsFromBitWidth(typeInfo.payloadFloatBitsOr(64));

        if (typeInfo.isIntLike())
            return microOpBitsFromBitWidth(typeInfo.payloadIntLikeBitsOr(64));

        return MicroOpBits::Zero;
    }

    inline MicroOpBits numericOrBoolBits(const TypeInfo& typeInfo)
    {
        if (typeInfo.isBool())
            return MicroOpBits::B8;
        return numericBits(typeInfo);
    }

    inline MicroOpBits copyBits(const TypeInfo& typeInfo)
    {
        const MicroOpBits bits = numericBits(typeInfo);
        if (bits != MicroOpBits::Zero)
            return bits;
        return MicroOpBits::B64;
    }

    inline MicroOpBits conditionBits(const TypeInfo& typeInfo, TaskContext& ctx)
    {
        const MicroOpBits bits = bitsFromStorageSize(typeInfo.sizeOf(ctx));
        if (bits != MicroOpBits::Zero)
            return bits;
        return MicroOpBits::B64;
    }

    inline MicroOpBits compareBits(const TypeInfo& typeInfo, TaskContext& ctx)
    {
        const MicroOpBits bits = numericOrBoolBits(typeInfo);
        if (bits != MicroOpBits::Zero)
            return bits;
        return conditionBits(typeInfo, ctx);
    }

    inline MicroOpBits scalarStoreBits(const TypeInfo& typeInfo, TaskContext& ctx)
    {
        const MicroOpBits bits = numericOrBoolBits(typeInfo);
        if (bits != MicroOpBits::Zero)
            return bits;

        if (typeInfo.isEnum() || typeInfo.isAnyPointer() || (typeInfo.isFunction() && !typeInfo.isLambdaClosure()) || typeInfo.isCString() || typeInfo.isTypeInfo())
            return bitsFromStorageSize(typeInfo.sizeOf(ctx));

        return MicroOpBits::Zero;
    }

    inline uint64_t blockPointerStride(TaskContext& ctx, const TypeInfo& pointerType)
    {
        SWC_ASSERT(pointerType.isAnyPointer());
        const uint64_t stride = ctx.typeMgr().get(pointerType.payloadTypeRef()).sizeOf(ctx);
        SWC_ASSERT(stride > 0);
        return stride;
    }

    inline uint64_t blockPointerStride(TaskContext& ctx, TypeRef pointerTypeRef)
    {
        return blockPointerStride(ctx, ctx.typeMgr().get(pointerTypeRef));
    }

    inline bool isStringCompareType(TaskContext& ctx, TypeRef typeRef)
    {
        const TypeRef   unwrappedTypeRef = ctx.typeMgr().unwrapAliasEnum(ctx, typeRef);
        const TypeInfo& typeInfo         = ctx.typeMgr().get(unwrappedTypeRef);
        return typeInfo.isString();
    }

    inline MicroOp intBinaryMicroOp(TokenId tokId, bool isSigned)
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

    inline MicroOp floatBinaryMicroOp(TokenId tokId)
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
}

SWC_END_NAMESPACE();
