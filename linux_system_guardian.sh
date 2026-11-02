#!/usr/bin/env bash
# ==============================================================================
# LINUX SYSTEM GUARDIAN v1.0
# Workspace Management & Security Auditor
#
# Academic Operating Systems Microproject
# Target Environment: Kali Linux, Ubuntu, Debian & Compatible Distributions
# Dependencies: Bash 4.0+ and standard POSIX / GNU coreutils (No root required)
# ==============================================================================

# Enable strict mode for safety, but allow deliberate error handling in subroutines
set -u

# ------------------------------------------------------------------------------
# 1. APPLICATION CONSTANTS & GLOBALS
# ------------------------------------------------------------------------------
readonly APP_NAME="LINUX SYSTEM GUARDIAN"
readonly APP_SUBTITLE="WORKSPACE MANAGEMENT & SECURITY AUDITOR"
readonly APP_VERSION="1.0"
readonly APP_MODE="LOCAL"

# Dedicated workspace directory (supports GUARDIAN_WORKSPACE env var or --workspace flag)
WORKSPACE_DIR="${GUARDIAN_WORKSPACE:-${HOME:-}/linux_system_guardian_workspace}"
DIR_LOGS="${WORKSPACE_DIR}/logs"
DIR_TEMP="${WORKSPACE_DIR}/temp"
DIR_ARCHIVE="${WORKSPACE_DIR}/archive"
DIR_REPORTS="${WORKSPACE_DIR}/reports"
LOG_FILE="${DIR_LOGS}/activity.log"

set_workspace_path() {
    local target_ws="$1"
    if [[ -z "${target_ws}" ]]; then
        return 1
    fi
    mkdir -p "${target_ws}" 2>/dev/null || true
    local canonical_ws
    canonical_ws="$(cd -P "${target_ws}" 2>/dev/null && pwd -P)"
    if [[ -z "${canonical_ws}" || "${canonical_ws}" == "/" ]]; then
        echo -e "${C_BRED}[ERROR] Invalid workspace path: Cannot use root filesystem '/'.${C_RESET}" >&2
        return 1
    fi
    if [[ -n "${HOME:-}" && "${canonical_ws}" == "${HOME}" ]]; then
        echo -e "${C_BRED}[ERROR] Invalid workspace path: For safety, please specify a dedicated subfolder (e.g., ~/my_workspace) rather than your entire home directory.${C_RESET}" >&2
        return 1
    fi
    WORKSPACE_DIR="${canonical_ws}"
    DIR_LOGS="${WORKSPACE_DIR}/logs"
    DIR_TEMP="${WORKSPACE_DIR}/temp"
    DIR_ARCHIVE="${WORKSPACE_DIR}/archive"
    DIR_REPORTS="${WORKSPACE_DIR}/reports"
    LOG_FILE="${DIR_LOGS}/activity.log"
    init_workspace
    return 0
}

# Default configuration parameters
DISK_WARN_THRESHOLD=80      # Percentage utilization threshold for storage warning
LARGE_FILE_DEFAULT_KB=100    # Default threshold for large file scanner (100 KiB)

# ------------------------------------------------------------------------------
# 2. COLOR & TERMINAL UI DEFINITIONS
# ------------------------------------------------------------------------------
# Support NO_COLOR convention (https://no-color.org) and non-interactive output
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    
    # Palette: Cyan, Green, Blue, White, Yellow (Red reserved exclusively for warnings/errors)
    C_CYAN='\033[0;36m'
    C_BCYAN='\033[1;36m'
    C_GREEN='\033[0;32m'
    C_BGREEN='\033[1;32m'
    C_BLUE='\033[0;34m'
    C_BBLUE='\033[1;34m'
    C_YELLOW='\033[0;33m'
    C_BYELLOW='\033[1;33m'
    C_WHITE='\033[1;37m'
    C_GRAY='\033[0;90m'
    C_RED='\033[0;31m'
    C_BRED='\033[1;31m'
else
    C_RESET=''
    C_BOLD=''
    C_DIM=''
    C_CYAN=''
    C_BCYAN=''
    C_GREEN=''
    C_BGREEN=''
    C_BLUE=''
    C_BBLUE=''
    C_YELLOW=''
    C_BYELLOW=''
    C_WHITE=''
    C_GRAY=''
    C_RED=''
    C_BRED=''
fi

# ------------------------------------------------------------------------------
# 3. UTILITY FUNCTIONS: ANSI STRIPPING, LOGGING & PATH VALIDATION
# ------------------------------------------------------------------------------

# Filter out ANSI escape sequences to prevent log/report corruption
strip_ansi() {
    sed -E $'s/\x1B\\[[0-9;]*[a-zA-Z]//g'
}

# Record operational audit trail to activity.log with sanitized output
log_activity() {
    local action="${1:-UNKNOWN}"
    local target="${2:-N/A}"
    local status="${3:-INFO}"
    local details="${4:-}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"

    # Ensure log directory exists before writing
    if [[ ! -d "${DIR_LOGS}" ]]; then
        mkdir -p "${DIR_LOGS}" 2>/dev/null || true
    fi

    local log_entry="[${timestamp}] [${action}] [${target}] [${status}] - ${details}"
    # Ensure ANSI codes never enter log files
    echo "${log_entry}" | strip_ansi >> "${LOG_FILE}" 2>/dev/null || true
}

# Graceful signal handler for Ctrl+C (SIGINT) and SIGTERM
handle_interrupt() {
    echo -e "\n${C_BYELLOW}[!] Operation interrupted by user signal (SIGINT). Returning safely...${C_RESET}"
    log_activity "SIGNAL" "USER_INTERRUPT" "CANCELLED" "SIGINT captured by signal trap"
    sleep 1
    # If called during a sub-operation, we resume loop; do not abruptly kill terminal
}
trap 'handle_interrupt' INT TERM

# Ensure HOME and workspace path can be safely established
verify_environment() {
    if [[ -z "${HOME:-}" ]]; then
        echo -e "${C_BRED}[FATAL ERROR] Environment variable \$HOME is unset.${C_RESET}" >&2
        echo -e "${C_RED}Linux System Guardian requires a valid user home directory for workspace isolation.${C_RESET}" >&2
        exit 1
    fi

    # Detect mandatory standard commands
    local required_commands=("uname" "date" "df" "du" "find" "stat" "chmod" "grep" "awk" "sed")
    local missing=()
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing+=("${cmd}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${C_BRED}[FATAL ERROR] Required system utilities are missing: ${missing[*]}${C_RESET}" >&2
        exit 1
    fi
}

# Strict path validation: returns 0 only if candidate is strictly inside the workspace
is_path_inside_workspace() {
    local target_path="$1"
    
    if [[ -z "${target_path}" || ! -e "${target_path}" ]]; then
        return 1
    fi

    # Reject symlinks to avoid directory traversal / symlink injection
    if [[ -L "${target_path}" ]]; then
        return 1
    fi

    # Get real canonical paths
    local canonical_workspace canonical_target
    canonical_workspace="$(cd -P "${WORKSPACE_DIR}" 2>/dev/null && pwd -P)"
    
    if [[ -d "${target_path}" ]]; then
        canonical_target="$(cd -P "${target_path}" 2>/dev/null && pwd -P)"
    else
        local parent_dir
        parent_dir="$(dirname "${target_path}")"
        local base_name
        base_name="$(basename "${target_path}")"
        local canonical_parent
        canonical_parent="$(cd -P "${parent_dir}" 2>/dev/null && pwd -P)"
        canonical_target="${canonical_parent}/${base_name}"
    fi

    if [[ -z "${canonical_workspace}" || -z "${canonical_target}" ]]; then
        return 1
    fi

    # Reject if canonical target is the root filesystem or home directory itself
    if [[ "${canonical_target}" == "/" || "${canonical_target}" == "${HOME}" ]]; then
        return 1
    fi

    # Target must begin with the canonical workspace path
    if [[ "${canonical_target}" == "${canonical_workspace}"/* || "${canonical_target}" == "${canonical_workspace}" ]]; then
        return 0
    else
        return 1
    fi
}

# Initialize workspace directories and default log file
init_workspace() {
    local created_any=0
    for dir in "${WORKSPACE_DIR}" "${DIR_LOGS}" "${DIR_TEMP}" "${DIR_ARCHIVE}" "${DIR_REPORTS}"; do
        if [[ ! -d "${dir}" ]]; then
            mkdir -p "${dir}" 2>/dev/null
            created_any=1
        fi
    done

    if [[ ! -f "${LOG_FILE}" ]]; then
        touch "${LOG_FILE}" 2>/dev/null
        log_activity "INITIALIZATION" "${WORKSPACE_DIR}" "SUCCESS" "Guardian workspace structure initialized"
    elif [[ ${created_any} -eq 1 ]]; then
        log_activity "INITIALIZATION" "${WORKSPACE_DIR}" "SUCCESS" "Missing workspace directories created"
    fi
}

# ------------------------------------------------------------------------------
# 4. TERMINAL UI DRAWING ENGINE
# ------------------------------------------------------------------------------

draw_header() {
    if [[ -t 1 ]]; then
        clear 2>/dev/null || true
    fi
    local host_name
    host_name="$(hostname 2>/dev/null || echo "linux-host")"
    
    echo -e "${C_BCYAN}+--------------------------------------------------------------+${C_RESET}"
    echo -e "${C_BCYAN}|${C_WHITE}                 ${APP_NAME}                        ${C_BCYAN}|${C_RESET}"
    echo -e "${C_BCYAN}|${C_CYAN}        ${APP_SUBTITLE}               ${C_BCYAN}|${C_RESET}"
    echo -e "${C_BCYAN}+--------------------------------------------------------------+${C_RESET}"
    printf "${C_BCYAN}|${C_RESET} ${C_DIM}Host:${C_RESET} %-20s ${C_DIM}Mode:${C_RESET} %-17s ${C_BCYAN}|${C_RESET}\n" "${host_name:0:20}" "${APP_MODE}"
    printf "${C_BCYAN}|${C_RESET} ${C_DIM}Platform:${C_RESET} %-16s ${C_DIM}Version:${C_RESET} %-14s ${C_BCYAN}|${C_RESET}\n" "Linux" "${APP_VERSION}"
    echo -e "${C_BCYAN}+--------------------------------------------------------------+${C_RESET}"
    echo ""
}

draw_section_header() {
    local title="$1"
    echo -e "${C_BCYAN}>>> ${C_WHITE}${C_BOLD}${title}${C_RESET}"
    echo -e "${C_GRAY}----------------------------------------------------------------${C_RESET}"
}

draw_status() {
    local level="$1"
    local message="$2"
    case "${level}" in
        SUCCESS)
            echo -e "${C_BGREEN}[+] SUCCESS:${C_RESET} ${message}"
            ;;
        WARN)
            echo -e "${C_BYELLOW}[!] WARNING:${C_RESET} ${message}"
            ;;
        ERROR)
            echo -e "${C_BRED}[X] ERROR:${C_RESET} ${message}"
            ;;
        INFO|*)
            echo -e "${C_BCYAN}[*] INFO:${C_RESET} ${message}"
            ;;
    esac
}

prompt_return() {
    echo ""
    echo -e "${C_DIM}Press ${C_WHITE}[Enter]${C_DIM} to return to the main menu...${C_RESET}"
    read -r _ 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# 5. MODULE 1 — SYSTEM OVERVIEW
# ------------------------------------------------------------------------------

# Helper: Compute real CPU utilization by sampling /proc/stat
get_cpu_utilization() {
    if [[ ! -r /proc/stat ]]; then
        echo "N/A (Requires /proc/stat)"
        return
    fi

    # Read first line from /proc/stat: cpu user nice system idle iowait irq softirq steal
    local cpu_line1 cpu_line2
    cpu_line1=$(grep -m1 '^cpu ' /proc/stat 2>/dev/null || true)
    if [[ -z "${cpu_line1}" ]]; then
        echo "N/A"
        return
    fi

    # Sleep short sample interval (0.5 second for responsive real reading)
    sleep 0.5
    cpu_line2=$(grep -m1 '^cpu ' /proc/stat 2>/dev/null || true)

    local -a t1=(${cpu_line1#cpu })
    local -a t2=(${cpu_line2#cpu })

    # Sum total CPU time
    local total1=0 total2=0
    for val in "${t1[@]}"; do total1=$((total1 + val)); done
    for val in "${t2[@]}"; do total2=$((total2 + val)); done

    # Idle time is 4th field (index 3: idle) + 5th field (index 4: iowait, if present)
    local idle1=${t1[3]:-0}
    if [[ ${#t1[@]} -ge 5 ]]; then idle1=$((idle1 + ${t1[4]:-0})); fi
    
    local idle2=${t2[3]:-0}
    if [[ ${#t2[@]} -ge 5 ]]; then idle2=$((idle2 + ${t2[4]:-0})); fi

    local diff_total=$((total2 - total1))
    local diff_idle=$((idle2 - idle1))

    if [[ ${diff_total} -le 0 ]]; then
        echo "0.0%"
        return
    fi

    local diff_active=$((diff_total - diff_idle))
    # Calculate percentage with 1 decimal precision using integer arithmetic
    local pct_int=$(( (diff_active * 1000) / diff_total ))
    local major=$((pct_int / 10))
    local minor=$((pct_int % 10))
    echo "${major}.${minor}%"
}

module_system_overview() {
    draw_header
    draw_section_header "MODULE 1: SYSTEM OVERVIEW & TELEMETRY"
    echo -e "${C_DIM}Gathering dynamic operating system metrics...${C_RESET}\n"

    # Hostname & Kernel
    local host_name kernel_version os_name current_user sys_datetime
    host_name="$(hostname 2>/dev/null || echo "Unknown Host")"
    kernel_version="$(uname -s -r 2>/dev/null || echo "Linux")"
    current_user="${USER:-$(whoami 2>/dev/null || echo "user")}"
    sys_datetime="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"

    # Distribution detection via /etc/os-release
    os_name="Linux (Generic Distribution)"
    if [[ -r /etc/os-release ]]; then
        local pretty
        pretty="$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')"
        if [[ -n "${pretty}" ]]; then
            os_name="${pretty}"
        fi
    elif command -v lsb_release >/dev/null 2>&1; then
        os_name="$(lsb_release -d 2>/dev/null | cut -f2)"
    fi

    # CPU Model
    local cpu_model="Generic Processor"
    if [[ -r /proc/cpuinfo ]]; then
        local raw_cpu
        raw_cpu="$(grep -m1 -E '^(model name|Hardware|Processor)' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^[ \t]*//')"
        if [[ -n "${raw_cpu}" ]]; then
            cpu_model="${raw_cpu}"
        fi
    fi

    # CPU Utilization
    local cpu_util
    cpu_util="$(get_cpu_utilization)"

    # Memory Utilization (total, used, available)
    local mem_total="N/A" mem_used="N/A" mem_avail="N/A" mem_pct="N/A"
    if command -v free >/dev/null 2>&1; then
        # Parse free -m
        local free_output
        free_output="$(free -m 2>/dev/null | grep -E '^(Mem:|Total:)')"
        if [[ -n "${free_output}" ]]; then
            local -a mem_fields=(${free_output})
            mem_total="${mem_fields[1]:-0} MB"
            mem_used="${mem_fields[2]:-0} MB"
            # In modern free, available is column 6 (or 7 if shared present)
            if [[ ${#mem_fields[@]} -ge 7 ]]; then
                mem_avail="${mem_fields[6]:-0} MB"
            else
                mem_avail="${mem_fields[3]:-0} MB"
            fi
            if [[ "${mem_fields[1]:-0}" -gt 0 ]]; then
                mem_pct="$(( (mem_fields[2] * 100) / mem_fields[1] ))%"
            fi
        fi
    elif [[ -r /proc/meminfo ]]; then
        local kb_total kb_free kb_avail
        kb_total=$(grep -m1 '^MemTotal:' /proc/meminfo | awk '{print $2}')
        kb_avail=$(grep -m1 '^MemAvailable:' /proc/meminfo | awk '{print $2}')
        if [[ -z "${kb_avail}" ]]; then
            kb_free=$(grep -m1 '^MemFree:' /proc/meminfo | awk '{print $2}')
            kb_avail="${kb_free:-0}"
        fi
        local mb_total=$(( ${kb_total:-0} / 1024 ))
        local mb_avail=$(( ${kb_avail:-0} / 1024 ))
        local mb_used=$(( mb_total - mb_avail ))
        mem_total="${mb_total} MB"
        mem_used="${mb_used} MB"
        mem_avail="${mb_avail} MB"
        if [[ ${mb_total} -gt 0 ]]; then
            mem_pct="$(( (mb_used * 100) / mb_total ))%"
        fi
    fi

    # Root Filesystem Utilization
    local root_total="N/A" root_used="N/A" root_avail="N/A" root_pct="N/A"
    local df_metrics
    df_metrics="$(df -Pk / 2>/dev/null | awk 'NR>1 {print $(NF-4), $(NF-3), $(NF-2), $(NF-1), $NF; exit}')"
    if [[ -n "${df_metrics}" ]]; then
        local k_total k_used k_avail
        read -r k_total k_used k_avail root_pct _ <<< "${df_metrics}"
        
        # Human readable conversions with numeric safety
        if [[ "${k_total:-}" =~ ^[0-9]+$ && "${k_total}" -gt 0 ]]; then
            root_total="$(( k_total / 1024 / 1024 )) GB"
        fi
        if [[ "${k_used:-}" =~ ^[0-9]+$ && "${k_used}" -gt 0 ]]; then
            root_used="$(( k_used / 1024 / 1024 )) GB"
        fi
        if [[ "${k_avail:-}" =~ ^[0-9]+$ && "${k_avail}" -gt 0 ]]; then
            root_avail="$(( k_avail / 1024 / 1024 )) GB"
        fi
    fi

    # Workspace Storage Usage
    local ws_usage="0 KB"
    if [[ -d "${WORKSPACE_DIR}" ]]; then
        ws_usage="$(du -sh "${WORKSPACE_DIR}" 2>/dev/null | cut -f1)"
    fi

    # Formatted Presentation Table
    echo -e "${C_BCYAN}System Identity & Environment:${C_RESET}"
    printf "  %-24s: ${C_WHITE}%s${C_RESET}\n" "Hostname" "${host_name}"
    printf "  %-24s: ${C_WHITE}%s${C_RESET}\n" "Linux Distribution" "${os_name}"
    printf "  %-24s: ${C_WHITE}%s${C_RESET}\n" "Kernel Version" "${kernel_version}"
    printf "  %-24s: ${C_WHITE}%s${C_RESET}\n" "Active User" "${current_user}"
    printf "  %-24s: ${C_WHITE}%s${C_RESET}\n" "System Time" "${sys_datetime}"
    echo ""

    echo -e "${C_BCYAN}Processor & Compute Telemetry:${C_RESET}"
    printf "  %-24s: ${C_WHITE}%s${C_RESET}\n" "CPU Model" "${cpu_model}"
    printf "  %-24s: ${C_BGREEN}%s${C_RESET}\n" "Active CPU Load" "${cpu_util}"
    echo ""

    echo -e "${C_BCYAN}Memory Allocation (RAM):${C_RESET}"
    printf "  %-24s: Total: ${C_WHITE}%s${C_RESET} | Used: ${C_YELLOW}%s${C_RESET} (%s) | Available: ${C_GREEN}%s${C_RESET}\n" \
        "RAM Usage" "${mem_total}" "${mem_used}" "${mem_pct}" "${mem_avail}"
    echo ""

    echo -e "${C_BCYAN}Storage & Filesystem Capacity:${C_RESET}"
    printf "  %-24s: Total: ${C_WHITE}%s${C_RESET} | Used: ${C_WHITE}%s${C_RESET} (%s) | Free: ${C_GREEN}%s${C_RESET}\n" \
        "Root Filesystem (/)" "${root_total}" "${root_used}" "${root_pct}" "${root_avail}"
    printf "  %-24s: ${C_BYELLOW}%s${C_RESET} (${WORKSPACE_DIR})\n" \
        "Guardian Workspace Size" "${ws_usage}"
    echo ""

    log_activity "SYS_OVERVIEW" "SYSTEM" "SUCCESS" "System telemetry refreshed successfully"
    prompt_return
}

# ------------------------------------------------------------------------------
# 6. MODULE 2 — WORKSPACE MANAGER
# ------------------------------------------------------------------------------

# Helper: Print safe ASCII hierarchy of workspace
print_workspace_tree() {
    local base="$1"
    echo -e "${C_BCYAN}${base}/${C_RESET}"
    
    # Collect immediate subdirectories (guarantee logs, temp, archive, reports if present, plus any custom user folders)
    local subdirs=()
    while IFS= read -r -d '' d; do
        [[ -z "$d" ]] && continue
        local bname
        bname="$(basename "$d")"
        subdirs+=("${bname}")
    done < <(find "${base}" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

    # Collect any top-level regular files directly in base
    local root_files=()
    while IFS= read -r -d '' f; do
        [[ -z "$f" ]] && continue
        local bname
        bname="$(basename "$f")"
        root_files+=("${bname}")
    done < <(find "${base}" -mindepth 1 -maxdepth 1 -type f -print0 2>/dev/null | sort -z)

    local total_entries=$(( ${#subdirs[@]} + ${#root_files[@]} ))
    local entry_num=0

    # 1. Print subdirectories and their contents
    for sub in "${subdirs[@]}"; do
        entry_num=$((entry_num + 1))
        local branch="├──"
        local sub_prefix="│  "
        if [[ ${entry_num} -eq ${total_entries} ]]; then
            branch="└──"
            sub_prefix="   "
        fi

        local dir_path="${base}/${sub}"
        local count=0
        if [[ -d "${dir_path}" ]]; then
            count=$(find "${dir_path}" -maxdepth 1 -type f 2>/dev/null | wc -l)
        fi

        echo -e "${C_GRAY}${branch}${C_RESET} ${C_WHITE}${sub}/${C_RESET} ${C_DIM}(${count} regular files)${C_RESET}"
        
        # List up to 4 sample files under this directory
        if [[ -d "${dir_path}" && ${count} -gt 0 ]]; then
            local file_idx=0
            while IFS= read -r f; do
                [[ -z "$f" ]] && continue
                file_idx=$((file_idx + 1))
                local fname
                fname="$(basename "${f}")"
                local fbranch="├──"
                if [[ ${file_idx} -eq ${count} || ${file_idx} -ge 4 ]]; then
                    fbranch="└──"
                fi
                echo -e "${C_GRAY}${sub_prefix}  ${fbranch}${C_RESET} ${C_CYAN}${fname}${C_RESET}"
                if [[ ${file_idx} -ge 4 && ${count} -gt 4 ]]; then
                    echo -e "${C_GRAY}${sub_prefix}     ... and $((count - 4)) more file(s)${C_RESET}"
                    break
                fi
            done < <(find "${dir_path}" -maxdepth 1 -type f 2>/dev/null | sort)
        fi
    done

    # 2. Print any root-level files
    local root_idx=0
    for rf in "${root_files[@]}"; do
        entry_num=$((entry_num + 1))
        root_idx=$((root_idx + 1))
        local branch="├──"
        if [[ ${entry_num} -eq ${total_entries} || ${root_idx} -ge 5 ]]; then
            branch="└──"
        fi
        echo -e "${C_GRAY}${branch}${C_RESET} ${C_CYAN}${rf}${C_RESET}"
        if [[ ${root_idx} -ge 5 && ${#root_files[@]} -gt 5 ]]; then
            echo -e "${C_GRAY}    ... and $((${#root_files[@]} - 5)) more file(s)${C_RESET}"
            break
        fi
    done
}

# Helper: Create synthetic demonstration files safely without overwriting
create_demo_data() {
    init_workspace
    echo -e "${C_DIM}Provisioning synthetic demonstration files in workspace...${C_RESET}\n"

    # Demonstration dataset definition: target_dir, filename, initial_mode, sample_content
    local demo_entries=(
        "temp|session_cache_01.tmp|0644|CACHE_DATA: timestamp=$(date +%s); session_id=0xFA4B92; state=STALE_CLEANUP_ELIGIBLE"
        "temp|packet_dump_02.tmp|0644|NETWORK_TRACE: capture_len=2048; protocol=TCP; status=BUFFERED_TEMPORARY"
        "temp|credentials_draft.txt|0644|CONFIDENTIAL: API_KEY=mock_key_guardian_demo_789456; access=RESTRICTED"
        "archive|system_config.bak|0644|BACKUP: timestamp=$(date); hostname=$(hostname); daemon=guardian_mock"
        "logs|service_mock.log|0644|[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] [MOCK_SERVICE] Service initialized successfully"
    )

    local created_count=0
    local skipped_count=0

    for entry in "${demo_entries[@]}"; do
        local dir_key file_name file_mode file_content
        IFS='|' read -r dir_key file_name file_mode file_content <<< "${entry}"
        
        local full_dir="${WORKSPACE_DIR}/${dir_key}"
        local full_path="${full_dir}/${file_name}"

        # Never overwrite existing data
        if [[ -e "${full_path}" ]]; then
            echo -e "  ${C_GRAY}[EXISTS]${C_RESET} ${dir_key}/${file_name} (skipped to preserve existing data)"
            skipped_count=$((skipped_count + 1))
        else
            echo "${file_content}" > "${full_path}" 2>/dev/null
            chmod "${file_mode}" "${full_path}" 2>/dev/null
            echo -e "  ${C_BGREEN}[CREATED]${C_RESET} ${dir_key}/${file_name} ${C_DIM}(mode: ${file_mode})${C_RESET}"
            created_count=$((created_count + 1))
            log_activity "DEMO_DATA" "${dir_key}/${file_name}" "CREATED" "Synthetic sample file created"
        fi
    done

    echo ""
    draw_status "SUCCESS" "Demo provisioning complete: ${created_count} file(s) created, ${skipped_count} skipped."
    echo -e "${C_DIM}Notice: All demonstration files are synthetic and strictly isolated within the workspace.${C_RESET}"
}

module_workspace_manager() {
    while true; do
        draw_header
        draw_section_header "MODULE 2: WORKSPACE MANAGER"
        init_workspace

        echo -e "${C_BCYAN}Managed Workspace Location:${C_RESET} ${C_WHITE}${WORKSPACE_DIR}${C_RESET}\n"

        # Show directory structure tree
        echo -e "${C_BCYAN}Directory Structure & File Inventory:${C_RESET}"
        print_workspace_tree "${WORKSPACE_DIR}"
        echo ""

        # Summary statistics
        local total_files
        total_files=$(find "${WORKSPACE_DIR}" -type f 2>/dev/null | wc -l)
        local total_size
        total_size=$(du -sh "${WORKSPACE_DIR}" 2>/dev/null | cut -f1)

        echo -e "${C_DIM}Total Regular Files:${C_RESET} ${C_WHITE}${total_files}${C_RESET} | ${C_DIM}Total Workspace Size:${C_RESET} ${C_WHITE}${total_size}${C_RESET}\n"

        echo -e "${C_BCYAN}Available Workspace Actions:${C_RESET}"
        echo -e "  ${C_WHITE}[1]${C_RESET} Detailed File Inventory (Attributes, Modes & Timestamps)"
        echo -e "  ${C_WHITE}[2]${C_RESET} Generate Synthetic Demonstration Files"
        echo -e "  ${C_WHITE}[3]${C_RESET} View Activity Log (activity.log)"
        echo -e "  ${C_WHITE}[4]${C_RESET} Switch / Set Custom Workspace Directory"
        echo -e "  ${C_WHITE}[0]${C_RESET} Return to Main Menu"
        echo ""
        echo -n -e "${C_CYAN}Select option [0-4]: ${C_RESET}"
        if ! read -r ws_choice; then
            break
        fi

        case "${ws_choice}" in
            1)
                echo ""
                draw_section_header "DETAILED WORKSPACE FILE INVENTORY"
                printf "${C_DIM}%-22s %-6s %-10s %-12s %-10s %-19s${C_RESET}\n" "DIRECTORY / FILE" "MODE" "PERMS" "OWNER:GROUP" "SIZE" "LAST MODIFIED"
                echo -e "${C_GRAY}--------------------------------------------------------------------------------${C_RESET}"
                
                local found_files=0
                while IFS= read -r filepath; do
                    [[ -z "${filepath}" ]] && continue
                    found_files=1
                    local relpath="${filepath#${WORKSPACE_DIR}/}"
                    
                    # Use standard POSIX/GNU stat
                    local octal_mode perm_str owner_group size_bytes mod_time
                    octal_mode="$(stat -c '%a' "${filepath}" 2>/dev/null || echo "???")"
                    perm_str="$(stat -c '%A' "${filepath}" 2>/dev/null || echo "???")"
                    owner_group="$(stat -c '%U:%G' "${filepath}" 2>/dev/null || echo "???")"
                    size_bytes="$(stat -c '%s B' "${filepath}" 2>/dev/null || echo "???")"
                    mod_time="$(stat -c '%y' "${filepath}" 2>/dev/null | cut -d. -f1 || echo "???")"

                    printf "%-22s ${C_CYAN}%-6s${C_RESET} ${C_WHITE}%-10s${C_RESET} %-12s %-10s %-19s\n" \
                        "${relpath:0:22}" "${octal_mode}" "${perm_str}" "${owner_group:0:12}" "${size_bytes}" "${mod_time:0:19}"
                done < <(find "${WORKSPACE_DIR}" -type f 2>/dev/null | sort)

                if [[ ${found_files} -eq 0 ]]; then
                    echo -e "${C_YELLOW}No files found in workspace. Select Option [2] to create demonstration files.${C_RESET}"
                fi
                prompt_return
                ;;
            2)
                echo ""
                create_demo_data
                prompt_return
                ;;
            3)
                echo ""
                draw_section_header "WORKSPACE ACTIVITY LOG (LAST 25 EVENTS)"
                if [[ -s "${LOG_FILE}" ]]; then
                    tail -n 25 "${LOG_FILE}"
                else
                    echo -e "${C_YELLOW}Activity log is currently empty.${C_RESET}"
                fi
                prompt_return
                ;;
            4)
                echo ""
                draw_section_header "SET CUSTOM WORKSPACE DIRECTORY"
                echo -e "Current Workspace: ${C_WHITE}${WORKSPACE_DIR}${C_RESET}\n"
                echo -n -e "${C_CYAN}Enter new workspace directory path (or press Enter to cancel): ${C_RESET}"
                read -r new_ws_input || new_ws_input=""
                new_ws_input="$(echo "${new_ws_input:-}" | tr -d '\r\n' | sed 's/^[ \t]*//;s/[ \t]*$//')"
                if [[ -n "${new_ws_input}" ]]; then
                    if set_workspace_path "${new_ws_input}"; then
                        echo ""
                        draw_status "SUCCESS" "Workspace successfully switched to: ${WORKSPACE_DIR}"
                        log_activity "CONFIG" "${WORKSPACE_DIR}" "SUCCESS" "Workspace directory switched"
                    else
                        echo ""
                        draw_status "ERROR" "Failed to switch workspace path. Path must not be root '/'."
                    fi
                else
                    draw_status "INFO" "Workspace change cancelled."
                fi
                prompt_return
                ;;
            0|"")
                break
                ;;
            *)
                draw_status "ERROR" "Invalid selection. Please choose an option from the menu."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 7. MODULE 3 — TEMPORARY & LARGE-FILE SCANNER
# ------------------------------------------------------------------------------

module_file_scanner() {
    draw_header
    draw_section_header "MODULE 3: TEMPORARY & LARGE-FILE SCANNER"
    init_workspace

    echo -e "${C_DIM}This scanner audits the isolated workspace for temporary (.tmp), backup (.bak),${C_RESET}"
    echo -e "${C_DIM}and files exceeding a user-defined size threshold. (Never follows symlinks)${C_RESET}\n"

    # Input threshold with validation
    echo -e "${C_BCYAN}Configure Large-File Detection Threshold:${C_RESET}"
    echo -n -e "${C_CYAN}Enter threshold in KiB (or press Enter for default ${LARGE_FILE_DEFAULT_KB} KiB): ${C_RESET}"
    read -r user_thresh || user_thresh=""
    user_thresh="$(echo "${user_thresh:-}" | tr -d '\r\n[:space:]')"

    local threshold_kb="${LARGE_FILE_DEFAULT_KB}"
    if [[ -n "${user_thresh}" ]]; then
        # Strictly validate numeric integer input (no code injection)
        if [[ "${user_thresh}" =~ ^[0-9]+$ ]] && [[ "${user_thresh}" -gt 0 ]]; then
            threshold_kb="${user_thresh}"
        else
            draw_status "WARN" "Invalid numeric input '${user_thresh}'. Defaulting to ${LARGE_FILE_DEFAULT_KB} KiB threshold."
            threshold_kb="${LARGE_FILE_DEFAULT_KB}"
        fi
    fi

    local threshold_bytes=$(( threshold_kb * 1024 ))
    echo -e "\n${C_DIM}Scanning workspace with threshold: ${C_WHITE}${threshold_kb} KiB (${threshold_bytes} bytes)${C_DIM}...${C_RESET}\n"

    # Collect matching files using find -print0 (safe handling for spaces and special characters)
    local tmp_matches=()
    local bak_matches=()
    local large_matches=()

    # 1. Scan for .tmp regular files (do not follow symlinks)
    while IFS= read -r -d '' file; do
        [[ -z "${file}" ]] && continue
        tmp_matches+=("${file}")
    done < <(find -P "${WORKSPACE_DIR}" -type f -name "*.tmp" -print0 2>/dev/null)

    # 2. Scan for .bak regular files
    while IFS= read -r -d '' file; do
        [[ -z "${file}" ]] && continue
        bak_matches+=("${file}")
    done < <(find -P "${WORKSPACE_DIR}" -type f -name "*.bak" -print0 2>/dev/null)

    # 3. Scan for large regular files exceeding threshold_bytes (independent of extension)
    while IFS= read -r -d '' file; do
        [[ -z "${file}" ]] && continue
        local sz
        sz=$(stat -c '%s' "${file}" 2>/dev/null || echo 0)
        if [[ ${sz} -ge ${threshold_bytes} ]]; then
            large_matches+=("${file}")
        fi
    done < <(find -P "${WORKSPACE_DIR}" -type f -print0 2>/dev/null)

    # Display Scan Results
    echo -e "${C_BCYAN}1. Temporary Files (*.tmp):${C_RESET}"
    local total_tmp_bytes=0
    if [[ ${#tmp_matches[@]} -eq 0 ]]; then
        echo -e "   ${C_GRAY}No .tmp files detected in workspace.${C_RESET}"
    else
        printf "   ${C_DIM}%-32s %-12s %-12s${C_RESET}\n" "RELATIVE PATH" "SIZE (BYTES)" "LOCATION"
        for f in "${tmp_matches[@]}"; do
            local relpath="${f#${WORKSPACE_DIR}/}"
            local sz
            sz=$(stat -c '%s' "${f}" 2>/dev/null || echo 0)
            total_tmp_bytes=$((total_tmp_bytes + sz))
            printf "   %-32s ${C_CYAN}%-12s${C_RESET} %-12s\n" "${relpath:0:32}" "${sz} B" "$(dirname "${relpath}")"
        done
        echo -e "   ${C_DIM}Count: ${C_WHITE}${#tmp_matches[@]}${C_DIM} | Cumulative Size: ${C_WHITE}${total_tmp_bytes} bytes${C_RESET}"
    fi
    echo ""

    echo -e "${C_BCYAN}2. Backup Files (*.bak):${C_RESET}"
    local total_bak_bytes=0
    if [[ ${#bak_matches[@]} -eq 0 ]]; then
        echo -e "   ${C_GRAY}No .bak files detected in workspace.${C_RESET}"
    else
        printf "   ${C_DIM}%-32s %-12s %-12s${C_RESET}\n" "RELATIVE PATH" "SIZE (BYTES)" "LOCATION"
        for f in "${bak_matches[@]}"; do
            local relpath="${f#${WORKSPACE_DIR}/}"
            local sz
            sz=$(stat -c '%s' "${f}" 2>/dev/null || echo 0)
            total_bak_bytes=$((total_bak_bytes + sz))
            printf "   %-32s ${C_CYAN}%-12s${C_RESET} %-12s\n" "${relpath:0:32}" "${sz} B" "$(dirname "${relpath}")"
        done
        echo -e "   ${C_DIM}Count: ${C_WHITE}${#bak_matches[@]}${C_DIM} | Cumulative Size: ${C_WHITE}${total_bak_bytes} bytes${C_RESET}"
    fi
    echo ""

    echo -e "${C_BCYAN}3. Large Files (>= ${threshold_kb} KiB):${C_RESET}"
    local total_large_bytes=0
    if [[ ${#large_matches[@]} -eq 0 ]]; then
        echo -e "   ${C_GRAY}No files meet or exceed the ${threshold_kb} KiB threshold in workspace.${C_RESET}"
    else
        printf "   ${C_DIM}%-32s %-12s %-12s${C_RESET}\n" "RELATIVE PATH" "SIZE (BYTES)" "EXTENSION"
        for f in "${large_matches[@]}"; do
            local relpath="${f#${WORKSPACE_DIR}/}"
            local sz
            sz=$(stat -c '%s' "${f}" 2>/dev/null || echo 0)
            total_large_bytes=$((total_large_bytes + sz))
            local ext="${f##*.}"
            printf "   %-32s ${C_BYELLOW}%-12s${C_RESET} %-12s\n" "${relpath:0:32}" "${sz} B" ".${ext:0:8}"
        done
        echo -e "   ${C_DIM}Count: ${C_WHITE}${#large_matches[@]}${C_DIM} | Cumulative Size: ${C_WHITE}${total_large_bytes} bytes${C_RESET}"
    fi
    echo ""

    local total_audited=$(( ${#tmp_matches[@]} + ${#bak_matches[@]} + ${#large_matches[@]} ))
    log_activity "SCAN" "WORKSPACE" "SUCCESS" "Audited ${total_audited} matching items (tmp=${#tmp_matches[@]}, bak=${#bak_matches[@]}, large=${#large_matches[@]})"
    prompt_return
}

# ------------------------------------------------------------------------------
# 8. MODULE 4 — FILE PERMISSION SECURITY AUDITOR
# ------------------------------------------------------------------------------

module_permission_auditor() {
    while true; do
        draw_header
        draw_section_header "MODULE 4: FILE PERMISSION SECURITY AUDITOR"
        init_workspace

        echo -e "${C_DIM}Audits POSIX permissions across the workspace. Identifies overly permissive files,${C_RESET}"
        echo -e "${C_DIM}world-writable assets, and provides controlled hardening to mode 600 (-rw-------).${C_RESET}\n"

        # List all regular files in workspace with permission breakdown
        local file_list=()
        while IFS= read -r -d '' f; do
            [[ -z "$f" ]] && continue
            file_list+=("$f")
        done < <(find -P "${WORKSPACE_DIR}" -type f -print0 2>/dev/null | sort -z)

        if [[ ${#file_list[@]} -eq 0 ]]; then
            draw_status "WARN" "No regular files exist in the workspace to audit."
            echo -e "${C_DIM}Use Module 2 (Workspace Manager) to generate synthetic demonstration files first.${C_RESET}"
            prompt_return
            return
        fi

        echo -e "${C_BCYAN}Workspace File Security & Permission Matrix:${C_RESET}"
        printf "${C_DIM}%-4s %-26s %-6s %-11s %-12s %-14s${C_RESET}\n" "NUM" "FILE PATH" "OCTAL" "STRING" "OWNER:GROUP" "SECURITY STATUS"
        echo -e "${C_GRAY}--------------------------------------------------------------------------------${C_RESET}"

        local idx=0
        for f in "${file_list[@]}"; do
            idx=$((idx + 1))
            local relpath="${f#${WORKSPACE_DIR}/}"
            local octal perm_str owner_grp
            octal="$(stat -c '%a' "${f}" 2>/dev/null || echo "???")"
            perm_str="$(stat -c '%A' "${f}" 2>/dev/null || echo "???")"
            owner_grp="$(stat -c '%U:%G' "${f}" 2>/dev/null || echo "???")"

            # Determine security posture based on POSIX octal bits
            local status_label="${C_GREEN}STANDARD (644)${C_RESET}"
            if [[ "${octal}" == "777" ]]; then
                status_label="${C_BRED}CRITICAL (777)${C_RESET}"
            elif [[ "${octal}" == *[2367][2367] || "${octal}" == *[2367] ]]; then
                status_label="${C_BYELLOW}RISK: WRITABLE${C_RESET}"
            elif [[ "${octal}" == "600" || "${octal}" == "400" ]]; then
                status_label="${C_BGREEN}HARDENED (600)${C_RESET}"
            fi

            printf "[%02d] %-26s ${C_CYAN}%-6s${C_RESET} ${C_WHITE}%-11s${C_RESET} %-12s %b\n" \
                "${idx}" "${relpath:0:26}" "${octal}" "${perm_str}" "${owner_grp:0:12}" "${status_label}"
        done

        echo ""
        echo -e "${C_BCYAN}Security Principles & Risk Notes:${C_RESET}"
        echo -e "  - ${C_BRED}777 (rwxrwxrwx):${C_RESET} Broadly open; allows any local user to modify, overwrite, or execute."
        echo -e "  - ${C_GREEN}644 (rw-r--r--):${C_RESET} Standard unclassified file; owner edits, others can only read."
        echo -e "  - ${C_BGREEN}600 (rw-------):${C_RESET} Hardened; strictly restricted to owner only (Owner read/write, Group/Others none)."
        echo ""
        echo -e "${C_BCYAN}Permission Hardening Action:${C_RESET}"
        echo -e "Enter the file number [1-${#file_list[@]}] to harden to ${C_BGREEN}mode 600${C_RESET}, or ${C_WHITE}[0]${C_RESET} to return:"
        echo -n -e "${C_CYAN}Select option: ${C_RESET}"
        if ! read -r target_idx; then
            break
        fi

        if [[ -z "${target_idx}" || "${target_idx}" == "0" ]]; then
            break
        fi

        if ! [[ "${target_idx}" =~ ^[0-9]+$ ]] || [[ "${target_idx}" -lt 1 || "${target_idx}" -gt ${#file_list[@]} ]]; then
            draw_status "ERROR" "Invalid file selection."
            sleep 1
            continue
        fi

        local selected_file="${file_list[$((target_idx - 1))]}"
        local rel_target="${selected_file#${WORKSPACE_DIR}/}"

        # Safety revalidation: ensure candidate is strictly a regular file inside workspace
        if ! is_path_inside_workspace "${selected_file}" || [[ ! -f "${selected_file}" ]]; then
            draw_status "ERROR" "Path validation failed. File is not eligible for modification."
            sleep 1.5
            continue
        fi

        local current_octal current_perm
        current_octal="$(stat -c '%a' "${selected_file}" 2>/dev/null || echo "???")"
        current_perm="$(stat -c '%A' "${selected_file}" 2>/dev/null || echo "???")"

        if [[ "${current_octal}" == "600" ]]; then
            echo ""
            draw_status "INFO" "File '${rel_target}' is already hardened to mode 600 (-rw-------)."
            sleep 1.5
            continue
        fi

        echo ""
        echo -e "${C_BYELLOW}[?] Confirm Permission Hardening:${C_RESET}"
        echo -e "  Target:        ${C_WHITE}${rel_target}${C_RESET}"
        echo -e "  Current Mode:  ${C_YELLOW}${current_octal} (${current_perm})${C_RESET}"
        echo -e "  Proposed Mode: ${C_BGREEN}600 (-rw-------)${C_RESET}"
        echo -n -e "${C_CYAN}Apply chmod 600 to target file? [y/N]: ${C_RESET}"
        read -r confirm_harden || confirm_harden=""
        confirm_harden="$(echo "${confirm_harden:-}" | tr -d '\r\n[:space:]')"

        if [[ "${confirm_harden}" =~ ^[Yy]$ ]]; then
            if chmod 600 "${selected_file}" 2>/dev/null; then
                local new_octal new_perm
                new_octal="$(stat -c '%a' "${selected_file}" 2>/dev/null || echo "600")"
                new_perm="$(stat -c '%A' "${selected_file}" 2>/dev/null || echo "-rw-------")"

                echo ""
                draw_status "SUCCESS" "Permissions successfully hardened!"
                echo -e "  Before: ${C_YELLOW}${current_octal} (${current_perm})${C_RESET}"
                echo -e "  After:  ${C_BGREEN}${new_octal} (${new_perm})${C_RESET}"
                log_activity "HARDEN_PERM" "${rel_target}" "SUCCESS" "Mode updated from ${current_octal} to ${new_octal}"
            else
                draw_status "ERROR" "Failed to update permissions on '${rel_target}'."
                log_activity "HARDEN_PERM" "${rel_target}" "FAILED" "chmod command returned non-zero exit status"
            fi
            prompt_return
        else
            draw_status "INFO" "Hardening cancelled by user. No permissions were modified."
            log_activity "HARDEN_PERM" "${rel_target}" "CANCELLED" "User aborted permission hardening prompt"
            sleep 1.5
        fi
    done
}

# ------------------------------------------------------------------------------
# 9. MODULE 5 — SAFE CLEANUP CENTER
# ------------------------------------------------------------------------------

module_cleanup_center() {
    draw_header
    draw_section_header "MODULE 5: SAFE CLEANUP CENTER (TWO-STAGE WORKFLOW)"
    init_workspace

    echo -e "${C_DIM}Safety Guarantee: Cleanups are strictly confined to regular (*.tmp) files directly${C_RESET}"
    echo -e "${C_DIM}inside the managed '${DIR_TEMP#${WORKSPACE_DIR}/}' directory. Never deletes outside workspace.${C_RESET}\n"

    # Stage A: DRY-RUN PREVIEW (Default action)
    echo -e "${C_BCYAN}STAGE A: DRY-RUN INSPECTION & PREVIEW${C_RESET}"
    echo -e "${C_GRAY}Scanning ${DIR_TEMP} for candidate temporary files...${C_RESET}\n"

    # Identify eligible regular files directly inside temp/ (maxdepth 1, no symlinks, regular files only)
    local candidate_files=()
    while IFS= read -r -d '' f; do
        [[ -z "$f" ]] && continue
        # Verify it is a regular file and NOT a symlink
        if [[ -f "$f" && ! -L "$f" ]]; then
            candidate_files+=("$f")
        fi
    done < <(find -P "${DIR_TEMP}" -maxdepth 1 -type f -name "*.tmp" -print0 2>/dev/null)

    local candidate_count=${#candidate_files[@]}
    local total_reclaimable=0

    if [[ ${candidate_count} -eq 0 ]]; then
        echo -e "${C_GREEN}[i] No candidate .tmp regular files found in ${DIR_TEMP#${WORKSPACE_DIR}/}.${C_RESET}"
        echo -e "${C_DIM}Nothing to clean. Workspace is in a clean state.${C_RESET}"
        echo -e "${C_DIM}(Use Module 2 if you wish to generate demonstration files for testing).${C_RESET}\n"
        log_activity "CLEANUP_DRYRUN" "${DIR_TEMP}" "CLEAN" "Dry run detected 0 candidate files"
        prompt_return
        return
    fi

    # Display candidate list
    printf "${C_DIM}%-4s %-32s %-12s %-19s${C_RESET}\n" "NUM" "CANDIDATE FILE" "SIZE (BYTES)" "MODIFIED TIME"
    echo -e "${C_GRAY}--------------------------------------------------------------------------------${C_RESET}"
    
    local c_idx=0
    for cand in "${candidate_files[@]}"; do
        c_idx=$((c_idx + 1))
        local cand_name
        cand_name="$(basename "${cand}")"
        local sz mod_time
        sz=$(stat -c '%s' "${cand}" 2>/dev/null || echo 0)
        mod_time=$(stat -c '%y' "${cand}" 2>/dev/null | cut -d. -f1 || echo "???")
        total_reclaimable=$((total_reclaimable + sz))

        printf "[%02d] %-32s ${C_CYAN}%-12s${C_RESET} %-19s\n" \
            "${c_idx}" "${cand_name:0:32}" "${sz} B" "${mod_time:0:19}"
    done

    echo ""
    echo -e "Candidate Count:      ${C_WHITE}${candidate_count}${C_RESET} eligible regular file(s)"
    echo -e "Reclaimable Storage:  ${C_BGREEN}${total_reclaimable} bytes${C_RESET}"
    echo ""
    echo -e "${C_BYELLOW}[DRY RUN NOTICE] This was a dry-run preview. NO FILES WERE DELETED.${C_RESET}\n"

    # Stage B: CONFIRMED DELETION
    echo -e "${C_BCYAN}STAGE B: CONFIRMED DELETION${C_RESET}"
    echo -e "${C_BRED}CAUTION:${C_RESET} This action permanently deletes the ${candidate_count} eligible .tmp files listed above."
    echo -e "${C_DIM}All archives (.bak), reports, logs, subdirectories, and unrelated files are preserved.${C_RESET}"
    echo -n -e "To execute cleanup, type '${C_BRED}DELETE${C_RESET}' (or press Enter to cancel): "
    read -r user_confirm || user_confirm=""
    user_confirm="$(echo "${user_confirm:-}" | tr -d '\r\n' | sed 's/^[ \t]*//;s/[ \t]*$//')"

    if [[ "${user_confirm}" != "DELETE" ]]; then
        echo ""
        draw_status "INFO" "Cleanup aborted. User did not type 'DELETE'. Zero files removed."
        log_activity "CLEANUP" "${DIR_TEMP}" "CANCELLED" "User aborted confirmation prompt (input='${user_confirm}')"
        prompt_return
        return
    fi

    # Execute deletion with strict individual path re-validation
    echo ""
    echo -e "${C_DIM}Executing confirmed cleanup with real-time path validation...${C_RESET}"
    
    local deleted_count=0
    local failed_count=0
    local bytes_cleaned=0

    for item in "${candidate_files[@]}"; do
        local base_item
        base_item="$(basename "${item}")"

        # Re-verify path safety immediately before unlinking
        if ! is_path_inside_workspace "${item}"; then
            echo -e "  ${C_BRED}[REJECTED]${C_RESET} Security check failed on: ${base_item}"
            failed_count=$((failed_count + 1))
            continue
        fi

        # Verify target is strictly a regular file and resides in DIR_TEMP
        local item_dir
        item_dir="$(cd -P "$(dirname "${item}")" 2>/dev/null && pwd -P)"
        local canonical_temp
        canonical_temp="$(cd -P "${DIR_TEMP}" 2>/dev/null && pwd -P)"

        if [[ "${item_dir}" != "${canonical_temp}" || ! -f "${item}" || -L "${item}" ]]; then
            echo -e "  ${C_BRED}[REJECTED]${C_RESET} Target outside designated temp folder: ${base_item}"
            failed_count=$((failed_count + 1))
            continue
        fi

        local file_size
        file_size=$(stat -c '%s' "${item}" 2>/dev/null || echo 0)

        # Atomic unlink using rm -f -- (never rm -rf)
        if rm -f -- "${item}" 2>/dev/null; then
            # Verify file no longer exists
            if [[ ! -e "${item}" ]]; then
                echo -e "  ${C_BGREEN}[DELETED]${C_RESET} ${base_item} (${file_size} B)"
                deleted_count=$((deleted_count + 1))
                bytes_cleaned=$((bytes_cleaned + file_size))
            else
                echo -e "  ${C_BRED}[FAILED]${C_RESET} File still present after unlink: ${base_item}"
                failed_count=$((failed_count + 1))
            fi
        else
            echo -e "  ${C_BRED}[ERROR]${C_RESET} Permission or OS error deleting: ${base_item}"
            failed_count=$((failed_count + 1))
        fi
    done

    echo ""
    if [[ ${failed_count} -eq 0 ]]; then
        draw_status "SUCCESS" "Cleanup executed cleanly. ${deleted_count} file(s) removed, ${bytes_cleaned} bytes reclaimed."
        log_activity "CLEANUP" "${DIR_TEMP}" "SUCCESS" "Removed ${deleted_count} files, reclaimed ${bytes_cleaned} bytes"
    else
        draw_status "WARN" "Cleanup finished with warnings: ${deleted_count} removed, ${failed_count} failed."
        log_activity "CLEANUP" "${DIR_TEMP}" "WARN" "Removed ${deleted_count} files, failed on ${failed_count}"
    fi

    prompt_return
}

# ------------------------------------------------------------------------------
# 10. MODULE 6 — STORAGE ANALYSIS
# ------------------------------------------------------------------------------

module_storage_analysis() {
    draw_header
    draw_section_header "MODULE 6: STORAGE ANALYSIS & CAPACITY AUDITING"
    init_workspace

    echo -e "${C_DIM}Comprehensive analysis distinguishing root partition utilization from isolated${C_RESET}"
    echo -e "${C_DIM}workspace storage quotas. Configurable threshold alerts for disk pressure.${C_RESET}\n"

    # Overall Root Filesystem Metrics via df -Pk /
    local root_pct_val=0
    local root_total_h="N/A" root_used_h="N/A" root_avail_h="N/A" root_mount="/"
    local df_metrics
    df_metrics="$(df -Pk / 2>/dev/null | awk 'NR>1 {print $(NF-4), $(NF-3), $(NF-2), $(NF-1), $NF; exit}')"

    if [[ -n "${df_metrics}" ]]; then
        local k_total k_used k_avail pct_str
        read -r k_total k_used k_avail pct_str root_mount <<< "${df_metrics}"
        root_pct_val="${pct_str%%%}"

        if [[ "${k_total:-}" =~ ^[0-9]+$ && "${k_total}" -gt 0 ]]; then
            root_total_h="$(( k_total / 1024 / 1024 )) GB"
        fi
        if [[ "${k_used:-}" =~ ^[0-9]+$ && "${k_used}" -gt 0 ]]; then
            root_used_h="$(( k_used / 1024 / 1024 )) GB"
        fi
        if [[ "${k_avail:-}" =~ ^[0-9]+$ && "${k_avail}" -gt 0 ]]; then
            root_avail_h="$(( k_avail / 1024 / 1024 )) GB"
        fi
    fi

    # Check for threshold alarm
    echo -e "${C_BCYAN}1. Host Filesystem Capacity (Mount: ${root_mount}):${C_RESET}"
    printf "  Total Capacity:     ${C_WHITE}%s${C_RESET}\n" "${root_total_h}"
    printf "  Space Consumed:     ${C_WHITE}%s${C_RESET} (${root_pct_val}%%)\n" "${root_used_h}"
    printf "  Space Available:    ${C_GREEN}%s${C_RESET}\n" "${root_avail_h}"

    if [[ ${root_pct_val} -ge ${DISK_WARN_THRESHOLD} ]]; then
        echo ""
        echo -e "${C_BRED}+--------------------------------------------------------------+${C_RESET}"
        echo -e "${C_BRED}| [!] WARNING: ROOT STORAGE UTILIZATION AT ${root_pct_val}% (Threshold: ${DISK_WARN_THRESHOLD}%)  |${C_RESET}"
        echo -e "${C_BRED}| Root disk partition is operating under elevated capacity.   |${C_RESET}"
        echo -e "${C_BRED}+--------------------------------------------------------------+${C_RESET}"
    else
        echo -e "  Threshold Posture:  ${C_BGREEN}HEALTHY${C_RESET} (Utilization ${root_pct_val}% is below ${DISK_WARN_THRESHOLD}% alert threshold)"
    fi
    echo ""

    # Workspace Subdirectory Breakdown
    echo -e "${C_BCYAN}2. Guardian Workspace Directory Storage Breakdown:${C_RESET}"
    printf "  ${C_DIM}%-18s %-12s %-10s${C_RESET}\n" "DIRECTORY" "SIZE" "FILES"
    echo -e "  ${C_GRAY}------------------------------------------------${C_RESET}"

    local subdirs=("logs" "temp" "archive" "reports")
    for s in "${subdirs[@]}"; do
        local s_path="${WORKSPACE_DIR}/${s}"
        local s_size="0 B"
        local s_files=0
        if [[ -d "${s_path}" ]]; then
            s_size="$(du -sh "${s_path}" 2>/dev/null | cut -f1)"
            s_files=$(find "${s_path}" -maxdepth 1 -type f 2>/dev/null | wc -l)
        fi
        printf "  %-18s ${C_CYAN}%-12s${C_RESET} %-10s\n" "${s}/" "${s_size}" "${s_files} file(s)"
    done
    
    local total_ws_size
    total_ws_size="$(du -sh "${WORKSPACE_DIR}" 2>/dev/null | cut -f1)"
    echo -e "  ${C_GRAY}------------------------------------------------${C_RESET}"
    printf "  ${C_BOLD}%-18s ${C_BYELLOW}%-12s${C_RESET}\n" "Total Workspace:" "${total_ws_size}"
    echo ""

    # Largest Regular Files in Workspace
    echo -e "${C_BCYAN}3. Top Largest Regular Files in Workspace:${C_RESET}"
    local large_list=()
    while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        large_list+=("$item")
    done < <(find -P "${WORKSPACE_DIR}" -type f -exec stat -c '%s %n' {} + 2>/dev/null | sort -nr | head -n 5)

    if [[ ${#large_list[@]} -eq 0 ]]; then
        echo -e "  ${C_GRAY}No files currently found in workspace.${C_RESET}"
    else
        printf "  ${C_DIM}%-32s %-12s${C_RESET}\n" "FILE PATH" "SIZE (BYTES)"
        for entry in "${large_list[@]}"; do
            local sz fpath
            sz="$(echo "${entry}" | awk '{print $1}')"
            fpath="$(echo "${entry}" | cut -d' ' -f2-)"
            local rel="${fpath#${WORKSPACE_DIR}/}"
            printf "  %-32s ${C_WHITE}%-12s${C_RESET}\n" "${rel:0:32}" "${sz} B"
        done
    fi
    echo ""

    # Academic OS Note
    echo -e "${C_BCYAN}Operating Systems Storage Note:${C_RESET}"
    echo -e "${C_DIM}Cleaning user workspace files recovers local quota, but does not alter system-level${C_RESET}"
    echo -e "${C_DIM}package caches or kernel image storage. System partition maintenance requires root/apt.${C_RESET}"

    log_activity "STORAGE_AUDIT" "WORKSPACE" "SUCCESS" "Storage metrics audited (root=${root_pct_val}%, ws=${total_ws_size})"
    prompt_return
}

# ------------------------------------------------------------------------------
# 11. MODULE 7 — REPORTS & ACTIVITY LOGS
# ------------------------------------------------------------------------------

generate_plain_report() {
    init_workspace
    local report_ts
    report_ts="$(date '+%Y%m%d_%H%M%S')"
    local report_file="${DIR_REPORTS}/guardian_report_${report_ts}.txt"

    # Dynamic metrics collection
    local host_name os_name kernel_ver now_date
    host_name="$(hostname 2>/dev/null || echo "Unknown")"
    kernel_ver="$(uname -s -r 2>/dev/null || echo "Linux")"
    now_date="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"
    
    os_name="Generic Linux"
    if [[ -r /etc/os-release ]]; then
        os_name="$(grep -E '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')"
    fi

    local df_metrics
    df_metrics="$(df -Pk / 2>/dev/null | awk 'NR>1 {print $(NF-4), $(NF-3), $(NF-2), $(NF-1), $NF; exit}')"
    local root_pct="N/A" root_gb_total=0 root_gb_used=0
    if [[ -n "${df_metrics}" ]]; then
        local k_total k_used k_avail
        read -r k_total k_used k_avail root_pct _ <<< "${df_metrics}"
        if [[ "${k_total:-}" =~ ^[0-9]+$ && "${k_total}" -gt 0 ]]; then
            root_gb_total="$(( k_total / 1024 / 1024 ))"
        fi
        if [[ "${k_used:-}" =~ ^[0-9]+$ && "${k_used}" -gt 0 ]]; then
            root_gb_used="$(( k_used / 1024 / 1024 ))"
        fi
    fi

    local ws_size
    ws_size="$(du -sh "${WORKSPACE_DIR}" 2>/dev/null | cut -f1)"

    local tmp_cnt bak_cnt total_files
    tmp_cnt=$(find -P "${WORKSPACE_DIR}" -type f -name "*.tmp" 2>/dev/null | wc -l)
    bak_cnt=$(find -P "${WORKSPACE_DIR}" -type f -name "*.bak" 2>/dev/null | wc -l)
    total_files=$(find -P "${WORKSPACE_DIR}" -type f 2>/dev/null | wc -l)

    # Build report content strictly without ANSI codes
    {
        echo "================================================================================"
        echo "                    LINUX SYSTEM GUARDIAN AUDIT REPORT"
        echo "                     Workspace Management & Security"
        echo "================================================================================"
        echo "Generated On       : ${now_date}"
        echo "Host Identity      : ${host_name}"
        echo "Operating System   : ${os_name}"
        echo "Kernel Version     : ${kernel_ver}"
        echo "Guardian Version   : ${APP_VERSION}"
        echo "Workspace Path     : ${WORKSPACE_DIR}"
        echo "--------------------------------------------------------------------------------"
        echo "1. STORAGE & PARTITION METRICS"
        echo "   Root Partition  : Total: ${root_gb_total} GB | Used: ${root_gb_used} GB (${root_pct})"
        echo "   Workspace Total : ${ws_size}"
        echo "   Logs Storage    : $(du -sh "${DIR_LOGS}" 2>/dev/null | cut -f1)"
        echo "   Temp Storage    : $(du -sh "${DIR_TEMP}" 2>/dev/null | cut -f1)"
        echo "   Archive Storage : $(du -sh "${DIR_ARCHIVE}" 2>/dev/null | cut -f1)"
        echo "   Reports Storage : $(du -sh "${DIR_REPORTS}" 2>/dev/null | cut -f1)"
        echo "--------------------------------------------------------------------------------"
        echo "2. FILE INVENTORY & SCANNER AUDIT"
        echo "   Total Files Audited : ${total_files}"
        echo "   Temporary Files (*.tmp) : ${tmp_cnt}"
        echo "   Backup Files (*.bak)    : ${bak_cnt}"
        echo ""
        echo "   Temporary Files Detail:"
        find -P "${WORKSPACE_DIR}" -type f -name "*.tmp" -exec stat -c '     - %n (%s bytes, mode %a)' {} + 2>/dev/null || echo "     (None)"
        echo "--------------------------------------------------------------------------------"
        echo "3. SECURITY & PERMISSION POSTURE"
        echo "   File Permission Sample:"
        find -P "${WORKSPACE_DIR}" -type f -exec stat -c '     - %A (%a) %U:%G %n' {} + 2>/dev/null | head -n 10
        echo "--------------------------------------------------------------------------------"
        echo "4. RECENT ACTIVITY LOG TRAIL (LAST 10 ENTRIES)"
        if [[ -s "${LOG_FILE}" ]]; then
            tail -n 10 "${LOG_FILE}" | sed 's/^/   /'
        else
            echo "   (No prior log entries)"
        fi
        echo "================================================================================"
        echo "                        END OF GUARDIAN AUDIT REPORT"
        echo "================================================================================"
    } | strip_ansi > "${report_file}"

    if [[ -f "${report_file}" && -s "${report_file}" ]]; then
        echo -e "${C_BGREEN}[+] Report generated successfully:${C_RESET}"
        echo -e "    ${C_WHITE}${report_file}${C_RESET} (${C_CYAN}$(stat -c '%s B' "${report_file}" 2>/dev/null)${C_RESET})"
        log_activity "REPORT_GEN" "$(basename "${report_file}")" "SUCCESS" "System audit report generated"
    else
        draw_status "ERROR" "Failed to generate report file."
        log_activity "REPORT_GEN" "N/A" "FAILED" "Failed to write report file to disk"
    fi
}

module_reports_and_logs() {
    while true; do
        draw_header
        draw_section_header "MODULE 7: REPORTS & ACTIVITY AUDIT TRAIL"
        init_workspace

        echo -e "${C_BCYAN}Audit Trail & Reporting Actions:${C_RESET}"
        echo -e "  ${C_WHITE}[1]${C_RESET} View Full Activity Log (${LOG_FILE#${WORKSPACE_DIR}/})"
        echo -e "  ${C_WHITE}[2]${C_RESET} Generate Comprehensive System Audit Report (.txt)"
        echo -e "  ${C_WHITE}[3]${C_RESET} List Existing Audit Reports (${DIR_REPORTS#${WORKSPACE_DIR}/})"
        echo -e "  ${C_WHITE}[4]${C_RESET} View Most Recent Audit Report"
        echo -e "  ${C_WHITE}[0]${C_RESET} Return to Main Menu"
        echo ""
        echo -n -e "${C_CYAN}Select option [0-4]: ${C_RESET}"
        if ! read -r rep_choice; then
            break
        fi

        case "${rep_choice}" in
            1)
                echo ""
                draw_section_header "ACTIVITY AUDIT TRAIL (FULL LOG)"
                if [[ -s "${LOG_FILE}" ]]; then
                    # Output with line numbers
                    nl -ba -w3 -s': ' "${LOG_FILE}"
                else
                    echo -e "${C_YELLOW}Log file is currently empty.${C_RESET}"
                fi
                prompt_return
                ;;
            2)
                echo ""
                generate_plain_report
                prompt_return
                ;;
            3)
                echo ""
                draw_section_header "EXISTING AUDIT REPORTS"
                local rep_count=0
                while IFS= read -r r; do
                    [[ -z "$r" ]] && continue
                    rep_count=$((rep_count + 1))
                    local r_name
                    r_name="$(basename "$r")"
                    local r_size r_date
                    r_size="$(stat -c '%s B' "$r" 2>/dev/null || echo "0 B")"
                    r_date="$(stat -c '%y' "$r" 2>/dev/null | cut -d. -f1 || echo "???")"
                    printf "  [%02d] ${C_WHITE}%-34s${C_RESET} ${C_CYAN}%-10s${C_RESET} %s\n" "${rep_count}" "${r_name}" "${r_size}" "${r_date}"
                done < <(find "${DIR_REPORTS}" -maxdepth 1 -type f -name "guardian_report_*.txt" 2>/dev/null | sort -r)

                if [[ ${rep_count} -eq 0 ]]; then
                    echo -e "${C_GRAY}No reports generated yet. Select Option [2] to create your first report.${C_RESET}"
                fi
                prompt_return
                ;;
            4)
                echo ""
                local latest_report
                latest_report="$(find "${DIR_REPORTS}" -maxdepth 1 -type f -name "guardian_report_*.txt" 2>/dev/null | sort -r | head -n 1)"
                if [[ -n "${latest_report}" && -f "${latest_report}" ]]; then
                    draw_section_header "LATEST REPORT: $(basename "${latest_report}")"
                    cat "${latest_report}"
                else
                    draw_status "WARN" "No audit reports found. Please generate one first."
                fi
                prompt_return
                ;;
            0|"")
                break
                ;;
            *)
                draw_status "ERROR" "Invalid option. Please choose between 0 and 4."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 12. MODULE 8 — HELP, ABOUT & OS CONCEPTS
# ------------------------------------------------------------------------------

module_help_and_about() {
    draw_header
    draw_section_header "MODULE 8: HELP, ACADEMIC CONCEPTS & SYSTEM ARCHITECTURE"

    echo -e "${C_BCYAN}1. Academic Project Overview:${C_RESET}"
    echo -e "  ${C_WHITE}${APP_NAME} v${APP_VERSION}${C_RESET} is an Operating Systems microproject"
    echo -e "  built for Kali Linux / Debian distributions to demonstrate native Linux systems"
    echo -e "  programming, POSIX filesystem operations, security audits, and shell automation.\n"

    echo -e "${C_BCYAN}2. Native Linux Utilities & System Commands Employed:${C_RESET}"
    echo -e "  - ${C_WHITE}uname, hostname, date${C_RESET} : System identification and kernel telemetry."
    echo -e "  - ${C_WHITE}/proc/stat, /proc/meminfo${C_RESET}: Kernel metrics, CPU timeslice sampling, memory states."
    echo -e "  - ${C_WHITE}df, du${C_RESET}                  : Filesystem mount capacities, disk utilization quotas."
    echo -e "  - ${C_WHITE}find (-print0, -P)${C_RESET}      : Directory traversal, size filters, symlink rejection."
    echo -e "  - ${C_WHITE}stat, chmod${C_RESET}             : Inode inspection, POSIX octal modes, security hardening."
    echo -e "  - ${C_WHITE}trap (SIGINT, SIGTERM)${C_RESET}  : Asynchronous signal handling and graceful state management."
    echo -e "  - ${C_WHITE}grep, awk, sed${C_RESET}          : Stream processing, regex parsing, ANSI escape stripping.\n"

    echo -e "${C_BCYAN}3. Operating Systems Core Concepts Demonstrated:${C_RESET}"
    echo -e "  - ${C_WHITE}Process Telemetry:${C_RESET} Calculates dynamic CPU load via Jiffies timeslices in /proc/stat."
    echo -e "  - ${C_WHITE}Virtual Memory:${C_RESET} Tracks active memory allocation vs cached buffers in RAM."
    echo -e "  - ${C_WHITE}Filesystem Security:${C_RESET} Audits POSIX file permissions (600 vs 644 vs 777)."
    echo -e "  - ${C_WHITE}Data Isolation:${C_RESET} Confines file operations exclusively to a managed workspace."
    echo -e "  - ${C_WHITE}Defensive Automation:${C_RESET} Strict two-stage cleanup (Dry-run preview before delete).\n"

    echo -e "${C_BCYAN}4. Safety Boundaries & Disclaimer:${C_RESET}"
    echo -e "  - Normal operations ${C_BGREEN}never require root / sudo${C_RESET} privileges."
    echo -e "  - Destruction is strictly limited to candidate .tmp regular files in workspace/temp."
    echo -e "  - Symlinks are never traversed, and broad commands (rm -rf /) are strictly forbidden."
    echo -e "  - This tool is an academic microproject and does not replace enterprise SIEMs."

    prompt_return
}

# ------------------------------------------------------------------------------
# 13. AUTOMATED SELF-TEST & VERIFICATION SUITE
# ------------------------------------------------------------------------------

run_self_test() {
    echo -e "${C_BCYAN}================================================================${C_RESET}"
    echo -e "${C_WHITE}${C_BOLD}   LINUX SYSTEM GUARDIAN — AUTOMATED SELF-TEST SUITE            ${C_RESET}"
    echo -e "${C_BCYAN}================================================================${C_RESET}"
    echo -e "${C_DIM}Running automated headless test verification on current environment...${C_RESET}\n"

    local tests_passed=0
    local tests_failed=0

    run_test() {
        local test_name="$1"
        local test_cmd="$2"

        printf "  Testing: %-52s " "${test_name}..."
        if eval "${test_cmd}" >/dev/null 2>&1; then
            echo -e "${C_BGREEN}[PASS]${C_RESET}"
            tests_passed=$((tests_passed + 1))
        else
            echo -e "${C_BRED}[FAIL]${C_RESET}"
            tests_failed=$((tests_failed + 1))
        fi
    }

    # Test 1: Environment verification
    run_test "Environment dependencies" "verify_environment"

    # Test 2: Workspace initialization
    run_test "Workspace directory initialization" "init_workspace && [[ -d '${DIR_TEMP}' && -d '${DIR_LOGS}' ]]"

    # Test 3: Path isolation logic
    run_test "Workspace path boundary isolation" "is_path_inside_workspace '${WORKSPACE_DIR}' && ! is_path_inside_workspace '/etc/passwd'"

    # Test 4: Activity log creation
    run_test "Activity log logging" "log_activity 'TEST' 'UNIT' 'SUCCESS' 'Self-test assertion' && grep -q 'Self-test assertion' '${LOG_FILE}'"

    # Test 5: Synthetic demo file generation
    run_test "Demo file generation (no overwrite)" "create_demo_data && [[ -f '${DIR_TEMP}/session_cache_01.tmp' ]]"

    # Test 6: Inode stat permission retrieval
    run_test "POSIX stat permission retrieval" "stat -c '%a' '${DIR_TEMP}/session_cache_01.tmp' | grep -E '^[0-7]{3,4}$'"

    # Test 7: Permission hardening to 600
    local test_audit_file="${DIR_TEMP}/test_perm_audit.tmp"
    echo "test" > "${test_audit_file}"
    chmod 644 "${test_audit_file}" 2>/dev/null
    run_test "Permission hardening (chmod 600)" "chmod 600 \"${test_audit_file}\" && { [[ \"\$(stat -c %a \"${test_audit_file}\" 2>/dev/null)\" == \"600\" ]] || [[ \"\$(uname -s)\" =~ NT|MSYS|MINGW ]]; }"
    rm -f "${test_audit_file}" 2>/dev/null

    # Test 8: Safe cleanup dry-run preserves files
    local test_clean_file="${DIR_TEMP}/test_preserve.tmp"
    echo "temporary payload" > "${test_clean_file}"
    run_test "Dry-run preserves temporary candidate" "[[ -f '${test_clean_file}' ]]"

    # Test 9: Confirmed cleanup unlinks eligible file
    rm -f -- "${test_clean_file}" 2>/dev/null
    run_test "Cleanup removal of eligible file" "[[ ! -e '${test_clean_file}' ]]"

    # Test 10: Non-tmp and backup files survive
    local test_bak="${DIR_ARCHIVE}/safe_keep.bak"
    echo "backup" > "${test_bak}"
    run_test "Preservation of .bak in archive" "[[ -f '${test_bak}' ]]"
    rm -f "${test_bak}" 2>/dev/null

    # Test 11: ANSI strip filter validation
    local ansi_str
    ansi_str="$(echo -e '\033[0;31mColorTest\033[0m' | strip_ansi)"
    run_test "ANSI escape sequence stripping" "[[ '${ansi_str}' == 'ColorTest' ]]"

    # Test 12: Report generation
    run_test "Plaintext audit report generation" "generate_plain_report && [[ -d '${DIR_REPORTS}' ]]"

    echo ""
    echo -e "${C_BCYAN}----------------------------------------------------------------${C_RESET}"
    echo -e "Self-Test Results: ${C_BGREEN}${tests_passed} Passed${C_RESET}, ${C_BRED}${tests_failed} Failed${C_RESET}"
    echo -e "${C_BCYAN}----------------------------------------------------------------${C_RESET}"

    if [[ ${tests_failed} -eq 0 ]]; then
        echo -e "${C_BGREEN}[+] All system verification tests passed successfully!${C_RESET}\n"
        return 0
    else
        echo -e "${C_BRED}[X] Some tests failed. Please review system environment.${C_RESET}\n"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 14. MAIN MENU DISPATCH LOOP
# ------------------------------------------------------------------------------

main_menu() {
    verify_environment
    init_workspace

    while true; do
        draw_header
        
        echo -e "${C_BCYAN}MAIN INTERACTIVE CONSOLE:${C_RESET}"
        echo -e "  ${C_WHITE}[01]${C_RESET} System Overview & Dynamic Telemetry"
        echo -e "  ${C_WHITE}[02]${C_RESET} Workspace Manager (Inventory, Tree & Demo Files)"
        echo -e "  ${C_WHITE}[03]${C_RESET} Temporary & Large-File Scanner"
        echo -e "  ${C_WHITE}[04]${C_RESET} File Permission Security Auditor"
        echo -e "  ${C_WHITE}[05]${C_RESET} Safe Cleanup Center (Dry-Run & Confirmed)"
        echo -e "  ${C_WHITE}[06]${C_RESET} Storage Analysis & Capacity Thresholds"
        echo -e "  ${C_WHITE}[07]${C_RESET} Reports & Activity Audit Trail"
        echo -e "  ${C_WHITE}[08]${C_RESET} Help, Architecture & Operating System Concepts"
        echo -e "  ${C_WHITE}[99]${C_RESET} Run Automated Self-Test Suite"
        echo -e "  ${C_WHITE}[00]${C_RESET} Exit Guardian"
        echo ""
        echo -n -e "${C_CYAN}Select option [00-08 / 99]: ${C_RESET}"
        if ! read -r menu_selection; then
            echo ""
            log_activity "SESSION" "GUARDIAN" "EXIT" "Interactive session terminated (EOF)"
            exit 0
        fi

        case "${menu_selection}" in
            1|01)
                module_system_overview
                ;;
            2|02)
                module_workspace_manager
                ;;
            3|03)
                module_file_scanner
                ;;
            4|04)
                module_permission_auditor
                ;;
            5|05)
                module_cleanup_center
                ;;
            6|06)
                module_storage_analysis
                ;;
            7|07)
                module_reports_and_logs
                ;;
            8|08)
                module_help_and_about
                ;;
            99|test)
                echo ""
                run_self_test
                prompt_return
                ;;
            0|00|q|Q|exit)
                echo ""
                echo -e "${C_BGREEN}[*] Thank you for using ${APP_NAME}.${C_RESET}"
                echo -e "${C_DIM}All operations logged safely in ${LOG_FILE}.${C_RESET}"
                log_activity "SESSION" "GUARDIAN" "EXIT" "User closed interactive Guardian console"
                echo ""
                exit 0
                ;;
            *)
                echo ""
                draw_status "ERROR" "Invalid option '${menu_selection}'. Please enter a valid menu number."
                sleep 1.2
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# 15. ENTRY POINT & CLI ARGUMENT PARSER
# ------------------------------------------------------------------------------

# Handle CLI flags
TARGET_MODULE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace|-w)
            if [[ $# -ge 2 ]]; then
                set_workspace_path "$2" || exit 1
                shift 2
            else
                echo "Error: --workspace requires a directory path."
                exit 1
            fi
            ;;
        --test|--self-test|-t)
            verify_environment
            init_workspace
            run_self_test
            exit $?
            ;;
        --module|-m)
            if [[ $# -ge 2 ]]; then
                TARGET_MODULE="$2"
                shift 2
            else
                echo "Error: --module requires a module number [1-8]."
                exit 1
            fi
            ;;
        --help|-h)
            echo "${APP_NAME} v${APP_VERSION} - ${APP_SUBTITLE}"
            echo "Usage: ./linux_system_guardian.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (no args)                     Launch full interactive console"
            echo "  --workspace, -w <dir>         Set custom directory as managed workspace"
            echo "  --module, -m <1-8>            Run a specific module directly and exit"
            echo "  --test, -t                    Run automated self-test verification suite and exit"
            echo "  --help, -h                    Display this command usage overview"
            echo "  --version, -v                 Print version information"
            echo ""
            echo "Environment Variables:"
            echo "  GUARDIAN_WORKSPACE=/path/dir  Sets the default managed workspace path"
            exit 0
            ;;
        --version|-v)
            echo "${APP_NAME} version ${APP_VERSION}"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Run './linux_system_guardian.sh --help' for usage."
            exit 1
            ;;
    esac
done

if [[ -n "${TARGET_MODULE}" ]]; then
    verify_environment
    init_workspace
    case "${TARGET_MODULE}" in
        1|overview) module_system_overview ;;
        2|workspace) module_workspace_manager ;;
        3|scan) module_file_scanner ;;
        4|audit) module_permission_auditor ;;
        5|cleanup) module_cleanup_center ;;
        6|storage) module_storage_analysis ;;
        7|reports) module_reports_and_logs ;;
        8|help) module_help_and_about ;;
        *) echo "Usage: ./linux_system_guardian.sh --module [1-8]"; exit 1 ;;
    esac
    exit 0
fi

# Launch interactive main console
main_menu
