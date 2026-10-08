const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const {runCompiler} = require('../src/compiler');

test('cancelling analysis reaps its helper process before releasing the result', {timeout: 10000}, async () =>
{
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'swag-process-test-'));
    const ready = path.join(root, 'ready');
    const controller = new AbortController();
    const script = `const {spawn} = require('node:child_process');
        const helper = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {stdio: 'inherit'});
        require('node:fs').writeFileSync(process.argv[1], String(helper.pid));
        setInterval(() => {}, 1000);`;
    const execution = runCompiler(process.execPath, ['-e', script, ready], root, controller.signal);
    const cancelled = assert.rejects(execution, /cancelled/);
    try
    {
        let pid;
        const deadline = Date.now() + 5000;
        while (!pid && Date.now() < deadline)
        {
            try { pid = Number(await fs.readFile(ready, 'utf8')); }
            catch (error) { if (error.code !== 'ENOENT') throw error; }
            if (!pid) await new Promise(resolve => setTimeout(resolve, 10));
        }
        assert.ok(pid, 'the analysis helper did not start');
        controller.abort();
        await cancelled;
        assert.throws(() => process.kill(pid, 0), {code: 'ESRCH'});
    }
    finally
    {
        controller.abort();
        await execution.catch(() => {});
        await fs.rm(root, {recursive: true, force: true});
    }
});
