#pragma once
#include "Support/Core/Utf8.h"
#include "Support/Report/DiagnosticTypes.h"

SWC_BEGIN_NAMESPACE();

struct DiagnosticSpan
{
    uint32_t           offset    = 0;
    uint32_t           len       = 0;
    DiagnosticSeverity severity  = DiagnosticSeverity::Zero;
    DiagnosticId       messageId = DiagnosticId::None;
    Utf8               message;
};

SWC_END_NAMESPACE();
