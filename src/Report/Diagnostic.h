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

    DiagnosticElement* last() const { return elements_.empty() ? nullptr : elements_.back().get(); }

    static Diagnostic error(DiagnosticId id, SourceFile* fileOwner = nullptr)
    {
        Diagnostic diag(fileOwner);
        diag.addError(id);
        return diag;
    }

    static void reportError(CompilerContext& ctx, DiagnosticId id)
    {
        const auto diag = error(id);
        diag.report(ctx);
    }
};
