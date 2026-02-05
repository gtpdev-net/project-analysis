# 00_scan-repo.ps1
# Creates a scan folder structure with date/time and commit hash information

param(
    [string]$RepositoryPath = "C:\svn_repository"
)

# 1. Create 'Scans' folder if it doesn't exist
$scansFolder = Join-Path -Path $PSScriptRoot -ChildPath "Scans"
if (-not (Test-Path -Path $scansFolder)) {
    New-Item -Path $scansFolder -ItemType Directory -Force | Out-Null
    Write-Host "Created 'Scans' folder at: $scansFolder"
}

# 2. Determine current date and time
$currentDateTime = Get-Date
$scanDate = $currentDateTime.ToString("yyyy-MM-dd")
$scanTime = $currentDateTime.ToString("HH:mm:ss")

# 3. Get Git commit hash for HEAD of current branch
try {
    Push-Location -Path $RepositoryPath
    $gitCommitHash = git rev-parse HEAD
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to retrieve Git commit hash"
    }
    
    # Get the first 8 characters of the commit hash
    $shortCommitHash = $gitCommitHash.Substring(0, 8)
    
    Pop-Location
    
    Write-Host "Repository: $RepositoryPath"
    Write-Host "Commit Hash: $gitCommitHash"
    Write-Host "Short Hash: $shortCommitHash"
}
catch {
    Write-Error "Error retrieving Git commit hash from repository at '$RepositoryPath': $_"
    if ((Get-Location).Path -ne $PSScriptRoot) {
        Pop-Location
    }
    exit 1
}

# 4. Create current scan folder
$folderName = "{0}_{1}" -f $currentDateTime.ToString("yyyy-MM-dd-HH-mm"), $shortCommitHash
$currentScanFolder = Join-Path -Path $scansFolder -ChildPath $folderName

try {
    New-Item -Path $currentScanFolder -ItemType Directory -Force | Out-Null
    Write-Host "Created scan folder: $currentScanFolder"
}
catch {
    Write-Error "Error creating scan folder: $_"
    exit 1
}

# 5. Create _scan-info.txt file with scan information
$scanInfoFile = Join-Path -Path $currentScanFolder -ChildPath "_scan-info.txt"

$scanInfo = @"
Scan Information
================

Date: $scanDate
Time: $scanTime
Git Commit Hash: $gitCommitHash
Short Hash: $shortCommitHash
Repository Path: $RepositoryPath
Scan Folder: $currentScanFolder
"@

try {
    $scanInfo | Out-File -FilePath $scanInfoFile -Encoding UTF8
    Write-Host "Created scan info file: $scanInfoFile"
}
catch {
    Write-Error "Error creating scan info file: $_"
    exit 1
}

Write-Host "`nScan setup completed successfully!" -ForegroundColor Green
Write-Host "Scan folder: $currentScanFolder" -ForegroundColor Cyan

# Export the current scan folder path and repository path for use by other scripts
$env:CURRENT_SCAN_FOLDER = $currentScanFolder
$env:REPOSITORY_PATH = $RepositoryPath
$env:SCAN_INFO_FILE = $scanInfoFile

# Execute 01_find-solutions.ps1 to find all solution files
Write-Host "`nExecuting solution file search..." -ForegroundColor Cyan
$findSolutionsScript = Join-Path -Path $PSScriptRoot -ChildPath "01_find-solutions.ps1"
if (Test-Path -Path $findSolutionsScript) {
    & $findSolutionsScript
} else {
    Write-Warning "01_find-solutions.ps1 not found at: $findSolutionsScript"
}

# Execute 02_find-projects.ps1 to find all project files
Write-Host "`nExecuting project file search..." -ForegroundColor Cyan
$findProjectsScript = Join-Path -Path $PSScriptRoot -ChildPath "02_find-projects.ps1"
if (Test-Path -Path $findProjectsScript) {
    & $findProjectsScript
} else {
    Write-Warning "02_find-projects.ps1 not found at: $findProjectsScript"
}

# Execute 03_extract-solution-info.ps1 to extract solution metadata
Write-Host "`nExecuting solution information extraction..." -ForegroundColor Cyan
$extractSolutionScript = Join-Path -Path $PSScriptRoot -ChildPath "03_extract-solution-info.ps1"
if (Test-Path -Path $extractSolutionScript) {
    & $extractSolutionScript
} else {
    Write-Warning "03_extract-solution-info.ps1 not found at: $extractSolutionScript"
}

# Execute 04_extract-project-info.ps1 to extract project metadata
Write-Host "`nExecuting project information extraction..." -ForegroundColor Cyan
$extractProjectScript = Join-Path -Path $PSScriptRoot -ChildPath "04_extract-project-info.ps1"
if (Test-Path -Path $extractProjectScript) {
    & $extractProjectScript
} else {
    Write-Warning "04_extract-project-info.ps1 not found at: $extractProjectScript"
}

# Execute 05_identify-assemblies.ps1 to identify all assemblies
Write-Host "`nExecuting assembly information extraction..." -ForegroundColor Cyan
$extractAssembliesScript = Join-Path -Path $PSScriptRoot -ChildPath "05_extract-assembly-info.ps1"
if (Test-Path -Path $extractAssembliesScript) {
    & $extractAssembliesScript
} else {
    Write-Warning "05_extract-assembly-info.ps1 not found at: $extractAssembliesScript"
}
# Execute 06_build-dependency-graph.ps1 to build dependency graphs
Write-Host "`nExecuting dependency graph build..." -ForegroundColor Cyan
$buildDependencyGraphScript = Join-Path -Path $PSScriptRoot -ChildPath "06_build-dependency-graph.ps1"
if (Test-Path -Path $buildDependencyGraphScript) {
    & $buildDependencyGraphScript
} else {
    Write-Warning "06_build-dependency-graph.ps1 not found at: $buildDependencyGraphScript"
}
# Execute 07_show-dependency-tree.ps1 to generate dependency tree visualization
Write-Host "`nExecuting dependency tree visualization..." -ForegroundColor Cyan
$showDependencyTreeScript = Join-Path -Path $PSScriptRoot -ChildPath "07_show-dependency-tree.ps1"
if (Test-Path -Path $showDependencyTreeScript) {
    & $showDependencyTreeScript
} else {
    Write-Warning "07_show-dependency-tree.ps1 not found at: $showDependencyTreeScript"
}
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host "SCAN COMPLETE!" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Green
Write-Host "Scan summary saved to: $scanInfoFile" -ForegroundColor Cyan

return $currentScanFolder
