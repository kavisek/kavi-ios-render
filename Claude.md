
# Production Philosphy

- Extensible
- Scalable: Optimized for Perforamnce
- Elegant:
- Dynamic:
- Simple

# Features

- `render start` (or bare `render`): opens a video player. Pick an .mp4
  via Cmd+O / Open Video, plays with AVKit's native controls.
- iPhone and iPad: same app and filter. Open videos from Files or Photos.
  `make start-ios` / `make start-ipad` run it in the simulator, and
  `make add-video VIDEO=…` adds a test video to the simulator's Photos.
  See adr/004-ios-and-ipados.md.
- CRT filter: Filters button (Cmd+Shift+F) opens a side panel to toggle a
  90s CRT look over the playing video, pick a preset (Living Room TV,
  Arcade Cabinet, PC Monitor, Worn VHS, Subtle) and tune every parameter
  live. See adr/003-crt-filter.md.
- `render add`: placeholder, not yet implemented.
- `render version`: prints the VERSION file's semantic version.
- `render help`: usage.
