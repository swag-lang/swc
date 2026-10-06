#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenReferenceHelpers
{
    // Return the final type already read while unwrapping the payload.
    inline const TypeInfo* unwrapAliasRefPayload(CodeGen& codeGen, CodeGenNodePayload& ioPayload, TypeRef& ioTypeRef)
    {
        while (ioTypeRef.isValid())
        {
            const TypeInfo* typeInfo = &codeGen.typeMgr().get(ioTypeRef);
            if (const TypeInfo* unwrappedType = typeInfo->unwrapAliasType(codeGen.ctx()))
            {
                ioTypeRef = unwrappedType->typeRef();
                typeInfo  = unwrappedType;
            }

            if (!typeInfo->isReference())
                return typeInfo;

            ioTypeRef         = typeInfo->payloadTypeRef();
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
        return nullptr;
    }
}

SWC_END_NAMESPACE();
