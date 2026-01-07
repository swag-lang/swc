#pragma once

SWC_BEGIN_NAMESPACE();

class Logger;
class LangSpec;
class JobManager;
struct CommandLine;

class Global
{
public:
    Global();
    void initialize(const CommandLine& cmdLine) const;

    Logger&     logger() const { return *logger_; }
    LangSpec&   langSpec() const { return *langSpec_; }
    JobManager& jobMgr() const { return *jobManager_; }

private:
    Logger*     logger_     = nullptr;
    LangSpec*   langSpec_   = nullptr;
    JobManager* jobManager_ = nullptr;
};

SWC_END_NAMESPACE();
