#pragma once

class Logger;
class Reporter;
class LangSpec;
class CommandLine;

class CompilerInstance
{
    std::unique_ptr<Reporter>    diagReporter_;
    std::unique_ptr<Logger>      logger_;
    std::unique_ptr<LangSpec>    langSpec_;
    std::unique_ptr<CommandLine> cmdLine_;

public:
    CompilerInstance();
    Reporter&    diagReporter() const { return *diagReporter_; }
    Logger&      logger() const { return *logger_; }
    LangSpec&    langSpec() const { return *langSpec_; }
    CommandLine& cmdLine() const { return *cmdLine_; }
};
