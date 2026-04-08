#pragma once

#include "Compiler/SourceFile.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

class CompilerInstance;
class TaskContext;

namespace Unittest
{
    fs::path   makeTestSourcePath(std::string_view partOfCompiler, std::string_view testName);
    void       registerTestSource(CompilerInstance& compiler, const fs::path& sourcePath, std::string_view content);
    void       registerTestSource(CompilerInstance& compiler, std::string_view partOfCompiler, std::string_view testName, std::string_view content);
    SourceFile& addTestSource(TaskContext& ctx, const fs::path& sourcePath, std::string_view content, FileFlags flags = FileFlagsE::CustomSrc);
    SourceFile& addTestSource(TaskContext& ctx, std::string_view partOfCompiler, std::string_view testName, std::string_view content, FileFlags flags = FileFlagsE::CustomSrc);
}

#endif

SWC_END_NAMESPACE();
