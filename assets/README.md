# Assets

`wallpaper.jpg` is "silhouette of off-road car" by Jonatan Pie (@r3dmax),
https://unsplash.com/photos/h8nxGssjQXs, under the Unsplash License. Set on
every desktop by `bin/macos-post-defaults`.

`librewolf-policies.plist` holds LibreWolf's enterprise policies.
`bin/librewolf-policies` writes each top-level key into the
`net.librewolf.librewolf` defaults domain, and only a personal Mac's bootstrap
runs it. It lives here, not in `config/`, because nothing links it.

If the file is missing, fetch it once:

```sh
curl -fsSL -o assets/wallpaper.jpg "https://unsplash.com/photos/h8nxGssjQXs/download?force=true"
```
