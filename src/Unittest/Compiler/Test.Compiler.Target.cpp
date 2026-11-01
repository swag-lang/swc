#include "pch.h"

#if SWC_HAS_UNITTEST
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(Compiler_CommandLineSelectsTargetOs)
{
    for (const auto target : {Runtime::TargetOs::Windows, Runtime::TargetOs::Linux})
    {
        CommandLine commandLine;
        char arg0[] = "swc";
        char arg1[] = "syntax";
        char arg2[] = "--os";
        char windows[] = "windows";
        char linuxOs[] = "linux";
        char* argv[] = {arg0, arg1, arg2, target == Runtime::TargetOs::Windows ? windows : linuxOs};
        CommandLineParser parser(const_cast<Global&>(ctx.global()), commandLine);
        SWC_RESULT(parser.parse(std::size(argv), argv));
        if (commandLine.targetOs != target)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();
#endif
