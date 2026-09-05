#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"

SWC_BEGIN_NAMESPACE();

class SymbolMap;

// Written before an instance is published, and retained when the same specialization is reused.
struct GenericInstanceOrigin
{
    SourceCodeRange  codeRange;
    const SymbolMap* caller = nullptr;
};

SWC_END_NAMESPACE();
