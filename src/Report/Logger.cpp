#include "pch.h"
#include "Logger.h"
#include <iostream>

void Logger::log(std::string message)
{
    std::cout << message;   
}

void Logger::logEol()
{
    std::cout << std::endl;   
}
