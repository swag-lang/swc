#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroReg parameterSourcePhysReg(const CallConv& callConv, const CodeGenHelpers::FunctionParameterInfo& paramInfo)
    {
        if (paramInfo.isFloat)
        {
            SWC_ASSERT(paramInfo.slotIndex < callConv.floatArgRegs.size());
            return callConv.floatArgRegs[paramInfo.slotIndex];
        }

        SWC_ASSERT(paramInfo.slotIndex < callConv.intArgRegs.size());
        return callConv.intArgRegs[paramInfo.slotIndex];
    }

    ABICall::PreparedArgKind abiPreparedArgKind(CallArgumentPassKind passKind)
    {
        switch (passKind)
        {
            case CallArgumentPassKind::Direct:
                return ABICall::PreparedArgKind::Direct;

            case CallArgumentPassKind::InterfaceObject:
                return ABICall::PreparedArgKind::InterfaceObject;

            default:
                SWC_UNREACHABLE();
        }
    }

    void setPayloadStorageKind(CodeGenNodePayload& payload, bool isIndirect)
    {
        if (isIndirect)
            payload.setIsAddress();
        else
            payload.setIsValue();
    }

    void emitFunctionCall(CodeGen& codeGen, SymbolFunction& calledFunction, const AstNodeRef& calleeRef, const ABICall::PreparedCall& preparedCall)
    {
        MicroBuilder&             builder       = codeGen.builder();
        const CallConvKind        callConvKind  = calledFunction.callConvKind();
        const CodeGenNodePayload* calleePayload = codeGen.payload(calleeRef);

        if (calleePayload)
        {
            ABICall::callReg(builder, callConvKind, calleePayload->reg, preparedCall);
            return;
        }

        const MicroReg callTargetReg = codeGen.nextVirtualIntRegister();
        if (calledFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &calledFunction, callTargetReg, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &calledFunction, callTargetReg, preparedCall);
    }

    void materializeRegisterParameters(CodeGen& codeGen, const SymbolFunction& symbolFunc)
    {
        const CallConv&                     callConv = CallConv::get(symbolFunc.callConvKind());
        const std::vector<SymbolVariable*>& params   = symbolFunc.parameters();
        MicroBuilder&                       builder  = codeGen.builder();

        for (size_t i = 0; i < params.size(); ++i)
        {
            const SymbolVariable* const symVar = params[i];
            if (!symVar)
                continue;

            const CodeGenHelpers::FunctionParameterInfo paramInfo = CodeGenHelpers::functionParameterInfo(codeGen, symbolFunc, *symVar);
            if (!paramInfo.isRegisterArg)
                continue;

            CodeGenNodePayload symbolPayload;
            symbolPayload.reg     = paramInfo.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
            symbolPayload.typeRef = symVar->typeRef();

            SmallVector<MicroReg> futureSourceRegs;
            for (size_t j = i + 1; j < params.size(); ++j)
            {
                const SymbolVariable* const laterSymVar = params[j];
                if (!laterSymVar)
                    continue;

                const CodeGenHelpers::FunctionParameterInfo laterParamInfo = CodeGenHelpers::functionParameterInfo(codeGen, symbolFunc, *laterSymVar);
                if (!laterParamInfo.isRegisterArg)
                    continue;

                futureSourceRegs.push_back(parameterSourcePhysReg(callConv, laterParamInfo));
            }

            builder.addVirtualRegForbiddenPhysRegs(symbolPayload.reg, futureSourceRegs);
            CodeGenHelpers::emitLoadFunctionParameterToReg(codeGen, symbolFunc, paramInfo, symbolPayload.reg);
            setPayloadStorageKind(symbolPayload, paramInfo.isIndirect);

            codeGen.setVariablePayload(*symVar, symbolPayload);
        }
    }

    void buildPreparedABIArguments(CodeGen& codeGen, const SymbolFunction& calledFunction, std::span<const ResolvedCallArgument> args, SmallVector<ABICall::PreparedArg>& outArgs)
    {
        // Convert resolved semantic arguments into ABI-prepared argument descriptors.
        outArgs.clear();
        outArgs.reserve(args.size());
        const CallConvKind                  callConvKind = calledFunction.callConvKind();
        const CallConv&                     callConv     = CallConv::get(callConvKind);
        const std::vector<SymbolVariable*>& params       = calledFunction.parameters();

        for (size_t i = 0; i < args.size(); ++i)
        {
            const auto&      arg    = args[i];
            const AstNodeRef argRef = arg.argRef;
            if (argRef.isInvalid())
                continue;
            const CodeGenNodePayload* argPayload = codeGen.payload(argRef);
            SWC_ASSERT(argPayload != nullptr);
            const SemaNodeView argView = codeGen.viewType(argRef);

            ABICall::PreparedArg preparedArg;
            preparedArg.srcReg = argPayload->reg;

            TypeRef normalizedTypeRef = TypeRef::invalid();
            if (i < params.size() && params[i])
                normalizedTypeRef = params[i]->typeRef();

            if (normalizedTypeRef.isInvalid())
                normalizedTypeRef = argView.typeRef();
            else
            {
                const TypeInfo& paramType = codeGen.ctx().typeMgr().get(normalizedTypeRef);
                if (paramType.isAnyVariadic())
                    normalizedTypeRef = argView.typeRef();
            }

            if (normalizedTypeRef.isValid())
            {
                const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, normalizedTypeRef, ABITypeNormalize::Usage::Argument);
                preparedArg.isFloat                                  = normalizedArg.isFloat;
                preparedArg.numBits                                  = normalizedArg.numBits;
                preparedArg.isAddressed                              = argPayload->isAddress() && !normalizedArg.isIndirect;
            }

            preparedArg.kind = abiPreparedArgKind(arg.passKind);

            outArgs.push_back(preparedArg);
        }
    }

    Result emitFunctionReturn(CodeGen& codeGen, const SymbolFunction& symbolFunc, AstNodeRef exprRef)
    {
        const CallConvKind                     callConvKind  = symbolFunc.callConvKind();
        const CallConv&                        callConv      = CallConv::get(callConvKind);
        const TypeRef                          returnTypeRef = symbolFunc.returnTypeRef();
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);

        if (normalizedRet.isVoid)
        {
            // Void returns only need control transfer; ABI return registers are irrelevant.
            codeGen.builder().emitRet();
            return Result::Continue;
        }

        SWC_ASSERT(exprRef.isValid());

        const CodeGenNodePayload* exprPayload = SWC_CHECK_NOT_NULL(codeGen.payload(exprRef));
        if (normalizedRet.isIndirect)
        {
            // Hidden first argument points to caller-provided return storage.
            SWC_ASSERT(!callConv.intArgRegs.empty());

            const CodeGenNodePayload* fnPayload = codeGen.payload(symbolFunc.declNodeRef());
            SWC_ASSERT(fnPayload);
            SWC_ASSERT(fnPayload->isAddress());

            const MicroReg outputStorageReg = fnPayload->reg;
            SWC_ASSERT(exprPayload->isAddress());
            CodeGenHelpers::emitMemCopy(codeGen, outputStorageReg, exprPayload->reg, normalizedRet.indirectSize);
            codeGen.builder().emitLoadRegReg(callConv.intReturn, outputStorageReg, MicroOpBits::B64);
        }
        else
        {
            // Direct returns are normalized to ABI return registers (int/float lane).
            const bool isAddressed = exprPayload->isAddress();
            ABICall::materializeValueToReturnRegs(codeGen.builder(), callConvKind, exprPayload->reg, isAddressed, normalizedRet);
        }

        codeGen.builder().emitRet();
        return Result::Continue;
    }
}

Result AstFunctionDecl::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::SkipChildren;

    const SymbolFunction&                  symbolFunc    = codeGen.function();
    const CallConvKind                     callConvKind  = symbolFunc.callConvKind();
    const CallConv&                        callConv      = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symbolFunc.returnTypeRef(), ABITypeNormalize::Usage::Return);
    materializeRegisterParameters(codeGen, symbolFunc);

    if (normalizedRet.isIndirect)
    {
        // Cache hidden return pointer in the function payload for return statements.
        SWC_ASSERT(!callConv.intArgRegs.empty());
        const CodeGenNodePayload& payload = codeGen.setPayloadAddress(codeGen.curNodeRef());
        codeGen.builder().emitLoadRegReg(payload.reg, callConv.intArgRegs[0], MicroOpBits::B64);
    }

    return Result::Continue;
}

Result AstFunctionDecl::codeGenPostNode(CodeGen& codeGen) const
{
    if (!hasFlag(AstFunctionFlagsE::Short))
        return Result::Continue;
    SWC_ASSERT(nodeBodyRef.isValid());
    return emitFunctionReturn(codeGen, codeGen.function(), nodeBodyRef);
}

Result AstReturnStmt::codeGenPostNode(CodeGen& codeGen) const
{
    return emitFunctionReturn(codeGen, codeGen.function(), nodeExprRef);
}

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    MicroBuilder&                          builder        = codeGen.builder();
    const SemaNodeView                     calleeView     = codeGen.viewZero(nodeExprRef);
    const SemaNodeView                     currentView    = codeGen.curViewTypeSymbol();
    SymbolFunction&                        calledFunction = currentView.sym()->cast<SymbolFunction>();
    const CallConvKind                     callConvKind   = calledFunction.callConvKind();
    const CallConv&                        callConv       = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType normalizedRet  = ABITypeNormalize::normalize(codeGen.ctx(), callConv, currentView.typeRef(), ABITypeNormalize::Usage::Return);

    SmallVector<ResolvedCallArgument> args;
    SmallVector<ABICall::PreparedArg> preparedArgs;
    codeGen.appendResolvedCallArguments(codeGen.curNodeRef(), args);
    buildPreparedABIArguments(codeGen, calledFunction, args, preparedArgs);

    // prepareArgs handles register placement, stack slots, and hidden indirect return arg.
    const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs, normalizedRet);
    CodeGenNodePayload&         nodePayload  = codeGen.setPayload(codeGen.curNodeRef(), currentView.typeRef());
    emitFunctionCall(codeGen, calledFunction, calleeView.nodeRef(), preparedCall);

    ABICall::materializeReturnToReg(builder, nodePayload.reg, callConvKind, normalizedRet);
    setPayloadStorageKind(nodePayload, normalizedRet.isIndirect);

    return Result::Continue;
}

SWC_END_NAMESPACE();
