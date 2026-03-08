#!/usr/bin/env bash
# Convenience script for playing catacombs on local katana.
# Usage:
#   ./scripts/play.sh create-cat <repo_hash>
#   ./scripts/play.sh get-cat <cat_id>
#   ./scripts/play.sh start-run <cat_id>
#   ./scripts/play.sh get-run <run_id>
#   ./scripts/play.sh get-node <run_id> <node_id>
#   ./scripts/play.sh choose-path <run_id> <node_id>
#   ./scripts/play.sh submit-scenario <run_id> <node_id> <scenario_hash>
#   ./scripts/play.sh resolve <run_id> <node_id> <skill_hash> <result:1-3> <hp_delta> <xp> <loot_id>
#   ./scripts/play.sh get-encounter <run_id> <node_id>
#   ./scripts/play.sh show-map <run_id>

set -e
export PATH="/home/paul/.dojo/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../contracts"

CMD="$1"
shift || true

node_type_name() {
    case "$1" in
        0) echo "Start" ;;
        1) echo "Combat" ;;
        2) echo "Treasure" ;;
        3) echo "Rest" ;;
        4) echo "Event" ;;
        5) echo "Shop" ;;
        6) echo "Boss" ;;
        *) echo "Unknown($1)" ;;
    esac
}

result_name() {
    case "$1" in
        0) echo "Pending" ;;
        1) echo "Success" ;;
        2) echo "Partial" ;;
        3) echo "Failure" ;;
        *) echo "Unknown($1)" ;;
    esac
}

parse_hex() {
    printf "%d" "$1" 2>/dev/null
}

connections_to_nodes() {
    local conn=$1
    local nodes=""
    for i in $(seq 0 7); do
        if (( (conn >> i) & 1 )); then
            nodes="$nodes $i"
        fi
    done
    echo "$nodes"
}

case "$CMD" in
    create-cat)
        echo "Creating cat with repo_hash=$1..."
        sozo execute --diff catacombs-cat_actions create_cat "$1" --wait
        ;;

    get-cat)
        raw=$(sozo call --diff catacombs-cat_actions get_cat "$1" 2>&1)
        # Parse the array
        vals=()
        for hex in $(echo "$raw" | tr -d '[],' | tr ' ' '\n' | grep '0x0x'); do
            vals+=("$(parse_hex "${hex#0x}")")
        done
        echo "=== Cat #${vals[0]} ==="
        echo "  Owner:    $(echo "$raw" | tr ' ' '\n' | grep '0x0x' | sed -n '2p' | sed 's/0x0x/0x/')"
        echo "  Repo:     ${vals[2]}"
        echo "  HP:       ${vals[3]}/${vals[4]}"
        echo "  Level:    ${vals[5]}"
        echo "  XP:       ${vals[6]}"
        echo "  ATK/DEF/SPD/LCK: ${vals[7]}/${vals[8]}/${vals[9]}/${vals[10]}"
        echo "  Alive:    $([ "${vals[11]}" = "1" ] && echo "yes" || echo "no")"
        echo "  Runs:     ${vals[12]} completed, ${vals[13]} failed"
        echo "  Verified: $([ "${vals[14]}" = "1" ] && echo "yes" || echo "no")"
        ;;

    start-run)
        echo "Starting run with cat $1..."
        sozo execute --diff catacombs-run_actions start_run "$1" --wait
        ;;

    get-run)
        raw=$(sozo call --diff catacombs-run_actions get_run "$1" 2>&1)
        vals=()
        for hex in $(echo "$raw" | tr -d '[],' | tr ' ' '\n' | grep '0x0x'); do
            vals+=("$(parse_hex "${hex#0x}")")
        done
        status_names=("Active" "Completed" "Failed")
        echo "=== Run #${vals[0]} ==="
        echo "  Cat:       ${vals[1]}"
        echo "  Node:      ${vals[3]}"
        echo "  Floor:     ${vals[4]}/${vals[5]}"
        echo "  Status:    ${status_names[${vals[6]}]}"
        echo "  Score:     ${vals[7]}"
        echo "  Visited:   ${vals[8]}"
        ;;

    get-node)
        raw=$(sozo call --diff catacombs-run_actions get_node "$1" "$2" 2>&1)
        vals=()
        for hex in $(echo "$raw" | tr -d '[],' | tr ' ' '\n' | grep '0x0x'); do
            vals+=("$(parse_hex "${hex#0x}")")
        done
        conn=$(connections_to_nodes "${vals[6]}")
        echo "=== Node ${vals[1]} (Run ${vals[0]}) ==="
        echo "  Floor:    ${vals[2]}"
        echo "  Type:     $(node_type_name "${vals[3]}")"
        echo "  Resolved: $([ "${vals[4]}" = "1" ] && echo "yes" || echo "no")"
        echo "  Connects: $conn"
        ;;

    choose-path)
        echo "Moving to node $2 in run $1..."
        sozo execute --diff catacombs-run_actions choose_path "$1" "$2" --wait
        ;;

    submit-scenario)
        echo "Submitting scenario for run $1 node $2..."
        sozo execute --diff catacombs-encounter_actions submit_scenario "$1" "$2" "$3" --wait
        ;;

    resolve)
        # resolve <run_id> <node_id> <skill_hash> <result:1-3> <hp_delta> <xp> <loot_id>
        echo "Resolving encounter: run=$1 node=$2 result=$(result_name "$4")"
        hp_arg="$5"
        if [ "$hp_arg" -lt 0 ] 2>/dev/null; then
            hp_arg="int:$hp_arg"
        fi
        sozo execute --diff catacombs-encounter_actions resolve_encounter "$1" "$2" "$3" "$4" "$hp_arg" "$6" "$7" --wait
        ;;

    get-encounter)
        raw=$(sozo call --diff catacombs-encounter_actions get_encounter "$1" "$2" 2>&1)
        vals=()
        for hex in $(echo "$raw" | tr -d '[],' | tr ' ' '\n' | grep '0x0x'); do
            vals+=("$(parse_hex "${hex#0x}")")
        done
        echo "=== Encounter (Run ${vals[0]}, Node ${vals[1]}) ==="
        echo "  Scenario: 0x$(printf '%x' "${vals[2]}")"
        echo "  Skill:    0x$(printf '%x' "${vals[3]}")"
        echo "  Result:   $(result_name "${vals[4]}")"
        echo "  XP:       ${vals[6]}"
        echo "  Loot:     ${vals[7]}"
        ;;

    show-map)
        echo "=== Map for Run $1 ==="
        for i in 0 1 2 3 4 5 6; do
            raw=$(sozo call --diff catacombs-run_actions get_node "$1" "$i" 2>&1)
            vals=()
            for hex in $(echo "$raw" | tr -d '[],' | tr ' ' '\n' | grep '0x0x'); do
                vals+=("$(parse_hex "${hex#0x}")")
            done
            conn=$(connections_to_nodes "${vals[6]}")
            resolved=$([ "${vals[4]}" = "1" ] && echo "*" || echo " ")
            printf "  [%s] Node %d: %-8s -> {%s }\n" "$resolved" "$i" "$(node_type_name "${vals[3]}")" "$conn"
        done
        ;;

    *)
        echo "Usage: $0 {create-cat|get-cat|start-run|get-run|get-node|choose-path|submit-scenario|resolve|get-encounter|show-map} [args...]"
        exit 1
        ;;
esac
