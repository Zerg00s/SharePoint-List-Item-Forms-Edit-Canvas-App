# SharePoint List Item Forms: Edit Canvas App (YAML round-trip toolkit)

Two small Windows/PowerShell tools that let you round-trip a SharePoint **list customized form** (the Canvas app that renders New/Edit/Display panes for a list) through plain YAML, so you can edit it in VS Code, prompt AI tools like GitHub Copilot or Claude Code to refactor it, and push the edits back to the live list.

If you've tried this workflow before, you already know the frustrating part: none of the obvious paths work. `pac canvas` has no upload verb, the Import Package "Update" flow silently hides customized forms, Studio's new UI removed File > Open, and the canvas-authoring MCP server strips the control that makes a customized form a customized form. There is exactly one path that works end-to-end, and this repo automates the two finicky bits of it.

For the full story (including what doesn't work and why), see the accompanying blog post.

## Prerequisites

* Windows with Windows PowerShell 5.1 (the default)
* [Power Platform CLI](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction) (`pac`) on PATH. Install:
  ```
  dotnet tool install --global Microsoft.PowerApps.CLI.Tool
  ```
* A SharePoint Online list whose form you've already customized at least once (List > Integrate > Power Apps > Customize forms, then publish).

## Repo layout

```
SharePoint-List-Item-Forms-Edit-Canvas-App/
├── Get-VersionsUrl.ps1      # Tool 1: build the hidden Versions URL
├── Get-VersionsUrl.bat      # Double-click wrapper for Tool 1
└── form-edit/               # Tool 2: unpack > edit YAML > repack
    ├── Unpack-Form.ps1
    ├── Pack-Form.ps1
    ├── 1-Unpack.bat         # Double-click: unpack the zip in .\src
    ├── 2-Pack.bat           # Double-click: repack .\unpacked into .\dist
    ├── src/                 # drop the exported form .zip here
    ├── unpacked/            # pac-canvas-unpack output (edit YAML here)
    ├── dist/                # repacked .zip output lands here
    └── .staging/            # scratch area the scripts use internally
```

## Tool 1: `Get-VersionsUrl` (find the hidden Versions page)

Customized forms do not appear in the `make.powerapps.com` **Apps** list. The only way to download their package is through the **Versions** page, which you reach by URL splice:

```
https://make.powerapps.com/environments/<env-id>/apps/<app-id>/versions
```

This tool takes the form's Studio URL (from the browser address bar while the form is open in Power Apps Studio) and constructs the Versions URL for you.

### Usage

1. Open the customized form in Power Apps Studio (from SharePoint: List > Integrate > Power Apps > Customize forms).
2. Copy the full URL from your browser's address bar.
3. Double-click `Get-VersionsUrl.bat`.
4. Paste the URL at the prompt and press Enter.
5. The Versions URL is printed to the console and copied to your clipboard. Answer `y` to open it in your default browser.
6. On the Versions page, pick the live version and download the `.zip` package.

Supports both the `/e/<env>/` and `/environments/<env>/` URL shapes, and both the bare-GUID and fully-qualified (`/providers/Microsoft.PowerApps/apps/<GUID>`) forms of the `app-id` query parameter.

## Tool 2: `form-edit` (unpack > edit > repack)

This is the YAML round-trip loop. The outer `.zip` contains a nested `.msapp`, and the `.msapp` contains the actual Canvas app source. `pac canvas unpack` handles the inner format; the outer `.zip` has to be rebuilt with a very specific `[System.IO.Compression.ZipFile]::CreateFromDirectory(..., Optimal, includeBaseDirectory=false)` recipe or the Power Apps importer rejects it without explanation. The scripts take care of both.

### Usage

1. Drop the exported form `.zip` (from Tool 1) into `form-edit\src\`.
2. Double-click `form-edit\1-Unpack.bat`. You'll get a tree of `.pa.yaml` / `.fx.yaml` files under `form-edit\unpacked\`.
3. Edit the YAML files in VS Code. Ask Copilot or Claude Code to make the changes you want (rename controls, flip `Required` flags, restyle cards, add a new `DataCard`, etc.). The most useful file is usually `Src\FormScreen1.fx.yaml`.
4. Double-click `form-edit\2-Pack.bat`. The script repacks the YAML and drops an edited `.zip` into `form-edit\dist\`.

The scripts also accept bare `.msapp` input if you'd rather work with the `.msapp` directly (for example, to open it in Studio with File > Open). In that case the output is a `.msapp`, not a `.zip`.

## Uploading the edited `.zip` back to the list

`pac canvas` has no upload command, and the Import Package **Update** flow hides customized forms. The only path that works:

1. Go to **Power Platform Admin Center > Environments > [your env] > Resources > Canvas apps**, find the customized form by name, and delete it. (The binding from the SharePoint list to the form is resolved by **app name**, not ID, so deleting is safe as long as you re-import with the same name next.)
2. Go to **make.powerapps.com > Apps > Import canvas app** and upload the edited `.zip`.
3. In the conflict-resolution panel, pick **"Create as new"** (not "Update", which won't list the form anyway) and **keep the exact same app name** the original had.
4. Click Import. Within a few seconds the list's New/Edit/Display panes render your edited form.

Warn anyone else editing the form before deleting it. Keep the Versions URL from Tool 1 noted somewhere so you can restore from the recycle bin if an import fails.

## Why does this exist

Because hand-editing a form with 50+ cards in Studio is miserable, and because Microsoft's InfoPath Forms Services retires on **July 14, 2026** (publishing blocked from **May 18, 2026**), which means thousands of legacy InfoPath forms have to be rebuilt as Canvas-based list customized forms in a narrow window. Once the form's source is on disk as plain YAML, AI tooling can refactor dozens of cards in one pass, and this toolkit is what closes the loop back to the live list.

## Notes & caveats

* The `.staging` folder name starts with a dot; on some Windows setups it's hidden. Don't delete it manually while the scripts are running; the pack step uses it as a scratch area.
* Windows PowerShell 5.1 only. PowerShell 7 has a breaking change in `Out-File -Encoding UTF8` default behavior; the scripts haven't been validated there.
* The zip recipe (`CreateFromDirectory` with `includeBaseDirectory=false` and `CompressionLevel::Optimal`) is non-negotiable. `Compress-Archive`, `tar`, and most GUI zippers will produce archives that the Power Apps importer silently rejects.
