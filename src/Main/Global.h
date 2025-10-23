#pragma once

class Logger;
class DiagnosticIds;
class LangSpec;
class JobManager;
struct CommandLine;
struct Stats;

class Global
{
    DiagnosticIds* diagIds_  = nullptr;
    Logger*        logger_   = nullptr;
    LangSpec*      langSpec_ = nullptr;
    CommandLine*   cmdLine_  = nullptr;
    JobManager*    jobMgr_   = nullptr;
    Stats*         stats_    = nullptr;

public:
    Global();
    
    static Global& get()
    {
        static Global instance;
        return instance;
    }

    void setup();

    const DiagnosticIds& diagIds() const { return *diagIds_; }
    Logger&              logger() const { return *logger_; }
    LangSpec&            langSpec() const { return *langSpec_; }
    CommandLine&         cmdLine() const { return *cmdLine_; }
    JobManager&          jobMgr() const { return *jobMgr_; }
    Stats&               stats() const { return *stats_; }
};
