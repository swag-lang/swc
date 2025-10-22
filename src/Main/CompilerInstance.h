#pragma once

class Logger;
class DiagnosticIds;
class LangSpec;
class JobManager;
struct CommandLine;

class CompilerInstance
{
    std::unique_ptr<DiagnosticIds> diagIds_;
    std::unique_ptr<Logger>        logger_;
    std::unique_ptr<LangSpec>      langSpec_;
    std::unique_ptr<CommandLine>   cmdLine_;
    std::unique_ptr<JobManager>    jobMgr_;

public:
    CompilerInstance();
    const DiagnosticIds& diagIds() const { return *diagIds_; }
    Logger&              logger() const { return *logger_; }
    LangSpec&            langSpec() const { return *langSpec_; }
    CommandLine&         cmdLine() const { return *cmdLine_; }
    JobManager&          jobMgr() const { return *jobMgr_; }
};
