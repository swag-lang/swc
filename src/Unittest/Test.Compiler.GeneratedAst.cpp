#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Parser/Ast/Ast.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct RestoreErrorCount
    {
        size_t saved = 0;

        ~RestoreErrorCount()
        {
            Stats::get().numErrors.store(saved, std::memory_order_relaxed);
        }
    };

    class ScopedGeneratedAstDirectory
    {
    public:
        explicit ScopedGeneratedAstDirectory(std::string_view testName)
        {
            root_ = (Os::getTemporaryPath() / "swc_unittest" / "generated-ast" / std::format("{}_p{}", testName, Os::currentProcessId())).lexically_normal();

            std::error_code ec;
            fs::remove_all(root_, ec);
            ec.clear();
            const bool created = fs::create_directories(root_, ec);
            if (!ec && (created || fs::exists(root_)))
                ready_ = true;
        }

        ~ScopedGeneratedAstDirectory()
        {
            std::error_code ec;
            fs::remove_all(root_, ec);
        }

        bool            ready() const { return ready_; }
        const fs::path& root() const { return root_; }

    private:
        fs::path root_;
        bool     ready_ = false;
    };

    const SourceFile* findFileByPath(const CompilerInstance& compiler, const fs::path& path)
    {
        for (const SourceFile* file : compiler.files())
        {
            if (file && FileSystem::pathEquals(file->path(), path))
                return file;
        }

        return nullptr;
    }

    bool isGeneratedAstFile(const SourceFile& file, const fs::path& directory)
    {
        return FileSystem::pathEquals(file.path().parent_path(), directory);
    }

    Result readGeneratedFileText(std::string& outText, const fs::path& path)
    {
        FileSystem::IoErrorInfo ioError;
        return FileSystem::readTextFile(path, outText, ioError);
    }

    uint32_t countRegularFiles(const fs::path& directory)
    {
        uint32_t        count = 0;
        std::error_code ec;
        for (fs::directory_iterator it(directory, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                break;

            if (it->is_regular_file(ec) && !ec)
                count++;
            ec.clear();
        }

        return count;
    }

    bool appendUniquePath(std::vector<fs::path>& paths, const fs::path& path)
    {
        for (const fs::path& existing : paths)
        {
            if (FileSystem::pathEquals(existing, path))
                return false;
        }

        paths.push_back(path);
        return true;
    }
}

SWC_TEST_BEGIN(Compiler_GeneratedAstMaterializesPerThreadFiles)
{
    static constexpr std::string_view SOURCE     = R"(#global fileprivate
#ast "const GeneratedA = 1"
#ast
{
    return "const GeneratedB = 2"
}
#assert(GeneratedA + GeneratedB == 3)
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "GeneratedAstMaterializesPerThreadFiles");
    ScopedGeneratedAstDirectory       workDir("GeneratedAstMaterializesPerThreadFiles");
    if (!workDir.ready())
        return Result::Error;

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Sema;
    cmdLine.name    = "compiler_generated_ast_thread_files";
    cmdLine.workDir = workDir.root();
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    const RestoreErrorCount restoreErrors{errorsBefore};
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const SourceFile* const originalFile = findFileByPath(compiler, sourcePath);
    if (!originalFile)
        return Result::Error;

    std::vector<const SourceFile*> generatedFiles;
    for (const SourceFile* file : compiler.files())
    {
        if (file && isGeneratedAstFile(*file, workDir.root()))
            generatedFiles.push_back(file);
    }

    if (generatedFiles.size() != 2)
        return Result::Error;

    std::vector<fs::path> generatedPaths;
    for (const SourceFile* file : generatedFiles)
    {
        if (!file->mustSkipFormat())
            return Result::Error;
        if (!fs::exists(file->path()))
            return Result::Error;
        if (!file->path().filename().string().starts_with("thread-"))
            return Result::Error;
        if (!file->ast().hasSourceView())
            return Result::Error;
        if (file->ast().srcView().ownerFileRef() != originalFile->ref())
            return Result::Error;

        appendUniquePath(generatedPaths, file->path());
    }

    if (countRegularFiles(workDir.root()) != generatedPaths.size())
        return Result::Error;

    bool foundGeneratedA = false;
    bool foundGeneratedB = false;
    bool foundLine2      = false;
    bool foundLine3      = false;
    for (const fs::path& generatedPath : generatedPaths)
    {
        std::string content;
        SWC_RESULT(readGeneratedFileText(content, generatedPath));
        if (!content.contains(std::format("// #ast source: {}", sourcePath.string())))
            return Result::Error;
        if (content.contains("const GeneratedA = 1"))
            foundGeneratedA = true;
        if (content.contains("const GeneratedB = 2"))
            foundGeneratedB = true;
        if (content.contains("// #ast line: 2"))
            foundLine2 = true;
        if (content.contains("// #ast line: 3"))
            foundLine3 = true;
    }

    if (!foundGeneratedA || !foundGeneratedB || !foundLine2 || !foundLine3)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_GeneratedAstDiagnosticsUseMaterializedSourceFile)
{
    static constexpr std::string_view SOURCE     = R"(#global fileprivate
#ast "const BrokenValue: UnknownType"
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "GeneratedAstDiagnosticsUseMaterializedSourceFile");
    ScopedGeneratedAstDirectory       workDir("GeneratedAstDiagnosticsUseMaterializedSourceFile");
    if (!workDir.ready())
        return Result::Error;

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Sema;
    cmdLine.name    = "compiler_generated_ast_diagnostics";
    cmdLine.silent  = true;
    cmdLine.workDir = workDir.root();
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    const RestoreErrorCount restoreErrors{errorsBefore};
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() == errorsBefore)
        return Result::Error;

    const SourceFile* const originalFile = findFileByPath(compiler, sourcePath);
    if (!originalFile)
        return Result::Error;

    const SourceFile* generatedFile = nullptr;
    for (const SourceFile* file : compiler.files())
    {
        if (file && isGeneratedAstFile(*file, workDir.root()) && file->hasError())
        {
            generatedFile = file;
            break;
        }
    }

    if (!generatedFile)
        return Result::Error;
    if (!fs::exists(generatedFile->path()))
        return Result::Error;
    if (!generatedFile->ast().hasSourceView())
        return Result::Error;
    if (generatedFile->ast().srcView().ownerFileRef() != originalFile->ref())
        return Result::Error;

    std::string content;
    SWC_RESULT(readGeneratedFileText(content, generatedFile->path()));
    if (!content.contains("UnknownType"))
        return Result::Error;
    if (!content.contains(std::format("// #ast source: {}", sourcePath.string())))
        return Result::Error;
    if (!content.contains("// #ast line: 2"))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
