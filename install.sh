#!/usr/bin/env bash
set -euo pipefail

REPO="SideQuest-Group/claude-skills"
SKILLS_SRC="${HOME}/.claude/skills-src/sidequest"
SKILLS_DIR="${HOME}/.claude/skills"

mkdir -p "${SKILLS_DIR}"

# clone or pull
if [[ -d "${SKILLS_SRC}/.git" ]]; then
    echo "updating ${SKILLS_SRC}"
    git -C "${SKILLS_SRC}" pull --ff-only
else
    echo "cloning ${REPO}"
    mkdir -p "$(dirname "${SKILLS_SRC}")"
    git clone "https://github.com/${REPO}.git" "${SKILLS_SRC}"
fi

# symlink each skill
linked=0
for skill_dir in "${SKILLS_SRC}/skills"/*/; do
    skill_name="$(basename "${skill_dir}")"
    target="${SKILLS_DIR}/${skill_name}"

    if [[ -L "${target}" ]]; then
        echo "  ${skill_name}: already linked"
    elif [[ -d "${target}" ]]; then
        echo "  ${skill_name}: exists (not a symlink, skipping)"
    else
        ln -s "${skill_dir}" "${target}"
        echo "  ${skill_name}: linked"
    fi
    linked=$((linked + 1))
done

echo "done — ${linked} skill(s) available"
