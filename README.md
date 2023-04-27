# Algogh Manager

**AL**-**GO** for **G**it**H**ub Manager

A straightforward script that recursively updates all `.app`-packages defined in the AL-GO settings file.

## Installation

You will need GitHub CLI to run this script.
Get it either using Windows Package Manager:
`winget install --id GitHub.cli`
Or download the installer from the [website](https://cli.github.com/)

To install the latest version of Algogh Manager using PowerShellGet, use the following command:
`Install-Script -Name AlgoghManager`
To update, use
`Update-Script -Name AlgoghManager`

You may have to restart the console for the installation to take effect.

## Usage

To start the script, run the following command from your app directory:

`Update-Algogh`

Algogh Manager requires a repository with a minimum of the following structure:

```txt
<root>
  L <app>
  |  L app.json
  L .AL-GO
     L settings.json
```

The script will download and/or update the app packages in the `<app>/.alpackages` directory. Any dependencies should be defined in the `.AL-GO/settings.json` manifest, as instructed by [this guide](https://github.com/microsoft/AL-Go/blob/main/Scenarios/AppDependencies.md).
When retrieving an artifact from a repository, Algogh Manager will automatically scan its `.AL-GO/settings.json` manifest for further dependencies and attempt to download those. It will skip any artifacts that have already been downloaded, and update if a newer version has been found. If artifacts of test apps are available, it will download those as well.

To be specific, Algogh will currently only download any matching release assets and extracts the to the dependencies folder. It will not download any artifacts defined in the `app.json` manifest or publish the dependencies to a server, local or otherwise.

## Uninstalling

To uninstall Algogh Manager, just type `Uninstall-Module -Name AlgoghManager`.

## Known Issues

Algogh Manager currently has only been tested on repositories with a single app. Behavior with test-apps and multiple projects is unknown.

## Wishlist

- Multi-project support
- Read app folders from `settings.json`
- Download artifacts from `app.json`
- Publish all downloaded artifacts to local server
