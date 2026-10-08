const vscode = require('vscode');
const providers = require('./src/providers');
const {LanguageClient, TransportKind} = require('vscode-languageclient/node');

let client;

function activate(context)
{
    context.subscriptions.push(vscode.tasks.registerTaskProvider("swag-build", new providers.TaskProvider()));
    const watcher = vscode.workspace.createFileSystemWatcher('**/*.{swg,swgs}');
    context.subscriptions.push(watcher);

    async function start()
    {
        if (client || !vscode.workspace.isTrusted) return;
        const config = vscode.workspace.getConfiguration('swag');
        if (!config.get('languageServer.enabled', true)) return;
        client = new LanguageClient('swag', 'Swag Language Server',
            {module: context.asAbsolutePath('src/server.js'), transport: TransportKind.ipc},
            {
                documentSelector: [{scheme: 'file', language: 'swag'}],
                synchronize: {fileEvents: watcher},
                initializationOptions: {
                    compilerPath: config.get('compilerPath', 'swc'),
                    analysisDelay: config.get('languageServer.analysisDelay', 500),
                    analysisTimeout: config.get('languageServer.analysisTimeout', 60000)
                }
            });
        try { await client.start(); }
        catch (error)
        {
            await client.dispose();
            client = undefined;
            vscode.window.showErrorMessage(`Cannot start the Swag language server: ${error.message}`);
        }
    }

    let restart = Promise.resolve();
    context.subscriptions.push(vscode.workspace.onDidGrantWorkspaceTrust(() => start()));
    context.subscriptions.push(vscode.workspace.onDidChangeConfiguration(event =>
    {
        if (event.affectsConfiguration('swag'))
            restart = restart.then(async () => { await deactivate(); await start(); });
    }));
    context.subscriptions.push(vscode.commands.registerCommand('swag.restartLanguageServer', () =>
        restart = restart.then(async () => { await deactivate(); await start(); })));
    return start();
}

async function deactivate()
{
    const current = client;
    client = undefined;
    await current?.dispose();
}

module.exports = {
	activate,
	deactivate
}
