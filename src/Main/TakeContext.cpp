#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

TaskContext::TaskContext(const Global& global, const CommandLine& cmdLine) :
    global_(&global),
    cmdLine_(&cmdLine)
{
}

TaskContext::TaskContext(CompilerInstance& compInst) :
    compilerInstance_(&compInst)
{
    global_  = &compInst.global();
    cmdLine_ = &compInst.cmdLine();
}

ConstantManager& TaskContext::cstMgr()
{
    return compiler().cstMgr();
}

const ConstantManager& TaskContext::cstMgr() const
{
    return compiler().cstMgr();
}

TypeManager& TaskContext::typeMgr()
{
    return compiler().typeMgr();
}

const TypeManager& TaskContext::typeMgr() const
{
    return compiler().typeMgr();
}

TypeGen& TaskContext::typeGen()
{
    return compiler().typeGen();
}

const TypeGen& TaskContext::typeGen() const
{
    return compiler().typeGen();
}

IdentifierManager& TaskContext::idMgr()
{
    return compiler().idMgr();
}

const IdentifierManager& TaskContext::idMgr() const
{
    return compiler().idMgr();
}

SWC_END_NAMESPACE();
