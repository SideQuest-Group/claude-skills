# SideQuest Claude Skills

Shared [Claude Code](https://claude.ai/code) skills for the SideQuest Group.

## Install

```sh
curl -fsSL get.ancla.dev/skills | bash
```

Or clone it and run the script yourself:

```sh
git clone https://github.com/SideQuest-Group/claude-skills.git
./claude-skills/install.sh
```

This clones the repo to `~/.claude/skills-src/sidequest/` and symlinks each skill into `~/.claude/skills/`. Run it again to update.

## Available skills

### ancla-buildpack

Sets up Buildpack-based builds for Ancla services. Handles CNB builder config, build-time env vars, pack CLI and kpack backends, and troubleshooting build failures. Triggers when you mention buildpacks, CNB, Paketo, or kpack in the context of Ancla.

Use it by typing `/ancla-buildpack` in Claude Code.

## Adding a skill

Drop a directory under `skills/` with a `SKILL.md` file. The frontmatter needs `name` and `description` fields — thats how Claude Code discovers it. Supporting docs go in the same directory.

```
skills/
  my-skill/
    SKILL.md          # required — frontmatter + instructions
    REFERENCE.md      # optional — extra context files
```

Run `install.sh` after adding a new skill to link it.

## Uninstall

Remove the symlinks and the source:

```sh
rm -rf ~/.claude/skills-src/sidequest
# then remove any symlinks in ~/.claude/skills/ that point there
```
