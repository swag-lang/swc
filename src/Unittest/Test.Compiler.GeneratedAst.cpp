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

    fs::path generatedAstDirectory()
    {
        return (Os::getTemporaryPath() / "swag" / "generated-ast").lexically_normal();
    }

    const SourceFile* findFileByPath(const CompilerInstance& compiler, const fs::path& path)
    {
        for (const SourceFile* file : compiler.files())
        {
            if (file && FileSystem::pathEquals(file->path(), path))
                return file;
        }

        return nullptr;
    }

    bool isGeneratedAstFile(const SourceFile& file)
    {
        return FileSystem::pathEquals(file.path().parent_path(), generatedAstDirectory());
    }

    Result readGeneratedFileText(std::string& outText, const SourceFile& file)
    {
        FileSystem::IoErrorInfo ioError;
        return FileSystem::readTextFile(file.path(), outText, ioError);
    }
}

SWC_TEST_BEGIN(Compiler_GeneratedAstMaterializesDistinctTempFiles)
{
    static constexpr std::string_view SOURCE     = R"(#global fileprivate
#ast "const GeneratedA = 1"
#ast
{
    return "const GeneratedB = 2"
}
#assert(GeneratedA + GeneratedB == 3)
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "GeneratedAstMaterializesDistinctTempFiles");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Sema;
    cmdLine.name    = "compiler_generated_ast_temp_files";
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
        if (file && isGeneratedAstFile(*file))
            generatedFiles.push_back(file);
    }

    if (generatedFiles.size() != 2)
        return Result::Error;
    if (FileSystem::pathEquals(generatedFiles[0]->path(), generatedFiles[1]->path()))
        return Result::Error;

    bool foundGeneratedA = false;
    bool foundGeneratedB = false;
    for (const SourceFile* file : generatedFiles)
    {
        if (!file->mustSkipFormat())
            return Result::Error;
        if (!fs::exists(file->path()))
            return Result::Error;
        if (!file->ast().hasSourceView())
            return Result::Error;
        if (file->ast().srcView().ownerFileRef() != originalFile->ref())
            return Result::Error;

        std::string content;
        SWC_RESULT(readGeneratedFileText(content, *file));
        if (content == "const GeneratedA = 1")
            foundGeneratedA = true;
        else if (content == "const GeneratedB = 2")
            foundGeneratedB = true;
    }

    if (!foundGeneratedA || !foundGeneratedB)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_GeneratedAstDiagnosticsUseMaterializedSourceFile)
{
    static constexpr std::string_view SOURCE     = R"(#global fileprivate
#ast "const BrokenValue: UnknownType"
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "GeneratedAstDiagnosticsUseMaterializedSourceFile");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Sema;
    cmdLine.name    = "compiler_generated_ast_diagnostics";
    cmdLine.silent  = true;
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
        if (file && isGeneratedAstFile(*file) && file->hasError())
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
    SWC_RESULT(readGeneratedFileText(content, *generatedFile));
    if (!content.contains("UnknownType"))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
