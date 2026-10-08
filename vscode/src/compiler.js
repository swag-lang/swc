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
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'swag-lsp-'));
    try
    {
        const overlay = path.join(directory, 'buffers');
        const index = path.join(directory, 'index.json');
        const selected = documents.filter(document =>
        {
            const key = pathKey(fileURLToPath(document.uri));
            return project.args[0] === '--file' ? key === project.key : key.startsWith(project.key + '/');
        });
        await fs.writeFile(overlay, overlayBuffer(selected));
        const args = ['sema', ...project.args];
        for (const directory of await standardApiDirectories(project, options.compilerPath || 'swc'))
            args.push('--import-api-dir', directory);
        args.push(
            '--editor-overlay', overlay, '--editor-index', index,
            '--out-dir', path.join(directory, 'output'), '--work-dir', path.join(directory, 'work'),
            '--num-cores', '6', '--diagnostic-one-line', '--path-display', 'absolute', '--no-log-color');
        let execution;
        try { execution = await runCompiler(options.compilerPath || 'swc', args, project.directory, signal); }
        catch (error)
        {
            if (error.code === 'ENOENT')
                throw new Error(`Cannot find the Swag compiler '${options.compilerPath || 'swc'}'; make it available on PATH and restart VS Code, or set swag.compilerPath to its executable`);
            throw error;
        }
        const {code, output} = execution;
        if (signal.aborted) return undefined;
        let snapshot;
        try { snapshot = JSON.parse(await fs.readFile(index, 'utf8')); }
        catch (error)
        {
            throw new Error(`Swag produced no editor snapshot; check the compiler output and --editor-index support\n${output || error.message}`);
        }
        if (snapshot.version !== 1 || !Array.isArray(snapshot.files))
            throw new Error('The compiler editor snapshot version is not supported');
        return {snapshot, output, code};
    }
    finally
    {
        await fs.rm(directory, {recursive: true, force: true});
    }
}

module.exports = {analyze, projectFor, standardApiDirectories, pathKey, overlayBuffer, pathToFileURL, runCompiler};
