#pragma once
#include "Support/Core/SmallVector.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

class DiagnosticBuilder
{
public:
    DiagnosticBuilder(const TaskContext& ctx, const Diagnostic& diag);
    Utf8 build();
    Utf8 formatMessage(const DiagnosticElement& element) const;

private:
    struct Part
    {
        std::optional<DiagnosticSeverity> tag;
        std::string                       text;
    };

    const TaskContext* ctx_;
    const Diagnostic*  diag_;
    Utf8               out_;

    static SmallVector<std::string_view> splitMessage(std::string_view msg);
    static SmallVector<Part>             parseParts(std::string_view msg);

    void writeMessage(std::string_view msg);
    void writeLocation(const DiagnosticElement& el);
    void writeSpans(const DiagnosticElement& el);
    void writeElement(const DiagnosticElement& el);

    std::string_view resolveMessageTemplate(DiagnosticId id, const DiagnosticElement* el) const;
    uint32_t         countReplacedArgs(std::string_view msg, const DiagnosticElement* el) const;
    static uint32_t  countMessagePlaceholders(std::string_view msg);
    Utf8             buildMessage(const Utf8& msg, const DiagnosticElement* el = nullptr) const;
    void             replaceArgsInString(Utf8& result, const DiagnosticArguments& arguments, const SmallVector<TypeRef>& qualifiedTypes) const;
    void             collectQualifiedTypes(SmallVector<TypeRef>& qualifiedTypes, const DiagnosticElement* el) const;
    static void      collectUniqueArgNames(std::vector<std::string_view>& argNames, const DiagnosticArguments& args);
    Utf8             argumentToString(const DiagnosticArgument& arg, bool qualified = false) const;
    void             expandMessageParts(SmallVector<std::unique_ptr<DiagnosticElement>>& elements) const;
};

SWC_END_NAMESPACE();
