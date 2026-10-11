const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {spawn} = require('node:child_process');
const {fileURLToPath, pathToFileURL} = require('node:url');

function pathKey(value)
{
    const normalized = path.resolve(value).replaceAll('\\', '/');
    return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

async function projectFor(uri)
{
    const file = fileURLToPath(uri);
    for (let directory = path.dirname(file); ; directory = path.dirname(directory))
    {
        try
        {
            await fs.access(path.join(directory, 'module.swg'));
            return {key: pathKey(directory), directory, args: ['--module', directory]};
        }
        catch (error)
        {
            if (error.code !== 'ENOENT') throw error;
        }
        if (path.dirname(directory) === directory) break;
    }
    return {key: pathKey(file), directory: path.dirname(file), args: ['--file', file]};
}

async function standardApiDirectories(project, compilerPath)
{
    const directories = new Map();
    const add = async directory =>
    {
        if (!directory) return;
        const normalized = path.resolve(directory);
        try
        {
            if ((await fs.stat(normalized)).isDirectory()) directories.set(pathKey(normalized), normalized);
        }
        catch (error) { if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error; }
    };

    const addInstallRoot = async root =>
    {
        if (root) await add(path.join(root, 'std', '.output'));
    };
    await addInstallRoot(process.env.SWAG_PATH);

    for (let directory = project.directory; ; directory = path.dirname(directory))
    {
        if (path.basename(directory).toLowerCase() === 'std')
        {
            try
            {
                await fs.access(path.join(directory, 'modules'));
                await add(path.join(directory, '.output'));
            }
            catch (error) { if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error; }
        }
        if (path.dirname(directory) === directory) break;
    }

    let executablePaths = [];
    if (path.isAbsolute(compilerPath) || compilerPath.includes(path.sep) || compilerPath.includes('/'))
        executablePaths.push(path.resolve(compilerPath));
    else
    {
        const executable = process.platform === 'win32' && !path.extname(compilerPath) ? `${compilerPath}.exe` : compilerPath;
        executablePaths = (process.env.PATH || '').split(path.delimiter).filter(Boolean).map(directory => path.join(directory, executable));
    }
    for (const executable of executablePaths)
    {
        try
        {
            await fs.access(executable);
            await addInstallRoot(path.dirname(executable));
            break;
        }
        catch (error) { if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error; }
    }

    return [...directories.values()];
}

function overlayBuffer(documents)
{
    const parts = [Buffer.from('SWAG-EDITOR-1\n')];
    for (const document of documents)
    {
        for (const text of [fileURLToPath(document.uri), document.getText()])
        {
            const bytes = Buffer.from(text, 'utf8');
            parts.push(Buffer.from(`${bytes.length}\n`), bytes);
        }
    }
    return Buffer.concat(parts);
}

function runCompiler(executable, args, cwd, signal)
{
    return new Promise((resolve, reject) =>
    {
        if (signal.aborted) { reject(new Error('Analysis cancelled')); return; }
        const child = spawn(executable, args, {cwd, windowsHide: true, shell: false, detached: process.platform !== 'win32'});
        const cancel = () =>
        {
            if (!child.pid || child.exitCode !== null) return;
            // Module setup can start helpers. Stop the analysis tree before removing its files.
            if (process.platform === 'win32')
            {
                const killer = spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], {windowsHide: true, stdio: 'ignore'});
                killer.on('error', () => child.kill());
            }
            else
            {
                try { process.kill(-child.pid, 'SIGKILL'); }
                catch (error) { if (error.code !== 'ESRCH') child.kill(); }
            }
        };
        signal.addEventListener('abort', cancel, {once: true});
        let output = '';
        // A runaway compile-time program cannot fill the language server's memory.
        const append = chunk => { output = (output + chunk).slice(-4 * 1024 * 1024); };
        child.stdout.setEncoding('utf8').on('data', append);
        child.stderr.setEncoding('utf8').on('data', append);
        let error;
        child.on('error', value => { error = value; });
        child.on('close', (code, killed) =>
        {
            signal.removeEventListener('abort', cancel);
            if (error) reject(error);
            else if (signal.aborted || killed) reject(new Error('Analysis cancelled'));
            else resolve({code, output});
        });
    });
}

async function analyze(project, documents, options, signal)
{
    if (signal.aborted) return undefined;
    const service = await getEditorService(project, options);
    return service.analyze(documents, signal);
}

const editorServices = new Map();
let nextRequestId = 1;
const EDITOR_SERVICE_IDLE_TIMEOUT = 10 * 60 * 1000;

async function getEditorService(project, options)
{
    const compilerPath = options.compilerPath || 'swc';
    const key = `${project.key}\0${compilerPath}`;
    let servicePromise = editorServices.get(key);
    if (!servicePromise)
    {
        servicePromise = EditorService.create(key, project, compilerPath);
        editorServices.set(key, servicePromise);
        try
        {
            const service = await servicePromise;
            service.onClose = () =>
            {
                if (editorServices.get(key) === servicePromise)
                    editorServices.delete(key);
            };
            if (service.closeResult)
                throw new Error('Swag editor service exited before accepting requests');
        }
        catch (error)
        {
            if (editorServices.get(key) === servicePromise)
                editorServices.delete(key);
            throw error;
        }
    }

    const service = await servicePromise;
    if (service.closeResult)
        throw new Error('Swag editor service exited before accepting requests');
    return service;
}

class EditorService
{
    static async create(key, project, compilerPath)
    {
        const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'swag-lsp-'));
        const service = new EditorService(key, project, compilerPath, directory);
        try
        {
            await service.start();
            return service;
        }
        catch (error)
        {
            await service.dispose();
            if (error.code === 'ENOENT')
                throw new Error(`Cannot find the Swag compiler '${compilerPath}'; make it available on PATH and restart VS Code, or set swag.compilerPath to its executable`);
            throw error;
        }
    }

    constructor(key, project, compilerPath, directory)
    {
        Object.assign(this, {key, project, compilerPath, directory});
        this.overlay = path.join(directory, 'buffers');
        this.index = path.join(directory, 'index.json');
        this.request = undefined;
        this.stdoutBuffer = '';
        this.stderrBuffer = '';
        this.disposed = false;
        this.readyStreams = new Set();
        this.touch();
    }

    touch()
    {
        clearTimeout(this.idleTimer);
        if (this.disposed) return;
        this.idleTimer = setTimeout(() => { void this.dispose(); }, EDITOR_SERVICE_IDLE_TIMEOUT);
        this.idleTimer.unref?.();
    }

    async start()
    {
        const args = ['sema', ...this.project.args];
        for (const directory of await standardApiDirectories(this.project, this.compilerPath))
            args.push('--import-api-dir', directory);
        args.push(
            '--editor-service', '--editor-overlay', this.overlay, '--editor-index', this.index,
            '--out-dir', path.join(this.directory, 'output'), '--work-dir', path.join(this.directory, 'work'),
            '--num-cores', '6', '--diagnostic-one-line', '--path-display', 'absolute', '--no-log-color');
        this.ready = new Promise((resolve, reject) => { this.resolveReady = resolve; this.rejectReady = reject; });
        this.child = spawn(this.compilerPath, args, {
            cwd: this.project.directory, windowsHide: true, shell: false,
            detached: process.platform !== 'win32', stdio: ['pipe', 'pipe', 'pipe']
        });
        this.child.stdout.setEncoding('utf8').on('data', chunk => this.onData('stdout', chunk));
        this.child.stderr.setEncoding('utf8').on('data', chunk => this.onData('stderr', chunk));
        this.child.on('error', error =>
        {
            this.rejectReady(error);
            this.fail(error);
        });
        this.closed = new Promise(resolve => this.child.on('close', (code, signal) =>
        {
            this.closeResult = {code, signal};
            const error = new Error(`Swag editor service exited${code === null ? ` (${signal || 'unknown signal'})` : ` with code ${code}`}`);
            this.rejectReady(error);
            this.fail(error);
            this.disposed = true;
            this.onClose?.();
            void fs.rm(this.directory, {recursive: true, force: true}).catch(() => {});
            resolve(this.closeResult);
        }));
        await this.ready;
    }

    onData(stream, chunk)
    {
        const bufferName = stream === 'stdout' ? 'stdoutBuffer' : 'stderrBuffer';
        this[bufferName] += chunk;
        let newline;
        while ((newline = this[bufferName].indexOf('\n')) >= 0)
        {
            const line = this[bufferName].slice(0, newline).replace(/\r$/, '');
            this[bufferName] = this[bufferName].slice(newline + 1);
            this.onLine(stream, line);
        }
    }

    onLine(stream, line)
    {
        if (line === 'SWAG-EDITOR-SERVICE\t1\tREADY')
        {
            this.readyStreams.add(stream);
            if (this.readyStreams.size === 2) this.resolveReady();
            return;
        }
        const marker = /^SWAG-EDITOR-SERVICE\t1\t(\d+)\t(-?\d+)$/.exec(line);
        if (marker && this.request && Number(marker[1]) === this.request.id)
        {
            this.request[stream] = true;
            if (stream === 'stdout') this.request.code = Number(marker[2]);
            if (!this.request.stdout || !this.request.stderr) return;
            const request = this.request;
            this.request = undefined;
            request.resolve({output: request.output, code: request.code});
            return;
        }
        if (this.request)
            this.request.output = `${this.request.output}${line}\n`.slice(-4 * 1024 * 1024);
        else if (line)
            this.startupOutput = `${this.startupOutput ?? ''}${line}\n`.slice(-1024 * 1024);
    }

    fail(error)
    {
        if (!this.request) return;
        const request = this.request;
        this.request = undefined;
        request.reject(error);
    }

    async analyze(documents, signal)
    {
        if (this.disposed) throw new Error('Swag editor service is closed');
        if (signal.aborted) return undefined;
        this.touch();
        const selected = documents.filter(document =>
        {
            const key = pathKey(fileURLToPath(document.uri));
            return this.project.args[0] === '--file' ? key === this.project.key : key.startsWith(this.project.key + '/');
        });
        await fs.writeFile(this.overlay, overlayBuffer(selected));
        await fs.rm(this.index, {force: true});
        const id = nextRequestId++;
        const execution = new Promise((resolve, reject) =>
        {
            this.request = {id, output: this.startupOutput ?? '', stdout: false, stderr: false, resolve, reject};
            this.startupOutput = '';
            this.child.stdin.write(`analyze\t${id}\n`, error => { if (error) this.fail(error); });
        });
        let abort;
        const cancelled = new Promise(resolve =>
        {
            abort = () => resolve(undefined);
            signal.addEventListener('abort', abort, {once: true});
            if (signal.aborted) abort();
        });
        const result = await Promise.race([execution, cancelled]);
        signal.removeEventListener('abort', abort);
        if (signal.aborted)
        {
            await this.terminate();
            return undefined;
        }
        if (!result) return undefined;
        let snapshot;
        try { snapshot = JSON.parse(await fs.readFile(this.index, 'utf8')); }
        catch (error)
        {
            throw new Error(`Swag produced no editor snapshot; check the compiler output and --editor-index support\n${result.output || error.message}`);
        }
        if (snapshot.version !== 1 || !Array.isArray(snapshot.files))
            throw new Error('The compiler editor snapshot version is not supported');
        this.touch();
        return {snapshot, output: result.output, code: result.code};
    }

    async terminate()
    {
        if (!this.child || this.closeResult) return;
        const child = this.child;
        if (child.pid)
        {
            if (process.platform === 'win32')
            {
                const killer = spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], {windowsHide: true, stdio: 'ignore'});
                killer.on('error', () => child.kill());
            }
            else
            {
                try { process.kill(-child.pid, 'SIGKILL'); }
                catch (error) { if (error.code !== 'ESRCH') child.kill(); }
            }
        }
        await this.closed;
        this.onClose?.();
        await fs.rm(this.directory, {recursive: true, force: true});
        this.disposed = true;
    }

    async dispose()
    {
        if (this.disposed) return;
        this.disposed = true;
        clearTimeout(this.idleTimer);
        this.onClose?.();
        if (this.child && !this.closeResult)
        {
            this.child.stdin.end('shutdown\n');
            await this.closed;
        }
        this.onClose?.();
        await fs.rm(this.directory, {recursive: true, force: true});
    }
}

async function dispose()
{
    const services = [...editorServices.values()];
    editorServices.clear();
    await Promise.allSettled(services.map(service => service.then(value => value.dispose())));
}

module.exports = {analyze, dispose, projectFor, standardApiDirectories, pathKey, overlayBuffer, pathToFileURL, runCompiler};
