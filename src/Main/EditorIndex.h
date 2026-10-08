#pragma once
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

struct CommandLine;
class CompilerInstance;

namespace EditorIndex
{
    // Keys are absolute source paths. The source keeps its identity when its text comes from an editor.
    std::string pathKey(const fs::path& path);
    Result      loadOverlays(CommandLine& cmdLine);
    Result      write(CompilerInstance& compiler);
}

SWC_END_NAMESPACE();
