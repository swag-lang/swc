#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Runtime.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

#undef SWC_TEST_KIND
#define SWC_TEST_KIND swc::Unittest::TestKind::Filesystem

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

    bool isInternalGeneratedSourceFile(const SourceFile& file)
    {
        return file.path().filename().string().contains("__swag_internal_");
    }

    Result readGeneratedFileText(std::string& outText, const fs::path& path)
    {
        FileSystem::IoErrorInfo ioError;
        return FileSystem::readTextFile(path, outText, ioError);
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

    bool containsGeneratedSpecOpText(const std::string_view content)
    {
        return content.contains("swagLifecycleInitWrapper") ||
               content.contains("swagLifecycleDropWrapper") ||
               content.contains("swagLifecyclePostcopyWrapper") ||
               content.contains("swagLifecyclePostmoveWrapper") ||
               content.contains("mtd const opEquals(") ||
               content.contains("mtd const opCompare(");
    }

    bool tryFindTokenCodeRef(const SourceView& srcView, std::string_view tokenText, SourceCodeRef& outCodeRef)
    {
        outCodeRef = SourceCodeRef::invalid();
        for (uint32_t i = 0; i < srcView.numTokens(); ++i)
        {
            const TokenRef tokRef{i};
            if (srcView.tokenString(tokRef) != tokenText)
                continue;

            outCodeRef = {.srcViewRef = srcView.ref(), .tokRef = tokRef};
            return true;
        }

        return false;
    }

    Result runLifecycleInitWrapperStressCompile(const TaskContext& ctx, uint32_t seed)
    {
        static constexpr std::string_view SOURCE = R"(#global fileprivate
struct(T) Wrapper
{
    value: T
}

func touch()
{
    let a: Wrapper's8
    let b: Wrapper's16
    let c: Wrapper's32
    let d: Wrapper's64
    let e: Wrapper'u8
    let f: Wrapper'u16
    let g: Wrapper'u32
    let h: Wrapper'u64
    let i: Wrapper'f32
    let j: Wrapper'f64
    let k: Wrapper'bool
    let l: Wrapper'string
    let m: Wrapper'(Wrapper's32)
    let n: Wrapper'(Wrapper'u64)

    #assert(#typeof(a.value) == s8)
    #assert(#typeof(b.value) == s16)
    #assert(#typeof(c.value) == s32)
    #assert(#typeof(d.value) == s64)
    #assert(#typeof(e.value) == u8)
    #assert(#typeof(f.value) == u16)
    #assert(#typeof(g.value) == u32)
    #assert(#typeof(h.value) == u64)
    #assert(#typeof(i.value) == f32)
    #assert(#typeof(j.value) == f64)
    #assert(#typeof(k.value) == bool)
    #assert(#typeof(l.value) == string)
    #assert(#typeof(m.value.value) == s32)
    #assert(#typeof(n.value.value) == u64)
}
)";

        const fs::path sourcePath = Unittest::makeTestSourcePath("Compiler", std::format("LifecycleInitWrapperStressCompile_{}", seed));

        CommandLine cmdLine;
        cmdLine.command   = CommandKind::Sema;
        cmdLine.name      = std::format("compiler_lifecycle_init_wrapper_stress_{}", seed);
        cmdLine.silent    = true;
        cmdLine.numCores  = 4;
        cmdLine.randomize = true;
        cmdLine.randSeed  = seed;
        cmdLine.files.insert(sourcePath);
        CommandLineParser::refreshBuildCfg(cmdLine);

        const uint64_t          errorsBefore = Stats::getNumErrors();
        const RestoreErrorCount restoreErrors{errorsBefore};
        CompilerInstance        compiler(ctx.global(), cmdLine);
        Unittest::registerTestSource(compiler, sourcePath, SOURCE);
        if (compiler.run() != ExitCode::Success)
            return Result::Error;
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;

        for (const SourceFile* file : compiler.files())
        {
            if (file && isInternalGeneratedSourceFile(*file))
                return Result::Error;
        }

        return Result::Continue;
    }

    Result runGeneratedSpecOpStressCompile(const TaskContext& ctx, uint32_t seed)
    {
        static constexpr std::string_view SOURCE = R"(#global fileprivate
using Swag

struct Tracked
{
    value: s32 = 1
}

impl Tracked
{
    mtd opDrop()
    {
    }

    mtd opPostCopy()
    {
        .value += 10
    }

    mtd opPostMove()
    {
        .value += 20
    }
}

#[Swag.Operators(opEquals, opCompare)]
struct GeneratedPair
{
    left, right: s32
}

#[Swag.Operators(opEquals, opCompare)]
struct(T) GeneratedBox
{
    value: T
}

struct(T) LifecycleBox
{
    value: T
}

struct LifecycleOwner
{
    first:  Tracked
    second: Tracked
}

func touch()
{
    let eqA = GeneratedBox's32{value: 1}
    let eqB = GeneratedBox's32{value: 2}
    let eqBoolA = eqA != eqB
    let eqBoolB = eqA < eqB

    let pairA = GeneratedPair{left: 1, right: 2}
    let pairB = GeneratedPair{left: 1, right: 3}
    let pairBoolA = pairA != pairB
    let pairBoolB = pairA < pairB

    let nestedA = GeneratedBox'GeneratedPair{value: GeneratedPair{left: 7, right: 8}}
    let nestedB = GeneratedBox'GeneratedPair{value: GeneratedPair{left: 7, right: 9}}
    let nestedBoolA = nestedA != nestedB
    let nestedBoolB = nestedA < nestedB

    var one: LifecycleBox'Tracked
    var two: LifecycleBox'Tracked
    var owner: LifecycleOwner
    var nested: LifecycleBox'LifecycleOwner

    @postcopy(one)
    @postmove(two)
    @drop(one)
    @drop(two)

    @postcopy(owner)
    @postmove(owner)
    @drop(owner)

    @postcopy(nested)
    @postmove(nested)
    @drop(nested)

    #assert(#typeof(eqBoolA) == bool)
    #assert(#typeof(eqBoolB) == bool)
    #assert(#typeof(pairBoolA) == bool)
    #assert(#typeof(pairBoolB) == bool)
    #assert(#typeof(nestedBoolA) == bool)
    #assert(#typeof(nestedBoolB) == bool)
    #assert(#typeof(one.value.value) == s32)
    #assert(#typeof(nested.value.first.value) == s32)
}
)";

        const fs::path sourcePath = Unittest::makeTestSourcePath("Compiler", std::format("GeneratedSpecOpStressCompile_{}", seed));

        CommandLine cmdLine;
        cmdLine.command   = CommandKind::Sema;
        cmdLine.name      = std::format("compiler_generated_spec_op_stress_{}", seed);
        cmdLine.silent    = true;
        cmdLine.numCores  = 4;
        cmdLine.randomize = true;
        cmdLine.randSeed  = seed;
        cmdLine.files.insert(sourcePath);
        CommandLineParser::refreshBuildCfg(cmdLine);

        const uint64_t          errorsBefore = Stats::getNumErrors();
        const RestoreErrorCount restoreErrors{errorsBefore};
        CompilerInstance        compiler(ctx.global(), cmdLine);
        Unittest::registerTestSource(compiler, sourcePath, SOURCE);
        if (compiler.run() != ExitCode::Success)
            return Result::Error;
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;

        for (const SourceFile* file : compiler.files())
        {
            if (file && isInternalGeneratedSourceFile(*file))
                return Result::Error;
        }

        return Result::Continue;
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
    const ScopedGeneratedAstDirectory workDir("GeneratedAstMaterializesPerThreadFiles");
    if (!workDir.ready())
        return Result::Error;

    CommandLine cmdLine;
    cmdLine.command  = CommandKind::Sema;
    cmdLine.name     = "compiler_generated_ast_thread_files";
    cmdLine.numCores = 1;
    cmdLine.workDir  = workDir.root();
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t          errorsBefore = Stats::getNumErrors();
    const RestoreErrorCount restoreErrors{errorsBefore};
    CompilerInstance        compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    if (compiler.run() != ExitCode::Success)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const SourceFile* originalFile = findFileByPath(compiler, sourcePath);
    if (!originalFile)
        return Result::Error;

    std::vector<const SourceFile*> generatedFiles;
    for (const SourceFile* file : compiler.files())
    {
        if (file &&
            isGeneratedAstFile(*file, workDir.root()) &&
            file->ast().hasSourceView() &&
            file->ast().srcView().ownerFileRef() == originalFile->ref())
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
        if (!file->path().filename().string().contains("generated-source-"))
            return Result::Error;
        if (file->path().extension() != ".swgsrc")
            return Result::Error;
        if (!file->ast().hasSourceView())
            return Result::Error;
        if (compiler.ownerSourceFile(file->ast().srcView()) != originalFile)
            return Result::Error;
        if (compiler.sourceViewFile(file->ast().srcView().ref()) != file)
            return Result::Error;
        if (compiler.owningSourceFile(file->ast().srcView()) != originalFile)
            return Result::Error;
        if (file->ast().srcView().ownerFileRef() != originalFile->ref())
            return Result::Error;

        appendUniquePath(generatedPaths, file->path());
    }

    // Generated snippets can land in one or more generated-source dumps depending
    // on which compiler thread materializes each section.
    if (generatedPaths.empty() || generatedPaths.size() > generatedFiles.size())
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

    size_t resolvedGeneratedFiles = 0;
    for (const SourceFile* file : generatedFiles)
    {
        SourceCodeRef generatedCodeRef;
        if (!tryFindTokenCodeRef(file->ast().srcView(), "GeneratedA", generatedCodeRef) &&
            !tryFindTokenCodeRef(file->ast().srcView(), "GeneratedB", generatedCodeRef))
            continue;

        CompilerInstance::ResolvedSourceLocation resolvedLocation;
        if (!compiler.tryResolveSourceLocation(ctx, resolvedLocation, generatedCodeRef))
            return Result::Error;
        if (resolvedLocation.sourceFile != file)
            return Result::Error;
        if (resolvedLocation.sourceFile == originalFile)
            return Result::Error;
        if (resolvedLocation.codeRange.srcView != &file->ast().srcView())
            return Result::Error;
        if (!resolvedLocation.codeRange.line)
            return Result::Error;
        if (resolvedLocation.codeRange.line < 3)
            return Result::Error;

        const std::string                 locationFileName = file->path().string();
        const Runtime::SourceCodeLocation runtimeLocation  = {
             .fileName  = {.ptr = locationFileName.c_str(), .length = locationFileName.size()},
             .funcName  = {.ptr = nullptr, .length = 0},
             .lineStart = resolvedLocation.codeRange.line,
             .colStart  = resolvedLocation.codeRange.column,
             .lineEnd   = resolvedLocation.codeRange.line,
             .colEnd    = resolvedLocation.codeRange.column + resolvedLocation.codeRange.len,
        };

        CompilerInstance::ResolvedSourceLocation resolvedRuntimeLocation;
        if (!compiler.tryResolveSourceLocation(ctx, resolvedRuntimeLocation, runtimeLocation))
            return Result::Error;
        if (resolvedRuntimeLocation.sourceFile != file)
            return Result::Error;
        if (resolvedRuntimeLocation.codeRange.srcView != &file->ast().srcView())
            return Result::Error;
        if (resolvedRuntimeLocation.codeRange.line != resolvedLocation.codeRange.line)
            return Result::Error;
        if (resolvedRuntimeLocation.codeRange.column != resolvedLocation.codeRange.column)
            return Result::Error;

        ++resolvedGeneratedFiles;
    }

    if (resolvedGeneratedFiles != generatedFiles.size())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_RuntimeLocationPicksGeneratedSourceViewMatchingLineOffset)
{
    static constexpr std::string_view FIRST_CONTENT  = R"(// #ast source: fake.swg
// #ast line: 2
const GeneratedA = 1
)";
    static constexpr std::string_view SECOND_CONTENT = R"(// #ast source: fake.swg
// #ast line: 3
const GeneratedB = 2
)";

    const ScopedGeneratedAstDirectory workDir("RuntimeLocationPicksGeneratedSourceViewMatchingLineOffset");
    if (!workDir.ready())
        return Result::Error;

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Sema;
    cmdLine.name    = "compiler_generated_ast_runtime_location";
    CommandLineParser::refreshBuildCfg(cmdLine);

    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      generatedCtx(compiler);

    const fs::path generatedPath = (workDir.root() / "generated-source-0.swgsrc").lexically_normal();
    SourceFile&     firstFile    = compiler.addLoadedFile(generatedPath, FileFlagsE::CustomSrc | FileFlagsE::SkipFmt, FIRST_CONTENT);
    SourceFile&     secondFile   = compiler.addLoadedFile(generatedPath, FileFlagsE::CustomSrc | FileFlagsE::SkipFmt, SECOND_CONTENT);

    firstFile.ast().srcView().setLineOffset(0);
    secondFile.ast().srcView().setLineOffset(3);

    Lexer lexer;
    lexer.tokenize(generatedCtx, firstFile.ast().srcView(), LexerFlagsE::Default);
    lexer.tokenize(generatedCtx, secondFile.ast().srcView(), LexerFlagsE::Default);

    const std::string                 locationFileName = generatedPath.string();
    const Runtime::SourceCodeLocation runtimeLocation  = {
         .fileName  = {.ptr = locationFileName.c_str(), .length = locationFileName.size()},
         .funcName  = {.ptr = nullptr, .length = 0},
         .lineStart = 6,
         .colStart  = 1,
         .lineEnd   = 6,
         .colEnd    = 6,
    };

    CompilerInstance::ResolvedSourceLocation resolvedLocation;
    if (!compiler.tryResolveSourceLocation(generatedCtx, resolvedLocation, runtimeLocation))
        return Result::Error;
    if (resolvedLocation.sourceFile != &secondFile)
        return Result::Error;
    if (resolvedLocation.codeRange.srcView != &secondFile.ast().srcView())
        return Result::Error;
    if (resolvedLocation.codeRange.line != runtimeLocation.lineStart)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_LifecycleInitWrapperStaysOutOfGeneratedThreadFiles)
{
    static constexpr std::string_view SOURCE     = R"(#global fileprivate
struct GeneratedInitNoise
{
    value: s32
}

#ast "const GeneratedValue = 1"
#assert(GeneratedValue == 1)
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "LifecycleInitWrapperStaysOutOfGeneratedThreadFiles");
    const ScopedGeneratedAstDirectory workDir("LifecycleInitWrapperStaysOutOfGeneratedThreadFiles");
    if (!workDir.ready())
        return Result::Error;

    CommandLine cmdLine;
    cmdLine.command  = CommandKind::Sema;
    cmdLine.name     = "compiler_generated_init_wrapper_noise";
    cmdLine.numCores = 1;
    cmdLine.workDir  = workDir.root();
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t          errorsBefore = Stats::getNumErrors();
    const RestoreErrorCount restoreErrors{errorsBefore};
    CompilerInstance        compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    if (compiler.run() != ExitCode::Success)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    std::vector<fs::path> generatedPaths;
    for (const SourceFile* file : compiler.files())
    {
        if (!file || !isGeneratedAstFile(*file, workDir.root()))
            continue;
        if (!fs::exists(file->path()))
            return Result::Error;

        appendUniquePath(generatedPaths, file->path());
    }

    if (generatedPaths.empty())
        return Result::Error;

    bool foundGeneratedValue = false;
    for (const fs::path& generatedPath : generatedPaths)
    {
        std::string content;
        SWC_RESULT(readGeneratedFileText(content, generatedPath));
        if (content.contains("const GeneratedValue = 1"))
            foundGeneratedValue = true;
        if (content.contains("swagLifecycleInitWrapper"))
            return Result::Error;
        if (content.contains("@init(me, 1)"))
            return Result::Error;
    }

    if (!foundGeneratedValue)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_LifecycleInitWrapperDoesNotCreateSyntheticSourceFilesUnderStress)
{
    for (uint32_t i = 0; i < 32; ++i)
        SWC_RESULT(runLifecycleInitWrapperStressCompile(ctx, 4000 + i));

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_GeneratedSpecOpsStayOutOfGeneratedThreadFiles)
{
    static constexpr std::string_view SOURCE = R"(#global fileprivate
using Swag

struct Tracked
{
    value: s32 = 1
}

impl Tracked
{
    mtd opDrop()
    {
    }

    mtd opPostCopy()
    {
        .value += 10
    }

    mtd opPostMove()
    {
        .value += 20
    }
}

#[Swag.Operators(opEquals, opCompare)]
struct GeneratedPair
{
    left, right: s32
}

struct LifecycleOwner
{
    first:  Tracked
    second: Tracked
}

func touch()
{
    let pairA = GeneratedPair{left: 1, right: 2}
    let pairB = GeneratedPair{left: 1, right: 3}
    let pairBool = pairA < pairB

    var owner: LifecycleOwner
    @postcopy(owner)
    @postmove(owner)
    @drop(owner)

    #assert(#typeof(pairBool) == bool)
}

#ast "const GeneratedValue = 1"
#assert(GeneratedValue == 1)
)";

    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "GeneratedSpecOpsStayOutOfGeneratedThreadFiles");
    const ScopedGeneratedAstDirectory workDir("GeneratedSpecOpsStayOutOfGeneratedThreadFiles");
    if (!workDir.ready())
        return Result::Error;

    CommandLine cmdLine;
    cmdLine.command  = CommandKind::Sema;
    cmdLine.name     = "compiler_generated_spec_op_thread_files";
    cmdLine.numCores = 1;
    cmdLine.workDir  = workDir.root();
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t          errorsBefore = Stats::getNumErrors();
    const RestoreErrorCount restoreErrors{errorsBefore};
    CompilerInstance        compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    if (compiler.run() != ExitCode::Success)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    std::vector<fs::path> generatedPaths;
    for (const SourceFile* file : compiler.files())
    {
        if (file && isInternalGeneratedSourceFile(*file))
            return Result::Error;
        if (!file || !isGeneratedAstFile(*file, workDir.root()))
            continue;
        if (!fs::exists(file->path()))
            return Result::Error;

        appendUniquePath(generatedPaths, file->path());
    }

    if (generatedPaths.empty())
        return Result::Error;

    bool foundGeneratedValue = false;
    for (const fs::path& generatedPath : generatedPaths)
    {
        std::string content;
        SWC_RESULT(readGeneratedFileText(content, generatedPath));
        if (content.contains("const GeneratedValue = 1"))
            foundGeneratedValue = true;
        if (containsGeneratedSpecOpText(content))
            return Result::Error;
    }

    if (!foundGeneratedValue)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_GeneratedSpecOpsDoNotCreateSyntheticSourceFilesUnderStress)
{
    for (uint32_t i = 0; i < 32; ++i)
        SWC_RESULT(runGeneratedSpecOpStressCompile(ctx, 5000 + i));

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_GeneratedAstDiagnosticsUseMaterializedSourceFile)
{
    static constexpr std::string_view SOURCE     = R"(#global fileprivate
#ast "const BrokenValue: UnknownType"
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "GeneratedAstDiagnosticsUseMaterializedSourceFile");
    const ScopedGeneratedAstDirectory workDir("GeneratedAstDiagnosticsUseMaterializedSourceFile");
    if (!workDir.ready())
        return Result::Error;

    CommandLine cmdLine;
    cmdLine.command            = CommandKind::Sema;
    cmdLine.name               = "compiler_generated_ast_diagnostics";
    cmdLine.silent             = true;
    cmdLine.devStopDiagnostics = false;
    cmdLine.numCores           = 1;
    cmdLine.workDir            = workDir.root();
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t          errorsBefore = Stats::getNumErrors();
    const RestoreErrorCount restoreErrors{errorsBefore};
    CompilerInstance        compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    if (compiler.run() == ExitCode::Success)
        return Result::Error;
    if (Stats::getNumErrors() == errorsBefore)
        return Result::Error;

    const SourceFile* originalFile = findFileByPath(compiler, sourcePath);
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
