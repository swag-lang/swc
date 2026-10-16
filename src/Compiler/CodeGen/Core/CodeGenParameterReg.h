#pragma once
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenParameterReg
{
    struct RegisterParameterPayload
    {
        const SymbolVariable*                         symVar    = nullptr;
        CodeGenNodePayload                            payload   = {};
        CodeGenFunctionHelpers::FunctionParameterInfo paramInfo = {};
    };

    inline MicroReg parameterSourcePhysReg(const CallConv& callConv, const CodeGenFunctionHelpers::FunctionParameterInfo& paramInfo)
    {
        if (paramInfo.isFloat)
        {
            SWC_ASSERT(paramInfo.registerIndex < callConv.floatArgRegs.size());
            return callConv.floatArgRegs[paramInfo.registerIndex];
        }

        SWC_ASSERT(paramInfo.registerIndex < callConv.intArgRegs.size());
        return callConv.intArgRegs[paramInfo.registerIndex];
    }

    inline void appendRegisterParameterIndices(SmallVector<uint32_t>& outIndices, const std::vector<SymbolVariable*>& params, std::span<const CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos)
    {
        SWC_ASSERT(paramInfos.size() == params.size());
        // Register parameters fit the inline buffer for the supported conventions.
        // Reserving for every parameter would also allocate for the stack-only tail.
        for (size_t i = 0; i < params.size(); ++i)
        {
            SWC_ASSERT(params[i] != nullptr);
            if (paramInfos[i].isRegisterArg)
                outIndices.push_back(static_cast<uint32_t>(i));
        }
    }

    inline void collectRegisterParameterIndices(SmallVector<uint32_t>& outIndices, const std::vector<SymbolVariable*>& params, std::span<const CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos)
    {
        outIndices.clear();
        appendRegisterParameterIndices(outIndices, params, paramInfos);
    }

    inline void collectFutureSourceRegs(SmallVector<MicroReg>& outRegs, const CallConv& callConv, std::span<const CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos, std::span<const uint32_t> registerParamIndices, size_t currentIndex, bool currentIsFloat)
    {
        outRegs.reserve(registerParamIndices.size() - currentIndex - 1);
        for (size_t j = currentIndex + 1; j < registerParamIndices.size(); ++j)
        {
            const uint32_t laterParamIndex = registerParamIndices[j];
            const auto&    laterParamInfo  = paramInfos[laterParamIndex];
            if (laterParamInfo.isFloat != currentIsFloat)
                continue;

            outRegs.push_back(parameterSourcePhysReg(callConv, laterParamInfo));
        }
    }

    inline void bindRegisterParameter(CodeGen& codeGen, MicroBuilder& builder, const SymbolFunction& symbolFunc, const SymbolVariable& symVar, const CodeGenFunctionHelpers::FunctionParameterInfo& paramInfo, CodeGenNodePayload& symbolPayload, const SmallVector<MicroReg>& futureSourceRegs, SmallVector<RegisterParameterPayload>& registerPayloads)
    {
        builder.addVirtualRegForbiddenPhysRegs(symbolPayload.reg, futureSourceRegs.span());
        if (!futureSourceRegs.empty())
            builder.preserveVirtualCopy(symbolPayload.reg);
        CodeGenFunctionHelpers::emitLoadFunctionParameterToReg(codeGen, symbolFunc, paramInfo, symbolPayload.reg);
        CodeGenFunctionHelpers::markImmutableIndirectParameter(codeGen, symVar, paramInfo, symbolPayload.reg);
        symbolPayload.setValueOrAddress(paramInfo.isIndirect);
        codeGen.setVariablePayload(symVar, symbolPayload);

        if (futureSourceRegs.empty())
            return;

        RegisterParameterPayload registerPayload;
        registerPayload.symVar    = &symVar;
        registerPayload.payload   = symbolPayload;
        registerPayload.paramInfo = paramInfo;
        registerPayloads.push_back(registerPayload);
    }

    inline void rebindRegisterParameters(CodeGen& codeGen, MicroBuilder& builder, std::span<const RegisterParameterPayload> registerPayloads)
    {
        for (const auto& registerPayload : registerPayloads)
        {
            CodeGenNodePayload reboundPayload = registerPayload.payload;
            reboundPayload.reg                = registerPayload.paramInfo.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(reboundPayload.reg, registerPayload.payload.reg, registerPayload.paramInfo.opBits);
            CodeGenFunctionHelpers::markImmutableIndirectParameter(codeGen, *registerPayload.symVar, registerPayload.paramInfo, reboundPayload.reg);
            codeGen.setVariablePayload(*registerPayload.symVar, reboundPayload);
        }
    }

    // Loads every register parameter into a fresh virtual register, keeping each one off the
    // physical registers the later parameters still arrive in, then rebinds them.
    inline void materializeRegisterParameters(CodeGen& codeGen, const SymbolFunction& symbolFunc, std::span<const CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos)
    {
        const std::vector<SymbolVariable*>& params = symbolFunc.parameters();
        SWC_ASSERT(paramInfos.size() == params.size());
        if (params.empty())
            return;

        const CallConv& callConv = CallConv::get(symbolFunc.callConvKind());
        MicroBuilder&   builder  = codeGen.builder();

        SmallVector<uint32_t> registerParamIndices;
        appendRegisterParameterIndices(registerParamIndices, params, paramInfos);
        SmallVector<RegisterParameterPayload> registerPayloads;
        registerPayloads.reserve(registerParamIndices.size());

        for (size_t i = 0; i < registerParamIndices.size(); ++i)
        {
            const uint32_t paramIndex = registerParamIndices[i];
            const auto*    symVar     = params[paramIndex];
            SWC_ASSERT(symVar != nullptr);
            const auto& paramInfo = paramInfos[paramIndex];

            SmallVector<MicroReg> futureSourceRegs;
            collectFutureSourceRegs(futureSourceRegs, callConv, paramInfos, registerParamIndices.span(), i, paramInfo.isFloat);

            CodeGenNodePayload symbolPayload;
            symbolPayload.reg     = paramInfo.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
            symbolPayload.typeRef = symVar->typeRef();
            bindRegisterParameter(codeGen, builder, symbolFunc, *symVar, paramInfo, symbolPayload, futureSourceRegs, registerPayloads);
        }

        rebindRegisterParameters(codeGen, builder, registerPayloads.span());
    }
}

SWC_END_NAMESPACE();
