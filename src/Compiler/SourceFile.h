#pragma once

SWC_BEGIN_NAMESPACE();

class NodePayload;
class SymbolNamespace;
class Ast;
class TaskContext;
class Global;
class Verify;

enum class FileFlagsE : uint32_t
{
    Zero        = 0,
    CustomSrc   = 1 << 0,
    ModuleSrc   = 1 << 1,
    Module      = 1 << 2,
    Runtime     = 1 << 3,
    SkipFmt     = 1 << 4,
    ImportedApi = 1 << 5,
};
using FileFlags = EnumFlags<FileFlagsE>;

class SourceFile;
using FileRef = StrongRef<SourceFile>;

class SourceFile
{
public:
    explicit SourceFile(FileRef fileRef, fs::path path, FileFlags flags);
    ~SourceFile();

    FileRef ref() const { return fileRef_; }

    fs::path                    path() const { return path_; }
    Utf8                        name() const { return path_.filename().string().c_str(); }
    const Utf8&                 formattedFileName(const TaskContext* ctx) const;
    Utf8                        formatFileLocation(const TaskContext* ctx, uint32_t line, uint32_t column = 0, uint32_t columnEnd = 0) const;
    size_t                      size() const { return content_.empty() ? 0 : content_.size() - TRAILING_0; }
    const std::vector<char8_t>& content() const { return content_; }
    std::string_view            sourceView() const { return std::string_view(reinterpret_cast<std::string_view::const_pointer>(content_.data()), size()); }

    FileFlags&       flags() { return flags_; }
    const FileFlags& flags() const { return flags_; }
    bool             hasFlag(FileFlags flag) const { return flags_.has(flag); }
    void             addFlag(FileFlags flag) { flags_.add(flag); }
    bool             isRuntime() const { return (flags_.has(FileFlagsE::Runtime)); }
    bool             isImportedApi() const { return flags_.has(FileFlagsE::ImportedApi); }
    bool             mustSkipFormat() const { return flags_.has(FileFlagsE::SkipFmt); }
    void             setMustSkipFormat() { flags_.add(FileFlagsE::SkipFmt); }

    NodePayload&           nodePayloadContext() { return *nodePayloadContext_; }
    const NodePayload&     nodePayloadContext() const { return *nodePayloadContext_; }
    Ast&                   ast();
    const Ast&             ast() const;
    void                   setModuleNamespace(SymbolNamespace& ns) const;
    const SymbolNamespace* moduleNamespace() const;
    void                   setFileNamespace(SymbolNamespace& ns) const;
    const SymbolNamespace* fileNamespace() const;
    Verify&                unitTest() { return *unitTest_; }
    const Verify&          unitTest() const { return *unitTest_; }

    void setHasError() { hasError_ = true; }
    bool hasError() const { return hasError_; }
    void addErrorLineRange(uint32_t lineStart, uint32_t lineEnd) const;
    bool hasErrorLineInRange(uint32_t lineStart, uint32_t lineEnd) const;
    void setHasWarning() { hasWarning_ = true; }
    bool hasWarning() const { return hasWarning_; }

    void   setContent(std::string_view content);
    Result loadContent(TaskContext& ctx);

private:
    void ensureSourceView(TaskContext& ctx);

    static constexpr int TRAILING_0 = 4;

    FileRef   fileRef_ = FileRef::invalid();
    fs::path  path_;
    FileFlags flags_ = FileFlagsE::Zero;

    std::array<Utf8, 3>         formattedFileNames_;
    std::vector<char8_t>         content_;
    std::unique_ptr<NodePayload> nodePayloadContext_;
    std::unique_ptr<Verify>      unitTest_;

    mutable std::mutex                                 errorLinesMutex_;
    mutable std::vector<std::pair<uint32_t, uint32_t>> errorLineRanges_;

    bool hasError_   = false;
    bool hasWarning_ = false;
};

SWC_END_NAMESPACE();
