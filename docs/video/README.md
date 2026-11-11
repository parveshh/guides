# Overview video

A 45-second overview of Guides for the main README.

| File | Contents | Format |
| --- | --- | --- |
| [guides-promo.mp4](guides-promo.mp4) | Full video with music and sound effects | 1920×1080, 30 fps, H.264 with AAC audio, 44.9 s |
| [guides-promo.gif](guides-promo.gif) | Silent preview shown in the README | 720×405, 10 fps |

## What the video is

The video is a motion-graphics recreation, not a screen recording. The Guides interface was redrawn in HTML from the app's own documentation renders and animated with HyperFrames, an HTML-to-video renderer. No desktop was captured and the app's permissions and behaviour are unchanged.

- The pricing card, the code editor and the chat window are illustrative samples. The measurements shown (a 24px gap, a 320 × 200 px area, a 16px radius) are fixture values drawn to scale, not properties inspected from another app.
- Design px values appear only after the toolbar shows **Design px** and **Scale 100%**, as in the app.
- The agent scene illustrates the `$guides` skill. Its commands follow the [CLI reference](../../skills/guides/references/cli.md); they are not output from a recorded run, and the radii in them are the agent's visual fits. Guides does not read CSS, Figma layers or the DOM.
- The end-card ruler mark is drawn to match the menu bar symbol. The app has no separate icon file.
- Music and sound effects were generated with ElevenLabs. The mix was measured at −15.9 LUFS integrated with a −1.2 dBTP true peak.

The HyperFrames source project is not included in this repository.

## Regenerate the preview

From the repository root, with `ffmpeg` installed:

```sh
ffmpeg -y -i docs/video/guides-promo.mp4 \
  -vf "fps=10,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96:stats_mode=diff[p];[b][p]paletteuse=dither=none:diff_mode=rectangle" \
  docs/video/guides-promo.gif
```
