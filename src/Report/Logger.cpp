#include "pch.h"
#include "Logger.h"
#include <iostream>

void Logger::log(Utf8 message)
{
    std::cout << message;   
}

void Logger::logEol()
{
    std::cout << std::endl;   
}
