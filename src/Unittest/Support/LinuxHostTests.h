#pragma once

namespace swc::LinuxHostTests
{
    void require(bool condition, const char* message);
    int  waitForChild(int child);
    void testHostBasics();
    void testFileServices();
    void testFileOwners();
    void testCrossToolchainDiscovery();
    void testDirectoryLocks();
    void testThreadStorage();
    void testModuleLoading();
    void testTerminal();
    void testCallStacks();
    void testFaultHandlerStacks();
    void testGeneratedUnwind();
    int  runProcessChild(int argc, char* argv[]);
    void testProcessOutput();
    void testProcessServices();
}
