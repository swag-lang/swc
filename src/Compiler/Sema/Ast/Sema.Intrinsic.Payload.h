#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;
class SymbolFunction;

struct IntrinsicCallCodeGenPayload : CodeGenNodePayload
{
    SymbolVariable* runtimeStorageSym           = nullptr;
    SymbolFunction* runtimeTlsGetValueFunction  = nullptr;
};

SWC_END_NAMESPACE();
