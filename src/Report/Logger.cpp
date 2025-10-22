#include "pch.h"
#include "Logger.h"
#include "Main/CommandLine.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"

void Logger::log(const CompilerContext &ctx, std::string_view message)
{
    if (ctx.ci().cmdLine().silent)
        return;
    std::cout << message;   
}

void Logger::logEol()
{
    std::cout << std::endl;   
}
