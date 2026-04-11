#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolImpl;
class SymbolInterface;
class SymbolStruct;
class SymbolVariable;

namespace CodeGenInterfaceHelpers
{
    struct InterfaceCastInfo
    {
        const SymbolStruct*   objectStruct        = nullptr;
        const SymbolImpl*     implSym             = nullptr;
        const SymbolVariable* usingField          = nullptr;
        bool                  usingFieldIsPointer = false;
    };

    bool   resolveInterfaceCastInfo(CodeGen& codeGen, const SymbolStruct& srcStruct, const SymbolInterface& dstItf, InterfaceCastInfo& outInfo);
    Result loadInterfaceMethodTableAddress(MicroReg& outReg, CodeGen& codeGen, const InterfaceCastInfo& castInfo);
}

SWC_END_NAMESPACE();
