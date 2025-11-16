#pragma once
#include "Parser/Parser.h"
#include "Report/UnitTest.h"

SWC_BEGIN_NAMESPACE()

class TaskContext;
class Global;

enum class FileFlagsE : uint32_t
{
    Zero = 0,
};
using FileFlags = EnumFlags<FileFlagsE>;

class SourceFile
{
    // Number of '\0' forced at the end of the file
    static constexpr int TRAILING_0 = 4;

    FileRef              ref_ = FileRef::invalid();
    fs::path             path_;
    std::vector<char8_t> content_;
    UnitTest             unittest_;
    FileFlags            flags_ = FileFlagsE::Zero;
    Ast                  ast_;

public:
    explicit SourceFile(fs::path path);

    fs::path                    path() const { return path_; }
    const std::vector<char8_t>& content() const { return content_; }
    std::string_view            sourceView() const { return std::string_view(reinterpret_cast<std::string_view::const_pointer>(content_.data()), size()); }

    size_t             size() const { return content_.size() - TRAILING_0; }
    FileRef            ref() const { return ref_; }
    LexerOutput&       lexOut() { return ast_.lexOut(); }
    const LexerOutput& lexOut() const { return ast_.lexOut(); }
    const Ast&         ast() const { return ast_; }
    Ast&               ast() { return ast_; }
    UnitTest&          unittest() { return unittest_; }
    const UnitTest&    unittest() const { return unittest_; }
    FileFlags&         flags() { return flags_; }
    const FileFlags&   flags() const { return flags_; }
    bool               hasFlag(FileFlags flag) const { return flags_.has(flag); }
    void               addFlag(FileFlags flag) { flags_.add(flag); }

    Result loadContent(const TaskContext& ctx);
};

SWC_END_NAMESPACE()
