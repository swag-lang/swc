#include "pch.h"
#include "Logger.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"

void Logger::log(std::string_view message)
{
    if (CompilerInstance::get().cmdLine().silent)
        return;
    std::cout << message;   
}

void Logger::logEol()
{
    std::cout << std::endl;   
}
