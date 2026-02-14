#include "pch.h"
#include "Backend/MachineCode/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroOpBits microOpBitsFromBitWidth(uint32_t bitWidth)
    {
        switch (bitWidth)
        {
            case 8:
                return MicroOpBits::B8;
            case 16:
                return MicroOpBits::B16;
            case 32:
                return MicroOpBits::B32;
            case 64:
                return MicroOpBits::B64;
            default:
                SWC_INTERNAL_ERROR();
        }
    }

    Result emitConstReturnValue(CodeGen& codeGen, const SemaNodeView& exprView)
    {
        SWC_ASSERT(exprView.cst);
        SWC_ASSERT(exprView.type);

        auto*       builder  = codeGen.builder();
        const auto& callConv = CallConv::host();
        const auto& cst      = *exprView.cst;
        const auto& ty       = *exprView.type;

        if (ty.isBool())
        {
            builder->encodeLoadRegImm(callConv.intReturn, cst.getBool() ? 1 : 0, MicroOpBits::B8, EncodeFlagsE::Zero);
            return Result::Continue;
        }

        if (ty.isIntLike())
        {
            uint64_t value = 0;
            if (cst.isInt())
                value = cst.getInt().isUnsigned() ? cst.getInt().as64() : std::bit_cast<uint64_t>(cst.getInt().as64Signed());
            else if (cst.isChar())
                value = cst.getChar();
            else if (cst.isRune())
                value = cst.getRune();
            else
                return Result::Continue;

            builder->encodeLoadRegImm(callConv.intReturn, value, microOpBitsFromBitWidth(ty.payloadIntLikeBits()), EncodeFlagsE::Zero);
            return Result::Continue;
        }

        if (ty.isEnum())
        {
            const TypeInfo& underlyingTy = codeGen.ctx().typeMgr().get(ty.payloadSymEnum().underlyingTypeRef());
            const ConstantValue* enumStorageCst = &cst;
            if (cst.isEnumValue())
                enumStorageCst = &codeGen.sema().cstMgr().get(cst.getEnumValue());
            if (!enumStorageCst->isInt())
                return Result::Continue;

            const uint64_t value = enumStorageCst->getInt().isUnsigned() ? enumStorageCst->getInt().as64() : std::bit_cast<uint64_t>(enumStorageCst->getInt().as64Signed());
            builder->encodeLoadRegImm(callConv.intReturn, value, microOpBitsFromBitWidth(underlyingTy.payloadIntLikeBits()), EncodeFlagsE::Zero);
            return Result::Continue;
        }

        if (ty.isFloat())
        {
            const MicroOpBits bits = microOpBitsFromBitWidth(ty.payloadFloatBits());
            const uint64_t    raw  = bits == MicroOpBits::B32 ? static_cast<uint64_t>(std::bit_cast<uint32_t>(cst.getFloat().asFloat())) : std::bit_cast<uint64_t>(cst.getFloat().asDouble());
            builder->encodeLoadRegImm(callConv.intReturn, raw, bits, EncodeFlagsE::Zero);
            builder->encodeLoadRegReg(callConv.floatReturn, callConv.intReturn, bits, EncodeFlagsE::Zero);
            return Result::Continue;
        }

        if (ty.isValuePointer())
        {
            builder->encodeLoadRegImm(callConv.intReturn, cst.getValuePointer(), MicroOpBits::B64, EncodeFlagsE::Zero);
            return Result::Continue;
        }

        if (ty.isBlockPointer())
        {
            builder->encodeLoadRegImm(callConv.intReturn, cst.getBlockPointer(), MicroOpBits::B64, EncodeFlagsE::Zero);
            return Result::Continue;
        }

        return Result::Continue;
    }
}

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView exprView(codeGen.sema(), nodeExprRef);
    if (exprView.cst && exprView.type && !exprView.type->isStruct())
        RESULT_VERIFY(emitConstReturnValue(codeGen, exprView));

    codeGen.builder()->encodeRet(EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
