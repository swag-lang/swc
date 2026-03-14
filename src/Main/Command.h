#pragma once

SWC_BEGIN_NAMESPACE();

class CompilerInstance;

namespace Command
{
    void verboseInfo(CompilerInstance& compiler);
    void syntax(CompilerInstance& compiler);
    void sema(CompilerInstance& compiler);
    void test(CompilerInstance& compiler);
    void build(CompilerInstance& compiler);
    void run(CompilerInstance& compiler);
}

SWC_END_NAMESPACE();
