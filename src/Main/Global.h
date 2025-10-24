#pragma once
SWC_BEGIN_NAMESPACE();

class Logger;
class LangSpec;
class JobManager;
class FileManager;
struct CommandLine;

class Global
{
    Logger*      logger_      = nullptr;
    LangSpec*    langSpec_    = nullptr;
    JobManager*  jobManager_  = nullptr;
    FileManager* fileManager_ = nullptr;

public:
    Global();
    void initialize(const CommandLine& cmdLine) const;

    Logger&      logger() const { return *logger_; }
    LangSpec&    langSpec() const { return *langSpec_; }
    JobManager&  jobMgr() const { return *jobManager_; }
    FileManager& fileMgr() const { return *fileManager_; }
};

SWC_END_NAMESPACE();
