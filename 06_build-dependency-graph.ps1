# 06_build-dependency-graph.ps1
# Builds a dependency graph from solutions, projects, and assemblies

<#
.SYNOPSIS
    Builds a dependency graph from solutions, projects, and assemblies.

.DESCRIPTION
    Reads solution, project, and assembly information to create dependency edges.
    Analyzes actual solution and project files to determine relationships.
    Creates two types of dependencies:
    - Project-level dependencies (Solution-to-Project, Project-to-Project)
    - Assembly-level dependencies (Assembly-to-Assembly, based on project references)
    
    Outputs:
    - 06_dependency-edges.csv: All project-level edges
    - 06_assembly-dependency-edges.csv: All assembly-level edges

.PARAMETER SolutionsInfoFile
    Path to solutions-info.csv. Defaults to 03_solutions-info.csv in scan folder.

.PARAMETER ProjectsInfoFile
    Path to projects-info.csv. Defaults to 04_projects-info.csv in scan folder.

.PARAMETER AssembliesInfoFile
    Path to assemblies-info.csv. Defaults to 05_assemblies-info.csv in scan folder.

.PARAMETER ProjectEdgesOutputFile
    Path to output project edges CSV. Defaults to "06_dependency-edges.csv".

.PARAMETER AssemblyEdgesOutputFile
    Path to output assembly edges CSV. Defaults to "06_assembly-dependency-edges.csv".

.EXAMPLE
    .\06_build-dependency-graph.ps1
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SolutionsInfoFile,
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectsInfoFile,
    
    [Parameter(Mandatory=$false)]
    [string]$AssembliesInfoFile,
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectEdgesOutputFile,
    
    [Parameter(Mandatory=$false)]
    [string]$AssemblyEdgesOutputFile
)

# Determine scan folder and input/output paths
$scanFolder = $env:CURRENT_SCAN_FOLDER
if ([string]::IsNullOrWhiteSpace($scanFolder) -or -not (Test-Path -Path $scanFolder)) {
    Write-Warning "Current scan folder not found. Using current directory for input/output."
    $scanFolder = $PSScriptRoot
}

# Set default paths if not provided
if ([string]::IsNullOrWhiteSpace($SolutionsInfoFile)) {
    $SolutionsInfoFile = Join-Path -Path $scanFolder -ChildPath "03_solutions-info.csv"
}

if ([string]::IsNullOrWhiteSpace($ProjectsInfoFile)) {
    $ProjectsInfoFile = Join-Path -Path $scanFolder -ChildPath "04_projects-info.csv"
}

if ([string]::IsNullOrWhiteSpace($AssembliesInfoFile)) {
    $AssembliesInfoFile = Join-Path -Path $scanFolder -ChildPath "05_assemblies-info.csv"
}

if ([string]::IsNullOrWhiteSpace($ProjectEdgesOutputFile)) {
    $ProjectEdgesOutputFile = Join-Path -Path $scanFolder -ChildPath "06_dependency-edges.csv"
}

if ([string]::IsNullOrWhiteSpace($AssemblyEdgesOutputFile)) {
    $AssemblyEdgesOutputFile = Join-Path -Path $scanFolder -ChildPath "06_assembly-dependency-edges.csv"
}

# Main script execution
Write-Host "Building dependency graph..." -ForegroundColor Cyan
Write-Host ""

# Load CSV files
$solutions = @()
$projects = @()
$assemblies = @()

if (Test-Path -Path $SolutionsInfoFile) {
    $solutions = Import-Csv -Path $SolutionsInfoFile
    Write-Host "Loaded $($solutions.Count) solution(s)" -ForegroundColor Green
} else {
    Write-Warning "Solutions info file not found: $SolutionsInfoFile"
}

if (Test-Path -Path $ProjectsInfoFile) {
    $projects = Import-Csv -Path $ProjectsInfoFile
    Write-Host "Loaded $($projects.Count) project(s)" -ForegroundColor Green
} else {
    Write-Warning "Projects info file not found: $ProjectsInfoFile"
}

if (Test-Path -Path $AssembliesInfoFile) {
    $assemblies = Import-Csv -Path $AssembliesInfoFile
    Write-Host "Loaded $($assemblies.Count) assembl(y|ies)" -ForegroundColor Green
} else {
    Write-Warning "Assemblies info file not found: $AssembliesInfoFile"
}

Write-Host ""

# Create lookup tables
$solutionByPath = @{}
$projectByPath = @{}
$projectByIdentifier = @{}
$assemblyByIdentifier = @{}

foreach ($solution in $solutions) {
    $normalizedPath = $solution.FilePath.ToLower().Replace('/', '\')
    $solutionByPath[$normalizedPath] = $solution
}

foreach ($project in $projects) {
    $normalizedPath = $project.FilePath.ToLower().Replace('/', '\')
    $projectByPath[$normalizedPath] = $project
    $projectByIdentifier[$project.UniqueIdentifier] = $project
}

foreach ($assembly in $assemblies) {
    $assemblyByIdentifier[$assembly.UniqueIdentifier] = $assembly
}

# Build PROJECT-LEVEL edges
Write-Host "Analyzing project dependencies..." -ForegroundColor Yellow
$projectEdges = @()
$projectEdgeSet = @{} # To avoid duplicates

# Solution-to-Project edges
foreach ($solution in $solutions) {
    $filePath = $solution.FilePath
    
    if (-not (Test-Path -Path $filePath)) {
        Write-Warning "Solution file not found: $filePath"
        continue
    }
    
    try {
        $content = Get-Content -Path $filePath -Raw -ErrorAction Stop
        $solutionDir = [System.IO.Path]::GetDirectoryName($filePath)
        
        $projectMatches = [regex]::Matches($content, 'Project\("[^"]+"\)\s*=\s*"[^"]+"\s*,\s*"([^"]+)"\s*,\s*"\{[0-9A-Fa-f\-]+\}"')
        
        foreach ($match in $projectMatches) {
            $relativePath = $match.Groups[1].Value
            if ($relativePath -match '\.csproj$') {
                $absolutePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($solutionDir, $relativePath))
                $normalizedPath = $absolutePath.ToLower().Replace('/', '\')
                
                if ($projectByPath.ContainsKey($normalizedPath)) {
                    $targetProject = $projectByPath[$normalizedPath]
                    $edgeKey = "$($solution.UniqueIdentifier)|$($targetProject.UniqueIdentifier)"
                    
                    if (-not $projectEdgeSet.ContainsKey($edgeKey)) {
                        $projectEdges += [PSCustomObject]@{
                            FromNodeId = $solution.UniqueIdentifier
                            FromNodeType = "Solution"
                            FromNodeName = $solution.Name
                            ToNodeId = $targetProject.UniqueIdentifier
                            ToNodeType = "Project"
                            ToNodeName = $targetProject.Name
                            DependencyType = "Project"
                            ReferenceType = "Solution-to-Project"
                        }
                        $projectEdgeSet[$edgeKey] = $true
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Error processing solution file '$filePath': $_"
    }
}

# Project-to-Project edges
foreach ($project in $projects) {
    $filePath = $project.FilePath
    
    if (-not (Test-Path -Path $filePath)) {
        Write-Warning "Project file not found: $filePath"
        continue
    }
    
    try {
        [xml]$projectXml = Get-Content -Path $filePath -Raw -ErrorAction Stop
        $projectDir = [System.IO.Path]::GetDirectoryName($filePath)
        
        $projectReferences = $projectXml.SelectNodes("//*[local-name()='ProjectReference']")
        
        foreach ($ref in $projectReferences) {
            $includeAttr = $ref.GetAttribute("Include")
            if ($includeAttr) {
                $absolutePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($projectDir, $includeAttr))
                $normalizedPath = $absolutePath.ToLower().Replace('/', '\')
                
                if ($projectByPath.ContainsKey($normalizedPath)) {
                    $targetProject = $projectByPath[$normalizedPath]
                    $edgeKey = "$($project.UniqueIdentifier)|$($targetProject.UniqueIdentifier)"
                    
                    if (-not $projectEdgeSet.ContainsKey($edgeKey)) {
                        $projectEdges += [PSCustomObject]@{
                            FromNodeId = $project.UniqueIdentifier
                            FromNodeType = "Project"
                            FromNodeName = $project.Name
                            ToNodeId = $targetProject.UniqueIdentifier
                            ToNodeType = "Project"
                            ToNodeName = $targetProject.Name
                            DependencyType = "Project"
                            ReferenceType = "Project-to-Project"
                        }
                        $projectEdgeSet[$edgeKey] = $true
                    }
                }
            }
        }
    }
    catch {
        Write-Warning "Error processing project file '$filePath': $_"
    }
}

Write-Host "Found $($projectEdges.Count) project-level edge(s)" -ForegroundColor Green
Write-Host ""

# Build ASSEMBLY-LEVEL edges (based on project-to-project relationships)
Write-Host "Analyzing assembly dependencies..." -ForegroundColor Yellow
$assemblyEdges = @()
$assemblyEdgeSet = @{} # To avoid duplicates

# Create mapping from project path to assembly
$projectPathToAssembly = @{}
foreach ($assembly in $assemblies) {
    # Assembly UniqueIdentifier is based on project path + assembly name
    # We need to find assemblies by matching the project they come from
    # For now, we'll match by assembly name to project name
    foreach ($project in $projects) {
        if ($project.Name -eq $assembly.Name -or 
            [System.IO.Path]::GetFileNameWithoutExtension($project.FilePath) -eq $assembly.Name) {
            $normalizedPath = $project.FilePath.ToLower().Replace('/', '\')
            if (-not $projectPathToAssembly.ContainsKey($normalizedPath)) {
                $projectPathToAssembly[$normalizedPath] = $assembly
            }
        }
    }
}

# Convert project-to-project edges into assembly-to-assembly edges
foreach ($projectEdge in $projectEdges) {
    if ($projectEdge.ReferenceType -eq "Project-to-Project") {
        # Find the source and target projects
        $sourceProject = $projectByIdentifier[$projectEdge.FromNodeId]
        $targetProject = $projectByIdentifier[$projectEdge.ToNodeId]
        
        if ($sourceProject -and $targetProject) {
            $sourceNormalizedPath = $sourceProject.FilePath.ToLower().Replace('/', '\')
            $targetNormalizedPath = $targetProject.FilePath.ToLower().Replace('/', '\')
            
            $sourceAssembly = $projectPathToAssembly[$sourceNormalizedPath]
            $targetAssembly = $projectPathToAssembly[$targetNormalizedPath]
            
            if ($sourceAssembly -and $targetAssembly) {
                $edgeKey = "$($sourceAssembly.UniqueIdentifier)|$($targetAssembly.UniqueIdentifier)"
                
                if (-not $assemblyEdgeSet.ContainsKey($edgeKey)) {
                    $assemblyEdges += [PSCustomObject]@{
                        FromNodeId = $sourceAssembly.UniqueIdentifier
                        FromNodeType = "Assembly"
                        FromNodeName = $sourceAssembly.Name
                        FromAssemblyFile = $sourceAssembly.AssemblyFileName
                        ToNodeId = $targetAssembly.UniqueIdentifier
                        ToNodeType = "Assembly"
                        ToNodeName = $targetAssembly.Name
                        ToAssemblyFile = $targetAssembly.AssemblyFileName
                        DependencyType = "Assembly"
                        ReferenceType = "Assembly-to-Assembly"
                    }
                    $assemblyEdgeSet[$edgeKey] = $true
                }
            }
        }
    }
}

Write-Host "Found $($assemblyEdges.Count) assembly-level edge(s)" -ForegroundColor Green
Write-Host ""

# Export project edges
if ($projectEdges.Count -gt 0) {
    $projectEdges | Export-Csv -Path $ProjectEdgesOutputFile -NoTypeInformation -Encoding UTF8
    Write-Host "Exported project dependencies to: $ProjectEdgesOutputFile" -ForegroundColor Green
} else {
    Write-Warning "No project edges to export."
}

# Export assembly edges
if ($assemblyEdges.Count -gt 0) {
    $assemblyEdges | Export-Csv -Path $AssemblyEdgesOutputFile -NoTypeInformation -Encoding UTF8
    Write-Host "Exported assembly dependencies to: $AssemblyEdgesOutputFile" -ForegroundColor Green
} else {
    Write-Warning "No assembly edges to export."
}

Write-Host ""

# Append summary to scan info file
if ($env:SCAN_INFO_FILE -and (Test-Path -Path $env:SCAN_INFO_FILE)) {
    $summary = "`n`n06_build-dependency-graph.ps1`n" + ("=" * 50) + "`nProject-level edges: $($projectEdges.Count)`n  Solution-to-Project: $(($projectEdges | Where-Object { $_.ReferenceType -eq 'Solution-to-Project' }).Count)`n  Project-to-Project: $(($projectEdges | Where-Object { $_.ReferenceType -eq 'Project-to-Project' }).Count)`nAssembly-level edges: $($assemblyEdges.Count)`nOutput files:`n  $ProjectEdgesOutputFile`n  $AssemblyEdgesOutputFile"
    $summary | Out-File -FilePath $env:SCAN_INFO_FILE -Append -Encoding UTF8
}

Write-Host "Dependency graph build complete!" -ForegroundColor Cyan

# Return edge counts for potential use by other scripts
return @{
    ProjectEdges = $projectEdges.Count
    AssemblyEdges = $assemblyEdges.Count
}
