#!/usr/bin/env bash
# claw-friends: seed.sh
# Manages seed profiles for cold-start community population
set -euo pipefail

OCFR_DIR="${HOME}/.ocfr"
REPO_DIR="${OCFR_DIR}/repo"

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  install     Copy seed profiles from templates/seeds/ into repo/profiles/"
    echo "  remove      Remove all seed profiles from repo/profiles/"
    echo "  count       Count seed vs real profiles"
    exit 1
}

ensure_repo() {
    if [ ! -d "${REPO_DIR}/.git" ]; then
        echo "ERROR: Repo not cloned. Run /friends init first."
        exit 1
    fi
}

get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

do_install() {
    ensure_repo

    local script_dir
    script_dir=$(get_script_dir)
    local seeds_dir="${script_dir}/../templates/seeds"

    if [ ! -d "${seeds_dir}" ]; then
        echo "ERROR: Seeds directory not found at ${seeds_dir}"
        exit 1
    fi

    local installed=0
    for seed_file in "${seeds_dir}"/*.yaml; do
        [ -f "${seed_file}" ] || continue
        local filename
        filename=$(basename "${seed_file}")
        local target="${REPO_DIR}/profiles/${filename}"

        # Only install if not already present (don't overwrite)
        if [ ! -f "${target}" ]; then
            cp "${seed_file}" "${target}"
            installed=$((installed + 1))
        fi
    done

    echo "OK: Installed ${installed} seed profiles."
}

do_remove() {
    ensure_repo

    local removed=0
    if [ -d "${REPO_DIR}/profiles" ]; then
        for profile in "${REPO_DIR}/profiles"/*.yaml; do
            [ -f "${profile}" ] || continue
            if grep -q 'is_seed: true' "${profile}" 2>/dev/null; then
                rm "${profile}"
                removed=$((removed + 1))
            fi
        done
    fi

    echo "OK: Removed ${removed} seed profiles."
}

do_count() {
    ensure_repo

    local total=0
    local seed=0
    if [ -d "${REPO_DIR}/profiles" ]; then
        total=$(find "${REPO_DIR}/profiles" -name "*.yaml" | wc -l | tr -d ' ')
        seed=$(grep -rl 'is_seed: true' "${REPO_DIR}/profiles/" 2>/dev/null | wc -l | tr -d ' ')
    fi
    local real=$((total - seed))

    echo "TOTAL:${total}"
    echo "SEED:${seed}"
    echo "REAL:${real}"
}

# --- Main ---

if [ $# -lt 1 ]; then
    usage
fi

case "$1" in
    install)
        do_install
        ;;
    remove)
        do_remove
        ;;
    count)
        do_count
        ;;
    *)
        usage
        ;;
esac
