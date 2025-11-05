#pragma once

SWC_BEGIN_NAMESPACE()

enum class DiagnosticSeverity
{
    Zero,
    Error,
    Warning,
    Note,
    Help,
};

enum class DiagnosticId
{
    None = 0,
#define SWC_DIAG_DEF(id) id,
#include "Report/Diagnostic_Errors_.def"

#include "Report/Diagnostic_Notes_.def"

#undef SWC_DIAG_DEF
    Count,
};

struct DiagnosticSpan
{
    uint32_t           offset    = 0;
    uint32_t           len       = 0;
    DiagnosticSeverity severity  = DiagnosticSeverity::Zero;
    DiagnosticId       messageId = DiagnosticId::None;
    Utf8               message;
};

SWC_END_NAMESPACE()
