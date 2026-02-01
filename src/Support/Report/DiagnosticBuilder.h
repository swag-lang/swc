#pragma once
#include "Support/Core/SmallVector.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

class DiagnosticBuilder
{
public:
    DiagnosticBuilder(const TaskContext& ctx, const Diagnostic& diag);
    Utf8 build();

private:
    enum class DiagPart : uint8_t
    {
        FileLocationArrow,
        FileLocationPath,
        FileLocationSep,
        GutterBar,
        LineNumber,
        CodeText,
        LabelMsgPrefix,
        LabelMsgText,
        Severity,
        QuoteText,
        Ellipsis,
        Reset,
    };

    struct AnsiSeq
    {
        std::vector<LogColor> seq;
        AnsiSeq(std::initializer_list<LogColor> s) :
            seq(s)
        {
        }
    };

    struct Part
    {
        std::optional<DiagnosticSeverity> tag;
        std::string                       text;
    };

    struct ColSpan
    {
        uint32_t       column;
        uint32_t       length;
        DiagnosticSpan span;
    };

    const TaskContext* ctx_;
    const Diagnostic*  diag_;
    Utf8               out_;
    uint32_t           gutterW_ = 0;

    static SmallVector<std::string_view> splitMessage(std::string_view msg);
    static SmallVector<Part>             parseParts(std::string_view msg);
    static AnsiSeq                       diagPalette(DiagPart p, std::optional<DiagnosticSeverity> sev);

    Utf8 toAnsiSeq(const AnsiSeq& s) const;
    Utf8 partStyle(DiagPart p) const;
    Utf8 partStyle(DiagPart p, DiagnosticSeverity sev) const;

    void writeHighlightedMessage(DiagnosticSeverity sev, std::string_view msg, const Utf8& reset);
    void writeLocation(const DiagnosticElement& el);
    void writeGutter(uint32_t gutter);
    void writeCodeLine(uint32_t lineNo, std::string_view startEllipsis, std::string_view code, std::string_view endEllipsis);
    void writeLabelMsg(const DiagnosticElement& el);
    void writeCodeUnderline(const DiagnosticElement& el, const SmallVector<ColSpan>& underlines);
    void writeCodeTrunc(const DiagnosticElement& elToUse, const SourceCodeLocation& loc, const DiagnosticSpan& span, uint32_t tokenLenChars, const Utf8& currentFullCodeLine, uint32_t currentFullCharCount);
    void writeCodeBlock(const DiagnosticElement& el);

    Utf8 buildMessage(const Utf8& msg, const DiagnosticElement* el = nullptr) const;
    Utf8 argumentToString(const DiagnosticArgument& arg) const;
    void expandMessageParts(SmallVector<std::unique_ptr<DiagnosticElement>>& elements) const;
};

SWC_END_NAMESPACE();
