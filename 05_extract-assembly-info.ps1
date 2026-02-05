# 05_extract-assembly-info.ps1
# Extracts assembly information from C# projects

<#
.SYNOPSIS
    Extracts assembly information from C# projects.

.DESCRIPTION
    Analyzes C# project (.csproj) files to determine what assemblies they will produce.
    Extracts metadata including:
    - Unique Identifier (GUID) - Deterministic hash based on project path and assembly name
    - Type (Assembly)
    - Name (AssemblyName)
    - AssemblyFileName (e.g., MyApp.dll, MyApp.exe)
    - OutputType (Library, Exe, WinExe, etc.)
    - ProjectStyle (SDK-style or Legacy)
    - TargetFramework(s)

.PARAMETER ProjectsListFile
    Path to the text file containing project file paths. Defaults to 02_projects-list.txt in the scan folder.

.PARAMETER OutputCsvFile
    Path to the output CSV file. Defaults to "05_assemblies-info.csv" in the scan folder.

.EXAMPLE
    .\05_extract-assembly-info.ps1
    
.EXAMPLE
    .\05_extract-assembly-info.ps1 -OutputCsvFile "custom-assemblies.csv"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ProjectsListFile,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputCsvFile
)

# Function to generate a GUID from a string using MD5 hash
function Get-GuidFromString {
    param([string]$InputString)
    
    # Normalize the string for consistency
    $normalizedString = $InputString.ToLower()
    
    # Compute MD5 hash
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalizedString))
    
    # Format as GUID: 8-4-4-4-12 hex characters
    $guid = "{0:X2}{1:X2}{2:X2}{3:X2}-{4:X2}{5:X2}-{6:X2}{7:X2}-{8:X2}{9:X2}-{10:X2}{11:X2}{12:X2}{13:X2}{14:X2}{15:X2}" -f `
        $hashBytes[0], $hashBytes[1], $hashBytes[2], $hashBytes[3], `
        $hashBytes[4], $hashBytes[5], `
        $hashBytes[6], $hashBytes[7], `
        $hashBytes[8], $hashBytes[9], `
        $hashBytes[10], $hashBytes[11], $hashBytes[12], $hashBytes[13], $hashBytes[14], $hashBytes[15]
    
    return $guid
}

# Function to determine if a project is SDK-style
function Test-SdkStyleProject {
    param([xml]$ProjectXml)
    
    # SDK-style projects have Sdk attribute on the Project element
    $sdkAttribute = $ProjectXml.Project.Sdk
    
    if ($sdkAttribute) {
        return $true
    }
    
    # Alternative: Check for Import with Sdk attribute
    $sdkImports = $ProjectXml.Project.Import | Where-Object { $_.Sdk }
    if ($sdkImports) {
        return $true
    }
    
    return $false
}

# Function to analyze a project and extract assembly information
function Get-AssemblyInfo {
    param(
        [string]$ProjectPath
    )
    
    if (-not (Test-Path -Path $ProjectPath)) {
        Write-Warning "Project file not found: $ProjectPath"
        return $null
    }
    
    try {
        [xml]$projectXml = Get-Content -Path $ProjectPath -Raw -ErrorAction Stop
        
        # Determine project style
        $isSdkStyle = Test-SdkStyleProject -ProjectXml $projectXml
        $projectStyle = if ($isSdkStyle) { "SDK-style" } else { "Legacy" }
        
        # Get PropertyGroups
        $propertyGroups = $projectXml.Project.PropertyGroup
        
        # Extract OutputType
        $outputType = "Library" # Default for SDK-style without explicit OutputType
        foreach ($propGroup in $propertyGroups) {
            if ($propGroup.OutputType) {
                $outputType = $propGroup.OutputType
                break
            }
        }
        
        # Extract AssemblyName
        $assemblyName = $null
        foreach ($propGroup in $propertyGroups) {
            if ($propGroup.AssemblyName) {
                $assemblyName = $propGroup.AssemblyName
                break
            }
        }
        
        # If no AssemblyName, use project file name
        if (-not $assemblyName) {
            $assemblyName = [System.IO.Path]::GetFileNameWithoutExtension($ProjectPath)
        }
        
        # Determine assembly file name and extension
        $assemblyExtension = switch ($outputType) {
            "Library" { ".dll" }
            "Exe" { ".exe" }
            "WinExe" { ".exe" }
            "Module" { ".netmodule" }
            default { ".dll" }
        }
        $assemblyFileName = "$assemblyName$assemblyExtension"
        
        # Extract TargetFramework or TargetFrameworks
        $targetFramework = "N/A"
        foreach ($propGroup in $propertyGroups) {
            if ($propGroup.TargetFramework) {
                $targetFramework = $propGroup.TargetFramework
                break
            }
            if ($propGroup.TargetFrameworks) {
                $targetFramework = $propGroup.TargetFrameworks
                break
            }
        }
        
        # For legacy projects, check TargetFrameworkVersion
        if ($targetFramework -eq "N/A" -and -not $isSdkStyle) {
            foreach ($propGroup in $propertyGroups) {
                if ($propGroup.TargetFrameworkVersion) {
                    $targetFramework = "net" + $propGroup.TargetFrameworkVersion.Replace("v", "").Replace(".", "")
                    break
                }
            }
        }
        
        # Count ProjectReference elements
        $projectReferences = $projectXml.SelectNodes("//*[local-name()='ProjectReference']")
        $projectCount = if ($projectReferences) { $projectReferences.Count } else { 0 }
        
        # Generate UniqueIdentifier based on project path and assembly name
        $uniqueString = "$ProjectPath|$assemblyName"
        $uniqueIdentifier = Get-GuidFromString -InputString $uniqueString
        
        return [PSCustomObject]@{
            UniqueIdentifier = $uniqueIdentifier
            Type = "Assembly"
            Name = $assemblyName
            AssemblyFileName = $assemblyFileName
            OutputType = $outputType
            ProjectStyle = $projectStyle
            TargetFramework = $targetFramework
        }
    }
    catch {
        Write-Warning "Error analyzing project '$ProjectPath': $_"
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

if ([string]::IsNullOrWhiteSpace($OutputCsvFile)) {
    $OutputCsvFile = Join-Path -Path $scanFolder -ChildPath "05_assemblies-info.csv"
}

# Main script execution
Write-Host "Identifying assemblies from projects..." -ForegroundColor Cyan
Write-Host ""

$results = @()

# Process Projects
if (Test-Path -Path $ProjectsListFile) {
    Write-Host "Reading projects from: $ProjectsListFile" -ForegroundColor Yellow
    $projectPaths = Get-Content -Path $ProjectsListFile | Where-Object { $_.Trim() -ne "" -and $_ -notmatch "^No project files found" }
    
    if ($projectPaths.Count -eq 0) {
        Write-Host "No project files to process." -ForegroundColor Yellow
    } else {
        $progressCounter = 0
        foreach ($path in $projectPaths) {
            $progressCounter++
            
            if ($progressCounter % 50 -eq 0) {
                Write-Host "  Processed $progressCounter / $($projectPaths.Count) projects..." -ForegroundColor Gray
            } else {
                Write-Host "Processing project: $path" -ForegroundColor Gray
            }
            
            $info = Get-AssemblyInfo -ProjectPath $path.Trim()
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

# Summary statistics
if ($results.Count -gt 0) {
    $dllCount = ($results | Where-Object { $_.OutputType -eq "Library" }).Count
    $exeCount = ($results | Where-Object { $_.OutputType -match "^(Exe|WinExe)$" }).Count
    $otherCount = $results.Count - $dllCount - $exeCount
    
    Write-Host "Assembly Summary:" -ForegroundColor Cyan
    Write-Host "  Total assemblies: $($results.Count)"
    Write-Host "  DLLs (Libraries): $dllCount" -ForegroundColor Green
    Write-Host "  EXEs (Executables): $exeCount" -ForegroundColor Green
    Write-Host "  Other: $otherCount" -ForegroundColor Gray
    Write-Host ""
}

# Export to CSV
if ($results.Count -gt 0) {
    $results | Export-Csv -Path $OutputCsvFile -NoTypeInformation -Encoding UTF8
    Write-Host "Successfully exported $($results.Count) record(s) to: $OutputCsvFile" -ForegroundColor Green
    
    # Append summary to scan info file
    if ($env:SCAN_INFO_FILE -and (Test-Path -Path $env:SCAN_INFO_FILE)) {
        $dllCount = ($results | Where-Object { $_.OutputType -eq "Library" }).Count
        $exeCount = ($results | Where-Object { $_.OutputType -match "^(Exe|WinExe)$" }).Count
        $otherCount = $results.Count - $dllCount - $exeCount
        
        $summary = "`n`n05_extract-assembly-info.ps1`n" + "=" * 50 + "`nTotal assemblies identified: $($results.Count)`nDLLs (Libraries): $dllCount`nEXEs (Executables): $exeCount`nOther: $otherCount`nOutput file: $OutputCsvFile"
        $summary | Out-File -FilePath $env:SCAN_INFO_FILE -Append -Encoding UTF8
    }
} else {
    Write-Warning "No assembly data to export. CSV file not created."
}

Write-Host "Assembly identification complete!" -ForegroundColor Cyan

# Return the results for potential use by other scripts
return $results
