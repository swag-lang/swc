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

    Logger&     logger() const { return *SWC_CHECK_NOT_NULL(logger_); }
    LangSpec&   langSpec() const { return *SWC_CHECK_NOT_NULL(langSpec_); }
    JobManager& jobMgr() const { return *SWC_CHECK_NOT_NULL(jobManager_); }

private:
    Logger*     logger_     = nullptr;
    LangSpec*   langSpec_   = nullptr;
    JobManager* jobManager_ = nullptr;
};

SWC_END_NAMESPACE();
