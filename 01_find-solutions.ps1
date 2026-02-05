# 01_find-solutions.ps1
# Finds all Microsoft Solution (.sln) files in the repository

<#
.SYNOPSIS
    Finds all Microsoft Solution (.sln) files in the repository.

.DESCRIPTION
    Recursively searches through all sub-folders in the repository path
    and captures the full path of all .sln files. Results are saved to
    the current scan folder.

.PARAMETER RepositoryPath
    The root folder path to search. Defaults to $env:REPOSITORY_PATH.

.PARAMETER OutputFile
    Optional. If specified, writes the results to this file name in the scan folder.
    Defaults to "01_solutions-list.txt".

.EXAMPLE
    .\01_find-solutions.ps1
    
.EXAMPLE
    .\01_find-solutions.ps1 -RepositoryPath "C:\MyRepo" -OutputFile "my-solutions.txt"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$RepositoryPath = $env:REPOSITORY_PATH,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "01_solutions-list.txt"
)

# Validate the repository path exists
if ([string]::IsNullOrWhiteSpace($RepositoryPath)) {
    Write-Error "Repository path is not specified. Please set `$env:REPOSITORY_PATH or provide -RepositoryPath parameter."
    exit 1
}

if (-not (Test-Path -Path $RepositoryPath)) {
    Write-Error "The specified repository path does not exist: $RepositoryPath"
    exit 1
}

# Validate the scan folder exists
$scanFolder = $env:CURRENT_SCAN_FOLDER
if ([string]::IsNullOrWhiteSpace($scanFolder) -or -not (Test-Path -Path $scanFolder)) {
    Write-Warning "Current scan folder not found. Using current directory for output."
    $scanFolder = $PSScriptRoot
}

Write-Host "Searching for .sln files in: $RepositoryPath" -ForegroundColor Cyan
Write-Host ""

# Find all .sln files recursively
$solutionFiles = Get-ChildItem -Path $RepositoryPath -Recurse -Include "*.sln" -File -ErrorAction SilentlyContinue

if ($solutionFiles.Count -eq 0) {
    Write-Host "No .sln files found." -ForegroundColor Yellow
    
    # Create empty output file to indicate scan was performed
    $outputPath = Join-Path -Path $scanFolder -ChildPath $OutputFile
    "No solution files found." | Out-File -FilePath $outputPath -Encoding UTF8
    Write-Host "Results saved to: $outputPath" -ForegroundColor Green
    exit 0
}

# Display results
Write-Host "Found $($solutionFiles.Count) solution file(s)" -ForegroundColor Green
Write-Host ""

# List all found solutions
$solutionFiles | ForEach-Object { 
    Write-Host "  - $($_.FullName)" -ForegroundColor Gray
}
Write-Host ""

# Save results to file in the scan folder
$outputPath = Join-Path -Path $scanFolder -ChildPath $OutputFile
$solutionFiles | ForEach-Object { $_.FullName } | Out-File -FilePath $outputPath -Encoding UTF8

Write-Host "Results saved to: $outputPath" -ForegroundColor Green
Write-Host "Total solutions found: $($solutionFiles.Count)" -ForegroundColor Cyan

# Append summary to scan info file
if ($env:SCAN_INFO_FILE -and (Test-Path -Path $env:SCAN_INFO_FILE)) {
    $summary = "`n`n01_find-solutions.ps1`n" + "=" * 50 + "`nTotal solution files found: $($solutionFiles.Count)`nOutput file: $outputPath"
    $summary | Out-File -FilePath $env:SCAN_INFO_FILE -Append -Encoding UTF8
}

# Return the solution files for potential use by other scripts
return $solutionFiles
