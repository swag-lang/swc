#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenInterfaceHelpers.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

bool CodeGenInterfaceHelpers::resolveInterfaceCastInfo(CodeGen& codeGen, const SymbolStruct& srcStruct, const SymbolInterface& dstItf, InterfaceCastInfo& outInfo)
{
    if (srcStruct.isGenericRoot() && !srcStruct.isGenericInstance())
        return false;

    if (const SymbolImpl* implSym = srcStruct.findInterfaceImpl(dstItf.idRef()))
    {
        outInfo.objectStruct = &srcStruct;
        outInfo.implSym      = implSym;
        outInfo.usingField   = nullptr;
        return true;
    }

    for (const SymbolVariable* field : srcStruct.fields())
    {
        SWC_ASSERT(field != nullptr);
        if (!field->isUsingField())
            continue;

        bool                usingFieldIsPointer = false;
        const SymbolStruct* targetStruct        = field->usingTargetStruct(codeGen.ctx(), usingFieldIsPointer);
        if (!targetStruct)
            continue;

        // Interface implementation can come from a `using` field, but the runtime object pointer must
        // still be adjusted to the embedded object before building the interface pair.
        if (const SymbolImpl* implSym = targetStruct->findInterfaceImpl(dstItf.idRef()))
        {
            outInfo.objectStruct        = targetStruct;
            outInfo.implSym             = implSym;
            outInfo.usingField          = field;
            outInfo.usingFieldIsPointer = usingFieldIsPointer;
            return true;
        }
    }

    return false;
}

Result CodeGenInterfaceHelpers::prepareInterfaceMethodTable(ConstantRef& outRef, CodeGen& codeGen, const InterfaceCastInfo& castInfo, bool allowIncomplete)
{
    SWC_ASSERT(castInfo.implSym != nullptr);
    outRef                   = ConstantRef::invalid();
    const Result tableResult = castInfo.implSym->ensureInterfaceMethodTable(codeGen.sema(), outRef);
    if (tableResult != Result::Continue)
    {
        if (allowIncomplete)
            return Result::Continue;
        return tableResult;
    }
    SWC_ASSERT(outRef.isValid());

    if (const SymbolInterface* interfaceSym = castInfo.implSym->symInterface())
    {
        for (const SymbolFunction* interfaceMethod : interfaceSym->functions())
        {
            SWC_ASSERT(interfaceMethod != nullptr);
            const SymbolFunction* implMethod = castInfo.implSym->resolveInterfaceMethodTarget(codeGen.ctx(), *interfaceMethod);
            if (!implMethod)
            {
                if (allowIncomplete)
                {
                    outRef = ConstantRef::invalid();
                    return Result::Continue;
                }

                return Result::Error;
            }

            codeGen.function().addCallDependency(implMethod);
        }
    }

    return Result::Continue;
}

void CodeGenInterfaceHelpers::emitLoadInterfaceMethodTableAddress(MicroReg& outReg, CodeGen& codeGen, const ConstantRef tableCstRef)
{
    SWC_ASSERT(tableCstRef.isValid());
    const ConstantValue& tableCst = codeGen.cstMgr().get(tableCstRef);
    SWC_ASSERT(tableCst.isArray());
    outReg = codeGen.nextVirtualIntRegister();
    codeGen.builder().emitLoadRegPtrReloc(outReg, reinterpret_cast<uint64_t>(tableCst.getArray().data()), tableCstRef);
}

SWC_END_NAMESPACE();
