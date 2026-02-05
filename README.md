# project-analysis

## Process

1. Identify the repository root on disk (Windows 11 workstation)
2. Identify the Git HEAD commit hash
3. Scan the repository for all Microsoft Visual Studio Professional 2022 Solution (`*.sln`) and Project (`*.csproj`) files
4. For each Solution and Project found, create a Container record: GUID, Type (Solution or Project), Name, Path on disk
5