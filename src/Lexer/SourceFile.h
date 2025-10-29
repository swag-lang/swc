﻿#pragma once
#include "Core/Types.h"
#include "Lexer/Lexer.h"
#include "Parser/Parser.h"
#include "Report/UnitTest.h"

SWC_BEGIN_NAMESPACE()

class Context;
class Global;

enum class FileFlags : uint32_t
{
    Zero        = 0,
    HasErrors   = 1 << 0,
    HasWarnings = 1 << 1,
    LexOnly     = 1 << 2,
};
SWC_ENABLE_BITMASK(FileFlags);

class SourceFile
{
    // Number of '\0' forced at the end of the file
    static constexpr int TRAILING_0 = 4;

    FileRef              ref_ = INVALID_REF;
    fs::path             path_;
    std::vector<uint8_t> content_;
    UnitTest             unittest_{this};
    FileFlags            flags_ = FileFlags::Zero;

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
    void             setHasError() { flags_ |= FileFlags::HasErrors; }
    void             setHasWarning() { flags_ |= FileFlags::HasWarnings; }
    bool             hasErrors() const { return has_any(flags_, FileFlags::HasErrors); }
    bool             hasWarnings() const { return has_any(flags_, FileFlags::HasWarnings); }
    bool             hasFlag(FileFlags flag) const { return has_any(flags_, flag); }
    void             addFlag(FileFlags flag) { flags_ |= flag; }

    Result           loadContent(const Context& ctx);
    Utf8             codeLine(const Context& ctx, uint32_t line) const;
    std::string_view codeView(uint32_t offset, uint32_t len) const;
};

SWC_END_NAMESPACE()
