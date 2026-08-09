#global namespace Tool

// Every source a repository tool is made of.
//
// An entry point loads this one file and nothing else: `#load` nests, so the list lives here
// rather than being restated by each of the sixteen tools.
#load("arguments.swg")
#load("args.swg")
#load("context.swg")
#load("backlog.swg")
#load("portability.swg")
#load("scope.swg")
#load("suites.swg")
#load("workspaces.swg")
#load("campaign.swg")
#load("maintenance.swg")
#load("usage.swg")
#load("entry.swg")
