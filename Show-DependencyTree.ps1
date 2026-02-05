<#
.SYNOPSIS
    Displays dependency trees in ASCII format for each Solution.

.DESCRIPTION
    Reads the project analysis and dependency data, then generates an ASCII
    tree visualization showing each Solution and its dependencies.
    Optionally includes project-to-project dependencies.

.PARAMETER NodesFile
    Path to the project-analysis.csv file. Defaults to "project-analysis.csv".

.PARAMETER EdgesFile
    Path to the dependency-edges.csv file. Defaults to "06_dependency-edges.csv".

.PARAMETER OutputFile
    Optional output file path. If not specified, displays to console only.

.PARAMETER SolutionName
    Optional solution name to filter output. If specified, only shows the matching solution.
    Requires exact match (case-insensitive).

.PARAMETER ShowProjectDependencies
    Include project-to-project dependencies in the tree. Defaults to $true.

.PARAMETER MaxDepth
    Maximum depth to traverse for project dependencies. Defaults to 3.

.EXAMPLE
    .\Show-DependencyTree.ps1
    
.EXAMPLE
    .\Show-DependencyTree.ps1 -OutputFile "07_dependency-tree.txt"
    
.EXAMPLE
    .\Show-DependencyTree.ps1 -ShowProjectDependencies $false

.EXAMPLE
    .\Show-DependencyTree.ps1 -SolutionName "MyApp"
    
.EXAMPLE
    .\Show-DependencyTree.ps1 -SolutionName "MyApp" -MaxDepth 5
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$NodesFile = "project-analysis.csv",
    
    [Parameter(Mandatory=$false)]
    [string]$EdgesFile = "06_dependency-edges.csv",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "",
    
    [Parameter(Mandatory=$false)]
    [string]$SolutionName = "",
    
    [Parameter(Mandatory=$false)]
    [bool]$ShowProjectDependencies = $true,
    
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
        [hashtable]$ShownAtShallowest = @{}
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
                } elseif ($ShallowestDepths.ContainsKey($depId) -and $ShallowestDepths[$depId] -lt $depthToChild) {
                    # We'll see this at a shallower depth, or already saw it
                    $annotation = "*"
                } else {
                    # Shouldn't normally happen, but expand if shallowest depth not found
                    $shouldExpand = $true
                    $ShownAtShallowest[$depId] = $true
                }
                
                $lines += Write-TreeNode -Text $depNode.Name -Prefix $Prefix -IsLast $isLast -Annotation $annotation
                
                # Recurse only if this is the shallowest occurrence and not circular
                if ($shouldExpand -and -not $newVisited.ContainsKey($depId) -and $ShowProjectDependencies) {
                    $newPrefix = Get-ContinuationPrefix -CurrentPrefix $Prefix -IsLast $isLast
                    $subLines = Get-DependencyTree -NodeId $depId -NodeLookup $NodeLookup -AdjacencyList $AdjacencyList -ShallowestDepths $ShallowestDepths -Prefix $newPrefix -CurrentDepth $depthToChild -VisitedInPath $newVisited -ShownAtShallowest $ShownAtShallowest
                    $lines += $subLines
                }
            }
        }
    }
    
    return $lines
}

# Main script execution
Write-Host "Generating ASCII dependency trees..." -ForegroundColor Cyan
Write-Host ""

# Load nodes
if (-not (Test-Path -Path $NodesFile)) {
    Write-Error "Nodes file not found: $NodesFile"
    exit 1
}

$nodes = Import-Csv -Path $NodesFile
Write-Host "Loaded $($nodes.Count) node(s)" -ForegroundColor Green

# Load edges
if (-not (Test-Path -Path $EdgesFile)) {
    Write-Error "Edges file not found: $EdgesFile"
    exit 1
}

$edges = Import-Csv -Path $EdgesFile
Write-Host "Loaded $($edges.Count) edge(s)" -ForegroundColor Green
Write-Host ""

# Build lookups
$nodeLookup = @{}
$solutions = @()
$projects = @()

foreach ($node in $nodes) {
    $nodeLookup[$node.UniqueIdentifier] = $node
    if ($node.Type -eq "Solution") {
        $solutions += $node
    } else {
        $projects += $node
    }
}

# Build adjacency list
$adjacencyList = @{}
foreach ($edge in $edges) {
    if (-not $adjacencyList.ContainsKey($edge.FromNodeId)) {
        $adjacencyList[$edge.FromNodeId] = @()
    }
    $adjacencyList[$edge.FromNodeId] += $edge.ToNodeId
}

# Filter solutions if SolutionName is specified
if ($SolutionName) {
    $filteredSolutions = $solutions | Where-Object { $_.Name -eq $SolutionName }
    
    if ($filteredSolutions.Count -eq 0) {
        Write-Warning "No solutions found matching: '$SolutionName'"
        Write-Host "Available solutions:" -ForegroundColor Yellow
        foreach ($sol in $solutions | Select-Object -First 10) {
            Write-Host "  - $($sol.Name)" -ForegroundColor Gray
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
$output += "=" * 80
$output += "DEPENDENCY TREE VISUALIZATION"
$output += "=" * 80
$output += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$output += "Total Solutions: $($solutions.Count)"
$output += "Total Projects: $($projects.Count)"
$output += "Total Dependencies: $($edges.Count)"

# Get git commit hash
try {
    $gitHash = & git -C "C:\svn_repository" rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitHash) {
        $output += "Commit Hash: $gitHash"
    }
} catch {
    # Silently ignore if git command fails
}

$output += "=" * 80
$output += ""

# Sort solutions alphabetically by name
$solutions = $solutions | Sort-Object -Property Name

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
        
        if ($solution.IsSingleProjectSolution -eq $true) {
            $output += "|   [Single-Project Solution]"
        }
        
        if ($solution.CopySuspected -eq $true) {
            $output += "|   ! [COPY SUSPECTED]"
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
                
                $treeLines = Get-DependencyTree -NodeId $solution.UniqueIdentifier -NodeLookup $nodeLookup -AdjacencyList $adjacencyList -ShallowestDepths $shallowestDepths -Prefix "|" -ShownAtShallowest $shownAtShallowest
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
foreach ($edge in $edges) {
    if ($edge.FromNodeType -eq "Solution") {
        $referencedProjects[$edge.ToNodeId] = $true
    }
}

$orphanedProjects = $projects | Where-Object { -not $referencedProjects.ContainsKey($_.UniqueIdentifier) }

if ($orphanedProjects.Count -gt 0) {
    $output += ""
    $output += "=" * 80
    $output += "ORPHANED PROJECTS (Not referenced by any Solution)"
    $output += "=" * 80
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
$output += "=" * 80
$output += "STATISTICS"
$output += "=" * 80

$solutionToProjectEdges = ($edges | Where-Object { $_.ReferenceType -eq "Solution-to-Project" }).Count
$projectToProjectEdges = ($edges | Where-Object { $_.ReferenceType -eq "Project-to-Project" }).Count
$copySuspected = ($nodes | Where-Object { $_.CopySuspected -eq $true }).Count

$output += "Solution -> Project references: $solutionToProjectEdges"
$output += "Project -> Project references: $projectToProjectEdges"
$output += "Copy-suspected items: $copySuspected"
$output += "Orphaned projects: $($orphanedProjects.Count)"
$output += "=" * 80

# Output to console
foreach ($line in $output) {
    Write-Host $line
}

# Save to file if specified
if ($OutputFile) {
    $output | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host ""
    Write-Host "Tree saved to: $OutputFile" -ForegroundColor Green
}

Write-Host ""
Write-Host "Complete!" -ForegroundColor Cyan
