# 03_extract-solution-info.ps1
# Extracts metadata from Solution (.sln) files

<#
.SYNOPSIS
    Extracts metadata from Solution (.sln) files.

.DESCRIPTION
    Reads a list of .sln file paths and extracts:
    - Unique Identifier (GUID) - Deterministic hash of file path
    - VisualStudioGUID - GUID from Visual Studio solution files (N/A if not found)
    - Name (as displayed in Visual Studio)
    - Full Path
    - Type (Solution)
    - GuidDeterminationMethod (How the VisualStudioGUID was determined)
    - NumberOfReferencedProjects (Count of projects referenced)
    - IsSingleProjectSolution (TRUE if solution references exactly one project)
    
    Outputs the data to a CSV file in the current scan folder.

.PARAMETER SolutionsListFile
    Path to the text file containing solution file paths. Defaults to 01_solutions-list.txt in the scan folder.

.PARAMETER OutputCsvFile
    Path to the output CSV file. Defaults to "03_solutions-info.csv" in the scan folder.

.EXAMPLE
    .\03_extract-solution-info.ps1
    
.EXAMPLE
    .\03_extract-solution-info.ps1 -SolutionsListFile "custom-solutions.txt" -OutputCsvFile "custom-output.csv"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SolutionsListFile,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputCsvFile
)

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

# Function to extract Solution information
function Get-SolutionInfo {
    param([string]$FilePath)
    
    if (-not (Test-Path -Path $FilePath)) {
        Write-Warning "Solution file not found: $FilePath"
        return $null
    }
    
    try {
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        
        # UniqueIdentifier is always generated from the file path
        $uniqueIdentifier = Get-GuidFromPath -Path $FilePath
        
        # Extract the solution GUID (typically found after "SolutionGuid = ")
        $guidMatch = [regex]::Match($content, 'SolutionGuid\s*=\s*\{([0-9A-Fa-f\-]+)\}')
        
        if ($guidMatch.Success) {
            $visualStudioGuid = $guidMatch.Groups[1].Value
            $guidMethod = "SolutionGuid"
        } else {
            # If no SolutionGuid found, mark as N/A
            $visualStudioGuid = "N/A"
            $guidMethod = "Not found"
        }
        
        # Count the number of .csproj projects referenced in the solution
        # Only count projects where the .csproj file actually exists
        $projectMatches = [regex]::Matches($content, 'Project\("[^"]+"\)\s*=\s*"[^"]+"\s*,\s*"([^"]+)"\s*,\s*"\{([0-9A-Fa-f\-]+)\}"')
        $projectCount = 0
        $singleProjectGuid = $null
        $solutionDir = [System.IO.Path]::GetDirectoryName($FilePath)
        
        foreach ($match in $projectMatches) {
            $projectPath = $match.Groups[1].Value
            if ($projectPath -match '\.csproj$') {
                # Resolve to absolute path and check if file exists
                $absoluteProjectPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($solutionDir, $projectPath))
                if (Test-Path -Path $absoluteProjectPath) {
                    $projectCount++
                    # Capture the project GUID for potential use
                    $singleProjectGuid = $match.Groups[2].Value
                }
            }
        }
        
        # If this is a single-project solution, use the project's GUID for VisualStudioGUID
        $isSingleProjectSolution = ($projectCount -eq 1)
        if ($isSingleProjectSolution -and $singleProjectGuid) {
            $visualStudioGuid = $singleProjectGuid
            $guidMethod = "From referenced project"
        }
        
        # Extract name from file path
        $name = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        
        return [PSCustomObject]@{
            UniqueIdentifier = $uniqueIdentifier
            VisualStudioGUID = $visualStudioGuid
            Type = "Solution"
            Name = $name
            FilePath = $FilePath
            GuidDeterminationMethod = $guidMethod
            NumberOfReferencedProjects = $projectCount
            IsSingleProjectSolution = $isSingleProjectSolution
        }
    }
    catch {
        Write-Warning "Error processing solution file '$FilePath': $_"
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
if ([string]::IsNullOrWhiteSpace($SolutionsListFile)) {
    $SolutionsListFile = Join-Path -Path $scanFolder -ChildPath "01_solutions-list.txt"
}

if ([string]::IsNullOrWhiteSpace($OutputCsvFile)) {
    $OutputCsvFile = Join-Path -Path $scanFolder -ChildPath "03_solutions-info.csv"
}

# Main script execution
Write-Host "Extracting Solution information..." -ForegroundColor Cyan
Write-Host ""

$results = @()

# Process Solutions
if (Test-Path -Path $SolutionsListFile) {
    Write-Host "Reading solutions from: $SolutionsListFile" -ForegroundColor Yellow
    $solutionPaths = Get-Content -Path $SolutionsListFile | Where-Object { $_.Trim() -ne "" -and $_ -notmatch "^No solution files found" }
    
    if ($solutionPaths.Count -eq 0) {
        Write-Host "No solution files to process." -ForegroundColor Yellow
    } else {
        foreach ($path in $solutionPaths) {
            Write-Host "Processing solution: $path" -ForegroundColor Gray
            $info = Get-SolutionInfo -FilePath $path.Trim()
            if ($info) {
                $results += $info
            }
        }
        Write-Host "Processed $($solutionPaths.Count) solution(s)" -ForegroundColor Green
    }
} else {
    Write-Warning "Solutions list file not found: $SolutionsListFile"
}

Write-Host ""

# Export to CSV
if ($results.Count -gt 0) {
    $results | Export-Csv -Path $OutputCsvFile -NoTypeInformation -Encoding UTF8
    Write-Host "Successfully exported $($results.Count) record(s) to: $OutputCsvFile" -ForegroundColor Green
    
    # Append summary to scan info file
    if ($env:SCAN_INFO_FILE -and (Test-Path -Path $env:SCAN_INFO_FILE)) {
        $summary = "`n`n03_extract-solution-info.ps1`n" + "=" * 50 + "`nTotal solutions processed: $($results.Count)`nOutput file: $OutputCsvFile"
        $summary | Out-File -FilePath $env:SCAN_INFO_FILE -Append -Encoding UTF8
    }
} else {
    Write-Warning "No solution data to export. CSV file not created."
}

Write-Host "Solution extraction complete!" -ForegroundColor Cyan

# Return the results for potential use by other scripts
return $results
