## Running workflow locally

You'll need to install `act` from https://github.com/nektos/act
see https://github.com/nektos/act#installation

on macOS you can use: 
`brew install act` 

run specific job with workflow_dispatch
`act -r --job ci --container-architecture linux/amd64 workflow_dispatch`

