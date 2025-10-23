#include "pch.h"
#include "Logger.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"

void Logger::log(std::string_view message)
{
    if (Global::get().cmdLine().silent)
        return;
    std::cout << message;   
}

void Logger::logEol()
{
    std::cout << std::endl;   
}
