#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenNodePayload.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenCString
{
    inline MicroReg emitLoadCStringReg(CodeGen& codeGen, const CodeGenNodePayload& payload)
    {
        const MicroReg cstrReg = codeGen.nextVirtualIntRegister();
        if (payload.isAddress())
            codeGen.builder().emitLoadRegMem(cstrReg, payload.reg, 0, MicroOpBits::B64);
        else
            codeGen.builder().emitLoadRegReg(cstrReg, payload.reg, MicroOpBits::B64);
        return cstrReg;
    }
}

SWC_END_NAMESPACE();
