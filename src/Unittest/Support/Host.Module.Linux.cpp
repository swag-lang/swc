// Native shared-library fixture for the compiler host loader, not a generated-code ABI test.
extern "C" int swcLinuxHostAdd(const int left, const int right)
{
    return left + right;
}
