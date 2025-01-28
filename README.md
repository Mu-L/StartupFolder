<p align="center">
    <a href="https://lowtechguys.com/startupfolder"><img width="128" height="128" src="StartupFolder/Assets.xcassets/AppIcon.appiconset/256.png" style="filter: drop-shadow(0px 2px 4px rgba(80, 50, 6, 0.2));"></a>
    <h1 align="center"><code style="text-shadow: 0px 3px 10px rgba(8, 0, 6, 0.35); font-size: 3rem; font-family: ui-monospace, Menlo, monospace; font-weight: 800; background: transparent; color: #4d3e56; padding: 0.2rem 0.2rem; border-radius: 6px">Startup Folder</code></h1>
    <h4 align="center" style="padding: 0; margin: 0; font-family: ui-monospace, monospace;">Run anything at startup</h4>
    <h6 align="center" style="padding: 0; margin: 0; font-family: ui-monospace, monospace; font-weight: 400;">By placing it in a special folder</h6>
</p>

<p align="center">
    <a href="https://files.lowtechguys.com/releases/StartupFolder.dmg">
        <img width=200 src="https://files.lowtechguys.com/macos-app.svg">
    </a>
</p>

### Run anything at startup

The app creates a `Startup` folder in your home directory. Anything you place in this folder will run at startup automatically.

You can place **apps**, **scripts**, **Shortcuts**, **links**, and really anything you want in the folder.

![Startup Folder UI](https://lowtechguys.com/static/img/startupfolder-ui.png)

#### How it works?

> The app is designed to be as simple as possible. It runs a background agent that launches and keeps track of startup items.
>
> The agent uses zero resources and has no impact on your system's performance.


### Drag and drop

**Apps** can be dragged with `Command-Option` to create an *alias*. **Links** can be dragged directly from the browser address bar.

**Shortcuts** simply need an empty file named `Shortcut Name.shortcut` and **scripts** can be written directly inside the folder.

The app also provides a convenient interface that helps you *choose apps*, *pick Shortcuts*, *create scripts* and manage the startup items.
