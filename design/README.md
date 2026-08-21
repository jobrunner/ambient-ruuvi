# App-Icon-Quelle

`app-icon.svg` ist die editierbare Quelle des App-Icons (Wassertropfen +
Funkwellen). Eigenständiges Artwork — nicht vom Ruuvi-Logo abgeleitet.

## Icon neu erzeugen

Das iOS-Marketing-Icon muss **1024×1024** und **deckend** (ohne Alphakanal)
sein. Aus der SVG rendern und den Alphakanal entfernen:

```sh
rsvg-convert -w 1024 -h 1024 design/app-icon.svg -o /tmp/icon-1024.png
magick /tmp/icon-1024.png -background '#0A3A47' -alpha remove -alpha off -strip \
  ambient-ruuvi/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

Die iPhone- (120 px) und iPad-Varianten (152 px) erzeugt `actool` beim Build
automatisch aus diesem Single-Size-Eintrag.
