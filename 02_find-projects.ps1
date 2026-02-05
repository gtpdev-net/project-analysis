# 02_find-projects.ps1
# Finds all C# Project (.csproj) files in the repository

<#
.SYNOPSIS
    Finds all C# Project (.csproj) files in the repository.

.DESCRIPTION
    Recursively searches through all sub-folders in the repository path
    and captures the full path of all .csproj files. Results are saved to
    the current scan folder.

.PARAMETER RepositoryPath
    The root folder path to search. Defaults to $env:REPOSITORY_PATH.

.PARAMETER OutputFile
    Optional. If specified, writes the results to this file name in the scan folder.
    Defaults to "02_projects-list.txt".

.EXAMPLE
    .\02_find-projects.ps1
    
.EXAMPLE
    .\02_find-projects.ps1 -RepositoryPath "C:\MyRepo" -OutputFile "my-projects.txt"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$RepositoryPath = $env:REPOSITORY_PATH,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "02_projects-list.txt"
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

Write-Host "Searching for .csproj files in: $RepositoryPath" -ForegroundColor Cyan
Write-Host ""

# Find all .csproj files recursively
$projectFiles = Get-ChildItem -Path $RepositoryPath -Recurse -Include "*.csproj" -File -ErrorAction SilentlyContinue

if ($projectFiles.Count -eq 0) {
    Write-Host "No .csproj files found." -ForegroundColor Yellow
    
    # Create empty output file to indicate scan was performed
    $outputPath = Join-Path -Path $scanFolder -ChildPath $OutputFile
    "No project files found." | Out-File -FilePath $outputPath -Encoding UTF8
    Write-Host "Results saved to: $outputPath" -ForegroundColor Green
    exit 0
}

# Display results
Write-Host "Found $($projectFiles.Count) project file(s)" -ForegroundColor Green
Write-Host ""

# List all found projects
$projectFiles | ForEach-Object { 
    Write-Host "  - $($_.FullName)" -ForegroundColor Gray
}
Write-Host ""

# Save results to file in the scan folder
$outputPath = Join-Path -Path $scanFolder -ChildPath $OutputFile
$projectFiles | ForEach-Object { $_.FullName } | Out-File -FilePath $outputPath -Encoding UTF8

Write-Host "Results saved to: $outputPath" -ForegroundColor Green
Write-Host "Total projects found: $($projectFiles.Count)" -ForegroundColor Cyan

# Append summary to scan info file
if ($env:SCAN_INFO_FILE -and (Test-Path -Path $env:SCAN_INFO_FILE)) {
    $summary = "`n`n02_find-projects.ps1`n" + "=" * 50 + "`nTotal project files found: $($projectFiles.Count)`nOutput file: $outputPath"
    $summary | Out-File -FilePath $env:SCAN_INFO_FILE -Append -Encoding UTF8
}

# Return the project files for potential use by other scripts
return $projectFiles
