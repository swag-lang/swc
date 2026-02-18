#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/ABI/ABICall.h"
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
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

    uint32_t parameterSlotIndex(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
    {
        const CallConv&                        callConv      = CallConv::get(symbolFunc.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symbolFunc.returnTypeRef(), ABITypeNormalize::Usage::Return);
        const std::vector<SymbolVariable*>& params    = symbolFunc.parameters();
        for (size_t i = 0; i < params.size(); i++)
        {
            if (params[i] != &symVar)
                continue;

            return ABICall::argumentIndexForFunctionParameter(normalizedRet, static_cast<uint32_t>(i));
        }

        SWC_ASSERT(false);
        return ABICall::argumentIndexForFunctionParameter(normalizedRet, 0);
    }

    void lowerParameterPayload(CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, CodeGenNodePayload& outPayload)
    {
        const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar.typeRef(), ABITypeNormalize::Usage::Argument);
        const uint32_t                         slotIndex       = parameterSlotIndex(codeGen, symbolFunc, symVar);
        const uint32_t                         numRegArgs      = callConv.numArgRegisterSlots();
        const MicroOpBits                      opBits          = parameterLoadBits(normalizedParam);
        MicroBuilder&                          builder         = codeGen.builder();

        if (slotIndex < numRegArgs)
        {
            if (normalizedParam.isFloat)
            {
                SWC_ASSERT(slotIndex < callConv.floatArgRegs.size());
                builder.encodeLoadRegReg(outPayload.reg, callConv.floatArgRegs[slotIndex], opBits);
            }
            else
            {
                SWC_ASSERT(slotIndex < callConv.intArgRegs.size());
                builder.encodeLoadRegReg(outPayload.reg, callConv.intArgRegs[slotIndex], opBits);
            }
        }
        else
        {
            const uint64_t stackOffset = ABICall::incomingArgStackOffset(callConv, slotIndex);
            builder.encodeLoadRegMem(outPayload.reg, callConv.stackPointer, stackOffset, opBits);
        }

        outPayload.storageKind = normalizedParam.isIndirect ? CodeGenNodePayload::StorageKind::Address : CodeGenNodePayload::StorageKind::Value;
    }

    void bindSingleVariableFromInitializer(CodeGen& codeGen, const SymbolVariable& symVar, AstNodeRef initRef)
    {
        if (initRef.isInvalid())
            return;

        const CodeGenNodePayload* initPayload = codeGen.payload(initRef);
        if (!initPayload)
            return;

        CodeGenNodePayload symbolPayload = *initPayload;
        symbolPayload.typeRef            = symVar.typeRef();
        codeGen.setVariablePayload(&symVar, symbolPayload);
    }
}

Result AstIdentifier::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView nodeView = codeGen.curNodeView();
    if (!nodeView.sym)
        return Result::Continue;

    const SymbolVariable* symVar = nodeView.sym->safeCast<SymbolVariable>();
    if (!symVar)
        return Result::Continue;

    const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar);
    if (!symbolPayload && symVar->hasExtraFlag(SymbolVariableFlagsE::Parameter))
    {
        const SymbolFunction&                  symbolFunc      = codeGen.function();
        const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar->typeRef(), ABITypeNormalize::Usage::Argument);

        CodeGenNodePayload paramPayload;
        paramPayload.reg         = normalizedParam.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
        paramPayload.typeRef     = symVar->typeRef();
        paramPayload.storageKind = CodeGenNodePayload::StorageKind::Value;

        lowerParameterPayload(codeGen, symbolFunc, *symVar, paramPayload);
        codeGen.setVariablePayload(symVar, paramPayload);
        symbolPayload = codeGen.variablePayload(symVar);
    }

    if (!symbolPayload)
        return Result::Continue;

    CodeGenNodePayload& payload = codeGen.setPayload(codeGen.curNodeRef(), nodeView.typeRef);
    payload.reg                 = symbolPayload->reg;
    payload.storageKind         = symbolPayload->storageKind;
    return Result::Continue;
}

Result AstSingleVarDecl::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView nodeView = codeGen.curNodeView();
    if (!nodeView.sym)
        return Result::Continue;

    SymbolVariable* symVar = nodeView.sym->safeCast<SymbolVariable>();
    if (!symVar)
        return Result::Continue;

    if (hasFlag(AstVarDeclFlagsE::Parameter))
    {
        const SymbolFunction&                  symbolFunc      = codeGen.function();
        const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar->typeRef(), ABITypeNormalize::Usage::Argument);

        CodeGenNodePayload symbolPayload;
        symbolPayload.reg         = normalizedParam.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
        symbolPayload.typeRef     = symVar->typeRef();
        symbolPayload.storageKind = CodeGenNodePayload::StorageKind::Value;

        lowerParameterPayload(codeGen, symbolFunc, *symVar, symbolPayload);
        codeGen.setVariablePayload(symVar, symbolPayload);
        return Result::Continue;
    }

    bindSingleVariableFromInitializer(codeGen, *symVar, nodeInitRef);
    return Result::Continue;
}

Result AstMultiVarDecl::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView nodeView = codeGen.curNodeView();
    if (nodeView.symList.empty())
        return Result::Continue;

    if (hasFlag(AstVarDeclFlagsE::Parameter))
    {
        const SymbolFunction& symbolFunc = codeGen.function();
        const CallConv&       callConv   = CallConv::get(symbolFunc.callConvKind());

        for (Symbol* sym : nodeView.symList)
        {
            SymbolVariable* symVar = sym ? sym->safeCast<SymbolVariable>() : nullptr;
            if (!symVar)
                continue;

            const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar->typeRef(), ABITypeNormalize::Usage::Argument);
            CodeGenNodePayload                     symbolPayload;
            symbolPayload.reg         = normalizedParam.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
            symbolPayload.typeRef     = symVar->typeRef();
            symbolPayload.storageKind = CodeGenNodePayload::StorageKind::Value;

            lowerParameterPayload(codeGen, symbolFunc, *symVar, symbolPayload);
            codeGen.setVariablePayload(symVar, symbolPayload);
        }

        return Result::Continue;
    }

    if (nodeView.symList.size() == 1)
    {
        SymbolVariable* symVar = nodeView.symList.front()->safeCast<SymbolVariable>();
        if (symVar)
            bindSingleVariableFromInitializer(codeGen, *symVar, nodeInitRef);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
