
<#PSScriptInfo

.VERSION 1.3

.GUID 5afb41c5-4043-48cb-9965-402a5c13ec5d

.AUTHOR Jakob Gillinger

.COMPANYNAME Cegeka GmbH

.COPYRIGHT Cegeka GmbH

.TAGS

.LICENSEURI

.PROJECTURI https://github.com/cegekaJG/Algogh-Manager

.ICONURI

.EXTERNALMODULEDEPENDENCIES GitHub.cli

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES
1.3) Fixed issue in which the script wouldn't search recursively
     Included repository name of base repository

#>

<#

.DESCRIPTION
A straightforward script that recursively updates all .app-packages defined in the AL-GO settings file. Created by modifying AL-GO for GitHub's 'ALGoHelper.ps1' and 'GitHubHelper.ps1' found @ https://github.com/microsoft/AL-Go
#>
Param(
    [string] $Path = $PWD.Path,
    [string] $dependenciesFolder = ".alpackages",
    [switch] $help,
    [switch] $h
)

if ($help -or $h) {
    Write-Host("Version 1.3. Downloads .app-packages defined in the AL-GO settings file. See https://github.com/cegekaJG/Algogh-Manager for instructions.")
    Write-Host("Options")
    Write-Host("  -Path <directory>              The path to the root directory of the repository, or the app directory containing the app.json manifest. Defaults to the current working directory.")
    Write-Host("  -DependenciesFolder <relative> The path to the location of the dependency apps, relative to the app folder. Defaults to '.alpackages'.")
    exit
}

$ErrorActionPreference = "stop"
Set-StrictMode -Version 2.0
if (Test-Path $path -ErrorAction Stop) {}   # Test if the given path is valid

$ALGoFolderName = '.AL-Go'
$ALGoSettingsFile = "$ALGoFolderName/settings.json"
$RepoSettingsFile = '.github/AL-Go-Settings.json'

function Get-RepoNameOfDirectory {
    Param(
        [parameter(position = 0)]
        [string] $Path = $PWD
    )

    $fullName = $null
    $pop = $false
    if ($Path -ne $PWD) {
        Push-Location
        Set-Location
        $pop = $true
    }

    try {
        $remoteUrl = & git remote get-url origin
        $remoteUrlSplit = $remoteUrl -split '/'
        $organization = $remoteUrlSplit[-2]
        $repoName = $remoteUrlSplit[-1]
        $lastIndex = $repoName.LastIndexOf('.git')
        if ($lastIndex -ge 0) {
            $repoName = $repoName.Substring(0, $lastIndex)
        }
        $fullName = "$organization/$repoName"
    }
    catch {}

    if ($pop) {
        Pop-Location
    }
    return $fullName
}

function Join-Uri($rootPath, $relativePath){
    if (-not ($rootPath.StartsWith("http://") -or $rootPath.StartsWith("https://"))) {
        $rootPath = Join-Path $rootPath $relativePath
    }
    elseif ($relativePath -ne '.' -and $relativePath -ne '*') {
        $rootPath = $rootPath + $relativePath
    }

    return $rootPath
}

function GetExtendedErrorMessage {
    Param(
        $errorRecord
    )

    $exception = $errorRecord.Exception
    $message = $exception.Message

    try {
        $errorDetails = $errorRecord.ErrorDetails | ConvertFrom-Json
        $message += " $($errorDetails.error)`n$($errorDetails.error_description)"
    }
    catch {}
    try {
        if ($exception -is [System.Management.Automation.MethodInvocationException]) {
            $exception = $exception.InnerException
        }
        $webException = [System.Net.WebException]$exception
        $webResponse = $webException.Response
        try {
            if ($webResponse.StatusDescription) {
                $message += "`n$($webResponse.StatusDescription)"
            }
        } catch {}
        $reqstream = $webResponse.GetResponseStream()
        $sr = new-object System.IO.StreamReader $reqstream
        $result = $sr.ReadToEnd()
        try {
            $json = $result | ConvertFrom-Json
            $message += "`n$($json.Message)"
        }
        catch {
            $message += "`n$result"
        }
        try {
            $correlationX = $webResponse.GetResponseHeader('ms-correlation-x')
            if ($correlationX) {
                $message += " (ms-correlation-x = $correlationX)"
            }
        }
        catch {}
    }
    catch{}
    $message
}

function CmdDo {
    Param(
        [string] $command = "",
        [string] $arguments = "",
        [switch] $silent,
        [switch] $returnValue,
        [string] $inputStr = ""
    )

    $oldNoColor = "$env:NO_COLOR"
    $env:NO_COLOR = "Y"
    $oldEncoding = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $command
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        if ($inputStr) {
            $pinfo.RedirectStandardInput = $true
        }
        $pinfo.WorkingDirectory = Get-Location
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $arguments
        $pinfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        if ($inputStr) {
            $p.StandardInput.WriteLine($inputStr)
            $p.StandardInput.Close()
        }
        $outtask = $p.StandardOutput.ReadToEndAsync()
        $errtask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit();

        $message = $outtask.Result
        $err = $errtask.Result

        if ("$err" -ne "") {
            $message += "$err"
        }

        $message = $message.Trim()

        if ($p.ExitCode -eq 0) {
            if (!$silent) {
                Write-Host $message
            }
            if ($returnValue) {
                $message.Replace("`r","").Split("`n")
            }
        }
        else {
            $message += "`n`nExitCode: "+$p.ExitCode + "`nCommandline: $command $arguments"
            throw $message
        }
    }
    finally {
        try { [Console]::OutputEncoding = $oldEncoding } catch {}
        $env:NO_COLOR = $oldNoColor
    }
}

function invoke-gh {
    Param(
        [parameter(mandatory = $false, ValueFromPipeline = $true)]
        [string] $inputStr = "",
        [switch] $silent,
        [switch] $returnValue,
        [parameter(mandatory = $true, position = 0)][string] $command,
        [parameter(mandatory = $false, position = 1, ValueFromRemainingArguments = $true)] $remaining
    )

    $arguments = "$command "
    $remaining | ForEach-Object {
        if ("$_".IndexOf(" ") -ge 0 -or "$_".IndexOf('"') -ge 0) {
            $arguments += """$($_.Replace('"','\"'))"" "
        }
        else {
            $arguments += "$_ "
        }
    }
    cmdDo -command gh -arguments $arguments -silent:$silent -returnValue:$returnValue -inputStr $inputStr
}

function MergeCustomObjectIntoOrderedDictionary {
    Param(
        [System.Collections.Specialized.OrderedDictionary] $dst,
        [PSCustomObject] $src
    )

    # Loop through all properties in the source object
    # If the property does not exist in the destination object, add it with the right type, but no value
    # Types supported: PSCustomObject, Object[] and simple types
    $src.PSObject.Properties.GetEnumerator() | ForEach-Object {
        $prop = $_.Name
        $srcProp = $src."$prop"
        $srcPropType = $srcProp.GetType().Name
        if (-not $dst.Contains($prop)) {
            if ($srcPropType -eq "PSCustomObject") {
                $dst.Add("$prop", [ordered]@{})
            }
            elseif ($srcPropType -eq "Object[]") {
                $dst.Add("$prop", @())
            }
            else {
                $dst.Add("$prop", $srcProp)
            }
        }
    }

    # Loop through all properties in the destination object
    # If the property does not exist in the source object, do nothing
    # If the property exists in the source object, but is of a different type, throw an error
    # If the property exists in the source object:
    # If the property is an Object, call this function recursively to merge values
    # If the property is an Object[], merge the arrays
    # If the property is a simple type, replace the value in the destination object with the value from the source object
    @($dst.Keys) | ForEach-Object {
        $prop = $_
        if ($src.PSObject.Properties.Name -eq $prop) {
            $dstProp = $dst."$prop"
            $srcProp = $src."$prop"
            $dstPropType = $dstProp.GetType().Name
            $srcPropType = $srcProp.GetType().Name
            if ($srcPropType -eq "PSCustomObject" -and $dstPropType -eq "OrderedDictionary") {
                MergeCustomObjectIntoOrderedDictionary -dst $dst."$prop" -src $srcProp
            }
            elseif ($dstPropType -ne $srcPropType -and !($srcPropType -eq "Int64" -and $dstPropType -eq "Int32")) {
                # Under Linux, the Int fields read from the .json file will be Int64, while the settings defaults will be Int32
                # This is not seen as an error and will not throw an error
                throw "property $prop should be of type $dstPropType, is $srcPropType."
            }
            else {
                if ($srcProp -is [Object[]]) {
                    $srcProp | ForEach-Object {
                        $srcElm = $_
                        $srcElmType = $srcElm.GetType().Name
                        if ($srcElmType -eq "PSCustomObject") {
                            # Array of objects are not checked for uniqueness
                            $ht = [ordered]@{}
                            $srcElm.PSObject.Properties | Sort-Object -Property Name -Culture "iv-iv" | ForEach-Object {
                                $ht[$_.Name] = $_.Value
                            }
                            $dst."$prop" += @($ht)
                        }
                        else {
                            # Add source element to destination array, but only if it does not already exist
                            $dst."$prop" = @($dst."$prop" + $srcElm | Select-Object -Unique)
                        }
                    }
                }
                else {
                    $dst."$prop" = $srcProp
                }
            }
        }
    }
}

# Read settings from the settings files
# Settings are read from the following files:
# - ALGoOrgSettings (github Variable)                 = Organization settings variable
# - .github/AL-Go-Settings.json                       = Repository Settings file
# - ALGoRepoSettings (github Variable)                = Repository settings variable
# - <project>/.AL-Go/settings.json                    = Project settings file
# - .github/<workflowName>.settings.json              = Workflow settings file
# - <project>/.AL-Go/<workflowName>.settings.json     = Project workflow settings file
# - <project>/.AL-Go/<userName>.settings.json         = User settings file
function ReadSettings {
    Param(
        [string] $baseFolder,
        [string] $repoName,
        [string] $project = '.',
        [string] $workflowName,
        [string] $userName,
        [string] $branchName,
        [string] $orgSettingsVariableValue,
        [string] $repoSettingsVariableValue,
        [string] $token
    )

    function GetSettingsObject  {
        Param(
            [string] $path,
            [string] $token
        )

        try {
            # If the path starts with http:// or https://, get the object via cUrl
            if ($path.StartsWith("http://") -or $path.StartsWith("https://")) {
                $contentInfo = & curl.exe -L $path -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $token" -H "X-GitHub-Api-Version: 2022-11-28" | ConvertFrom-Json

                if ($contentInfo.PSObject.Members['download_url']) {
                    $settings = & curl.exe -L -s $contentInfo.download_url -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $token" -H "X-GitHub-Api-Version: 2022-11-28" | ConvertFrom-Json
                }
            }
            elseif (Test-Path $path) {
                $settings = Get-Content $path -Encoding UTF8 | ConvertFrom-Json
            }
        }
        catch {
            throw "Error reading $path.`n$($_.Exception.Message)`n$($_.ScriptStackTrace)"
        }

        if ($settings) {
            return $settings
        }
        else {
            return $null
        }
    }

    $repoName = $repoName.SubString("$repoName".LastIndexOf('/') + 1)
    $githubFolder = Join-Uri $baseFolder ".github"
    $workflowName = $workflowName.Trim().Split([System.IO.Path]::getInvalidFileNameChars()) -join ""

    # Start with default settings
    $settings = [ordered]@{
        "type"                                   = "PTE"
        "unusedALGoSystemFiles"                  = @()
        "projects"                               = @()
        "country"                                = "us"
        "artifact"                               = ""
        "companyName"                            = ""
        "repoVersion"                            = "1.0"
        "repoName"                               = $repoName
        "versioningStrategy"                     = 0
        "runNumberOffset"                        = 0
        "appBuild"                               = 0
        "appRevision"                            = 0
        "keyVaultName"                           = ""
        "licenseFileUrlSecretName"               = "licenseFileUrl"
        "insiderSasTokenSecretName"              = "insiderSasToken"
        "ghTokenWorkflowSecretName"              = "ghTokenWorkflow"
        "adminCenterApiCredentialsSecretName"    = "adminCenterApiCredentials"
        "applicationInsightsConnectionStringSecretName" = "applicationInsightsConnectionString"
        "keyVaultCertificateUrlSecretName"       = ""
        "keyVaultCertificatePasswordSecretName"  = ""
        "keyVaultClientIdSecretName"             = ""
        "codeSignCertificateUrlSecretName"       = "codeSignCertificateUrl"
        "codeSignCertificatePasswordSecretName"  = "codeSignCertificatePassword"
        "additionalCountries"                    = @()
        "appDependencies"                        = @()
        "appFolders"                             = @()
        "testDependencies"                       = @()
        "testFolders"                            = @()
        "bcptTestFolders"                        = @()
        "installApps"                            = @()
        "installTestApps"                        = @()
        "installOnlyReferencedApps"              = $true
        "generateDependencyArtifact"             = $false
        "skipUpgrade"                            = $false
        "applicationDependency"                  = "18.0.0.0"
        "updateDependencies"                     = $false
        "installTestRunner"                      = $false
        "installTestFramework"                   = $false
        "installTestLibraries"                   = $false
        "installPerformanceToolkit"              = $false
        "enableCodeCop"                          = $false
        "enableUICop"                            = $false
        "customCodeCops"                         = @()
        "failOn"                                 = "error"
        "treatTestFailuresAsWarnings"            = $false
        "rulesetFile"                            = ""
        "assignPremiumPlan"                      = $false
        "enableTaskScheduler"                    = $false
        "doNotBuildTests"                        = $false
        "doNotRunTests"                          = $false
        "doNotRunBcptTests"                      = $false
        "doNotPublishApps"                       = $false
        "doNotSignApps"                          = $false
        "configPackages"                         = @()
        "appSourceCopMandatoryAffixes"           = @()
        "obsoleteTagMinAllowedMajorMinor"        = ""
        "memoryLimit"                            = ""
        "templateUrl"                            = ""
        "templateBranch"                         = ""
        "appDependencyProbingPaths"              = @()
        "useProjectDependencies"                 = $false
        "runs-on"                                = "windows-latest"
        "shell"                                  = "powershell"
        "githubRunner"                           = ""
        "cacheImageName"                         = "my"
        "cacheKeepDays"                          = 3
        "alwaysBuildAllProjects"                 = $false
        "environments"                           = @()
        "buildModes"                             = @()
    }

    # Read settings from files and merge them into the settings object

    $settingsObjects = @()
    # Read settings from organization settings variable (parameter)
    if ($orgSettingsVariableValue) {
        $orgSettingsVariableObject = $orgSettingsVariableValue | ConvertFrom-Json
        $settingsObjects += @($orgSettingsVariableObject)
    }
    # Read settings from repository settings file
    $repoSettingsObject = GetSettingsObject -Path (Join-Uri $baseFolder $RepoSettingsFile) -token $token
    $settingsObjects += @($repoSettingsObject)
    # Read settings from repository settings variable (parameter)
    if ($repoSettingsVariableValue) {
        $repoSettingsVariableObject = $repoSettingsVariableValue | ConvertFrom-Json
        $settingsObjects += @($repoSettingsVariableObject)
    }
    if ($project) {
        # Read settings from project settings file
        $projectFolder = Join-Uri $baseFolder $project -Resolve
        $projectSettingsObject = GetSettingsObject -Path (Join-Uri $projectFolder $ALGoSettingsFile) -token $token
        $settingsObjects += @($projectSettingsObject)
    }
    if ($workflowName) {
        # Read settings from workflow settings file
        $workflowSettingsObject = GetSettingsObject -Path (Join-Uri $gitHubFolder "$workflowName.settings.json") -token $token
        $settingsObjects += @($workflowSettingsObject)
        if ($project) {
            # Read settings from project workflow settings file
            $projectWorkflowSettingsObject = GetSettingsObject -Path (Join-Uri $projectFolder "$ALGoFolderName/$workflowName.settings.json") -token $token
            # Read settings from user settings file
            $userSettingsObject = GetSettingsObject -Path (Join-Uri $projectFolder "$ALGoFolderName/$userName.settings.json") #Todo: Get GH username
            $settingsObjects += @($projectWorkflowSettingsObject, $userSettingsObject)
        }
    }
    $settingsObjects | Where-Object { $_ } | ForEach-Object {
        $settingsJson = $_
        MergeCustomObjectIntoOrderedDictionary -dst $settings -src $settingsJson
        if ("$settingsJson" -ne "" -and $settingsJson.PSObject.Properties.Name -eq "ConditionalSettings") {
            $settingsJson.ConditionalSettings | ForEach-Object {
                $conditionalSetting = $_
                if ("$conditionalSetting" -ne "") {
                    $conditionMet = $true
                    $conditions = @()
                    if ($conditionalSetting.PSObject.Properties.Name -eq "branches") {
                        $conditionMet = $conditionMet -and ($conditionalSetting.branches | Where-Object { $branchName -like $_ })
                        $conditions += @("branchName: $branchName")
                    }
                    if ($conditionalSetting.PSObject.Properties.Name -eq "repositories") {
                        $conditionMet = $conditionMet -and ($conditionalSetting.repositories | Where-Object { $repoName -like $_ })
                        $conditions += @("repoName: $repoName")
                    }
                    if ($project -and $conditionalSetting.PSObject.Properties.Name -eq "projects") {
                        $conditionMet = $conditionMet -and ($conditionalSetting.projects | Where-Object { $project -like $_ })
                        $conditions += @("project: $project")
                    }
                    if ($workflowName -and $conditionalSetting.PSObject.Properties.Name -eq "workflows") {
                        $conditionMet = $conditionMet -and ($conditionalSetting.workflows | Where-Object { $workflowName -like $_ })
                        $conditions += @("workflowName: $workflowName")
                    }
                    if ($userName -and $conditionalSetting.PSObject.Properties.Name -eq "users") {
                        $conditionMet = $conditionMet -and ($conditionalSetting.users | Where-Object { $userName -like $_ })
                        $conditions += @("userName: $userName")
                    }
                    if ($conditionMet) {
                        Write-Host "${repository}: Applying conditional settings for $($conditions -join ", ")"
                        MergeCustomObjectIntoOrderedDictionary -dst $settings -src $conditionalSetting.settings
                    }
                }
            }
        }
    }

    $settings
}

# Convert a semantic version string to a semantic version object
# SemVer strings supported are defined under https://semver.org, additionally allowing a leading 'v' (as supported by GitHub semver sorting)
#
# The string has the following format:
#   if allowMajorMinorOnly is specified:
#     [v]major.minor.[patch[-addt0[.addt1[.addt2[.addt3[.addt4]]]]]]
#   else
#     [v]major.minor.patch[-addt0[.addt1[.addt2[.addt3[.addt4]]]]]
#
# Returns the SemVer object. The SemVer object has the following properties:
#   Prefix: 'v' or ''
#   Major: the major version number
#   Minor: the minor version number
#   Patch: the patch version number
#   Addt0: the first additional segment (zzz means not specified)
#   Addt1: the second additional segment (zzz means not specified)
#   Addt2: the third additional segment (zzz means not specified)
#   Addt3: the fourth additional segment (zzz means not specified)
#   Addt4: the fifth additional segment (zzz means not specified)
function SemVerStrToSemVerObj {
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $semVerStr,
        [switch] $allowMajorMinorOnly
    )

    $obj = New-Object PSCustomObject
    try {
        # Only allowed prefix is a 'v'.
        # This is supported by GitHub when sorting tags
        $prefix = ''
        $verstr = $semVerStr
        if ($semVerStr -like 'v*') {
            $prefix = 'v'
            $verStr = $semVerStr.Substring(1)
        }
        # Next part is a version number with 2 or 3 segments
        # 2 segments are allowed only if $allowMajorMinorOnly is specified
        $version = [System.Version]"$($verStr.split('-')[0])"
        if ($version.Revision -ne -1) { throw "not semver" }
        if ($version.Build -eq -1) {
            if ($allowMajorMinorOnly) {
                $version = [System.Version]"$($version.Major).$($version.Minor).0"
                $idx = $semVerStr.IndexOf('-')
                if ($idx -eq -1) {
                    $semVerStr = "$semVerStr.0"
                }
                else {
                    $semVerstr = $semVerstr.insert($idx, '.0')
                }
            }
            else {
                throw "not semver"
            }
        }
        # Add properties to the object
        $obj | Add-Member -MemberType NoteProperty -Name "Prefix" -Value $prefix
        $obj | Add-Member -MemberType NoteProperty -Name "Major" -Value ([int]$version.Major)
        $obj | Add-Member -MemberType NoteProperty -Name "Minor" -Value ([int]$version.Minor)
        $obj | Add-Member -MemberType NoteProperty -Name "Patch" -Value ([int]$version.Build)
        0..4 | ForEach-Object {
            # default segments to 'zzz' for sorting of SemVer Objects to work as GitHub does
            $obj | Add-Member -MemberType NoteProperty -Name "Addt$_" -Value 'zzz'
        }
        $idx = $verStr.IndexOf('-')
        if ($idx -gt 0) {
            $segments = $verStr.SubString($idx+1).Split('.')
            if ($segments.Count -gt 5) {
                throw "max. 5 segments"
            }
            # Add all 5 segments to the object
            # If the segment is a number, it is converted to an integer
            # If the segment is a string, it cannot be -ge 'zzz' (would be sorted wrongly)
            0..($segments.Count-1) | ForEach-Object {
                $result = 0
                if ([int]::TryParse($segments[$_], [ref] $result)) {
                    $obj."Addt$_" = [int]$result
                }
                else {
                    if ($segments[$_] -ge 'zzz') {
                        throw "Unsupported segment"
                    }
                    $obj."Addt$_" = $segments[$_]
                }
            }
        }
        # Check that the object can be converted back to the original string
        $newStr = SemVerObjToSemVerStr -semVerObj $obj
        if ($newStr -cne $semVerStr) {
            throw "Not equal"
        }
    }
    catch {
        throw "'$semVerStr' cannot be recognized as a semantic version string (https://semver.org)"
    }
    $obj
}

function GetReleases {
    Param(
        [string] $token,
        [string] $repository
    )

    Write-Host "${repository}: Analyzing releases..."
    $releases = @(invoke-gh -silent -returnValue api "/repos/$repository/releases" | ConvertFrom-Json)
    if ($releases.Count -gt 1) {
        # Sort by SemVer tag
        try {
            $sortedReleases = $releases.tag_name |
                ForEach-Object { SemVerStrToSemVerObj -semVerStr $_ } |
                Sort-Object -Property Major,Minor,Patch,Addt0,Addt1,Addt2,Addt3,Addt4 -Descending |
                ForEach-Object { SemVerObjToSemVerStr -semVerObj $_ } | ForEach-Object {
                    $tag_name = $_
                    $releases | Where-Object { $_.tag_name -eq $tag_name }
                }
            $sortedReleases
        }
        catch {
            Write-Host "::Warning::Some of the release tags cannot be recognized as a semantic version string (https://semver.org). Using default GitHub sorting for releases, which will not work for release branches"
            $releases
        }
    }
    else {
        $releases
    }
}

function Get-Dependencies {
    Param(
        $probingPathsJson,
        [string] $dependenciesFolder
    )

    if (!(Test-Path $dependenciesFolder)) {
        New-Item $dependenciesFolder -ItemType Directory | Out-Null
    }

    $downloadedList = @()
    $probingPathsJson | ForEach-Object {
        $dependency = $_
        $projects = $dependency.projects
        $repository = ([uri]$dependency.repo).AbsolutePath.Replace(".git", "").TrimStart("/")

        if ($dependency.release_status -ne "thisBuild" -and $dependency.release_status -ne "include") {
            $releases = GetReleases -token $dependency.authTokenSecret -repository $repository
            if ($dependency.version -ne "latest") {
                $releases = $releases | Where-Object { ($_.tag_name -eq $dependency.version) }
            }

            switch ($dependency.release_status) {
                "release" { $release = $releases | Where-Object { -not ($_.prerelease -or $_.draft ) } | Select-Object -First 1 }
                "prerelease" { $release = $releases | Where-Object { ($_.prerelease ) } | Select-Object -First 1 }
                "draft" { $release = $releases | Where-Object { ($_.draft ) } | Select-Object -First 1 }
                Default { throw "Invalid release status '$($dependency.release_status)' is encountered." }
            }

            if (!($release)) {
                throw "Could not find a release that matches the criteria."
            }

            'Apps','TestApps' | ForEach-Object {
                $download = DownloadRelease -token $dependency.authTokenSecret -projects $projects -repository $repository -path $dependenciesFolder -release $release -mask $_
                if ($download) {
                    if ($_ -eq 'TestApps') {
                        $downloadedList += @("($download)")
                    }
                    else {
                        $downloadedList += @($download)
                    }
                }
            }
        }
    }
    return $downloadedList
}

function DownloadRelease {
    Param(
        [string] $token,
        [string] $projects = "*",
        [string] $repository,
        [string] $path,
        [string] $mask = "Apps",
        $release
    )

    if ($projects -eq "") { $projects = "*" }
    Write-Host "${repository}: Checking release $($release.Name), type $mask"

    # Get token if it is missing
    if ([string]::IsNullOrEmpty($token)) {
        $authstatus = (invoke-gh -silent -returnValue auth status --show-token) -join " "
        $token = $authStatus.SubString($authstatus.IndexOf('Token: ')+7).Trim().Split(' ')[0]
        $token = invoke-gh -silent -returnValue auth status token
    }

    # TODO: Support for multiple projects
    $listpath = Join-Path $dependenciesFolder "dependencies.json"
    $list = @{}
    if (Test-Path $listpath) {
        $rlist = Get-Content $listpath | ConvertFrom-Json
        $rlist.PsObject.Members | Where-Object {$_.MemberType -eq 'NoteProperty'} | ForEach-Object {
            $list[$_.name] = $_.value
        }
    }

    $projects.Split(',') | ForEach-Object {
        $project = $_.Replace('\','_').Replace('/','_')
        if ($project -ne "*") {
            Write-Host "- Project '$project'"
        }

        $release.assets | Where-Object { $_.name -like "$project-*-$mask-*.zip" -or $_.name -like "$project-$mask-*.zip" } | ForEach-Object {
            $name = $_.name

            # Check if a download is required
            if ($list.ContainsKey($name)) {
                if ($_.created_at -le $list.$name) {
                    return
                }
                else {
                    $list.Remove($name)
                }
            }

            # Download the asset, extract it and add the timestamp to the dependency doc
            try {
                Write-Host "- Downloading $name..."
                $archivename = Join-Path $path $name
                & curl.exe -L $_.url -o $archivename -H "Accept: application/octet-stream" -H "Authorization: Bearer $token" -H "X-GitHub-Api-Version: 2022-11-28"
                Expand-Archive $archivename -DestinationPath $path -Force
                Remove-Item $archivename

                # Add the new timestamp to the dependency doc and save it
                $list[$name] = $_.created_at
                ConvertTo-Json $list | Set-Content $listpath

                return $name
            }
            catch {
                Write-Host -ForegroundColor Red "Error trying to retrieve $name."
                Write-Host -ForegroundColor Red $_.Exception.Message
            }
        }
    }
}

function Start-GitHubSession {
    try {
        $authStatus = invoke-gh -returnValue -silent auth status
    }
    catch {
        & gh auth login --web
        $authStatus = invoke-gh -returnValue -silent auth status
    }
    $authStatus = $authStatus[1]
    $index = $authstatus.IndexOf('Logged in to github.com as')+27
    return $authStatus.SubString($index).Trim().Split(' ')[0]
}

function Get-GitHubToken {
    $retry = $true
    while ($retry) {
        try {
            $authTokenSecret = invoke-gh -silent -returnValue auth token
            $retry = $false
        }
        catch {
            Write-Host -ForegroundColor Red "Error trying to retrieve GitHub token."
            Write-Host -ForegroundColor Red $_.Exception.Message
            Read-Host "Press ENTER to retry operation (or Ctrl+C to cancel)"
        }
    }
    return $authTokenSecret
}

function Complete-DependencyPaths {
    Param(
        [hashTable] $settings,
        [string] $token,
        [string] $repository
    )

    if ($settings.appDependencyProbingPaths) {
        $server_url = "https://github.com/"
        Write-Host "${repository}: Checking appDependencyProbingPaths"
        $settings.appDependencyProbingPaths = @($settings.appDependencyProbingPaths | ForEach-Object {
            if ($_.GetType().Name -eq "PSCustomObject") {
                $_
            }
            else {
                New-Object -Type PSObject -Property $_
            }
        })
        $settings.appDependencyProbingPaths | ForEach-Object {
            $dependency = $_
            if (-not ($dependency.PsObject.Properties.name -eq "repo")) {
                throw "${repository}: appDependencyProbingPaths needs to contain a repo property, pointing to the repository on which you have a dependency"
            }
            if ($dependency.Repo -eq ".") {
                $dependency.Repo = "$server_url/$repository"
            }
            elseif ($dependency.Repo -notlike "https://*") {
                $dependency.Repo = "$server_url/$($dependency.Repo)"
            }
            if (-not ($dependency.PsObject.Properties.name -eq "Version")) {
                $dependency | Add-Member -name "Version" -MemberType NoteProperty -Value "latest"
            }
            if (-not ($dependency.PsObject.Properties.name -eq "projects")) {
                $dependency | Add-Member -name "projects" -MemberType NoteProperty -Value "*"
            }
            elseif ([String]::IsNullOrEmpty($dependency.projects)) {
                $dependency.projects = '*'
            }
            if (-not ($dependency.PsObject.Properties.name -eq "release_status")) {
                $dependency | Add-Member -name "release_status" -MemberType NoteProperty -Value "release"
            }
            if (-not ($dependency.PsObject.Properties.name -eq "branch")) {
                $dependency | Add-Member -name "branch" -MemberType NoteProperty -Value "main"
            }
            if (-not ($dependency.PsObject.Properties.name -eq "AuthTokenSecret")) {
                $dependency | Add-Member -name "AuthTokenSecret" -MemberType NoteProperty -Value $token
            }
            if (-not ($dependency.PsObject.Properties.name -eq "alwaysIncludeApps")) {
                $dependency | Add-Member -name "alwaysIncludeApps" -MemberType NoteProperty -Value @()
            }
            elseif ($dependency.alwaysIncludeApps -is [string]) {
                $dependency.alwaysIncludeApps = $dependency.alwaysIncludeApps.Split(' ')
            }
            if ($dependency.alwaysIncludeApps) {
                Write-Host "${repository}: Always including apps: $($dependency.alwaysIncludeApps -join ", ")"
            }
        }
    }

    $settings
}

function Get-AppsOfDependencies {
    Param(
        $probingPathsJson,
        [string]$dependenciesFolder
    )

    $downloaded = @()

    $probingPathsJson | ForEach-Object {
        $dependency = $_
        $projects = $dependency.projects
        $repository = ([uri]$dependency.repo).AbsolutePath.Replace(".git", "").TrimStart("/")

        # Recursively get dependencies of the repository
        $downloaded += Get-AppsOfRepo -repository $repository -project $projects -dependenciesFolder $dependenciesFolder -token $dependency.authTokenSecret
    }
    $downloaded
}

function Get-AppsOfRepo {
    Param(
        [string] $repository,
        [string] $baseFolder = "https://api.github.com/repos/$repository/contents/",
        [string] $project = '.',
        [string] $dependenciesFolder,
        [string] $token
    )

    if (-not ($baseFolder.StartsWith("http://") -or $baseFolder.StartsWith("https://"))) {
        $projectFolder = Join-Path $baseFolder $project -Resolve
    }
    elseif ($project -ne '.' -and $project -ne '*') {
        $projectFolder = $baseFolder + $project
    }

    $params = @{
        "baseFolder" = $baseFolder
        "project" = $project
        "workflowName" = "UpdateDependencies"
        "token" = $token
    }

    $settings = ReadSettings @params

    if ($settings.Contains("appDependencyProbingPaths")) {
        $authTokenSecret = Get-GitHubToken
        $settings.appDependencyProbingPaths | ForEach-Object {
            $_.authTokenSecret = $authTokenSecret
        }
    }

    $settings = Complete-DependencyPaths -settings $settings -token $token -repository $repository

    $params = @{
        "settings" = $settings
        "baseFolder" = $projectFolder
        "doNotRunTests" = $true
        "doNotRunBcptTests" = $true
    }

    $downloaded = @()

    if ($settings.appDependencyProbingPaths) {
        if (-not (Test-Path $dependenciesFolder)) {
            New-Item $dependenciesFolder -ItemType Directory | Out-Null
        }

        $settings.appDependencyProbingPaths = @($settings.appDependencyProbingPaths | ForEach-Object {
            if ($_.GetType().Name -eq "PSCustomObject") {
                $_
            }
            else {
                New-Object -Type PSObject -Property $_
            }
        })

        Write-Host "${repository}: Locating all artifacts from probing paths."
        $downloaded += Get-AppsOfDependencies -probingPathsJson $settings.appDependencyProbingPaths -dependenciesFolder $dependenciesFolder
        $downloaded += Get-Dependencies -probingPathsJson $settings.appDependencyProbingPaths -dependenciesFolder $dependenciesFolder
    }
    $downloaded
}

function Get-AppFolder {
    Param(
        [parameter(Mandatory = $true)]
        [string]$baseFolder,
        [string]$project = '.'
    )

    if ($project -ne '.') {
        return Join-Path $baseFolder $project -Resolve
    }

    $subDirectories = Get-ChildItem -Path $baseFolder -Directory

    # Loop through each subdirectory and look for the app.json file
    foreach ($subDirectory in $subDirectories) {
        $appPath = Join-Path $subDirectory.FullName "app.json"

        # Check if the app.json file exists within the current subdirectory
        if (Test-Path $appPath) {
            # If the app.json file exists, return the path to the subdirectory and exit the script
            Write-Host "Using $($subDirectory.Name) as app folder."
            return $subDirectory.FullName
        }
    }

    throw "No valid app folder found: Could not find app.json file in any subdirectory of $baseFolder"
}

$Project = "."
$repoName = Get-RepoNameOfDirectory $Path

if (Test-Path (Join-Path $Path 'app.json')) {
    $projectFolder = $Path
    $Path = (Join-Path $Path '..' -Resolve)
} else {
    $projectFolder = Get-AppFolder -baseFolder $Path -project $Project
}

$dependenciesFolder = Join-Path $projectFolder $dependenciesFolder
$userName = Start-GitHubSession

$params = @{
    'baseFolder' = $Path
    'dependenciesFolder' = $dependenciesFolder
}

if (![string]::IsNullOrEmpty($Project)) {
    $params += @{ 'project' = $Project}
}
if (![string]::IsNullOrEmpty($repoName)) {
    $params += @{ 'repository' = $repoName}
}

$downloaded = Get-AppsOfRepo @params

if ($null -ne $downloaded) {
    Write-Host "Downloaded the following dependencies:"
    $downloaded
} else {
    Write-Host "No new artifacts to download."
}
