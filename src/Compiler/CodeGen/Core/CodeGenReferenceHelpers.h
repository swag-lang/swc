#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenReferenceHelpers
{
    inline void unwrapAliasRefPayload(CodeGen& codeGen, CodeGenNodePayload& ioPayload, TypeRef& ioTypeRef)
    {
        while (ioTypeRef.isValid())
        {
            const TypeInfo& typeInfo  = codeGen.typeMgr().get(ioTypeRef);
            const TypeRef   unwrapped = typeInfo.unwrap(codeGen.ctx(), TypeRef::invalid(), TypeExpandE::Alias);
            if (unwrapped.isValid())
            {
                ioTypeRef = unwrapped;
                continue;
            }

            if (!typeInfo.isReference())
                break;

            ioTypeRef         = typeInfo.payloadTypeRef();
            ioPayload.typeRef = ioTypeRef;
            if (ioPayload.isValue())
            {
                ioPayload.setIsAddress();
                continue;
            }

            const MicroReg referenceSlotReg = ioPayload.reg;
            ioPayload.reg                   = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegMem(ioPayload.reg, referenceSlotReg, 0, MicroOpBits::B64);
            ioPayload.setIsAddress();
        }
    }
}

SWC_END_NAMESPACE();
