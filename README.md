# URJA Community Microgrid (PS #38, Aarambh WCE Hackathon 2026)

AC community microgrid: MATLAB plant, 4 ESP32 node controllers, MATLAB main
controller, Raspberry Pi dashboard. The working system is **`mg_hier/`**.

```
Commuinty_Micro_Grid/
  mg_hier/              CURRENT SYSTEM - code, firmware, tests, data (see mg_hier/README.md)
  docs/
    competition/        rulebook, problem statements, presentation decks (v2..v6)
    team/               team briefing, Pi IoT server setup, component list, AI/ML inputs
    reference/          background material and reference projects
    roadmap/            post-hackathon roadmap
    images/             architecture pictures, screenshots
    claude_outputs/     files produced by Claude for the team
  archive/              earlier generations, kept for reference only - do not develop here
    mg_twin/            12 V DC digital twin (first model, own git history)
    mg_ac/              AC single-controller version (hackathon Plan B)
    mg_ac.rar, mg_hier_src.tgz   old snapshots
```

Rules
- Work on a git branch, never directly on `master`. `hackathon-final` tags what was presented.
- Raw datasets (`mg_hier/data/raw/`) are not in git; re-download with `mg_hier/tools/data/`.
- Keep this folder out of Google Drive sync (it corrupts `.git`); GitHub is the backup.
- Learning manual: "mg_hier Learning Manual" (Claude doc, linked in the project progress report).
