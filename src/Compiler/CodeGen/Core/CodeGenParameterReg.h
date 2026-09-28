#pragma once
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenParameterReg
{
    struct RegisterParameterPayload
    {
        const SymbolVariable*                         symVar      = nullptr;
        CodeGenNodePayload                            payload     = {};
        CodeGenFunctionHelpers::FunctionParameterInfo paramInfo   = {};
        bool                                          needsRebind = false;
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

    inline void collectRegisterParameterIndices(SmallVector<uint32_t>& outIndices, const std::vector<SymbolVariable*>& params, std::span<const CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos)
    {
        SWC_ASSERT(paramInfos.size() == params.size());
        outIndices.clear();
        outIndices.reserve(params.size());
        for (size_t i = 0; i < params.size(); ++i)
        {
            SWC_ASSERT(params[i] != nullptr);
            if (paramInfos[i].isRegisterArg)
                outIndices.push_back(static_cast<uint32_t>(i));
        }
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

    inline void rebindRegisterParameters(CodeGen& codeGen, MicroBuilder& builder, std::span<const RegisterParameterPayload> registerPayloads)
    {
        for (const auto& registerPayload : registerPayloads)
        {
            if (!registerPayload.needsRebind)
                continue;

            CodeGenNodePayload reboundPayload = registerPayload.payload;
            reboundPayload.reg                = registerPayload.paramInfo.isFloat ? codeGen.nextVirtualFloatRegister() : codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(reboundPayload.reg, registerPayload.payload.reg, registerPayload.paramInfo.opBits);
            codeGen.setVariablePayload(*registerPayload.symVar, reboundPayload);
        }
    }
}

SWC_END_NAMESPACE();
