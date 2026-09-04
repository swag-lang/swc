const vscode = require('vscode');

////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////

let buildTasks = [];

function registerTask(cmdLine, name, taskGroup)
{
    var execution = new vscode.ShellExecution(cmdLine);
    let task = new vscode.Task({type: "swag-build", cmdLine: cmdLine}, vscode.TaskScope.Workspace, name, "swag", execution, '$swag');
    task.group = taskGroup;
    task.presentationOptions.clear = true;
    task.presentationOptions.close = true;
    buildTasks.push(task);
}

class TaskProvider
{
    provideTasks()
    {
        registerTask("swag build -w:${workspaceFolder}",             "build",    vscode.TaskGroup.Build);
        registerTask("swag build -w:${workspaceFolder} --rebuild",   "rebuild",  vscode.TaskGroup.Rebuild);
        registerTask("swag format -f:${file}",                       "format",   vscode.TaskGroup.Clean);
        return buildTasks;
    }

    resolveTask(task)
    {
        return task;
    }
}

module.exports = {
    TaskProvider
}
