# 04_extract-project-info.ps1
# Extracts metadata from C# Project (.csproj) files

<#
.SYNOPSIS
    Extracts metadata from C# Project (.csproj) files.

.DESCRIPTION
    Reads a list of .csproj file paths and extracts:
    - Unique Identifier (GUID) - Deterministic hash of file path
    - VisualStudioGUID - GUID from Visual Studio project files (N/A if not found)
    - Name (as displayed in Visual Studio)
    - Full Path
    - Type (Project)
    - GuidDeterminationMethod (How the VisualStudioGUID was determined)
    - NumberOfReferencedProjects (Count of ProjectReference elements)
    
    Outputs the data to a CSV file in the current scan folder.

.PARAMETER ProjectsListFile
    Path to the text file containing project file paths. Defaults to 02_projects-list.txt in the scan folder.

.PARAMETER SolutionsListFile
    Path to the text file containing solution file paths (for GUID mapping). Defaults to 01_solutions-list.txt in the scan folder.

.PARAMETER OutputCsvFile
    Path to the output CSV file. Defaults to "04_projects-info.csv" in the scan folder.

.EXAMPLE
    .\04_extract-project-info.ps1
    
.EXAMPLE
    .\04_extract-project-info.ps1 -ProjectsListFile "custom-projects.txt" -OutputCsvFile "custom-output.csv"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ProjectsListFile,
    
    [Parameter(Mandatory=$false)]
    [string]$SolutionsListFile,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputCsvFile
)

# Function to build a mapping of project paths to GUIDs from solution files
function New-ProjectGuidMap {
    param([string[]]$SolutionPaths)
    
    $projectGuidMap = @{}
    
    foreach ($solutionPath in $SolutionPaths) {
        if (-not (Test-Path -Path $solutionPath)) {
            continue
        }
        
        try {
            $content = Get-Content -Path $solutionPath -Raw -ErrorAction Stop
            $solutionDir = [System.IO.Path]::GetDirectoryName($solutionPath)
            
            # Match Project lines: Project("{type-guid}") = "Name", "RelativePath\Project.csproj", "{project-guid}"
            $projectMatches = [regex]::Matches($content, 'Project\("[^"]+"\)\s*=\s*"[^"]+"\s*,\s*"([^"]+)"\s*,\s*"\{([0-9A-Fa-f\-]+)\}"')
            
            foreach ($match in $projectMatches) {
                $relativePath = $match.Groups[1].Value
                $projectGuid = $match.Groups[2].Value
                
                # Only process .csproj files
                if ($relativePath -match '\.csproj$') {
                    # Resolve to absolute path
                    $absolutePath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($solutionDir, $relativePath))
                    $normalizedPath = $absolutePath.ToLower().Replace('/', '\\')
                    
                    # Store the mapping (use lowercase for case-insensitive matching)
                    if (-not $projectGuidMap.ContainsKey($normalizedPath)) {
                        $projectGuidMap[$normalizedPath] = $projectGuid
                    }
                }
            }
        }
        catch {
            Write-Warning "Error parsing solution file for project mappings '$solutionPath': $_"
        }
    }
    
    return $projectGuidMap
}

# Function to generate a GUID from a file path using MD5 hash
function Get-GuidFromPath {
    param([string]$Path)
    
    # Normalize the path for consistency
    $normalizedPath = [System.IO.Path]::GetFullPath($Path).ToLower()
    
    # Compute MD5 hash of the path
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalizedPath))
    
    # Format as GUID: 8-4-4-4-12 hex characters
    $guid = "{0:X2}{1:X2}{2:X2}{3:X2}-{4:X2}{5:X2}-{6:X2}{7:X2}-{8:X2}{9:X2}-{10:X2}{11:X2}{12:X2}{13:X2}{14:X2}{15:X2}" -f `
        $hashBytes[0], $hashBytes[1], $hashBytes[2], $hashBytes[3], `
        $hashBytes[4], $hashBytes[5], `
        $hashBytes[6], $hashBytes[7], `
        $hashBytes[8], $hashBytes[9], `
        $hashBytes[10], $hashBytes[11], $hashBytes[12], $hashBytes[13], $hashBytes[14], $hashBytes[15]
    
    return $guid
}

# Function to extract Project information
function Get-ProjectInfo {
    param(
        [string]$FilePath,
        [hashtable]$ProjectGuidMap = @{}
    )
    
    if (-not (Test-Path -Path $FilePath)) {
        Write-Warning "Project file not found: $FilePath"
        return $null
    }
    
    try {
        [xml]$projectXml = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        
        # UniqueIdentifier is always generated from the file path
        $uniqueIdentifier = Get-GuidFromPath -Path $FilePath
        
        # Try to extract ProjectGuid (old-style projects)
        # Use local-name() to ignore XML namespaces
        $guidNode = $projectXml.SelectSingleNode("//*[local-name()='ProjectGuid']")
        
        if ($guidNode -and $guidNode.InnerText) {
            # Remove curly braces if present
            $visualStudioGuid = $guidNode.InnerText -replace '[{}]', ''
            $guidMethod = "ProjectGuid element"
        } else {
            # For SDK-style projects, try to get GUID from solution files
            $normalizedPath = $FilePath.ToLower().Replace('/', '\\')
            if ($ProjectGuidMap.ContainsKey($normalizedPath)) {
                $visualStudioGuid = $ProjectGuidMap[$normalizedPath]
                $guidMethod = "From solution file"
            } else {
                # No GUID found, mark as N/A
                $visualStudioGuid = "N/A"
                $guidMethod = "Not found"
            }
        }
        
        # Try to extract project name from AssemblyName or RootNamespace
        $assemblyNameNode = $projectXml.SelectSingleNode("//AssemblyName")
        $rootNamespaceNode = $projectXml.SelectSingleNode("//RootNamespace")
        
        if ($assemblyNameNode -and $assemblyNameNode.InnerText) {
            $name = $assemblyNameNode.InnerText
        } elseif ($rootNamespaceNode -and $rootNamespaceNode.InnerText) {
            $name = $rootNamespaceNode.InnerText
        } else {
            # Fall back to file name
            $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        }
        
        # Count the number of ProjectReference elements (use local-name to ignore namespaces)
        $projectReferences = $projectXml.SelectNodes("//*[local-name()='ProjectReference']")
        $projectCount = if ($projectReferences) { $projectReferences.Count } else { 0 }
        
        return [PSCustomObject]@{
            UniqueIdentifier = $uniqueIdentifier
            VisualStudioGUID = $visualStudioGuid
            Type = "Project"
            Name = $name
            FilePath = $FilePath
            GuidDeterminationMethod = $guidMethod
            NumberOfReferencedProjects = $projectCount
        }
    }
    catch {
        Write-Warning "Error processing project file '$FilePath': $_"
        return $null
    }
}

# Determine scan folder and input/output paths
$scanFolder = $env:CURRENT_SCAN_FOLDER
if ([string]::IsNullOrWhiteSpace($scanFolder) -or -not (Test-Path -Path $scanFolder)) {
    Write-Warning "Current scan folder not found. Using current directory for input/output."
    $scanFolder = $PSScriptRoot
}

# Set default paths if not provided
if ([string]::IsNullOrWhiteSpace($ProjectsListFile)) {
    $ProjectsListFile = Join-Path -Path $scanFolder -ChildPath "02_projects-list.txt"
}

if ([string]::IsNullOrWhiteSpace($SolutionsListFile)) {
    $SolutionsListFile = Join-Path -Path $scanFolder -ChildPath "01_solutions-list.txt"
}

if ([string]::IsNullOrWhiteSpace($OutputCsvFile)) {
    $OutputCsvFile = Join-Path -Path $scanFolder -ChildPath "04_projects-info.csv"
}

# Main script execution
Write-Host "Extracting Project information..." -ForegroundColor Cyan
Write-Host ""

# Build project GUID mapping from solution files
Write-Host "Building project GUID map from solution files..." -ForegroundColor Yellow
$projectGuidMap = @{}
if (Test-Path -Path $SolutionsListFile) {
    $solutionPaths = Get-Content -Path $SolutionsListFile | Where-Object { $_.Trim() -ne "" -and $_ -notmatch "^No solution files found" }
    if ($solutionPaths.Count -gt 0) {
        $projectGuidMap = New-ProjectGuidMap -SolutionPaths $solutionPaths
        Write-Host "Found $($projectGuidMap.Count) project GUID mapping(s) in solution files" -ForegroundColor Green
    } else {
        Write-Host "No solution files available for GUID mapping" -ForegroundColor Yellow
    }
} else {
    Write-Warning "Solutions list file not found: $SolutionsListFile"
}
Write-Host ""

$results = @()

# Process Projects
if (Test-Path -Path $ProjectsListFile) {
    Write-Host "Reading projects from: $ProjectsListFile" -ForegroundColor Yellow
    $projectPaths = Get-Content -Path $ProjectsListFile | Where-Object { $_.Trim() -ne "" -and $_ -notmatch "^No project files found" }
    
    if ($projectPaths.Count -eq 0) {
        Write-Host "No project files to process." -ForegroundColor Yellow
    } else {
        foreach ($path in $projectPaths) {
            Write-Host "Processing project: $path" -ForegroundColor Gray
            $info = Get-ProjectInfo -FilePath $path.Trim() -ProjectGuidMap $projectGuidMap
            if ($info) {
                $results += $info
            }
        }
        Write-Host "Processed $($projectPaths.Count) project(s)" -ForegroundColor Green
    }
} else {
    Write-Warning "Projects list file not found: $ProjectsListFile"
}

Write-Host ""

# Export to CSV
if ($results.Count -gt 0) {
    $results | Export-Csv -Path $OutputCsvFile -NoTypeInformation -Encoding UTF8
    Write-Host "Successfully exported $($results.Count) record(s) to: $OutputCsvFile" -ForegroundColor Green
    
    # Append summary to scan info file
    if ($env:SCAN_INFO_FILE -and (Test-Path -Path $env:SCAN_INFO_FILE)) {
        $guidFromSolutionCount = ($results | Where-Object { $_.GuidDeterminationMethod -eq "From solution file" }).Count
        $guidFromElementCount = ($results | Where-Object { $_.GuidDeterminationMethod -eq "ProjectGuid element" }).Count
        $guidNotFoundCount = ($results | Where-Object { $_.GuidDeterminationMethod -eq "Not found" }).Count
        
        $summary = "`n`n04_extract-project-info.ps1`n" + "=" * 50 + "`nTotal projects processed: $($results.Count)`nGUIDs from solution files: $guidFromSolutionCount`nGUIDs from ProjectGuid element: $guidFromElementCount`nGUIDs not found: $guidNotFoundCount`nOutput file: $OutputCsvFile"
        $summary | Out-File -FilePath $env:SCAN_INFO_FILE -Append -Encoding UTF8
    }
} else {
    Write-Warning "No project data to export. CSV file not created."
}

Write-Host "Project extraction complete!" -ForegroundColor Cyan

# Return the results for potential use by other scripts
return $results
