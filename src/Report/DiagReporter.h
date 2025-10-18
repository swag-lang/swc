#pragma once

struct Diagnostic;

#define SWAG_DIAG(__id) __id,
enum class DiagnosticId
{
#include "Report/DiagnosticList.h" 
};


struct DiagReporter
{
    static std::unique_ptr<Diagnostic> diagnostic(DiagnosticId id);
};
