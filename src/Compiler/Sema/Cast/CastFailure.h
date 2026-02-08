#pragma once
#include "Support/Report/DiagnosticElement.h"

SWC_BEGIN_NAMESPACE();

class Diagnostic;

struct CastFailure
{
    DiagnosticId        diagId     = DiagnosticId::None;
    DiagnosticId        noteId     = DiagnosticId::None;
    AstNodeRef          nodeRef    = AstNodeRef::invalid();
    SourceCodeRef       codeRef    = SourceCodeRef::invalid();
    TypeRef             srcTypeRef = TypeRef::invalid();
    TypeRef             dstTypeRef = TypeRef::invalid();
    TypeRef             optTypeRef = TypeRef::invalid();
    Utf8                valueStr{};
    DiagnosticArguments arguments{};

    void set(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note);

    template<typename T>
    void addArgument(std::string_view name, T&& arg)
    {
        for (auto& a : arguments)
        {
            if (a.name == name)
            {
                a.val = std::forward<T>(arg);
                return;
            }
        }
        arguments.emplace_back(DiagnosticArgument{name, std::forward<T>(arg)});
    }

    bool hasArgument(std::string_view name) const;
    void applyArguments(Diagnostic& diag) const;
    void applyArguments(DiagnosticElement& element) const;
};

SWC_END_NAMESPACE();
