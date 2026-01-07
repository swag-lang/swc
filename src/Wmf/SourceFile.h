#pragma once

SWC_BEGIN_NAMESPACE();

class SemaInfo;
class Ast;
class TaskContext;
class Global;
class Verify;

enum class FileFlagsE : uint32_t
{
    Zero = 0,
    CustomSrc,
    ModuleSrc,
    Module,
    Runtime
};
using FileFlags = EnumFlags<FileFlagsE>;

class SourceFile;
using FileRef = StrongRef<SourceFile>;

class SourceFile
{
public:
    explicit SourceFile(FileRef fileRef, fs::path path, FileFlags flags);
    ~SourceFile();

    FileRef                     ref() const { return fileRef_; }
    fs::path                    path() const { return path_; }
    Utf8                        name() const { return path_.filename().string().c_str(); }
    const std::vector<char8_t>& content() const { return content_; }
    std::string_view            sourceView() const { return std::string_view(reinterpret_cast<std::string_view::const_pointer>(content_.data()), size()); }

    size_t           size() const { return content_.size() - TRAILING_0; }
    SemaInfo&        semaInfo() { return *semaInfo_; }
    const SemaInfo&  semaInfo() const { return *semaInfo_; }
    FileFlags&       flags() { return flags_; }
    const FileFlags& flags() const { return flags_; }
    bool             hasFlag(FileFlags flag) const { return flags_.has(flag); }
    void             addFlag(FileFlags flag) { flags_.add(flag); }
    Verify&          unitTest() { return *unitTest_; }
    const Verify&    unitTest() const { return *unitTest_; }
    Ast&             ast();
    const Ast&       ast() const;
    bool             isRuntime() const { return (flags_.has(FileFlagsE::Runtime)); }

    void setHasError() { hasError_ = true; }
    void setHasWarning() { hasWarning_ = true; }
    bool hasError() const { return hasError_; }
    bool hasWarning() const { return hasWarning_; }

    Result loadContent(TaskContext& ctx);

private:
    static constexpr int      TRAILING_0 = 4; // Number of '\0' forced at the end of the file
    FileRef                   fileRef_   = FileRef::invalid();
    fs::path                  path_;
    std::vector<char8_t>      content_;
    FileFlags                 flags_ = FileFlagsE::Zero;
    std::unique_ptr<SemaInfo> semaInfo_;
    std::unique_ptr<Verify>   unitTest_;
    bool                      hasError_   = false;
    bool                      hasWarning_ = false;
};

SWC_END_NAMESPACE();
