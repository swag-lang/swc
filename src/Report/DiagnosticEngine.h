#pragma once
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

class DiagnosticEngine
{
public:
    static Utf8 build(const Context& ctx, const Diagnostic& diag);
};

SWC_END_NAMESPACE()
