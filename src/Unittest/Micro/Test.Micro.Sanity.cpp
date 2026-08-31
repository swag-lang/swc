#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.Sanity.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class ReturnAddressKind
    {
        Stack,
        NonStack,
    };

    Result runStackEscapeSanity(TaskContext& ctx, TypeRef returnTypeRef, ReturnAddressKind addressKind)
    {
        SymbolFunction function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        function.setReturnTypeRef(returnTypeRef);

        const CallConv& callConv  = CallConv::get(CallConvKind::Swag);
        const MicroReg  stackBase = MicroReg::virtualIntReg(1);
        MicroBuilder    builder(ctx);

        if (addressKind == ReturnAddressKind::Stack)
            builder.emitLoadAddressRegMem(callConv.intReturn, stackBase, 16, MicroOpBits::B64);
        else
            builder.emitLoadRegImm(callConv.intReturn, ApInt(1, 64), MicroOpBits::B64);
        builder.emitRet();

        MicroSanityPass  pass;
        MicroPassManager passManager;
        passManager.addPreRaAnalysisPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind             = CallConvKind::Swag;
        passContext.debugStackBaseVirtualReg = stackBase;
        passContext.sanitizerFunction        = &function;
        passContext.sanitizerSafetyMask      = static_cast<uint16_t>(Runtime::SafetyWhat::Memory);
        return builder.runPasses(passManager, nullptr, passContext);
    }
}

SWC_TEST_BEGIN(MicroSanity_RejectsStackAddressReturnedAsPointer)
{
    if (runStackEscapeSanity(ctx, ctx.typeMgr().typeValuePtrU8(), ReturnAddressKind::Stack) != Result::Error)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSanity_AllowsKnownNonStackPointer)
{
    SWC_RESULT(runStackEscapeSanity(ctx, ctx.typeMgr().typeValuePtrU8(), ReturnAddressKind::NonStack));
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroSanity_IgnoresStackAddressReturnedAsInteger)
{
    SWC_RESULT(runStackEscapeSanity(ctx, ctx.typeMgr().typeU64(), ReturnAddressKind::Stack));
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
