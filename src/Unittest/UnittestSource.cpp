#include "pch.h"
#include "Unittest/UnittestSource.h"

#if SWC_HAS_UNITTEST

#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    fs::path unittestRootPath()
    {
        fs::path path = fs::path(__FILE__).parent_path();
        if (!path.is_absolute())
            path = fs::absolute(path);
        return path.lexically_normal();
    }
}

namespace Unittest
{
    fs::path makeTestSourcePath(const std::string_view partOfCompiler, const std::string_view testName)
    {
        return (unittestRootPath() / std::format("Test.{}.{}.swg", partOfCompiler, testName)).lexically_normal();
    }

    void registerTestSource(CompilerInstance& compiler, const fs::path& sourcePath, const std::string_view content)
    {
        compiler.registerInMemoryFile(sourcePath, content);
    }

    void registerTestSource(CompilerInstance& compiler, const std::string_view partOfCompiler, const std::string_view testName, const std::string_view content)
    {
        registerTestSource(compiler, makeTestSourcePath(partOfCompiler, testName), content);
    }

    SourceFile& addTestSource(TaskContext& ctx, const fs::path& sourcePath, const std::string_view content, const FileFlags flags)
    {
        SourceFile& sourceFile = ctx.compiler().addFile(sourcePath, flags);
        sourceFile.setContent(content);
        return sourceFile;
    }

    SourceFile& addTestSource(TaskContext& ctx, const std::string_view partOfCompiler, const std::string_view testName, const std::string_view content, const FileFlags flags)
    {
        return addTestSource(ctx, makeTestSourcePath(partOfCompiler, testName), content, flags);
    }
}

SWC_END_NAMESPACE();

#endif
