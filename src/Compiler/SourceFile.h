#pragma once

#include "Compiler/SourceContent.h"
#include "Support/Core/Flags.h"
#include "Support/Core/Result.h"
#include "Support/Core/StrongRef.h"
#include "Support/Core/Utf8.h"

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
    // Reached by a '#load' from the module setup file. Such a file states module setup
    // directives of its own, so the setup pass reads them and the regular pass skips them,
    // exactly as it does for the setup file itself.
    SetupLoaded = 1 << 6,
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

    const fs::path&             path() const { return path_; }
    uint64_t                    revisionId() const { return revisionId_; }
    const Utf8&                 pathString() const;
    const Utf8&                 genericPathString() const;
    Utf8                        name() const { return path_.filename().string().c_str(); }
    const Utf8&                 formattedFileName(const TaskContext* ctx) const;
    Utf8                        formatFileLocation(const TaskContext* ctx, uint32_t line, uint32_t column = 0, uint32_t columnEnd = 0) const;
    size_t                      size() const { return content().empty() ? 0 : content().size() - TRAILING_0; }
    const std::vector<char8_t>& content() const { return sharedContent_ ? sharedContent_->bytes() : content_; }
    std::string_view            sourceView() const { return std::string_view(reinterpret_cast<std::string_view::const_pointer>(content().data()), size()); }

    FileFlags&       flags() { return flags_; }
    const FileFlags& flags() const { return flags_; }
    bool             hasFlag(FileFlags flag) const { return flags_.has(flag); }
    void             addFlag(FileFlags flag) { flags_.add(flag); }
    bool             isEditorActive() const { return editorActive_; }
    void             setEditorActive(bool active) { editorActive_ = active; }
    bool             isRuntime() const { return (flags_.has(FileFlagsE::Runtime)); }
    bool             isImportedApi() const { return flags_.has(FileFlagsE::ImportedApi); }
    bool             mustSkipFormat() const { return flags_.has(FileFlagsE::SkipFmt); }
    void             setMustSkipFormat() { flags_.add(FileFlagsE::SkipFmt); }

    // The module a generated public API file describes. It is what a 'Swag.Foreign' that
    // names no module resolves to, so every entry of a module API can leave it out.
    const Utf8& apiModuleName() const { return apiModuleName_; }
    void        setApiModuleName(const std::string_view name) { apiModuleName_ = name; }

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
    void   setContent(std::shared_ptr<const SourceContent> content);
    void   beginEditorRevision(std::string_view content, bool force = false);
    Result loadContent(TaskContext& ctx);

private:
    void ensureSourceView(TaskContext& ctx);

    struct PriorRevision
    {
        std::vector<char8_t>                 content;
        std::shared_ptr<const SourceContent> sharedContent;
        std::unique_ptr<NodePayload>         nodePayload;
        uint64_t                             revisionId = 0;
    };

    static constexpr size_t TRAILING_0 = SourceContent::TRAILING_0;

    FileRef   fileRef_ = FileRef::invalid();
    fs::path  path_;
    FileFlags flags_ = FileFlagsE::Zero;
    Utf8      apiModuleName_;

    mutable std::once_flag               pathStringOnce_;
    mutable Utf8                         pathString_;
    mutable std::once_flag               genericPathStringOnce_;
    mutable Utf8                         genericPathString_;
    mutable std::mutex                   formattedFileNamesMutex_;
    mutable std::array<Utf8, 3>          formattedFileNames_;
    mutable std::array<bool, 3>          formattedFileNamesComputed_ = {};
    std::vector<char8_t>                 content_;
    std::shared_ptr<const SourceContent> sharedContent_;
    std::unique_ptr<NodePayload>         nodePayloadContext_;
    uint64_t                             revisionId_ = 0;
    // Old revisions stay alive while retained symbols or source views still refer to them.
    std::vector<PriorRevision> priorRevisions_;
    std::unique_ptr<Verify>    unitTest_;

    mutable std::mutex                                 errorLinesMutex_;
    mutable std::vector<std::pair<uint32_t, uint32_t>> errorLineRanges_;

    bool hasError_     = false;
    bool hasWarning_   = false;
    bool editorActive_ = true;
};

SWC_END_NAMESPACE();
