const vscode = require('vscode');
const providers = require('./src/providers');

function activate(context)
{
    context.subscriptions.push(vscode.tasks.registerTaskProvider("swag-build", new providers.TaskProvider()));
}

function deactivate()
{
}

module.exports = {
	activate,
	deactivate
}
