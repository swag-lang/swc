#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"

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
        const std::vector<SymbolVariable*>&    params        = symbolFunc.parameters();
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
        const MicroOpBits                      opBits          = parameterLoadBits(normalizedParam);
        const uint32_t                         numRegArgs      = callConv.numArgRegisterSlots();
        MicroBuilder&                          builder         = codeGen.builder();

        if (slotIndex < numRegArgs)
        {
            if (normalizedParam.isFloat)
            {
                SWC_ASSERT(slotIndex < callConv.floatArgRegs.size());
                builder.emitLoadRegReg(outPayload.reg, callConv.floatArgRegs[slotIndex], opBits);
            }
            else
            {
                SWC_ASSERT(slotIndex < callConv.intArgRegs.size());
                builder.emitLoadRegReg(outPayload.reg, callConv.intArgRegs[slotIndex], opBits);
            }
        }
        else
        {
            const uint64_t stackOffset = ABICall::incomingArgStackOffset(callConv, slotIndex);
            builder.emitLoadRegMem(outPayload.reg, callConv.stackPointer, stackOffset, opBits);
        }

        if (normalizedParam.isIndirect)
            CodeGen::setPayloadAddress(outPayload);
        else
            CodeGen::setPayloadValue(outPayload);
    }

    void materializeParameterVariablePayload(CodeGenNodePayload& outPayload, CodeGen& codeGen, const SymbolFunction& symbolFunc, const SymbolVariable& symVar)
    {
        const CallConv&                        callConv        = CallConv::get(symbolFunc.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedParam = ABITypeNormalize::normalize(codeGen.ctx(), callConv, symVar.typeRef(), ABITypeNormalize::Usage::Argument);
        outPayload.reg                                         = normalizedParam.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
        outPayload.typeRef                                     = symVar.typeRef();
        lowerParameterPayload(codeGen, symbolFunc, symVar, outPayload);
    }

    bool resolveIdentifierVariablePayload(CodeGenNodePayload& outPayload, CodeGen& codeGen, const SymbolVariable& symVar)
    {
        const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar);
        if (!symbolPayload && symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const SymbolFunction& symbolFunc = codeGen.function();
            CodeGenNodePayload    paramPayload;
            materializeParameterVariablePayload(paramPayload, codeGen, symbolFunc, symVar);
            codeGen.setVariablePayload(symVar, paramPayload);
            symbolPayload = codeGen.variablePayload(symVar);
        }

        if (!symbolPayload)
            return false;

        outPayload = *symbolPayload;
        return true;
    }

    Result codeGenIdentifierVariable(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        CodeGenNodePayload symbolPayload;
        if (!resolveIdentifierVariablePayload(symbolPayload, codeGen, symVar))
            return Result::Continue;

        CodeGenNodePayload& payload = codeGen.setPayload(codeGen.curNodeRef(), symVar.typeRef());
        payload.reg                 = symbolPayload.reg;
        payload.storageKind         = symbolPayload.storageKind;
        return Result::Continue;
    }

    Result codeGenIdentifierFromSymbol(CodeGen& codeGen, const Symbol& symbol)
    {
        switch (symbol.kind())
        {
            case SymbolKind::Variable:
                return codeGenIdentifierVariable(codeGen, symbol.cast<SymbolVariable>());

            default:
                return Result::Continue;
        }
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
        codeGen.setVariablePayload(symVar, symbolPayload);
    }
}

Result AstIdentifier::codeGenPostNode(CodeGen& codeGen)
{
    const SemaNodeView nodeView = codeGen.curNodeView();
    SWC_ASSERT(nodeView.sym);
    return codeGenIdentifierFromSymbol(codeGen, *nodeView.sym);
}

Result AstSingleVarDecl::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView nodeView = codeGen.curNodeView();
    SWC_ASSERT(nodeView.sym);
    const SymbolVariable& symVar = nodeView.sym->cast<SymbolVariable>();

    if (hasFlag(AstVarDeclFlagsE::Parameter))
    {
        const SymbolFunction& symbolFunc = codeGen.function();
        CodeGenNodePayload    symbolPayload;
        materializeParameterVariablePayload(symbolPayload, codeGen, symbolFunc, symVar);
        codeGen.setVariablePayload(symVar, symbolPayload);
        return Result::Continue;
    }

    bindSingleVariableFromInitializer(codeGen, symVar, nodeInitRef);
    return Result::Continue;
}

Result AstMultiVarDecl::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView nodeView = codeGen.curNodeView();
    SWC_ASSERT(!nodeView.symList.empty());

    if (hasFlag(AstVarDeclFlagsE::Parameter))
    {
        const SymbolFunction& symbolFunc = codeGen.function();

        for (Symbol* sym : nodeView.symList)
        {
            const SymbolVariable& symVar = sym->cast<SymbolVariable>();

            CodeGenNodePayload symbolPayload;
            materializeParameterVariablePayload(symbolPayload, codeGen, symbolFunc, symVar);
            codeGen.setVariablePayload(symVar, symbolPayload);
        }

        return Result::Continue;
    }

    if (nodeView.symList.size() == 1)
    {
        const SymbolVariable& symVar = nodeView.symList.front()->cast<SymbolVariable>();
        bindSingleVariableFromInitializer(codeGen, symVar, nodeInitRef);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
