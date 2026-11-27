# The map's source

[`map.excalidraw`](map.excalidraw) is the source of [`../map.png`](../map.png).
It follows the diagram rules of WizSkills' `image` skill: the Excalidraw
hand-drawn look, the Virgil font, an off-white background, coloured rounded
frames for where things run, bold black boxes with one grey line under the
name, few boxes and lots of space.

## Change it

1. Open `map.excalidraw` in Excalidraw (excalidraw.com, File > Open), edit
   it, and save it back here. Keep text in Virgil (the hand-drawn font).
2. Render the PNG with Excalidraw's own exporter, pinned in
   [`render.html`](render.html): serve this folder
   (`python3 -m http.server` here), open `render.html` in a browser and
   save the image as `docs/map.png`. It renders at twice the scene's size.
   The page loads the exporter from esm.sh; a headless browser can read the
   same PNG from `#out` once `body` has `data-ready="true"`: its text is
   `PNG:` and then the PNG as base64, or `ERROR:` and the error.
3. Look at the new PNG before committing it: labels readable, nothing
   overlapping, every frame still showing where things run.
