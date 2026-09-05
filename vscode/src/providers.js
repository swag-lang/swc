const vscode = require('vscode');

function createTask(command, definition, scope, name)
{
    let args;
    switch (command)
    {
        case 'build':
            args = ['build', '--workspace', '${workspaceFolder}'];
            break;
        case 'rebuild':
            args = ['build', '--workspace', '${workspaceFolder}', '--rebuild'];
            break;
        case 'format':
            args = ['format', '--file', '${file}'];
            break;
        default:
            return undefined;
    }

    args.push('--diagnostic-one-line', '--path-display', 'absolute', '--no-log-color');

    // Paths are individual process arguments, including after VSCode expands its variables.
    const execution = new vscode.ProcessExecution('swc', args);
    const task = new vscode.Task(definition, scope, name, 'swag', execution, '$swag');
    if (command !== 'format')
        task.group = vscode.TaskGroup.Build;
    task.presentationOptions.clear = true;
    task.presentationOptions.close = true;
    return task;
}

class TaskProvider
{
    provideTasks()
    {
        return ['build', 'rebuild', 'format'].map(command =>
            createTask(command, {type: 'swag-build', command}, vscode.TaskScope.Workspace, command));
    }

    resolveTask(task)
    {
        return createTask(task.definition.command, task.definition, task.scope, task.name);
    }
};

module.exports = {
    TaskProvider
}
