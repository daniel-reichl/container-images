#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# ============================================================
#  COLORS & FORMATTING
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ============================================================
#  ARGUMENT PARSING
# ============================================================
MODE="interactive"

usage() {
  echo "Usage: $(basename "$0") [MODE]"
  echo ""
  echo "Stop and remove Docker containers, images, volumes, networks, and build cache."
  echo ""
  echo "Modes:"
  echo "  (default)         Interactive — review each category and choose what to keep"
  echo "  --nuke            Destroy everything immediately — full reset to clean slate"
  echo "  --list            Read-only inventory of all Docker resources"
  echo ""
  echo "Options:"
  echo "  --help            Show this help message and exit"
  echo ""
  echo "Examples:"
  echo "  $(basename "$0")              # interactive cleanup"
  echo "  $(basename "$0") --nuke       # wipe all Docker resources"
  echo "  $(basename "$0") --list       # just show what exists"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --nuke)
      MODE="nuke"
      shift
      ;;
    --list)
      MODE="list"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# ============================================================
#  PREFLIGHT CHECKS
# ============================================================
if ! command -v docker &> /dev/null; then
  echo "Error: Docker is not installed or not in PATH"
  exit 1
fi

if ! docker info &> /dev/null; then
  echo "Error: Docker daemon is not running"
  exit 1
fi

# ============================================================
#  HELPER: Human-readable time-ago
# ============================================================
time_ago() {
  local created_str="$1"
  local now
  now=$(date -u +%s)
  local created_epoch
  created_epoch=$(date -d "$created_str" -u +%s 2>/dev/null \
    || date -jf "%Y-%m-%dT%H:%M:%S" "$(echo "$created_str" | cut -d. -f1)" -u +%s 2>/dev/null \
    || echo "0")
  if [[ "$created_epoch" -eq 0 ]]; then
    echo "unknown"
    return
  fi
  local diff=$(( now - created_epoch ))
  if   (( diff < 60 ));       then echo "${diff}s ago"
  elif (( diff < 3600 ));     then echo "$(( diff / 60 ))m ago"
  elif (( diff < 86400 ));    then echo "$(( diff / 3600 ))h ago"
  elif (( diff < 2592000 ));  then echo "$(( diff / 86400 ))d ago"
  elif (( diff < 31536000 )); then echo "$(( diff / 2592000 ))mo ago"
  else echo "$(( diff / 31536000 ))y ago"
  fi
}

# ============================================================
#  HELPER: Truncate string to N chars
# ============================================================
trunc() {
  local str="$1" max="$2"
  if (( ${#str} > max )); then
    echo "${str:0:$((max-2))}.."
  else
    echo "$str"
  fi
}

# ============================================================
#  HELPER: Interactive checklist for a category
#
#  Arguments:
#    $1 — category title (e.g. "Containers")
#    $2 — header line for the table
#    $3 — newline-delimited rows: "ID|display_line"
#
#  Outputs the IDs that the user chose to REMOVE to stdout.
#  Returns 1 if the category was skipped (nothing found).
# ============================================================
interactive_checklist() {
  local title="$1"
  local header="$2"
  local items="$3"

  if [[ -z "$items" ]]; then
    echo -e "${DIM}  No ${title,,} found.${RESET}" >&2
    echo ""  >&2
    return 1
  fi

  local -a ids=()
  local -a lines=()
  local -a selected=()

  while IFS= read -r row; do
    local id="${row%%|*}"
    local display="${row#*|}"
    ids+=("$id")
    lines+=("$display")
    selected+=(1)  # 1 = marked for removal
  done <<< "$items"

  local count=${#ids[@]}

  while true; do
    echo -e "\n${BOLD}${CYAN}═══ ${title} (${count} found) ═══${RESET}" >&2
    echo -e "  ${DIM}${header}${RESET}" >&2

    for i in "${!ids[@]}"; do
      local marker
      if [[ "${selected[$i]}" -eq 1 ]]; then
        marker="${RED}[X]${RESET}"
      else
        marker="${GREEN}[ ]${RESET}"
      fi
      printf "  %b %2d) %s\n" "$marker" "$((i + 1))" "${lines[$i]}" >&2
    done

    echo "" >&2
    echo -e "  ${DIM}[X] = will be removed   [ ] = will be kept${RESET}" >&2
    echo -e "  ${BOLD}Commands:${RESET} Toggle items: ${CYAN}1 3 5${RESET} | Select all: ${CYAN}all${RESET} | Deselect all: ${CYAN}none${RESET} | Confirm: ${CYAN}Enter${RESET}" >&2
    echo -n "  > " >&2
    local input
    read -r input

    # Empty input = confirm current selection
    if [[ -z "$input" ]]; then
      break
    fi

    if [[ "$input" == "all" ]]; then
      for i in "${!selected[@]}"; do selected[$i]=1; done
      continue
    fi
    if [[ "$input" == "none" ]]; then
      for i in "${!selected[@]}"; do selected[$i]=0; done
      continue
    fi

    # Toggle listed numbers
    for token in $input; do
      if [[ "$token" =~ ^[0-9]+$ ]] && (( token >= 1 && token <= count )); then
        local idx=$(( token - 1 ))
        if [[ "${selected[$idx]}" -eq 1 ]]; then
          selected[$idx]=0
        else
          selected[$idx]=1
        fi
      else
        echo -e "  ${YELLOW}Ignoring invalid input: ${token}${RESET}" >&2
      fi
    done
  done

  # Collect IDs marked for removal
  local remove_ids=""
  for i in "${!ids[@]}"; do
    if [[ "${selected[$i]}" -eq 1 ]]; then
      remove_ids+="${ids[$i]}"$'\n'
    fi
  done

  # Return via stdout (trimmed)
  echo "$remove_ids" | sed '/^$/d'
}

# ============================================================
#  HELPER: Print section banner
# ============================================================
banner() {
  echo -e "\n${BOLD}${CYAN}>>> $1${RESET}"
}

# ============================================================
#  DATA GATHERING (shared across modes)
# ============================================================
gather_containers() {
  local rows=""
  for cid in $(docker ps -aq 2>/dev/null); do
    local name image status created age
    name=$(docker inspect -f '{{.Name}}' "$cid" | sed 's|^/||')
    image=$(docker inspect -f '{{.Config.Image}}' "$cid")
    status=$(docker inspect -f '{{.State.Status}}' "$cid")
    created=$(docker inspect -f '{{.Created}}' "$cid")
    age=$(time_ago "$created")
    local display
    display=$(printf "%-14s %-25s %-12s %s" \
      "$(trunc "$name" 14)" "$(trunc "$image" 25)" "$status" "$age")
    rows+="${cid}|${display}"$'\n'
  done
  echo "$rows" | sed '/^$/d'
}

gather_images() {
  local rows=""
  while IFS=$'\t' read -r img_id repo tag size age; do
    [[ -z "$img_id" ]] && continue
    local label="${repo}:${tag}"
    [[ "$repo" == "<none>" ]] && label="<none>"
    local display
    display=$(printf "%-35s %-10s %s" "$(trunc "$label" 35)" "$size" "$age")
    rows+="${img_id}|${display}"$'\n'
  done < <(docker images --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}' 2>/dev/null)
  echo "$rows" | sed '/^$/d'
}

gather_volumes() {
  local rows=""
  while IFS= read -r vname; do
    [[ -z "$vname" ]] && continue
    local driver created age
    driver=$(docker volume inspect -f '{{.Driver}}' "$vname" 2>/dev/null || echo "unknown")
    created=$(docker volume inspect -f '{{.CreatedAt}}' "$vname" 2>/dev/null || echo "")
    age=$(time_ago "$created")
    local display
    display=$(printf "%-45s %-10s %s" "$(trunc "$vname" 45)" "$driver" "$age")
    rows+="${vname}|${display}"$'\n'
  done < <(docker volume ls -q 2>/dev/null)
  echo "$rows" | sed '/^$/d'
}

gather_networks() {
  local rows=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local net_id net_name driver scope
    net_id=$(echo "$line" | awk '{print $1}')
    net_name=$(echo "$line" | awk '{print $2}')
    driver=$(echo "$line" | awk '{print $3}')
    scope=$(echo "$line" | awk '{print $4}')
    local display
    display=$(printf "%-30s %-12s %s" "$(trunc "$net_name" 30)" "$driver" "$scope")
    rows+="${net_id}|${display}"$'\n'
  done < <(docker network ls --filter "type=custom" --format '{{.ID}} {{.Name}} {{.Driver}} {{.Scope}}' 2>/dev/null)
  echo "$rows" | sed '/^$/d'
}

# ============================================================
#  HELPER: Print a category table (for --list mode)
# ============================================================
print_category() {
  local title="$1"
  local header="$2"
  local rows="$3"

  echo -e "\n${BOLD}${CYAN}═══ ${title} ═══${RESET}"
  if [[ -z "$rows" ]]; then
    echo -e "  ${DIM}None found.${RESET}"
    return
  fi

  local count
  count=$(echo "$rows" | wc -l | xargs)
  echo -e "  ${DIM}${header}${RESET}"
  while IFS= read -r row; do
    local display="${row#*|}"
    printf "  %s\n" "$display"
  done <<< "$rows"
  echo -e "  ${DIM}(${count} total)${RESET}"
}

# ============================================================
#  LIST MODE
# ============================================================
run_list() {
  echo -e "${BOLD}${CYAN}Docker Resource Inventory${RESET}"
  echo "========================================"

  print_category "Containers" \
    "$(printf '%-14s %-25s %-12s %s' 'NAME' 'IMAGE' 'STATUS' 'AGE')" \
    "$(gather_containers)"

  print_category "Images" \
    "$(printf '%-35s %-10s %s' 'REPOSITORY:TAG' 'SIZE' 'AGE')" \
    "$(gather_images)"

  print_category "Volumes" \
    "$(printf '%-45s %-10s %s' 'NAME' 'DRIVER' 'AGE')" \
    "$(gather_volumes)"

  print_category "Networks (custom)" \
    "$(printf '%-30s %-12s %s' 'NAME' 'DRIVER' 'SCOPE')" \
    "$(gather_networks)"

  banner "Build Cache"
  local cache_size
  cache_size=$(docker system df --format '{{.Size}}' 2>/dev/null | tail -1)
  if [[ -n "$cache_size" && "$cache_size" != "0B" && "$cache_size" != "0" ]]; then
    echo -e "  Using ${BOLD}${cache_size}${RESET}"
  else
    echo -e "  ${DIM}Empty.${RESET}"
  fi
}

# ============================================================
#  NUKE MODE
# ============================================================
run_nuke() {
  echo -e "${BOLD}${RED}Docker Cleanup — NUKE MODE${RESET}"
  echo "========================================"

  # --- Containers ---
  banner "Stopping all running containers..."
  local running
  running=$(docker ps -q)
  if [[ -n "$running" ]]; then
    echo "  Found $(echo "$running" | wc -l) running container(s)"
    echo "$running" | xargs docker stop
  else
    echo "  No running containers."
  fi

  banner "Removing all containers..."
  local all_containers
  all_containers=$(docker ps -aq)
  if [[ -n "$all_containers" ]]; then
    echo "  Found $(echo "$all_containers" | wc -l) container(s)"
    echo "$all_containers" | xargs docker rm -f
  else
    echo "  No containers."
  fi

  # --- Images ---
  banner "Removing all images..."
  local all_images
  all_images=$(docker images -aq)
  if [[ -n "$all_images" ]]; then
    echo "  Found $(echo "$all_images" | wc -l) image(s)"
    echo "$all_images" | xargs docker rmi -f 2>/dev/null || true
  else
    echo "  No images."
  fi

  # --- Volumes ---
  banner "Removing all volumes..."
  local all_volumes
  all_volumes=$(docker volume ls -q)
  if [[ -n "$all_volumes" ]]; then
    echo "  Found $(echo "$all_volumes" | wc -l) volume(s)"
    echo "$all_volumes" | xargs docker volume rm -f 2>/dev/null || true
  else
    echo "  No volumes."
  fi

  # --- Networks ---
  banner "Removing all custom networks..."
  local custom_networks
  custom_networks=$(docker network ls --filter "type=custom" -q)
  if [[ -n "$custom_networks" ]]; then
    echo "  Found $(echo "$custom_networks" | wc -l) custom network(s)"
    echo "$custom_networks" | xargs docker network rm 2>/dev/null || true
  else
    echo "  No custom networks."
  fi

  # --- Build cache ---
  banner "Purging build cache..."
  docker builder prune -af 2>/dev/null || true
}

# ============================================================
#  INTERACTIVE MODE
# ============================================================
run_interactive() {
  echo -e "${BOLD}${CYAN}Docker Cleanup — INTERACTIVE MODE${RESET}"
  echo "========================================"
  echo -e "${DIM}Review each category and choose what to remove.${RESET}"

  local tmpfile
  tmpfile=$(mktemp)
  trap "rm -f '$tmpfile'" EXIT

  # -------------------------------------------------------
  #  CONTAINERS
  # -------------------------------------------------------
  banner "Containers"
  local container_rows
  container_rows=$(gather_containers)

  if [[ -n "$container_rows" ]]; then
    interactive_checklist "Containers" \
      "$(printf '%-14s %-25s %-12s %s' 'NAME' 'IMAGE' 'STATUS' 'AGE')" \
      "$container_rows" > "$tmpfile"

    if [[ -s "$tmpfile" ]]; then
      local to_stop="" to_rm=""
      while IFS= read -r cid; do
        local state
        state=$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo "false")
        if [[ "$state" == "true" ]]; then
          to_stop+=" $cid"
        fi
        to_rm+=" $cid"
      done < "$tmpfile"

      if [[ -n "$to_stop" ]]; then
        echo -e "  ${YELLOW}Stopping running containers...${RESET}"
        docker stop $to_stop
      fi
      echo -e "  ${RED}Removing containers...${RESET}"
      docker rm -f $to_rm 2>/dev/null || true
      echo -e "  ${GREEN}Done.${RESET}"
    else
      echo -e "  ${GREEN}Nothing selected for removal.${RESET}"
    fi
  else
    echo -e "  ${DIM}No containers found.${RESET}"
  fi

  # -------------------------------------------------------
  #  IMAGES
  # -------------------------------------------------------
  banner "Images"
  local image_rows
  image_rows=$(gather_images)

  if [[ -n "$image_rows" ]]; then
    interactive_checklist "Images" \
      "$(printf '%-35s %-10s %s' 'REPOSITORY:TAG' 'SIZE' 'AGE')" \
      "$image_rows" > "$tmpfile"

    if [[ -s "$tmpfile" ]]; then
      echo -e "  ${RED}Removing images...${RESET}"
      xargs docker rmi -f < "$tmpfile" 2>/dev/null || true
      echo -e "  ${GREEN}Done.${RESET}"
    else
      echo -e "  ${GREEN}Nothing selected for removal.${RESET}"
    fi
  else
    echo -e "  ${DIM}No images found.${RESET}"
  fi

  # -------------------------------------------------------
  #  VOLUMES
  # -------------------------------------------------------
  banner "Volumes"
  local volume_rows
  volume_rows=$(gather_volumes)

  if [[ -n "$volume_rows" ]]; then
    interactive_checklist "Volumes" \
      "$(printf '%-45s %-10s %s' 'NAME' 'DRIVER' 'AGE')" \
      "$volume_rows" > "$tmpfile"

    if [[ -s "$tmpfile" ]]; then
      echo -e "  ${RED}Removing volumes...${RESET}"
      xargs docker volume rm -f < "$tmpfile" 2>/dev/null || true
      echo -e "  ${GREEN}Done.${RESET}"
    else
      echo -e "  ${GREEN}Nothing selected for removal.${RESET}"
    fi
  else
    echo -e "  ${DIM}No volumes found.${RESET}"
  fi

  # -------------------------------------------------------
  #  NETWORKS
  # -------------------------------------------------------
  banner "Networks"
  local network_rows
  network_rows=$(gather_networks)

  if [[ -n "$network_rows" ]]; then
    interactive_checklist "Networks" \
      "$(printf '%-30s %-12s %s' 'NAME' 'DRIVER' 'SCOPE')" \
      "$network_rows" > "$tmpfile"

    if [[ -s "$tmpfile" ]]; then
      echo -e "  ${RED}Removing networks...${RESET}"
      xargs docker network rm < "$tmpfile" 2>/dev/null || true
      echo -e "  ${GREEN}Done.${RESET}"
    else
      echo -e "  ${GREEN}Nothing selected for removal.${RESET}"
    fi
  else
    echo -e "  ${DIM}No custom networks found.${RESET}"
  fi

  # -------------------------------------------------------
  #  BUILD CACHE (yes/no — can't selectively remove items)
  # -------------------------------------------------------
  banner "Build Cache"
  local cache_size
  cache_size=$(docker system df --format '{{.Size}}' 2>/dev/null | tail -1)
  if [[ -n "$cache_size" && "$cache_size" != "0B" && "$cache_size" != "0" ]]; then
    echo -e "  Build cache is using ${BOLD}${cache_size}${RESET}"
    echo -n "  Purge build cache? [y/N] "
    local answer
    read -r answer
    if [[ "$answer" =~ ^[Yy] ]]; then
      echo -e "  ${RED}Purging build cache...${RESET}"
      docker builder prune -af 2>/dev/null || true
      echo -e "  ${GREEN}Done.${RESET}"
    else
      echo -e "  ${GREEN}Skipped.${RESET}"
    fi
  else
    echo -e "  ${DIM}No build cache to clean.${RESET}"
  fi
}

# ============================================================
#  MAIN
# ============================================================
case "$MODE" in
  list)        run_list ;;
  nuke)        run_nuke ;;
  interactive) run_interactive ;;
esac

# ============================================================
#  SUMMARY
# ============================================================
echo ""
echo -e "${BOLD}========================================"
if [[ "$MODE" == "list" ]]; then
  echo -e "  Inventory complete."
else
  echo -e "  Cleanup complete!"
fi
echo -e "========================================${RESET}"
echo ""
echo "Current Docker status:"
echo "  Containers: $(docker ps -aq 2>/dev/null | wc -l | xargs) total ($(docker ps -q 2>/dev/null | wc -l | xargs) running)"
echo "  Images:     $(docker images -q 2>/dev/null | wc -l | xargs)"
echo "  Volumes:    $(docker volume ls -q 2>/dev/null | wc -l | xargs)"
echo "  Networks:   $(docker network ls -q 2>/dev/null | wc -l | xargs)"
