extern "C" {
__declspec(noinline) unsigned long long loadPair(const unsigned long long* p, unsigned long long a, unsigned long long b) { return p[0] + p[1]; }
__declspec(noinline) unsigned long long loadRepeated(const unsigned long long* p, unsigned long long a, unsigned long long b) { return p[0] * a + p[0]; }
__declspec(noinline) unsigned long long loadScaled(const unsigned long long* p, unsigned long long a, unsigned long long b) { return p[a] + b; }
__declspec(noinline) unsigned long long loadScaledOffset(const unsigned long long* p, unsigned long long a, unsigned long long b) { return p[a + 3] + b; }
__declspec(noinline) unsigned long long loadNarrow(const unsigned char* p, unsigned long long a, unsigned long long b) { return (unsigned long long) p[a] + b; }
__declspec(noinline) long long loadSigned(const short* p, unsigned long long a, long long b) { return (long long) p[a] + b; }
__declspec(noinline) unsigned long long maskedLoad(const unsigned long long* p, unsigned long long a, unsigned long long b) { return p[0] & 0xFF; }
__declspec(noinline) unsigned long long shiftedLoad(const unsigned long long* p, unsigned long long a, unsigned long long b) { return (p[0] >> 16) & 0xFF; }
__declspec(noinline) unsigned long long selectLoad(const unsigned long long* p, unsigned long long a, unsigned long long b) { return a != 0 ? p[0] : p[1]; }
__declspec(noinline) unsigned long long loadCompare(const unsigned long long* p, unsigned long long a, unsigned long long b) { return p[0] < a ? b : 0; }
__declspec(noinline) unsigned long long loadBit(const unsigned long long* p, unsigned long long a, unsigned long long b) { return (p[0] & 1) != 0 ? a : b; }
__declspec(noinline) unsigned long long loadSum4(const unsigned long long* p, unsigned long long a, unsigned long long b) { return p[0] + p[1] + p[2] + p[3]; }
__declspec(noinline) unsigned long long storeReload(unsigned long long* p, unsigned long long a, unsigned long long b) { p[0]=a; return p[0]+b; }
__declspec(noinline) unsigned long long storeNarrow(unsigned char* p, unsigned long long a, unsigned long long b) { p[0]=(unsigned char)a; return (unsigned long long)p[0]+b; }
__declspec(noinline) unsigned long long updateMemory(unsigned long long* p, unsigned long long a, unsigned long long b) { p[0]+=a; return p[0]+b; }
__declspec(noinline) unsigned long long accumulate(const unsigned long long* p, unsigned long long a, unsigned long long b) { unsigned long long result=b; for(unsigned long long i=0;i<a;i++) result+=p[i]; return result; }
}
