#pragma once
#include "Lexer/Lexer.h"
#include "Parser/Parser.h"
#include "Report/UnitTest.h"

SWC_BEGIN_NAMESPACE()

class TaskContext;
class Global;

enum class FileFlagsE : uint32_t
{
    Zero        = 0,
    HasErrors   = 1 << 0,
    HasWarnings = 1 << 1,
    LexOnly     = 1 << 2,
};
using FileFlags = EnumFlags<FileFlagsE>;

class SourceFile
{
    // Number of '\0' forced at the end of the file
    static constexpr int TRAILING_0 = 4;

    FileRef              ref_ = FileRef::invalid();
    fs::path             path_;
    std::vector<uint8_t> content_;
    UnitTest             unittest_{this};
    FileFlags            flags_ = FileFlagsE::Zero;

protected:
    friend class Lexer;
    friend class Parser;
    LexerOutput  lexOut_;
    ParserOutput parserOut_;

public:
    explicit SourceFile(fs::path path);

    fs::path                    path() const { return path_; }
    const std::vector<uint8_t>& content() const { return content_; }
    size_t                      size() const { return content_.size() - TRAILING_0; }
    FileRef                     ref() const { return ref_; }

    const LexerOutput&  lexOut() const { return lexOut_; }
    const ParserOutput& parserOut() const { return parserOut_; }
    UnitTest&           unittest() { return unittest_; }
    const UnitTest&     unittest() const { return unittest_; }

    FileFlags&       flags() { return flags_; }
    const FileFlags& flags() const { return flags_; }
    void             setHasError() { flags_.add(FileFlagsE::HasErrors); }
    void             setHasWarning() { flags_.add(FileFlagsE::HasWarnings); }
    bool             hasErrors() const { return flags_.has(FileFlagsE::HasErrors); }
    bool             hasWarnings() const { return flags_.has(FileFlagsE::HasWarnings); }
    bool             hasFlag(FileFlags flag) const { return flags_.has(flag); }
    void             addFlag(FileFlags flag) { flags_.add(flag); }

    Result           loadContent(const TaskContext& ctx);
    Utf8             codeLine(const TaskContext& ctx, uint32_t line) const;
    std::string_view codeView(uint32_t offset, uint32_t len) const;
};

SWC_END_NAMESPACE()
