#define NOMINMAX
#include <windows.h>
#include <dbghelp.h>
#include <tlhelp32.h>
#include <psapi.h>
#include <algorithm>
#include <cstdio>
#include <map>
#include <set>
#include <string>
#include <vector>
#pragma comment(lib, "dbghelp.lib")
#pragma comment(lib, "psapi.lib")

struct Sample { std::vector<DWORD64> stack; double seconds; };
static unsigned long long ticks(FILETIME t) { return (static_cast<unsigned long long>(t.dwHighDateTime) << 32) | t.dwLowDateTime; }
int wmain(int argc, wchar_t** argv)
{
    if (argc < 4) return 2;
    std::wstring command;
    for (int i = 3; i < argc; ++i) { if (i > 3) command += L" "; command += L"\""; command += argv[i]; command += L"\""; }
    SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
    HANDLE log = CreateFileW(argv[2], GENERIC_WRITE, FILE_SHARE_READ, &security, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    STARTUPINFOW startup{sizeof(startup)};
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdOutput = startup.hStdError = log;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(nullptr, command.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, nullptr, &startup, &process)) return 3;
    SymSetOptions(SYMOPT_UNDNAME | SYMOPT_LOAD_LINES | SYMOPT_DEFERRED_LOADS);
    SymInitialize(process.hProcess, nullptr, FALSE);
    ResumeThread(process.hThread);
    Sleep(30);
    HMODULE modules[1024]; DWORD bytes = 0;
    if (EnumProcessModules(process.hProcess, modules, sizeof(modules), &bytes))
    {
        for (DWORD i = 0; i < bytes / sizeof(HMODULE); ++i)
        {
            wchar_t path[MAX_PATH]; MODULEINFO info{};
            if (GetModuleFileNameExW(process.hProcess, modules[i], path, MAX_PATH) && GetModuleInformation(process.hProcess, modules[i], &info, sizeof(info)))
                SymLoadModuleExW(process.hProcess, nullptr, path, nullptr, reinterpret_cast<DWORD64>(info.lpBaseOfDll), info.SizeOfImage, nullptr, 0);
        }
    }
    std::map<DWORD, unsigned long long> previous;
    std::vector<Sample> samples;
    while (WaitForSingleObject(process.hProcess, 10) == WAIT_TIMEOUT)
    {
        HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
        THREADENTRY32 entry{sizeof(entry)};
        if (Thread32First(snapshot, &entry)) do
        {
            if (entry.th32OwnerProcessID != process.dwProcessId) continue;
            HANDLE thread = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, entry.th32ThreadID);
            if (!thread) continue;
            FILETIME created{}, exited{}, kernel{}, user{};
            GetThreadTimes(thread, &created, &exited, &kernel, &user);
            auto total = ticks(kernel) + ticks(user);
            auto delta = total - previous[entry.th32ThreadID];
            previous[entry.th32ThreadID] = total;
            if (delta && SuspendThread(thread) != DWORD(-1))
            {
                CONTEXT context{}; context.ContextFlags = CONTEXT_FULL;
                if (GetThreadContext(thread, &context))
                {
                    STACKFRAME64 frame{};
                    frame.AddrPC = {context.Rip, 0, AddrModeFlat};
                    frame.AddrFrame = {context.Rbp, 0, AddrModeFlat};
                    frame.AddrStack = {context.Rsp, 0, AddrModeFlat};
                    Sample sample{{context.Rip}, delta / 1e7};
                    for (int depth = 0; depth < 48; ++depth)
                    {
                        if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, process.hProcess, thread, &frame, &context, nullptr, SymFunctionTableAccess64, SymGetModuleBase64, nullptr) || !frame.AddrPC.Offset) break;
                        if (frame.AddrPC.Offset != sample.stack.back()) sample.stack.push_back(frame.AddrPC.Offset);
                    }
                    samples.push_back(std::move(sample));
                }
                ResumeThread(thread);
            }
            CloseHandle(thread);
        } while (Thread32Next(snapshot, &entry));
        CloseHandle(snapshot);
    }
    FILE* output = nullptr; _wfopen_s(&output, argv[1], L"w");
    std::map<DWORD64, std::string> names;
    std::map<std::string, double> inclusive, exclusive, stacks, lines;
    double total = 0;
    for (auto& sample : samples)
    {
        std::set<std::string> seen;
        std::string stack;
        for (auto address : sample.stack)
        {
            auto [it, inserted] = names.try_emplace(address);
            if (inserted)
            {
                char storage[sizeof(SYMBOL_INFO) + MAX_SYM_NAME]{};
                auto symbol = reinterpret_cast<SYMBOL_INFO*>(storage);
                symbol->SizeOfStruct = sizeof(SYMBOL_INFO); symbol->MaxNameLen = MAX_SYM_NAME;
                DWORD64 displacement;
                if (SymFromAddr(process.hProcess, address, &displacement, symbol)) it->second = symbol->Name;
                else { char text[40]; sprintf_s(text, "0x%llx", address); it->second = text; }
            }
            if (seen.insert(it->second).second) inclusive[it->second] += sample.seconds;
            if (!stack.empty()) stack += " <- "; else exclusive[it->second] += sample.seconds;
            stack += it->second;
        }
        IMAGEHLP_LINE64 line{sizeof(line)};
        DWORD displacement = 0;
        if (SymGetLineFromAddr64(process.hProcess, sample.stack.front(), &displacement, &line))
            lines[std::string(line.FileName) + ":" + std::to_string(line.LineNumber)] += sample.seconds;
        stacks[stack] += sample.seconds; total += sample.seconds;
    }
    fprintf(output, "Samples: %zu, sampled thread CPU seconds: %.3f\n", samples.size(), total);
    for (const auto& group : {std::make_pair("INCLUSIVE", &inclusive), std::make_pair("EXCLUSIVE", &exclusive), std::make_pair("LINES", &lines), std::make_pair("STACKS", &stacks)})
    {
        std::vector<std::pair<double, std::string>> ordered;
        for (auto& [name, count] : *group.second) ordered.emplace_back(count, name);
        std::sort(ordered.rbegin(), ordered.rend());
        fprintf(output, "\n%s\n", group.first);
        for (size_t i = 0; i < std::min<size_t>(ordered.size(), 100); ++i)
            fprintf(output, "%7.2f%% %9.3f %s\n", ordered[i].first / total * 100, ordered[i].first, ordered[i].second.c_str());
    }
    fclose(output);
    DWORD code; GetExitCodeProcess(process.hProcess, &code);
    SymCleanup(process.hProcess); CloseHandle(process.hThread); CloseHandle(process.hProcess); CloseHandle(log);
    return static_cast<int>(code);
}
