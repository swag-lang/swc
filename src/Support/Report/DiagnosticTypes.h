#pragma once

SWC_BEGIN_NAMESPACE();

enum class DiagnosticSeverity
{
    Zero,
    Error,
    Warning,
    Note,
    Help,
};

// How a warning is reported once the policy layers have had their say.
// Must stay in sync with 'Swag.WarningLevel' in "bin/runtime/attributes.swg".
enum class WarningLevel : uint8_t
{
    Disable,
    Warning,
    Error,
};

enum class DiagnosticId
{
    None = 0,
#define SWC_DIAG_DEF(id) id,
#include "Support/Report/Msg/Errors.inc"

#include "Support/Report/Msg/Notes.inc"

#undef SWC_DIAG_DEF
    Count,
};

SWC_END_NAMESPACE();
