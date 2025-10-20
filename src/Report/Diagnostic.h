#pragma once
#include "Report/DiagnosticElement.h"
#include "Report/DiagnosticIds.h"

class CompilerContext;
enum class DiagnosticId;

enum class DiagnosticKind
{
    Error,
    Warning,
    Note,
    Hint,
};

class Logger;

class Diagnostic
{
    std::vector<std::unique_ptr<DiagnosticElement>> elements_;
    SourceFile*                                     fileOwner_ = nullptr;

    Utf8 build(CompilerContext& ctx) const;

public:
    explicit Diagnostic(SourceFile* fileOwner = nullptr) :
        fileOwner_(fileOwner)
    {
    }

    void                                                   report(CompilerContext& ctx) const;
    const std::vector<std::unique_ptr<DiagnosticElement>>& elements() const { return elements_; }
    SourceFile*                                            fileOwner() const { return fileOwner_; }

    DiagnosticElement* addElement(DiagnosticKind kind, DiagnosticId id);
    DiagnosticElement* addError(DiagnosticId id) { return addElement(DiagnosticKind::Error, id); }
};
