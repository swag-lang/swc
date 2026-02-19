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
    MicroOpBits parameterLoadBits(const ABITypeNormalize::NormalizedType& normalizedParam)
    {
        if (normalizedParam.isFloat)
            return microOpBitsFromBitWidth(normalizedParam.numBits);
        return MicroOpBits::B64;
    }

    void materializeRegisterParameters(CodeGen& codeGen, const SymbolFunction& symbolFunc)
    {
        const CallConv&                     callConv   = CallConv::get(symbolFunc.callConvKind());
        const uint32_t                      numRegArgs = callConv.numArgRegisterSlots();
        const std::vector<SymbolVariable*>& params     = symbolFunc.parameters();
        MicroBuilder&                       builder    = codeGen.builder();

        for (size_t i = 0; i < params.size(); ++i)
        {
            const SymbolVariable* const symVar = params[i];
            if (!symVar)
                continue;

            const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar->typeRef(), ABITypeNormalize::Usage::Argument);
            const uint32_t                         slotIndex       = ABICall::argumentIndexForFunctionParameter(codeGen.ctx(), symbolFunc.callConvKind(), symbolFunc.returnTypeRef(), static_cast<uint32_t>(i));
            const MicroOpBits                      opBits          = parameterLoadBits(normalizedParam);
            if (slotIndex >= numRegArgs)
                continue;

            CodeGenNodePayload symbolPayload;
            symbolPayload.reg     = normalizedParam.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
            symbolPayload.typeRef = symVar->typeRef();

            SmallVector<MicroReg> futureSourceRegs;
            for (size_t j = i + 1; j < params.size(); ++j)
            {
                const SymbolVariable* const laterSymVar = params[j];
                if (!laterSymVar)
                    continue;

                const ABITypeNormalize::NormalizedType normalizedLater = ABITypeNormalize::normalize(codeGen.ctx(), callConv, laterSymVar->typeRef(), ABITypeNormalize::Usage::Argument);
                const uint32_t                         laterSlotIndex  = ABICall::argumentIndexForFunctionParameter(codeGen.ctx(), symbolFunc.callConvKind(), symbolFunc.returnTypeRef(), static_cast<uint32_t>(j));
                if (laterSlotIndex >= numRegArgs)
                    continue;

                if (normalizedLater.isFloat)
                {
                    SWC_ASSERT(laterSlotIndex < callConv.floatArgRegs.size());
                    futureSourceRegs.push_back(callConv.floatArgRegs[laterSlotIndex]);
                }
                else
                {
                    SWC_ASSERT(laterSlotIndex < callConv.intArgRegs.size());
                    futureSourceRegs.push_back(callConv.intArgRegs[laterSlotIndex]);
                }
            }

            builder.addVirtualRegForbiddenPhysRegs(symbolPayload.reg, futureSourceRegs);

            if (normalizedParam.isFloat)
            {
                SWC_ASSERT(slotIndex < callConv.floatArgRegs.size());
                builder.emitLoadRegReg(symbolPayload.reg, callConv.floatArgRegs[slotIndex], opBits);
            }
            else
            {
                SWC_ASSERT(slotIndex < callConv.intArgRegs.size());
                builder.emitLoadRegReg(symbolPayload.reg, callConv.intArgRegs[slotIndex], opBits);
            }

            if (normalizedParam.isIndirect)
                CodeGen::setPayloadAddress(symbolPayload);
            else
                CodeGen::setPayloadValue(symbolPayload);

            codeGen.setVariablePayload(*symVar, symbolPayload);
        }
    }

    bool shouldDeferCallResultMaterializationToCompilerRun(CodeGen& codeGen, const ABITypeNormalize::NormalizedType& normalizedRet)
    {
        // Compiler-run wrappers consume return registers directly, so avoid extra moves.
        if (normalizedRet.isVoid || normalizedRet.isIndirect)
            return false;

        const AstNodeRef parentNodeRef = codeGen.visit().parentNodeRef(0);
        if (parentNodeRef.isInvalid())
            return false;

        const AstNode* parentNode = codeGen.visit().parentNode(0);
        if (!parentNode || parentNode->isNot(AstNodeId::CompilerRunExpr))
            return false;

        const AstCompilerRunExpr* runExpr = parentNode->safeCast<AstCompilerRunExpr>();
        if (!runExpr)
            return false;

        return runExpr->nodeExprRef == codeGen.curNodeRef();
    }

    void buildPreparedABIArguments(CodeGen& codeGen, CallConvKind callConvKind, std::span<const ResolvedCallArgument> args, SmallVector<ABICall::PreparedArg>& outArgs)
    {
        // Convert resolved semantic arguments into ABI-prepared argument descriptors.
        outArgs.clear();
        outArgs.reserve(args.size());
        const CallConv& callConv = CallConv::get(callConvKind);

        for (const auto& arg : args)
        {
            const AstNodeRef argRef = arg.argRef;
            if (argRef.isInvalid())
                continue;
            const CodeGenNodePayload* argPayload = codeGen.payload(argRef);
            SWC_ASSERT(argPayload != nullptr);

            ABICall::PreparedArg preparedArg;
            preparedArg.srcReg = argPayload->reg;

            const SemaNodeView argView = codeGen.nodeView(argRef);
            if (argView.type)
            {
                const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, argView.typeRef, ABITypeNormalize::Usage::Argument);
                preparedArg.isFloat                                  = normalizedArg.isFloat;
                preparedArg.numBits                                  = normalizedArg.numBits;
                preparedArg.isAddressed                              = argPayload->storageKind == CodeGenNodePayload::StorageKind::Address && !normalizedArg.isIndirect;
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
            SWC_ASSERT(fnPayload->storageKind == CodeGenNodePayload::StorageKind::Address);

            const MicroReg outputStorageReg = fnPayload->reg;
            SWC_ASSERT(exprPayload->storageKind == CodeGenNodePayload::StorageKind::Address);
            CodeGenHelpers::emitMemCopy(codeGen, outputStorageReg, exprPayload->reg, normalizedRet.indirectSize);
            codeGen.builder().emitLoadRegReg(callConv.intReturn, outputStorageReg, MicroOpBits::B64);
        }
        else
        {
            // Direct returns are normalized to ABI return registers (int/float lane).
            const bool isAddressed = exprPayload->storageKind == CodeGenNodePayload::StorageKind::Address;
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
    const SemaNodeView                     calleeView     = codeGen.nodeView(nodeExprRef);
    SymbolFunction&                        calledFunction = codeGen.curNodeView().sym->cast<SymbolFunction>();
    const CallConvKind                     callConvKind   = calledFunction.callConvKind();
    const CallConv&                        callConv       = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType normalizedRet  = ABITypeNormalize::normalize(codeGen.ctx(), callConv, codeGen.curNodeView().typeRef, ABITypeNormalize::Usage::Return);

    SmallVector<ResolvedCallArgument> args;
    SmallVector<ABICall::PreparedArg> preparedArgs;
    codeGen.appendResolvedCallArguments(codeGen.curNodeRef(), args);
    buildPreparedABIArguments(codeGen, callConvKind, args, preparedArgs);
    // prepareArgs handles register placement, stack slots, and hidden indirect return arg.
    const ABICall::PreparedCall preparedCall  = ABICall::prepareArgs(builder, callConvKind, preparedArgs, normalizedRet);
    CodeGenNodePayload&         nodePayload   = codeGen.setPayload(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);
    const CodeGenNodePayload*   calleePayload = codeGen.payload(calleeView.nodeRef);
    const MicroReg              resultReg     = nodePayload.reg;

    if (calleePayload)
        // Function value call: target already computed in a register.
        ABICall::callReg(builder, callConvKind, calleePayload->reg, preparedCall);
    else
    {
        const MicroReg callTargetReg = codeGen.nextVirtualIntRegister();
        if (calledFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &calledFunction, callTargetReg, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &calledFunction, callTargetReg, preparedCall);
    }

    const bool deferMaterializationToRunExpr = shouldDeferCallResultMaterializationToCompilerRun(codeGen, normalizedRet);
    if (deferMaterializationToRunExpr)
    {
        // Compiler-run call wrapper reads raw ABI return regs itself.
        if (normalizedRet.isFloat)
            nodePayload.reg = callConv.floatReturn;
        else
            nodePayload.reg = callConv.intReturn;
    }
    else
    {
        ABICall::materializeReturnToReg(builder, resultReg, callConvKind, normalizedRet);
    }

    if (normalizedRet.isIndirect)
        CodeGen::setPayloadAddress(nodePayload);
    else
        CodeGen::setPayloadValue(nodePayload);
    return Result::Continue;
}

SWC_END_NAMESPACE();
