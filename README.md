# Algogh Manager

**AL**-**GO** for **G**it**H**ub Manager

A straightforward script that recursively updates all `.app`-packages defined in the AL-GO settings file.

## Installation

You will need GitHub CLI to run this script.
Get it either using Windows Package Manager:
`winget install --id GitHub.cli`
Or download the installer from the [website](https://cli.github.com/)

To install the latest version of Algogh Manager using PowerShellGet, use the following command:
`Install-Module -Name AlgoghManager`
To update, use
`Update-Module -Name AlgoghManager`

## Usage

Algogh Manager requires a repository with a minimum of the following structure:

```txt
<root>
  L <app>
  |  L app.json
  L .AL-GO
     L settings.json
```

With the root folder of the repository as the current working directory, type `Update-AlgoghManager` to download and/or update the app packages in the `<app>/.alpackages` folder. Any dependencies should be defined in the `.AL-GO/settings.json` manifest, as instructed by [this guide](https://github.com/microsoft/AL-Go/blob/main/Scenarios/AppDependencies.md).
When retrieving an artifact from a repository, Algogh Manager will automatically search that repository's `.AL-GO/settings.json` manifest for further dependencies and attempt to download those. It will skip any artifacts that have already been downloaded, and update if a newer version has been found. If artifacts of test apps are available, it will download those as well.

To be specific, Algogh will currently only download any matching release assets and extracts the to the dependencies folder. It will not download any artifacts defined in the `app.json` manifest or publish the dependencies to a server, local or otherwise.

## Uninstalling

To uninstall Algogh Manager, just type `Uninstall-Module -Name AlgoghManager`.
