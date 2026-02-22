#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroReg materializeCountLikeBaseReg(CodeGen& codeGen, const CodeGenNodePayload& payload)
    {
        if (payload.isValue())
            return payload.reg;

        const MicroReg baseReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegMem(baseReg, payload.reg, 0, MicroOpBits::B64);
        return baseReg;
    }

    Result codeGenCountOf(CodeGen& codeGen, AstNodeRef exprRef)
    {
        MicroBuilder&                   builder       = codeGen.builder();
        const SemaNodeView              exprView      = codeGen.viewType(exprRef);
        const CodeGenNodePayload* const exprPayload   = SWC_CHECK_NOT_NULL(codeGen.payload(exprRef));
        const TypeInfo* const           exprType      = exprView.type();
        const TypeRef                   resultTypeRef = codeGen.curViewType().typeRef();
        SWC_ASSERT(exprType != nullptr);

        if (exprType->isIntUnsigned())
        {
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
            const uint32_t            intBits       = exprType->payloadIntBits() ? exprType->payloadIntBits() : 64;
            const MicroOpBits         opBits        = microOpBitsFromBitWidth(intBits);
            if (exprPayload->isAddress())
                builder.emitLoadRegMem(resultPayload.reg, exprPayload->reg, 0, opBits);
            else
                builder.emitLoadRegReg(resultPayload.reg, exprPayload->reg, opBits);
            return Result::Continue;
        }

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        const MicroReg            baseReg       = materializeCountLikeBaseReg(codeGen, *exprPayload);
        if (exprType->isString())
        {
            builder.emitLoadRegMem(resultPayload.reg, baseReg, offsetof(Runtime::String, length), MicroOpBits::B64);
            return Result::Continue;
        }

        if (exprType->isSlice() || exprType->isAnyVariadic())
        {
            builder.emitLoadRegMem(resultPayload.reg, baseReg, offsetof(Runtime::Slice<std::byte>, count), MicroOpBits::B64);
            return Result::Continue;
        }

        SWC_INTERNAL_ERROR();
    }

    Result codeGenDataOf(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(!children.empty());

        const AstNodeRef          exprRef     = children[0];
        const CodeGenNodePayload* exprPayload = SWC_CHECK_NOT_NULL(codeGen.payload(exprRef));
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        const CodeGenNodePayload& payload     = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&             builder     = codeGen.builder();

        if (exprView.type() && (exprView.type()->isString() || exprView.type()->isSlice() || exprView.type()->isAny()))
            builder.emitLoadRegMem(payload.reg, exprPayload->reg, 0, MicroOpBits::B64);
        else if (exprView.type() && exprView.type()->isArray())
            builder.emitLoadRegReg(payload.reg, exprPayload->reg, MicroOpBits::B64);
        else if (exprPayload->isAddress())
            builder.emitLoadRegMem(payload.reg, exprPayload->reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(payload.reg, exprPayload->reg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenKindOf(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(!children.empty());

        const AstNodeRef                exprRef     = children[0];
        const CodeGenNodePayload* const exprPayload = SWC_CHECK_NOT_NULL(codeGen.payload(exprRef));
        CodeGenNodePayload&             result      = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&                   builder     = codeGen.builder();
        const MicroReg                  anyBaseReg  = exprPayload->reg;
        result.reg                                  = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(result.reg, anyBaseReg, offsetof(Runtime::Any, type), MicroOpBits::B64);
        return Result::Continue;
    }
}

Result AstCountOfExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return codeGenCountOf(codeGen, nodeExprRef);
}

Result AstIntrinsicCall::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicDataOf:
            return codeGenDataOf(codeGen, *this);
        case TokenId::IntrinsicKindOf:
            return codeGenKindOf(codeGen, *this);

        default:
            SWC_UNREACHABLE();
    }
}

Result AstIntrinsicCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicAssert:
        {
            SmallVector<AstNodeRef> args;
            collectArguments(args, codeGen.ast());
            if (args.empty())
                return Result::Continue;

            const CodeGenNodePayload* const argPayload = codeGen.payload(args[0]);
            if (!argPayload)
                return Result::Continue;
            const MicroReg                  condReg    = codeGen.nextVirtualIntRegister();
            MicroBuilder&                   builder    = codeGen.builder();
            if (argPayload->isAddress())
                builder.emitLoadRegMem(condReg, argPayload->reg, 0, MicroOpBits::B8);
            else
                builder.emitLoadRegReg(condReg, argPayload->reg, MicroOpBits::B8);

            const Ref okLabel = builder.createLabel();
            builder.emitCmpRegImm(condReg, ApInt(uint64_t{0}, 64), MicroOpBits::B8);
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, okLabel);
            builder.emitAssertTrap();
            builder.placeLabel(okLabel);
            return Result::Continue;
        }

        case TokenId::IntrinsicBcBreakpoint:
            codeGen.builder().emitBreakpoint();
            return Result::Continue;

        case TokenId::IntrinsicCompiler:
        {
            const uint64_t            compilerIfAddress = reinterpret_cast<uint64_t>(&codeGen.compiler().runtimeCompiler());
            const SemaNodeView        view              = codeGen.curViewType();
            const CodeGenNodePayload& payload           = codeGen.setPayloadValue(codeGen.curNodeRef(), view.typeRef());
            codeGen.builder().emitLoadRegPtrImm(payload.reg, compilerIfAddress);
            return Result::Continue;
        }

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
