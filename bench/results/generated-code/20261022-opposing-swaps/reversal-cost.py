import json,collections
from pathlib import Path
n=9; p=list(range(n)); counts=[0]*n; r=n; checksum=maximum=permutation=0; hist=collections.Counter()
while True:
    while r!=1: counts[r-1]=r; r-=1
    work=p.copy(); flips=0; k=work[0]
    while k:
        hist[k]+=1
        i=0;j=k
        while i<j: work[i],work[j]=work[j],work[i];i+=1;j-=1
        flips+=1;k=work[0]
    maximum=max(maximum,flips);checksum+=flips if permutation%2==0 else -flips
    done=False
    while True:
        if r==n: done=True;break
        first=p[0]
        for i in range(r): p[i]=p[i+1]
        p[r]=first; counts[r]-=1
        if counts[r]>0: break
        r+=1
    if done:break
    permutation+=1
calls=sum(hist.values()); swaps=sum(((k+1)//2)*v for k,v in hist.items())
old=3*calls+8*swaps;new=2*calls+7*swaps
out={'checksum':checksum*1000+maximum,'permutations':permutation+1,'last_index_histogram':dict(hist),'reverse_entries':calls,'swaps':swaps,'before_executed_reverse_instructions':old,'after_executed_reverse_instructions':new,'saved':old-new,'fraction_saved':1-new/old,'memory_accesses_each':4*swaps,'note':'entry plus exchange and exit checks; excludes outer flip update/reload and alignment NOPs. k=1..8 uses no scalar tail.'}
print(json.dumps(out,indent=2))
assert out['checksum']==8629030
Path(r'C:/Users/chris/AppData/Local/swc-agent-builds/prompt2-20261022-1515/reversal-cost.json').write_text(json.dumps(out,indent=2)+'\n')
