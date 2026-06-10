# Factorio Mods

A small collection of mods for Factorio 2.0. Each mod lives in its own folder
with its own `info.json`, `Makefile`, and `LICENSE`.

## Mods

- **[Improved Item Names](improved-item-names/)**: renames circuits, belts,
  inserters, chests, and science packs to the community color names, keeping the
  originals in parentheses so search still works.
- **[Friend Cam](friend-cam/)**: a movable multiplayer window with a live
  camera that follows another player, with a picker and zoom.
- **[Production Tracker](production-tracker/)**: a live window of every item
  produced on the current surface, with per-second/minute rates, sorting, and search.

## Usage

```sh
cd <mod-folder>
make install    # symlink into your Factorio mods folder (dev)
make zip        # build <mod>_<version>.zip for the portal
```

## License

MIT. Each mod folder contains its own `LICENSE`.
