#pragma once
#include "Core/SmallVector.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

class DiagnosticBuilder
{
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

    const Context*    ctx_;
    const Diagnostic* diag_;
    Utf8              out_;
    uint32_t          gutterW_ = 0;

    static SmallVector<std::string_view> splitMessage(std::string_view msg);
    static SmallVector<Part>             parseParts(std::string_view msg);
    static AnsiSeq                       diagPalette(DiagPart p, std::optional<DiagnosticSeverity> sev);

    Utf8 toAnsiSeq(const AnsiSeq& s) const;
    Utf8 partStyle(DiagPart p) const;
    Utf8 partStyle(DiagPart p, DiagnosticSeverity sev) const;

    void writeHighlightedMessage(DiagnosticSeverity sev, std::string_view msg, const Utf8& reset);
    void writeFileLocation(const std::string& path, uint32_t line, uint32_t col, uint32_t len);
    void writeGutter(uint32_t gutter);
    void writeCodeLine(uint32_t lineNo, std::string_view code);
    void writeLabelMsg(const DiagnosticElement& el);
    void writeCodeUnderline(const DiagnosticElement& el, uint32_t columnOneBased, uint32_t underlineLen);
    void writeCodeBlock(const DiagnosticElement& el);

    Utf8 message(const DiagnosticElement& el) const;
    Utf8 argumentToString(const Diagnostic::Argument& arg) const;
    void expandMessageParts(SmallVector<std::unique_ptr<DiagnosticElement>>& elements) const;

public:
    DiagnosticBuilder(const Context& ctx, const Diagnostic& diag) :
        ctx_(&ctx),
        diag_(&diag)
    {
    }

    Utf8 build();
};

SWC_END_NAMESPACE()
