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

Result CodeGenInterfaceHelpers::loadInterfaceMethodTableAddress(MicroReg& outReg, CodeGen& codeGen, const InterfaceCastInfo& castInfo)
{
    SWC_ASSERT(castInfo.implSym != nullptr);
    ConstantRef tableCstRef = ConstantRef::invalid();
    SWC_RESULT(castInfo.implSym->ensureInterfaceMethodTable(codeGen.sema(), tableCstRef));
    SWC_ASSERT(tableCstRef.isValid());

    if (const SymbolInterface* interfaceSym = castInfo.implSym->symInterface())
    {
        for (const SymbolFunction* interfaceMethod : interfaceSym->functions())
        {
            SWC_ASSERT(interfaceMethod != nullptr);
            const SymbolFunction* implMethod = castInfo.implSym->resolveInterfaceMethodTarget(*interfaceMethod);
            SWC_ASSERT(implMethod != nullptr);
            codeGen.function().addCallDependency(const_cast<SymbolFunction*>(implMethod));
        }
    }

    const ConstantValue& tableCst = codeGen.cstMgr().get(tableCstRef);
    SWC_ASSERT(tableCst.isArray());
    outReg = codeGen.nextVirtualIntRegister();
    codeGen.builder().emitLoadRegPtrReloc(outReg, reinterpret_cast<uint64_t>(tableCst.getArray().data()), tableCstRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
