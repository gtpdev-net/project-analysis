# 07_show-dependency-tree.ps1
# Displays dependency trees in ASCII format for each Solution

<#
.SYNOPSIS
    Displays dependency trees in ASCII format for each Solution.

.DESCRIPTION
    Reads solution, project, and dependency data to generate ASCII tree visualizations
    showing each Solution and its dependencies.
    Optionally includes project-to-project dependencies.
    
    Outputs:
    - 07_dependency-tree.txt: ASCII tree visualization of all solutions

.PARAMETER SolutionsInfoFile
    Path to solutions-info.csv. Defaults to 03_solutions-info.csv in scan folder.

.PARAMETER ProjectsInfoFile
    Path to projects-info.csv. Defaults to 04_projects-info.csv in scan folder.

.PARAMETER EdgesFile
    Path to dependency-edges.csv. Defaults to 06_dependency-edges.csv in scan folder.

.PARAMETER AssembliesInfoFile
    Path to assemblies-info.csv. Defaults to 05_assemblies-info.csv in scan folder.

.PARAMETER AssemblyEdgesFile
    Path to assembly-dependency-edges.csv. Defaults to 06_assembly-dependency-edges.csv in scan folder.

.PARAMETER OutputFile
    Path to output file. Defaults to "07_dependency-tree.txt" in scan folder.

.PARAMETER SolutionName
    Optional solution name to filter output. If specified, only shows the matching solution.

.PARAMETER ShowProjectDependencies
    Include project-to-project dependencies in the tree. Defaults to $true.

.PARAMETER ShowAssemblyDependencies
    Include assembly-level dependencies under each project. Defaults to $true.

.PARAMETER MaxDepth
    Maximum depth to traverse for project dependencies. Defaults to 3.

.EXAMPLE
    .\07_show-dependency-tree.ps1
    
.EXAMPLE
    .\07_show-dependency-tree.ps1 -SolutionName "MyApp" -MaxDepth 5
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SolutionsInfoFile,
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectsInfoFile,
    
    [Parameter(Mandatory=$false)]
    [string]$EdgesFile,
    
    [Parameter(Mandatory=$false)]
    [string]$AssembliesInfoFile,
    
    [Parameter(Mandatory=$false)]
    [string]$AssemblyEdgesFile,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile,
    
    [Parameter(Mandatory=$false)]
    [string]$SolutionName = "",
    
    [Parameter(Mandatory=$false)]
    [bool]$ShowProjectDependencies = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$ShowAssemblyDependencies = $true,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxDepth = 3
)

# Function to render a tree node
function Write-TreeNode {
    param(
        [string]$Text,
        [string]$Prefix = "",
        [bool]$IsLast = $false,
        [string]$Annotation = ""
    )
    
    $branch = if ($IsLast) { "+-- " } else { "|-- " }
    $line = "$Prefix$branch$Text"
    
    if ($Annotation) {
        $line += " $Annotation"
    }
    
    return $line
}

# Function to get continuation prefix
function Get-ContinuationPrefix {
    param(
        [string]$CurrentPrefix,
        [bool]$IsLast
    )
    
    if ($IsLast) {
        return "$CurrentPrefix    "
    } else {
        return "$CurrentPrefix|   "
    }
}

# Function to calculate shallowest depth for each node using BFS
function Get-ShallowestDepths {
    param(
        [string]$RootNodeId,
        [hashtable]$AdjacencyList
    )
    
    $depths = @{}
    $queue = New-Object System.Collections.Queue
    
    # Start with root at depth 0
    $queue.Enqueue(@{NodeId = $RootNodeId; Depth = 0})
    $depths[$RootNodeId] = 0
    
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $currentId = $current.NodeId
        $currentDepth = $current.Depth
        
        if ($AdjacencyList.ContainsKey($currentId)) {
            foreach ($childId in $AdjacencyList[$currentId]) {
                # Only record depth if this is the first time we see this node (shallowest)
                if (-not $depths.ContainsKey($childId)) {
                    $depths[$childId] = $currentDepth + 1
                    $queue.Enqueue(@{NodeId = $childId; Depth = $currentDepth + 1})
                }
            }
        }
    }
    
    return $depths
}

# Function to display assembly dependencies for a project
function Get-AssemblyDependencies {
    param(
        [string]$ProjectId,
        [hashtable]$ProjectToAssembly,
        [hashtable]$NodeLookup,
        [hashtable]$AssemblyAdjacencyList,
        [string]$Prefix = "",
        [int]$MaxDepth = 3,
        [hashtable]$VisitedAssemblies = @{},
        [int]$CurrentDepth = 0
    )
    
    $lines = @()
    
    if (-not $ProjectToAssembly.ContainsKey($ProjectId)) {
        return $lines
    }
    
    $assembly = $ProjectToAssembly[$ProjectId]
    $lines += Write-TreeNode -Text $assembly.AssemblyFileName -Prefix $Prefix -IsLast $false
    
    # Recurse into assembly dependencies
    $subLines = Get-AssemblyDependencyTree -AssemblyId $assembly.UniqueIdentifier -NodeLookup $NodeLookup -AssemblyAdjacencyList $AssemblyAdjacencyList -Prefix (Get-ContinuationPrefix -CurrentPrefix $Prefix -IsLast $false) -MaxDepth $MaxDepth -VisitedAssemblies $VisitedAssemblies -CurrentDepth $CurrentDepth
    $lines += $subLines
    
    return $lines
}

# Function to recursively display assembly dependency tree
function Get-AssemblyDependencyTree {
    param(
        [string]$AssemblyId,
        [hashtable]$NodeLookup,
        [hashtable]$AssemblyAdjacencyList,
        [string]$Prefix = "",
        [int]$MaxDepth = 3,
        [hashtable]$VisitedAssemblies = @{},
        [int]$CurrentDepth = 0
    )
    
    $lines = @()
    
    # Check for circular reference
    if ($VisitedAssemblies.ContainsKey($AssemblyId)) {
        return $lines
    }
    
    # Check max depth
    if ($CurrentDepth -ge $MaxDepth) {
        return $lines
    }
    
    # Mark as visited
    $newVisited = $VisitedAssemblies.Clone()
    $newVisited[$AssemblyId] = $true
    
    # Show assembly dependencies
    if ($AssemblyAdjacencyList.ContainsKey($AssemblyId)) {
        $assemblyDeps = $AssemblyAdjacencyList[$AssemblyId]
        
        if ($assemblyDeps.Count -gt 0) {
            $assemblyDeps = $assemblyDeps | Sort-Object { 
                if ($NodeLookup.ContainsKey($_)) { 
                    $NodeLookup[$_].Name 
                } else { 
                    $_ 
                } 
            }
            
            $depCount = $assemblyDeps.Count
            for ($i = 0; $i -lt $depCount; $i++) {
                $depId = $assemblyDeps[$i]
                $isLast = ($i -eq ($depCount - 1))
                
                if ($NodeLookup.ContainsKey($depId)) {
                    $depAssembly = $NodeLookup[$depId]
                    
                    # Check if this assembly was already visited (circular or duplicate)
                    $annotation = ""
                    if ($newVisited.ContainsKey($depId)) {
                        $annotation = "[*CIRCULAR*]"
                    }
                    
                    $lines += Write-TreeNode -Text $depAssembly.AssemblyFileName -Prefix $Prefix -IsLast $isLast -Annotation $annotation
                    
                    # Recurse only if not visited
                    if (-not $newVisited.ContainsKey($depId)) {
                        $newPrefix = Get-ContinuationPrefix -CurrentPrefix $Prefix -IsLast $isLast
                        $subLines = Get-AssemblyDependencyTree -AssemblyId $depId -NodeLookup $NodeLookup -AssemblyAdjacencyList $AssemblyAdjacencyList -Prefix $newPrefix -MaxDepth $MaxDepth -VisitedAssemblies $newVisited -CurrentDepth ($CurrentDepth + 1)
                        $lines += $subLines
                    }
                }
            }
        }
    }
    
    return $lines
}

# Function to build dependency tree recursively
function Get-DependencyTree {
    param(
        [string]$NodeId,
        [hashtable]$NodeLookup,
        [hashtable]$AdjacencyList,
        [hashtable]$ShallowestDepths,
        [string]$Prefix = "",
        [int]$CurrentDepth = 0,
        [hashtable]$VisitedInPath = @{},
        [hashtable]$ShownAtShallowest = @{},
        [int]$MaxDepth
    )
    
    $lines = @()
    
    # Check for circular reference within current path
    if ($VisitedInPath.ContainsKey($NodeId)) {
        return @("$Prefix    [CIRCULAR REFERENCE]")
    }
    
    # Check max depth
    if ($CurrentDepth -ge $MaxDepth) {
        return @("$Prefix    [MAX DEPTH REACHED]")
    }
    
    # Mark as visited in current path
    $newVisited = $VisitedInPath.Clone()
    $newVisited[$NodeId] = $true
    
    # Get dependencies
    if ($AdjacencyList.ContainsKey($NodeId)) {
        $dependencies = $AdjacencyList[$NodeId]
        
        # Sort dependencies alphabetically by name
        $dependencies = $dependencies | Sort-Object { 
            if ($NodeLookup.ContainsKey($_)) { 
                $NodeLookup[$_].Name 
            } else { 
                $_ 
            } 
        }
        
        $depCount = $dependencies.Count
        
        for ($i = 0; $i -lt $depCount; $i++) {
            $depId = $dependencies[$i]
            $isLast = ($i -eq ($depCount - 1))
            
            if ($NodeLookup.ContainsKey($depId)) {
                $depNode = $NodeLookup[$depId]
                $annotation = ""
                $shouldExpand = $false
                
                $depthToChild = $CurrentDepth + 1
                
                if ($newVisited.ContainsKey($depId)) {
                    $annotation = "[*CIRCULAR*]"
                } elseif ($ShownAtShallowest.ContainsKey($depId)) {
                    $annotation = "*"
                } elseif ($ShallowestDepths.ContainsKey($depId) -and $ShallowestDepths[$depId] -eq $depthToChild) {
                    # This is the shallowest occurrence, expand it
                    $shouldExpand = $true
                    $ShownAtShallowest[$depId] = $true
                } else {
                    # This is not the shallowest occurrence, just mark it
                    $annotation = "..."
                }
                
                $lines += Write-TreeNode -Text $depNode.Name -Prefix $Prefix -IsLast $isLast -Annotation $annotation
                
                # Show assembly dependencies if this is a project node and ShowAssemblyDependencies is enabled
                if ($depNode.Type -eq "Project" -and $script:ShowAssemblyDependenciesFlag) {
                    $newPrefix = Get-ContinuationPrefix -CurrentPrefix $Prefix -IsLast $isLast
                    $assemblyLines = Get-AssemblyDependencies -ProjectId $depId -ProjectToAssembly $script:ProjectToAssemblyMap -NodeLookup $NodeLookup -AssemblyAdjacencyList $script:AssemblyAdjacencyListGlobal -Prefix $newPrefix -MaxDepth $MaxDepth
                    $lines += $assemblyLines
                }
                
                # Recurse only if this is the shallowest occurrence and not circular
                if ($shouldExpand -and -not $newVisited.ContainsKey($depId)) {
                    $newPrefix = Get-ContinuationPrefix -CurrentPrefix $Prefix -IsLast $isLast
                    $subLines = Get-DependencyTree -NodeId $depId -NodeLookup $NodeLookup -AdjacencyList $AdjacencyList -ShallowestDepths $ShallowestDepths -Prefix $newPrefix -CurrentDepth $depthToChild -VisitedInPath $newVisited -ShownAtShallowest $ShownAtShallowest -MaxDepth $MaxDepth
                    $lines += $subLines
                }
            }
        }
    }
    
    return $lines
}

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

if ([string]::IsNullOrWhiteSpace($EdgesFile)) {
    $EdgesFile = Join-Path -Path $scanFolder -ChildPath "06_dependency-edges.csv"
}

if ([string]::IsNullOrWhiteSpace($AssembliesInfoFile)) {
    $AssembliesInfoFile = Join-Path -Path $scanFolder -ChildPath "05_assemblies-info.csv"
}

if ([string]::IsNullOrWhiteSpace($AssemblyEdgesFile)) {
    $AssemblyEdgesFile = Join-Path -Path $scanFolder -ChildPath "06_assembly-dependency-edges.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path -Path $scanFolder -ChildPath "07_dependency-tree.txt"
}

# Main script execution
Write-Host "Generating ASCII dependency trees..." -ForegroundColor Cyan
Write-Host ""

# Load solutions
$solutions = @()
if (Test-Path -Path $SolutionsInfoFile) {
    $solutions = Import-Csv -Path $SolutionsInfoFile
    Write-Host "Loaded $($solutions.Count) solution(s)" -ForegroundColor Green
} else {
    Write-Warning "Solutions info file not found: $SolutionsInfoFile"
}

# Load projects
$projects = @()
if (Test-Path -Path $ProjectsInfoFile) {
    $projects = Import-Csv -Path $ProjectsInfoFile
    Write-Host "Loaded $($projects.Count) project(s)" -ForegroundColor Green
} else {
    Write-Warning "Projects info file not found: $ProjectsInfoFile"
}

# Load assemblies
$assemblies = @()
if (Test-Path -Path $AssembliesInfoFile) {
    $assemblies = Import-Csv -Path $AssembliesInfoFile
    Write-Host "Loaded $($assemblies.Count) assembl(y|ies)" -ForegroundColor Green
} else {
    Write-Warning "Assemblies info file not found: $AssembliesInfoFile"
}

# Load project edges
$projectEdges = @()
if (Test-Path -Path $EdgesFile) {
    $projectEdges = Import-Csv -Path $EdgesFile
    Write-Host "Loaded $($projectEdges.Count) project edge(s)" -ForegroundColor Green
} else {
    Write-Warning "Project edges file not found: $EdgesFile"
}

# Load assembly edges
$assemblyEdges = @()
if (Test-Path -Path $AssemblyEdgesFile) {
    $assemblyEdges = Import-Csv -Path $AssemblyEdgesFile
    Write-Host "Loaded $($assemblyEdges.Count) assembly edge(s)" -ForegroundColor Green
} else {
    Write-Warning "Assembly edges file not found: $AssemblyEdgesFile"
}

if ($projectEdges.Count -eq 0 -and $assemblyEdges.Count -eq 0) {
    Write-Warning "No edges found."
    Write-Host "Dependency tree generation skipped." -ForegroundColor Yellow
    exit 0
}

Write-Host ""

# Build lookups - combine solutions, projects, and assemblies as nodes
$nodeLookup = @{}
$allNodes = @()

foreach ($solution in $solutions) {
    $nodeLookup[$solution.UniqueIdentifier] = $solution
    $allNodes += $solution
}

foreach ($project in $projects) {
    $nodeLookup[$project.UniqueIdentifier] = $project
    $allNodes += $project
}

foreach ($assembly in $assemblies) {
    $nodeLookup[$assembly.UniqueIdentifier] = $assembly
    $allNodes += $assembly
}

# Build project-to-assembly mapping
$projectToAssembly = @{}
foreach ($assembly in $assemblies) {
    # Match assemblies to projects by name
    foreach ($project in $projects) {
        if ($project.Name -eq $assembly.Name -or 
            [System.IO.Path]::GetFileNameWithoutExtension($project.FilePath) -eq $assembly.Name) {
            $projectToAssembly[$project.UniqueIdentifier] = $assembly
            break
        }
    }
}

# Build adjacency lists (separate for project and assembly levels)
$adjacencyList = @{}
$assemblyAdjacencyList = @{}

# Add project edges
foreach ($edge in $projectEdges) {
    if (-not $adjacencyList.ContainsKey($edge.FromNodeId)) {
        $adjacencyList[$edge.FromNodeId] = @()
    }
    $adjacencyList[$edge.FromNodeId] += $edge.ToNodeId
}

# Add assembly edges to separate list
foreach ($edge in $assemblyEdges) {
    if (-not $assemblyAdjacencyList.ContainsKey($edge.FromNodeId)) {
        $assemblyAdjacencyList[$edge.FromNodeId] = @()
    }
    $assemblyAdjacencyList[$edge.FromNodeId] += $edge.ToNodeId
}

# Filter solutions if SolutionName is specified
if ($SolutionName) {
    $filteredSolutions = $solutions | Where-Object { $_.Name -eq $SolutionName }
    
    if ($filteredSolutions.Count -eq 0) {
        Write-Warning "No solutions found matching: '$SolutionName'"
        Write-Host "Available solutions:" -ForegroundColor Yellow
        
        $displayCount = [Math]::Min(10, $solutions.Count)
        for ($i = 0; $i -lt $displayCount; $i++) {
            Write-Host "  - $($solutions[$i].Name)" -ForegroundColor Yellow
        }
        
        if ($solutions.Count -gt 10) {
            Write-Host "  ... and $($solutions.Count - 10) more" -ForegroundColor Gray
        }
        exit 0
    }
    
    $solutions = $filteredSolutions
    Write-Host "Filtered to $($solutions.Count) solution(s) matching '$SolutionName'" -ForegroundColor Green
    Write-Host ""
}

# Generate output
$output = @()
$output += ("=" * 80)
$output += "DEPENDENCY TREE VISUALIZATION"
$output += ("=" * 80)
$output += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$output += "Total Solutions: $($solutions.Count)"
$output += "Total Projects: $($projects.Count)"
$output += "Total Assemblies: $($assemblies.Count)"
$output += "Project Dependencies: $($projectEdges.Count)"
$output += "Assembly Dependencies: $($assemblyEdges.Count)"
$output += "Max Depth: $MaxDepth"
$output += "Show Project Dependencies: $ShowProjectDependencies"
$output += "Show Assembly Dependencies: $ShowAssemblyDependencies"

# Get git commit hash from environment
if ($env:REPOSITORY_PATH) {
    try {
        Push-Location -Path $env:REPOSITORY_PATH
        $gitHash = git rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $gitHash) {
            $output += "Commit Hash: $gitHash"
        }
        Pop-Location
    } catch {
        # Silently ignore if git command fails
        if ((Get-Location).Path -ne $PSScriptRoot) {
            Pop-Location
        }
    }
}

$output += ("=" * 80)
$output += ""

# Sort solutions alphabetically by name
$solutions = $solutions | Sort-Object -Property Name

# Set script-level variables for use in nested functions
$script:ShowAssemblyDependenciesFlag = $ShowAssemblyDependencies
$script:ProjectToAssemblyMap = $projectToAssembly
$script:AssemblyAdjacencyListGlobal = $assemblyAdjacencyList

# Process each solution
if ($solutions.Count -eq 0) {
    $output += "No solutions found in the data."
} else {
    foreach ($solution in $solutions) {
        $output += ""
        $output += "+-- SOLUTION: $($solution.Name)"
        $output += "|   Path: $($solution.FilePath)"
        $output += "|   GUID: $($solution.VisualStudioGUID)"
        $output += "|   Projects Referenced: $($solution.NumberOfReferencedProjects)"
        
        if ($solution.IsSingleProjectSolution -eq "True" -or $solution.IsSingleProjectSolution -eq $true) {
            $output += "|   [Single-Project Solution]"
        }
        
        $output += "|"
        
        # Get direct dependencies
        if ($adjacencyList.ContainsKey($solution.UniqueIdentifier)) {
            $dependencies = $adjacencyList[$solution.UniqueIdentifier]
            
            if ($dependencies.Count -eq 0) {
                $output += "+-- (No dependencies)"
            } else {
                # Calculate shallowest depths for all nodes from this solution
                $shallowestDepths = Get-ShallowestDepths -RootNodeId $solution.UniqueIdentifier -AdjacencyList $adjacencyList
                
                # Create tracking hashtable for nodes shown at their shallowest depth
                $shownAtShallowest = @{}
                
                $treeLines = Get-DependencyTree -NodeId $solution.UniqueIdentifier -NodeLookup $nodeLookup -AdjacencyList $adjacencyList -ShallowestDepths $shallowestDepths -Prefix "|" -ShownAtShallowest $shownAtShallowest -MaxDepth $MaxDepth
                $output += $treeLines
                $output += "+--"
            }
        } else {
            $output += "+-- (No dependencies)"
        }
        
        $output += ""
    }
}

# Add orphaned projects (projects not referenced by any solution)
$referencedProjects = @{}
foreach ($edge in $projectEdges) {
    if ($edge.FromNodeType -eq "Solution") {
        $referencedProjects[$edge.ToNodeId] = $true
    }
}

$orphanedProjects = $projects | Where-Object { -not $referencedProjects.ContainsKey($_.UniqueIdentifier) }

if ($orphanedProjects.Count -gt 0) {
    $output += ""
    $output += ("=" * 80)
    $output += "ORPHANED PROJECTS (Not referenced by any Solution)"
    $output += ("=" * 80)
    $output += ""
    
    foreach ($project in $orphanedProjects) {
        $output += "• $($project.Name)"
        $output += "  Path: $($project.FilePath)"
        $output += "  GUID: $($project.VisualStudioGUID)"
        
        if ($adjacencyList.ContainsKey($project.UniqueIdentifier)) {
            $depCount = $adjacencyList[$project.UniqueIdentifier].Count
            if ($depCount -gt 0) {
                $output += "  Dependencies: $depCount project(s)"
            }
        }
        
        $output += ""
    }
}

# Add summary statistics
$output += ""
$output += ("=" * 80)
$output += "STATISTICS"
$output += ("=" * 80)

$solutionToProjectEdges = ($projectEdges | Where-Object { $_.ReferenceType -eq "Solution-to-Project" }).Count
$projectToProjectEdges = ($projectEdges | Where-Object { $_.ReferenceType -eq "Project-to-Project" }).Count
$assemblyToAssemblyEdges = ($assemblyEdges | Where-Object { $_.ReferenceType -eq "Assembly-to-Assembly" }).Count

$output += "Solution -> Project references: $solutionToProjectEdges"
$output += "Project -> Project references: $projectToProjectEdges"
$output += "Assembly -> Assembly references: $assemblyToAssemblyEdges"
$output += "Orphaned projects: $($orphanedProjects.Count)"
$output += ("=" * 80)

# Save to file
$output | Out-File -FilePath $OutputFile -Encoding UTF8
Write-Host "Tree saved to: $OutputFile" -ForegroundColor Green

# Append summary to scan info fileTotal projects: $($projects.Count)`nTotal assemblies: $($assemblies.Count)`nProject edges: $($projectEdges.Count)`nAssembly edges: $($assemblyEdges.Count)`n
if ($env:SCAN_INFO_FILE -and (Test-Path -Path $env:SCAN_INFO_FILE)) {
    $summary = "`n`n07_show-dependency-tree.ps1`n" + ("=" * 50) + "`nSolutions visualized: $($solutions.Count)`nOrphaned projects: $($orphanedProjects.Count)`nMax depth: $MaxDepth`nOutput file: $OutputFile"
    $summary | Out-File -FilePath $env:SCAN_INFO_FILE -Append -Encoding UTF8
}

Write-Host "Dependency tree generation complete!" -ForegroundColor Cyan

# Return statistics
return @{
    SolutionsVisualized = $solutions.Count
    OrphanedProjects = $orphanedProjects.Count
}
