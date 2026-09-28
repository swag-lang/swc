#pragma once
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenBinaryValueCall
{
    struct CallInfo
    {
        CallConvKind    callConvKind;
        const CallConv* callConv;
    };

    inline CallInfo emit(CodeGen& codeGen, SymbolFunction& function, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload)
    {
        const CallConvKind callConvKind = function.callConvKind();
        const CallConv&    callConv     = CallConv::get(callConvKind);
        const auto&       params       = function.parameters();
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(2);

        SWC_ASSERT(params.size() >= 2);
        SWC_ASSERT(params[0] != nullptr);
        SWC_ASSERT(params[1] != nullptr);
        CodeGenCallHelpers::appendPreparedValueArg(preparedArgs, codeGen, callConv, leftPayload, params[0]->typeRef());
        CodeGenCallHelpers::appendPreparedValueArg(preparedArgs, codeGen, callConv, rightPayload, params[1]->typeRef());

        CodeGenCallHelpers::isolatePreparedRegisterArgSources(codeGen, callConv, preparedArgs);

        MicroBuilder&               builder      = codeGen.builder();
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        if (function.isForeign())
            ABICall::callExtern(builder, callConvKind, &function, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &function, preparedCall);

        return {callConvKind, &callConv};
    }
}

SWC_END_NAMESPACE();
