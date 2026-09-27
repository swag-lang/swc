#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Constant/ConstantManager.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenPointerConstant
{
    inline void emitPointerConstant(CodeGen& codeGen, MicroReg reg, const uint64_t value, ConstantRef cstRef)
    {
        if (!value)
        {
            codeGen.builder().emitLoadRegImm(reg, ApInt(0, 64), MicroOpBits::B64);
            return;
        }

        DataSegmentRef sourceRef;
        if (codeGen.cstMgr().resolveConstantDataSegmentRef(sourceRef, cstRef, reinterpret_cast<const void*>(value)))
            codeGen.builder().emitLoadRegPtrReloc(reg, value, cstRef);
        else
            codeGen.builder().emitLoadRegPtrImm(reg, value);
    }
}

SWC_END_NAMESPACE();
