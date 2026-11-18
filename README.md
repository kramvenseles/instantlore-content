# instantlore — content delivery mirror

A static mirror for the **instant-lore-mod** (Minecraft 1.21.11, Fabric).
The directory is served as-is via GitHub Pages.

Primary delivery is `https://play-cs2.com/lore/`. This mirror exists to give the
client a **second domain of failure**: the mod never auto-updates its own code,
so losing the single address would mean the content could never be updated again.
See the mod's `ARCHITECTURE.md`, "Security" section, for the full rationale.

## Nothing here to steal, nothing to abuse

All content is public by design: clients fetch it without any authentication.

Trust in the host is **not required at all**. `manifest.json` is signed with
Ed25519 and the public key is baked into the mod; the sha256 of every file is
listed inside the manifest and verified on load. A tampered or corrupted file is
rejected no matter who served it. A mirror can only fail to respond — it cannot lie.

## How it updates

Automatically, from `lore-content/deploy.sh` alongside the main delivery.
There is no need to commit here by hand: the whole directory is rebuilt from `publish/`.
