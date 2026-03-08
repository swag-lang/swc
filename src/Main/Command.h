#pragma once

SWC_BEGIN_NAMESPACE();

class CompilerInstance;

namespace Command
{
    void syntax(CompilerInstance& compiler);
    void sema(CompilerInstance& compiler);
    void test(CompilerInstance& compiler);
}

SWC_END_NAMESPACE();
