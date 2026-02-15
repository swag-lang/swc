#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/ABI/ABICall.h"
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void buildPreparedABIArguments(CodeGen& codeGen, std::span<const ResolvedCallArgument> args, SmallVector<ABICall::PreparedArg>& outArgs)
    {
        outArgs.clear();
        outArgs.reserve(args.size());

        for (const auto& arg : args)
        {
            const AstNodeRef argRef     = arg.argRef;
            const auto*      argPayload = codeGen.payload(argRef);
            SWC_ASSERT(argPayload != nullptr);

            ABICall::PreparedArg preparedArg;
            preparedArg.srcReg = argPayload->reg;

            const auto argView = codeGen.nodeView(argRef);
            if (argView.type)
            {
                preparedArg.isFloat = argView.type->isFloat();
                if (preparedArg.isFloat)
                    preparedArg.numBits = static_cast<uint8_t>(argView.type->payloadFloatBits());
            }

            switch (arg.passKind)
            {
                case CallArgumentPassKind::Direct:
                    preparedArg.kind = ABICall::PreparedArgKind::Direct;
                    break;

                case CallArgumentPassKind::InterfaceObject:
                    preparedArg.kind = ABICall::PreparedArgKind::InterfaceObject;
                    break;

                default:
                    SWC_UNREACHABLE();
            }

            outArgs.push_back(preparedArg);
        }
    }

    Result emitFunctionReturn(CodeGen& codeGen, const SymbolFunction& symbolFunc, AstNodeRef exprRef)
    {
        const CallConvKind callConvKind  = symbolFunc.callConvKind();
        const CallConv&    callConv      = CallConv::get(callConvKind);
        const TypeRef      returnTypeRef = symbolFunc.returnTypeRef();
        const auto         normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);

        if (normalizedRet.isVoid)
        {
            codeGen.builder().encodeRet();
            return Result::Continue;
        }

        SWC_ASSERT(exprRef.isValid());
        SWC_ASSERT(!normalizedRet.isIndirect);

        const auto* exprPayload = SWC_CHECK_NOT_NULL(codeGen.payload(exprRef));
        const bool  isLValue    = codeGen.sema().isLValue(exprRef);
        ABICall::materializeValueToReturnRegs(codeGen.builder(), callConvKind, exprPayload->reg, isLValue, normalizedRet);

        codeGen.builder().encodeRet();
        return Result::Continue;
    }
}

Result AstFunctionDecl::codeGenPreNodeChild(CodeGen&, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::SkipChildren;
    return Result::Continue;
}

Result AstFunctionDecl::codeGenPostNode(CodeGen& codeGen) const
{
    if (!hasFlag(AstFunctionFlagsE::Short))
        return Result::Continue;
    if (nodeBodyRef.isInvalid())
        return Result::Error;
    return emitFunctionReturn(codeGen, codeGen.function(), nodeBodyRef);
}

Result AstReturnStmt::codeGenPostNode(CodeGen& codeGen) const
{
    return emitFunctionReturn(codeGen, codeGen.function(), nodeExprRef);
}

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    MicroInstrBuilder& builder        = codeGen.builder();
    const auto         calleeView     = codeGen.nodeView(nodeExprRef);
    SymbolFunction&    calledFunction = codeGen.curNodeView().sym->cast<SymbolFunction>();
    const CallConvKind callConvKind   = calledFunction.callConvKind();
    const CallConv&    callConv       = CallConv::get(callConvKind);
    const auto         normalizedRet  = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.curNodeView().typeRef, ABITypeNormalize::Usage::Return);

    SmallVector<ResolvedCallArgument> args;
    SmallVector<ABICall::PreparedArg> preparedArgs;
    codeGen.sema().appendResolvedCallArguments(codeGen.curNodeRef(), args);
    buildPreparedABIArguments(codeGen, args, preparedArgs);
    const uint32_t numAbiArgs    = ABICall::prepareArgs(builder, callConvKind, preparedArgs, normalizedRet);
    const auto&    nodePayload   = codeGen.setPayload(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);
    const auto*    calleePayload = codeGen.payload(calleeView.nodeRef);
    const MicroReg resultReg     = nodePayload.reg;
    bool           didCall       = false;

    if (calleePayload)
    {
        ABICall::callByReg(builder, callConvKind, calleePayload->reg, numAbiArgs, &calledFunction);
        didCall = true;
    }
    else if (calledFunction.hasJitEntryAddress())
    {
        ABICall::callByLocal(builder, callConvKind, calledFunction.idRef(), calledFunction.jitEntryAddress(), numAbiArgs, &calledFunction);
        didCall = true;
    }
    else
    {
        return Result::Pause;
    }

    SWC_ASSERT(didCall);
    ABICall::materializeReturnToReg(builder, resultReg, callConvKind, normalizedRet);
    return Result::Continue;
}

Result AstIntrinsicCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicCompiler:
        {
            const auto  compilerIfAddress = reinterpret_cast<uint64_t>(&codeGen.ctx().compiler().runtimeCompiler());
            const auto  nodeView          = codeGen.curNodeView();
            const auto& payload           = codeGen.setPayload(codeGen.curNodeRef(), nodeView.typeRef);
            codeGen.builder().encodeLoadRegImm(payload.reg, compilerIfAddress, MicroOpBits::B64);
            return Result::Continue;
        }

        default:
            SWC_ASSERT(false); // TODO: replace assert with a proper codegen diagnostic.
            return Result::Error;
    }
}

SWC_END_NAMESPACE();

