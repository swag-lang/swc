#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef resolveDerefResultTypeRef(CodeGen& codeGen, TypeRef operandTypeRef)
    {
        operandTypeRef = codeGen.typeMgr().get(operandTypeRef).unwrapAliasEnum(codeGen.ctx(), operandTypeRef);
        return codeGen.typeMgr().get(operandTypeRef).dereferenceTypeRef(codeGen.ctx());
    }

    using CodeGenMemoryHelpers::loadOperandToRegister;

    struct UnaryOperandInfo
    {
        const CodeGenNodePayload* childPayload    = nullptr;
        TypeRef                   operandTypeRef  = TypeRef::invalid();
        TypeRef                   resultTypeRef   = TypeRef::invalid();
        const TypeInfo*           operandTypeInfo = nullptr;
        MicroOpBits               opBits          = MicroOpBits::Zero;
    };

    UnaryOperandInfo collectUnaryOperandInfo(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        UnaryOperandInfo info;
        info.childPayload            = &codeGen.payload(nodeExprRef);
        const SemaNodeView childView = codeGen.viewType(nodeExprRef);
        info.operandTypeRef          = info.childPayload->effectiveTypeRef(childView.typeRef());
        info.resultTypeRef           = codeGen.curViewType().typeRef();
        info.operandTypeInfo         = &codeGen.typeMgr().get(info.operandTypeRef);
        info.opBits                  = CodeGenTypeHelpers::compareBits(*info.operandTypeInfo, codeGen.ctx());
        SWC_ASSERT(info.opBits != MicroOpBits::Zero);
        return info;
    }

    Result codeGenUnaryPlus(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        const UnaryOperandInfo info = collectUnaryOperandInfo(codeGen, nodeExprRef);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), info.resultTypeRef);
        loadOperandToRegister(resultPayload.reg, codeGen, *info.childPayload, info.operandTypeRef, info.opBits);
        return Result::Continue;
    }

    Result codeGenUnaryMinus(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        MicroBuilder&          builder = codeGen.builder();
        const UnaryOperandInfo info    = collectUnaryOperandInfo(codeGen, nodeExprRef);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), info.resultTypeRef);
        loadOperandToRegister(resultPayload.reg, codeGen, *info.childPayload, info.operandTypeRef, info.opBits);

        if (info.operandTypeInfo->isFloat())
        {
            // The micro layer exposes float subtraction but no dedicated float negate, so lower `-x` as
            // `0 - x`.
            const MicroReg zeroReg = codeGen.nextVirtualRegisterForType(info.operandTypeRef);
            builder.emitClearReg(zeroReg, info.opBits);
            builder.emitOpBinaryRegReg(zeroReg, resultPayload.reg, MicroOp::FloatSubtract, info.opBits);
            resultPayload.reg = zeroReg;
            return Result::Continue;
        }

        builder.emitOpUnaryReg(resultPayload.reg, MicroOp::Negate, info.opBits);
        if (CodeGenSafety::hasOverflowRuntimeSafety(codeGen) && info.operandTypeInfo->isIntSigned())
        {
            const auto& node = codeGen.node(codeGen.curNodeRef()).cast<AstUnaryExpr>();
            SWC_RESULT(CodeGenSafety::emitOverflowTrapOnFailure(codeGen, node, MicroCond::NotOverflow));
        }
        return Result::Continue;
    }

    Result codeGenUnaryBang(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        const UnaryOperandInfo info = collectUnaryOperandInfo(codeGen, nodeExprRef);

        MicroReg operandReg;
        loadOperandToRegister(operandReg, codeGen, *info.childPayload, info.operandTypeRef, info.opBits);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&             builder       = codeGen.builder();
        builder.emitCmpRegImm(operandReg, ApInt(0, 64), info.opBits);
        builder.emitSetCondReg(resultPayload.reg, MicroCond::Equal);
        builder.emitLoadZeroExtendRegReg(resultPayload.reg, resultPayload.reg, MicroOpBits::B32, MicroOpBits::B8);
        return Result::Continue;
    }

    Result codeGenUnaryBitwiseNot(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        const UnaryOperandInfo info = collectUnaryOperandInfo(codeGen, nodeExprRef);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), info.resultTypeRef);
        loadOperandToRegister(resultPayload.reg, codeGen, *info.childPayload, info.operandTypeRef, info.opBits);
        codeGen.builder().emitOpUnaryReg(resultPayload.reg, MicroOp::BitwiseNot, info.opBits);
        return Result::Continue;
    }

    Result codeGenUnaryDeref(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        MicroBuilder&             builder      = codeGen.builder();
        const CodeGenNodePayload& childPayload = codeGen.payload(nodeExprRef);
        const SemaNodeView        childView    = codeGen.viewType(nodeExprRef);
        SWC_ASSERT(childView.type());

        const TypeRef             resultTypeRef = resolveDerefResultTypeRef(codeGen, childView.typeRef());
        const CodeGenNodePayload& payload       = codeGen.setPayloadAddress(codeGen.curNodeRef(), resultTypeRef);
        if (childPayload.isAddress())
            builder.emitLoadRegMem(payload.reg, childPayload.reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(payload.reg, childPayload.reg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenUnaryTakeAddress(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        const SemaNodeView        view              = codeGen.curViewType();
        const SemaNodeView        childView         = codeGen.viewTypeSymbol(nodeExprRef);
        const CodeGenNodePayload& payload           = codeGen.setPayloadValue(codeGen.curNodeRef(), view.typeRef());
        const CodeGenNodePayload* childPayloadMaybe = codeGen.safePayload(nodeExprRef);
        if (childView.sym() && childView.sym()->isFunction() && (!childPayloadMaybe || !childPayloadMaybe->reg.isValid()))
        {
            // Function symbols do not materialize an lvalue payload, so taking their address loads the
            // code pointer directly.
            auto& symFunc = childView.sym()->cast<SymbolFunction>();
            codeGen.builder().emitLoadRegPtrReloc(payload.reg, 0, ConstantRef::invalid(), &symFunc);
            return Result::Continue;
        }

        const CodeGenNodePayload& childPayload = codeGen.payload(nodeExprRef);
        if (childView.type() && childView.type()->isReference())
        {
            if (childPayload.isAddress())
                codeGen.builder().emitLoadRegMem(payload.reg, childPayload.reg, 0, MicroOpBits::B64);
            else
                codeGen.builder().emitLoadRegReg(payload.reg, childPayload.reg, MicroOpBits::B64);
        }
        else if (childPayload.isAddress())
            codeGen.builder().emitLoadRegReg(payload.reg, childPayload.reg, MicroOpBits::B64);
        else
            codeGen.builder().emitLoadRegReg(payload.reg, childPayload.reg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenUnaryMoveRef(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        MicroBuilder&             builder      = codeGen.builder();
        const CodeGenNodePayload& childPayload = codeGen.payload(nodeExprRef);

        const SemaNodeView        view    = codeGen.curViewType();
        const CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef(), view.typeRef());
        if (childPayload.isAddress())
            builder.emitLoadRegMem(payload.reg, childPayload.reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(payload.reg, childPayload.reg, MicroOpBits::B64);
        return Result::Continue;
    }
}

Result AstUnaryExpr::codeGenPostNode(CodeGen& codeGen) const
{
    SmallVector<ResolvedCallArgument> resolvedArgs;
    codeGen.sema().appendResolvedCallArguments(codeGen.curNodeRef(), resolvedArgs);

    if (const auto* unaryPayload = codeGen.sema().semaPayload<UnarySpecOpPayload>(codeGen.curNodeRef());
        unaryPayload && unaryPayload->calledFn != nullptr)
    {
        codeGen.sema().setSymbol(codeGen.curNodeRef(), unaryPayload->calledFn);
        if (unaryPayload->calledFn->specOpKind() == SpecOpKind::OpUnary)
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid());
    }

    const SemaNodeView specialOpView = codeGen.curViewSymbol();
    if (!resolvedArgs.empty() && specialOpView.sym() && specialOpView.sym()->isFunction())
    {
        const auto& calledFn = specialOpView.sym()->cast<SymbolFunction>();
        if (calledFn.specOpKind() == SpecOpKind::OpUnary)
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid());
    }

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
        case TokenId::SymAmpersand:
            return codeGenUnaryTakeAddress(codeGen, nodeExprRef);
        case TokenId::KwdMoveRef:
            return codeGenUnaryMoveRef(codeGen, nodeExprRef);

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
