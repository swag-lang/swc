#include "pch.h"

#include "LogColor.h"
#include "Logger.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"

void Logger::print(std::string_view message)
{
    if (Global::get().cmdLine().silent)
        return;
    std::cout << message;   
}

void Logger::printEol()
{
    if (Global::get().cmdLine().silent)
        return;    
    std::cout << std::endl;   
}

void Logger::printHeaderDot(LogColor headerColor, std::string_view header, LogColor msgColor, std::string_view message, std::string_view dot, size_t messageColumn)
{
    if (Global::get().cmdLine().silent)
        return;
    
    lock();
    print(Color::toAnsi(headerColor));
    print(header);
    for (size_t i = header.size(); i < messageColumn; ++i)
        print(dot);
    print(Color::toAnsi(msgColor));
    print(message);
    printEol();
    unlock();
}