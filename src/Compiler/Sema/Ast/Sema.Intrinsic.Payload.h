#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"

SWC_BEGIN_NAMESPACE();

class SymbolVariable;

struct IntrinsicCallCodeGenPayload : CodeGenNodePayload
{
    SymbolVariable* runtimeStorageSym = nullptr;
};

SWC_END_NAMESPACE();
