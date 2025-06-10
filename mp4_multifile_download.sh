#!/bin/bash

#================================================================================
# MP4 files downloader | Multifile downloader
# 
# Description: Interactive script to authenticate, parse HTML pages, and download
#              files from page threads with comprehensive format support
# 
# Usage: ./download_mp4_from_multiple_pages.sh [output_directory]
#================================================================================

set -e

# Change to user's home directory to ensure proper working directory
cd "$HOME"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
OUTPUT_DIR="${1:-$HOME/Downloads/mp4_downloads}"
URLS_FILE=$(mktemp)
CREDENTIALS_FILE="$HOME/Downloads/download_mp4_credentials_file.txt"
LOGS_DIR="$HOME/Downloads/mp4_downloader_logs"

# Global settings
VERBOSE_MODE=false
DEBUG_MODE=false

# Create logs directory
mkdir -p "$LOGS_DIR"

# Function to get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Function to get timestamp for filenames
get_file_timestamp() {
    date '+%Y%m%d_%H%M%S'
}

# Function to write to log file only (no console output)
write_to_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(get_timestamp)
    
    if [ -n "${CURRENT_LOG_FILE:-}" ]; then
        echo "[$timestamp] [$level] $message" >> "$CURRENT_LOG_FILE"
    fi
}

# Function to log messages (INFO level)
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(get_timestamp)
    
    # Always write to log file
    write_to_log "$level" "$message"
    
    # Display with timestamp if verbose mode is on
    if [ "$VERBOSE_MODE" = true ]; then
        echo -e "${BLUE}[$timestamp]${NC} $message"
    else
        echo -e "$message"
    fi
}

# Function to debug log
debug_log() {
    local message="$1"
    local timestamp=$(get_timestamp)
    
    # Always write to log file
    write_to_log "DEBUG" "$message"
    
    # Only display if debug mode is on
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${PURPLE}[DEBUG $timestamp]${NC} $message"
    fi
}

# Function to log CURL operations
log_curl() {
    local curl_command="$1"
    local curl_output="$2"
    local timestamp=$(get_timestamp)
    
    write_to_log "CURL" "Command: $curl_command"
    if [ -n "$curl_output" ]; then
        write_to_log "CURL" "Output: $curl_output"
    fi
    
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${CYAN}[CURL $timestamp]${NC} $curl_command"
        if [ -n "$curl_output" ]; then
            echo -e "${CYAN}[CURL OUTPUT]${NC} $curl_output"
        fi
    fi
}

# Function to clean wget output (remove progress bar noise)
clean_wget_output() {
    local raw_output="$1"
    # Remove carriage returns, progress bars, and keep only meaningful lines
    echo "$raw_output" | sed 's/\r/\n/g' | grep -E "(^Length:|^Saving to:|saved \[|^--.*--|ERROR|failed|^HTTP)" | head -10
}

# Function to log WGET operations
log_wget() {
    local wget_command="$1"
    local wget_output="$2"
    local timestamp=$(get_timestamp)
    
    write_to_log "WGET" "Command: $wget_command"
    if [ -n "$wget_output" ]; then
        # Clean the output before logging
        local clean_output=$(clean_wget_output "$wget_output")
        if [ -n "$clean_output" ]; then
            write_to_log "WGET" "Output: $clean_output"
        fi
    fi
    
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${GREEN}[WGET $timestamp]${NC} $wget_command"
        if [ -n "$wget_output" ]; then
            local clean_output=$(clean_wget_output "$wget_output")
            if [ -n "$clean_output" ]; then
                echo -e "${GREEN}[WGET OUTPUT]${NC} $clean_output"
            fi
        fi
    fi
}

# Function to log ERROR operations
log_error() {
    local error_message="$1"
    local error_details="$2"
    local timestamp=$(get_timestamp)
    
    write_to_log "ERROR" "$error_message"
    if [ -n "$error_details" ]; then
        write_to_log "ERROR" "Details: $error_details"
    fi
    
    # Always display errors
    echo -e "${RED}[ERROR $timestamp]${NC} $error_message"
    if [ -n "$error_details" ] && [ "$DEBUG_MODE" = true ]; then
        echo -e "${RED}[ERROR DETAILS]${NC} $error_details"
    fi
}

# Function to log download progress
log_download() {
    local filename="$1"
    local size="$2"
    local url="$3"
    local timestamp=$(get_timestamp)
    
    write_to_log "DOWNLOAD" "File: $filename, Size: $size, URL: $url"
    
    echo -e "${GREEN}[DOWNLOAD $timestamp]${NC} $filename ($size)"
    if [ "$VERBOSE_MODE" = true ]; then
        echo -e "${BLUE}   Source: $url${NC}"
    fi
}

# Function to execute curl with debug/verbose support
execute_curl() {
    local curl_args=("$@")
    local verbose_flag=""
    local silent_flag="-s"
    
    # Add verbose flags based on mode
    if [ "$DEBUG_MODE" = true ]; then
        verbose_flag="-v"
        silent_flag=""  # Remove silent flag in debug mode
        debug_log "Executing curl with debug mode"
        debug_log "Curl command: curl $verbose_flag ${curl_args[*]}"
    elif [ "$VERBOSE_MODE" = true ]; then
        silent_flag=""  # Remove silent flag in verbose mode
        log_message "INFO" "Executing curl command"
    fi
    
    # Execute curl with appropriate flags
    if [ "$DEBUG_MODE" = true ] || [ "$VERBOSE_MODE" = true ]; then
        curl $verbose_flag "${curl_args[@]}"
    else
        curl $silent_flag "${curl_args[@]}"
    fi
}

# Function to execute wget with debug/verbose support  
execute_wget() {
    local wget_args=("$@")
    local verbose_flag=""
    
    # Add verbose flags based on mode
    if [ "$DEBUG_MODE" = true ]; then
        verbose_flag="--debug --verbose"
        debug_log "Executing wget with debug mode"
        debug_log "Wget command: wget $verbose_flag ${wget_args[*]}"
    elif [ "$VERBOSE_MODE" = true ]; then
        verbose_flag="--verbose"
        log_message "INFO" "Executing wget command"
    else
        verbose_flag="--quiet"
    fi
    
    # Execute wget with appropriate flags
    wget $verbose_flag "${wget_args[@]}"
}

# Function to extract clean domain name for log filename
extract_domain_for_log() {
    local url="$1"
    if [ -z "$url" ]; then
        echo "unknown_domain"
        return
    fi
    
    # Extract domain and clean it for filename use
    local domain=$(echo "$url" | grep -oP '^https?://[^/]+' | sed 's|^https\?://||' | sed 's/^www\.//')
    # Replace invalid filename characters with underscores
    domain=$(echo "$domain" | sed 's/[^a-zA-Z0-9.-]/_/g')
    echo "$domain"
}

# Function to initialize log file for download session
init_log_file() {
    local download_type="$1"
    local domain="${2:-unknown_domain}"
    local timestamp=$(get_file_timestamp)
    
    # Clean domain name for filename
    local clean_domain=$(extract_domain_for_log "$domain")
    
    CURRENT_LOG_FILE="$LOGS_DIR/${clean_domain}_${download_type}_${timestamp}.log"
    
    # Create log file and write header
    cat > "$CURRENT_LOG_FILE" << EOF
# MP4 files downloader | Multifile downloader - Log File
# Download Type: $download_type
# Session Started: $(get_timestamp)
# Script Version: MP4 files downloader | Multifile downloader
# Output Directory: $OUTPUT_DIR
# Verbose Mode: $VERBOSE_MODE
# Debug Mode: $DEBUG_MODE
#================================================================================

EOF
    
    log_message "INFO" "Log session started - Type: $download_type"
    debug_log "Log file initialized: $CURRENT_LOG_FILE"
}

# Function to update log filename with domain when first URL is available
update_log_filename_with_domain() {
    local first_url="$1"
    local download_type="$2"
    
    if [ -z "$first_url" ] || [ -z "${CURRENT_LOG_FILE:-}" ]; then
        return
    fi
    
    local clean_domain=$(extract_domain_for_log "$first_url")
    local timestamp=$(get_file_timestamp)
    local new_log_file="$LOGS_DIR/${clean_domain}_${download_type}_${timestamp}.log"
    
    # If the new filename is different, rename the log file
    if [ "$new_log_file" != "$CURRENT_LOG_FILE" ] && [ -f "$CURRENT_LOG_FILE" ]; then
        # Move the log file to the new name
        mv "$CURRENT_LOG_FILE" "$new_log_file"
        CURRENT_LOG_FILE="$new_log_file"
        
        # Add domain info to log
        echo -e "\n# Domain detected: $clean_domain (from $first_url)" >> "$CURRENT_LOG_FILE"
        log_message "INFO" "Log file renamed with domain: $clean_domain"
    fi
}

# Function to complete logging session
complete_log_session() {
    if [ -n "${CURRENT_LOG_FILE:-}" ]; then
        log_message "INFO" "Log session completed"
        echo -e "\n# Log session completed at: $(get_timestamp)" >> "$CURRENT_LOG_FILE"
    fi
}

# Log management helper functions
list_log_files() {
    echo -e "\n${BOLD}${GREEN}📁 Log Files List${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${BLUE}📂 Log Directory: ${BOLD}$LOGS_DIR${NC}\n"
    
    if [ ! -d "$LOGS_DIR" ]; then
        echo -e "${RED}❌ Log directory does not exist: $LOGS_DIR${NC}"
        echo -e "${YELLOW}💡 The directory will be created when you first run a download.${NC}"
        return
    fi
    
    local log_count=$(find "$LOGS_DIR" -name "*.log" -type f 2>/dev/null | wc -l)
    if [ "$log_count" -eq 0 ]; then
        echo -e "${YELLOW}No log files found in the directory.${NC}"
        echo -e "${YELLOW}💡 Log files will be created when you run downloads.${NC}"
        return
    fi
    
    echo -e "${GREEN}📊 Found $log_count log files:${NC}\n"
    ls -lha "$LOGS_DIR"/*.log 2>/dev/null
}

view_log_file() {
    echo -e "\n${BOLD}${BLUE}📄 View Log File${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    local log_files=($(find "$LOGS_DIR" -name "*.log" -type f 2>/dev/null | sort))
    
    if [ ${#log_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}No log files found${NC}"
        return
    fi
    
    echo -e "${CYAN}Available log files:${NC}"
    for i in "${!log_files[@]}"; do
        local filename=$(basename "${log_files[$i]}")
        echo -e "${GREEN}$(($i + 1)))${NC} ${BOLD}$filename${NC}"
    done
    echo
    
    read -p "$(echo -e "${BOLD}Select log file (number or filename): ${NC}")" file_choice
    
    local selected_file=""
    
    # Check if input is a number
    if [[ "$file_choice" =~ ^[0-9]+$ ]] && [ "$file_choice" -ge 1 ] && [ "$file_choice" -le "${#log_files[@]}" ]; then
        selected_file="${log_files[$((file_choice - 1))]}"
    else
        # Check if input is a filename
        for log_file in "${log_files[@]}"; do
            local filename=$(basename "$log_file")
            if [ "$filename" = "$file_choice" ] || [ "$log_file" = "$file_choice" ]; then
                selected_file="$log_file"
                break
            fi
        done
    fi
    
    if [ -n "$selected_file" ] && [ -f "$selected_file" ]; then
        echo -e "\n${GREEN}📄 Viewing: ${BOLD}$(basename "$selected_file")${NC}\n"
        less "$selected_file"
    else
        echo -e "${RED}❌ Invalid choice. Please enter a number (1-${#log_files[@]}) or exact filename.${NC}"
    fi
}

search_log_files() {
    echo -e "\n${BOLD}${PURPLE}🔍 Search in Log Files${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    # Check if log directory exists and has log files
    if [ ! -d "$LOGS_DIR" ]; then
        echo -e "${RED}❌ Log directory does not exist: $LOGS_DIR${NC}"
        return
    fi
    
    local log_count=$(find "$LOGS_DIR" -name "*.log" -type f 2>/dev/null | wc -l)
    if [ "$log_count" -eq 0 ]; then
        echo -e "${YELLOW}No log files found in $LOGS_DIR${NC}"
        return
    fi
    
    echo -e "${BLUE}📂 Found $log_count log files to search${NC}\n"
    
    # Show available log files
    echo -e "${CYAN}Available log files:${NC}"
    local file_index=1
    declare -a log_files_array
    for log_file in "$LOGS_DIR"/*.log; do
        if [ -f "$log_file" ]; then
            log_files_array[$file_index]="$log_file"
            echo -e "${YELLOW}  [$file_index]${NC} $(basename "$log_file")"
            ((file_index++))
        fi
    done
    echo -e "${YELLOW}  [0]${NC} Search in ALL files"
    echo
    
    # Ask user to choose search scope
    read -p "$(echo -e "${BOLD}Select file to search (0 for all, 1-$((file_index-1)) for specific): ${NC}")" file_choice
    
    # Validate file choice
    if ! [[ "$file_choice" =~ ^[0-9]+$ ]] || [ "$file_choice" -lt 0 ] || [ "$file_choice" -ge $file_index ]; then
        echo -e "${RED}❌ Invalid file selection${NC}"
        return
    fi
    
    # Get search pattern
    read -p "$(echo -e "${BOLD}Enter search pattern (regex): ${NC}")" search_pattern
    
    if [ -z "$search_pattern" ]; then
        echo -e "${RED}❌ Search pattern cannot be empty${NC}"
        return
    fi
    
    echo -e "\n${GREEN}🔍 Searching for: ${BOLD}$search_pattern${NC}"
    
    if [ "$file_choice" -eq 0 ]; then
        echo -e "${CYAN}📁 Scope: ALL files${NC}\n"
        local found_matches=false
        
        for log_file in "$LOGS_DIR"/*.log; do
            if [ -f "$log_file" ]; then
                local matches=$(grep -n "$search_pattern" "$log_file" 2>/dev/null || true)
                if [ -n "$matches" ]; then
                    found_matches=true
                    echo -e "${BLUE}📄 ${BOLD}$(basename "$log_file"):${NC}"
                    echo "$matches" | while read line; do
                        echo -e "${GREEN}   $line${NC}"
                    done
                    echo
                fi
            fi
        done
        
        if [ "$found_matches" = false ]; then
            echo -e "${YELLOW}No matches found for pattern: $search_pattern${NC}"
        fi
    else
        # Search in specific file
        local selected_file="${log_files_array[$file_choice]}"
        echo -e "${CYAN}📄 Scope: $(basename "$selected_file")${NC}\n"
        
        local matches=$(grep -n "$search_pattern" "$selected_file" 2>/dev/null || true)
        if [ -n "$matches" ]; then
            echo -e "${BLUE}📄 ${BOLD}$(basename "$selected_file"):${NC}"
            echo "$matches" | while read line; do
                echo -e "${GREEN}   $line${NC}"
            done
            echo
        else
            echo -e "${YELLOW}No matches found for pattern: $search_pattern in $(basename "$selected_file")${NC}"
        fi
    fi
}

delete_log_file() {
    echo -e "\n${BOLD}${RED}🗑️  Delete Log File${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    local log_files=($(find "$LOGS_DIR" -name "*.log" -type f 2>/dev/null | sort))
    
    if [ ${#log_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}No log files found${NC}"
        return
    fi
    
    echo -e "${CYAN}Available log files:${NC}"
    for i in "${!log_files[@]}"; do
        local filename=$(basename "${log_files[$i]}")
        echo -e "${GREEN}$(($i + 1)))${NC} ${BOLD}$filename${NC}"
    done
    echo
    
    read -p "$(echo -e "${BOLD}Select log file to delete (number or filename): ${NC}")" file_choice
    
    local selected_file=""
    
    # Check if input is a number
    if [[ "$file_choice" =~ ^[0-9]+$ ]] && [ "$file_choice" -ge 1 ] && [ "$file_choice" -le "${#log_files[@]}" ]; then
        selected_file="${log_files[$((file_choice - 1))]}"
    else
        # Check if input is a filename
        for log_file in "${log_files[@]}"; do
            local filename=$(basename "$log_file")
            if [ "$filename" = "$file_choice" ] || [ "$log_file" = "$file_choice" ]; then
                selected_file="$log_file"
                break
            fi
        done
    fi
    
    if [ -n "$selected_file" ] && [ -f "$selected_file" ]; then
        local filename=$(basename "$selected_file")
        
        echo -e "\n${RED}⚠️  WARNING: This will permanently delete the log file!${NC}"
        read -p "$(echo -e "${BOLD}Are you sure you want to delete ${filename}? (y/N): ${NC}")" confirm
        
        case "$confirm" in
            [Yy]|[Yy][Ee][Ss])
                if rm "$selected_file"; then
                    echo -e "\n${GREEN}✓ Log file deleted: $filename${NC}"
                else
                    echo -e "\n${RED}❌ Failed to delete log file${NC}"
                fi
                ;;
            *)
                echo -e "\n${YELLOW}Deletion cancelled${NC}"
                ;;
        esac
    else
        echo -e "${RED}❌ Invalid choice. Please enter a number (1-${#log_files[@]}) or exact filename.${NC}"
    fi
}

delete_all_log_files() {
    echo -e "\n${BOLD}${RED}🗑️  Delete All Log Files${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    local log_count=$(find "$LOGS_DIR" -name "*.log" -type f 2>/dev/null | wc -l)
    
    if [ "$log_count" -eq 0 ]; then
        echo -e "${YELLOW}No log files found${NC}"
        return
    fi
    
    echo -e "${RED}⚠️  WARNING: This will permanently delete ALL $log_count log files!${NC}"
    echo -e "${YELLOW}This action cannot be undone.${NC}\n"
    
    read -p "$(echo -e "${BOLD}Are you sure you want to delete ALL log files? (y/N): ${NC}")" confirm
    
    case "$confirm" in
        [Yy]|[Yy][Ee][Ss])
            if rm "$LOGS_DIR"/*.log 2>/dev/null; then
                echo -e "\n${GREEN}✓ All log files deleted${NC}"
            else
                echo -e "\n${YELLOW}No log files to delete or operation failed${NC}"
            fi
            ;;
        *)
            echo -e "\n${YELLOW}Deletion cancelled${NC}"
            ;;
    esac
}

# Function for log files management menu
log_files_management_menu() {
    while true; do
        echo -e "\n${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${CYAN}║                         LOG FILES MANAGEMENT                          ║${NC}"
        echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════════╝${NC}\n"
        
        echo -e "${BLUE}📂 Log Directory: ${BOLD}$LOGS_DIR${NC}\n"
        
        echo -e "${BOLD}${CYAN}Choose an option:${NC}\n"
        echo -e "${GREEN}1)${NC} ${BOLD}List all log files${NC}"
        echo -e "${GREEN}   ${NC}→ Show all log files with details\n"
        
        echo -e "${YELLOW}2)${NC} ${BOLD}View a log file${NC}"
        echo -e "${YELLOW}   ${NC}→ View contents of a specific log file\n"
        
        echo -e "${BLUE}3)${NC} ${BOLD}Search in log files${NC}"
        echo -e "${BLUE}   ${NC}→ Find text pattern in log files\n"
        
        echo -e "${PURPLE}4)${NC} ${BOLD}Delete a log file${NC}"
        echo -e "${PURPLE}   ${NC}→ Remove a specific log file\n"
        
        echo -e "${RED}5)${NC} ${BOLD}Delete all log files${NC}"
        echo -e "${RED}   ${NC}→ Remove all log files\n"
        
        echo -e "${CYAN}6)${NC} ${BOLD}Back to main menu${NC}\n"
        
        read -p "$(echo -e "${BOLD}Enter your choice (1-6): ${NC}")" logs_choice
        
        case $logs_choice in
            1)
                list_log_files
                ;;
            2)
                view_log_file
                ;;
            3)
                search_log_files
                ;;
            4)
                delete_log_file
                ;;
            5)
                delete_all_log_files
                ;;
            6)
                break
                ;;
            *)
                echo -e "\n${RED}❌ Invalid choice. Please enter 1, 2, 3, 4, 5, or 6.${NC}"
                ;;
        esac
        
        if [ "$logs_choice" != "6" ]; then
            echo -e "\n${PURPLE}Press Enter to continue...${NC}"
            read
        fi
    done
}

# Function for verbose and debug settings menu
verbose_debug_settings_menu() {
    while true; do
        echo -e "\n${BOLD}${PURPLE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${PURPLE}║                      VERBOSE & DEBUG SETTINGS                         ║${NC}"
        echo -e "${BOLD}${PURPLE}╚════════════════════════════════════════════════════════════════════════╝${NC}\n"
        
        # Display current status
        local verbose_status="OFF ${RED}●${NC}"
        local debug_status="OFF ${RED}●${NC}"
        
        if [ "$VERBOSE_MODE" = true ]; then
            verbose_status="ON ${GREEN}●${NC}"
        fi
        
        if [ "$DEBUG_MODE" = true ]; then
            debug_status="ON ${GREEN}●${NC}"
        fi
        
        echo -e "${BOLD}${CYAN}Current Settings:${NC}"
        echo -e "${BLUE}Verbose Mode: ${BOLD}$verbose_status${NC}"
        echo -e "${BLUE}Debug Mode:   ${BOLD}$debug_status${NC}\n"
        
        echo -e "${BOLD}${CYAN}Choose an option:${NC}\n"
        echo -e "${GREEN}1)${NC} ${BOLD}Toggle Verbose Mode${NC}"
        echo -e "${GREEN}   ${NC}→ Show/hide timestamps and detailed messages\n"
        
        echo -e "${YELLOW}2)${NC} ${BOLD}Toggle Debug Mode${NC}"
        echo -e "${YELLOW}   ${NC}→ Show/hide debug information\n"
        
        echo -e "${BLUE}3)${NC} ${BOLD}Enable Both${NC}"
        echo -e "${BLUE}   ${NC}→ Turn on both verbose and debug modes\n"
        
        echo -e "${PURPLE}4)${NC} ${BOLD}Disable Both${NC}"
        echo -e "${PURPLE}   ${NC}→ Turn off both modes\n"
        
        echo -e "${CYAN}5)${NC} ${BOLD}Back to main menu${NC}\n"
        
        read -p "$(echo -e "${BOLD}Enter your choice (1-5): ${NC}")" settings_choice
        
        case $settings_choice in
            1)
                if [ "$VERBOSE_MODE" = true ]; then
                    VERBOSE_MODE=false
                    echo -e "\n${YELLOW}✓ Verbose Mode disabled${NC}"
                else
                    VERBOSE_MODE=true
                    echo -e "\n${GREEN}✓ Verbose Mode enabled${NC}"
                fi
                ;;
            2)
                if [ "$DEBUG_MODE" = true ]; then
                    DEBUG_MODE=false
                    echo -e "\n${YELLOW}✓ Debug Mode disabled${NC}"
                else
                    DEBUG_MODE=true
                    echo -e "\n${GREEN}✓ Debug Mode enabled${NC}"
                fi
                ;;
            3)
                VERBOSE_MODE=true
                DEBUG_MODE=true
                echo -e "\n${GREEN}✓ Both Verbose and Debug modes enabled${NC}"
                ;;
            4)
                VERBOSE_MODE=false
                DEBUG_MODE=false
                echo -e "\n${YELLOW}✓ Both Verbose and Debug modes disabled${NC}"
                ;;
            5)
                break
                ;;
            *)
                echo -e "\n${RED}❌ Invalid choice. Please enter 1, 2, 3, 4, or 5.${NC}"
                ;;
        esac
        
        if [ "$settings_choice" != "5" ]; then
            echo -e "\n${PURPLE}Press Enter to continue...${NC}"
            read
        fi
    done
}

main_menu() {
	#================================================================================
	# HEADER SECTION
	#================================================================================

	echo -e "\n${BOLD}${PURPLE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
	echo -e "${BOLD}${PURPLE}║                MP4 files downloader | Multifile downloader             ║${NC}"
	echo -e "${BOLD}${PURPLE}╚════════════════════════════════════════════════════════════════════════╝${NC}"

	echo -e "\n${CYAN}📁 Output directory: ${BOLD}$OUTPUT_DIR${NC}\n"

	# Create output directory if it doesn't exist
	mkdir -p "$OUTPUT_DIR"

#================================================================================
# UTILITY FUNCTIONS
#================================================================================

# Function to validate URL
validate_url() {
    local url="$1"
    if [[ "$url" =~ ^https?://[^[:space:]]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to convert relative URLs to absolute URLs
make_absolute_url() {
    local base_url="$1"
    local relative_url="$2"
    
    # If already absolute, return as-is
    if [[ "$relative_url" =~ ^https?:// ]]; then
        echo "$relative_url"
        return
    fi
    
    # Extract base domain and path
    local protocol=$(echo "$base_url" | grep -oP '^https?://')
    local domain=$(echo "$base_url" | grep -oP '^https?://[^/]+')
    local path=$(echo "$base_url" | grep -oP '^https?://[^/]+\K/.*' | sed 's/[^/]*$//')
    
    # Handle different relative URL formats
    if [[ "$relative_url" =~ ^// ]]; then
        # Protocol-relative URL
        echo "${protocol}${relative_url#//}"
    elif [[ "$relative_url" =~ ^/ ]]; then
        # Root-relative URL
        echo "${domain}${relative_url}"
    else
        # Path-relative URL
        echo "${domain}${path}${relative_url}"
    fi
}

# Function to extract domain from URL
extract_domain() {
    local url="$1"
    echo "$url" | grep -oP '^https?://[^/]+' | sed 's|^https\?://||'
}

#================================================================================
# CREDENTIALS MANAGEMENT FUNCTIONS
#================================================================================

# Function to create credentials file with header if it doesn't exist
create_credentials_file() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        cat > "$CREDENTIALS_FILE" << 'EOF'
# MP4 files downloader | Multifile downloader - Credentials File
# Format: domain|username|password|description
# Example: example.com|myuser|mypass|My page Account
# Lines starting with # are comments and will be ignored
EOF
        echo -e "${GREEN}✓ Created credentials file: $CREDENTIALS_FILE${NC}"
    fi
}

# Function to list credentials
list_credentials() {
    echo -e "${BOLD}${CYAN}📋 Credentials File Management${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    if [ -f "$CREDENTIALS_FILE" ]; then
        echo -e "${GREEN}📁 File details:${NC}"
        ls -lha "$CREDENTIALS_FILE"
        echo
        
        echo -e "${BLUE}📄 File contents:${NC}"
        if [ -s "$CREDENTIALS_FILE" ]; then
            cat -n "$CREDENTIALS_FILE"
        else
            echo -e "${YELLOW}   (File is empty)${NC}"
        fi
    else
        echo -e "${RED}❌ Credentials file not found: $CREDENTIALS_FILE${NC}"
        echo -e "${YELLOW}💡 Use 'Save new credentials' option to create it.${NC}"
    fi
}

# Function to edit credentials file
edit_credentials() {
    echo -e "${BOLD}${YELLOW}✏️  Editing Credentials File${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    create_credentials_file
    
    # Try to find a suitable editor
    if command -v nano >/dev/null 2>&1; then
        EDITOR="nano"
    elif command -v vim >/dev/null 2>&1; then
        EDITOR="vim"
    elif command -v vi >/dev/null 2>&1; then
        EDITOR="vi"
    else
        echo -e "${RED}❌ No suitable text editor found (nano, vim, vi)${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Opening file with $EDITOR...${NC}"
    echo -e "${YELLOW}Format: domain|username|password|description${NC}\n"
    
    "$EDITOR" "$CREDENTIALS_FILE"
    
    echo -e "\n${GREEN}✓ File editing completed${NC}"
}

# Function to save new credentials
save_credentials() {
    echo -e "${BOLD}${GREEN}💾 Save New Credentials${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    create_credentials_file
    
    read -p "$(echo -e "${BOLD}Enter domain (e.g., example.com): ${NC}")" domain
    if [ -z "$domain" ]; then
        echo -e "${RED}❌ Domain cannot be empty${NC}"
        return 1
    fi
    
    read -p "$(echo -e "${BOLD}Enter username: ${NC}")" username
    if [ -z "$username" ]; then
        echo -e "${RED}❌ Username cannot be empty${NC}"
        return 1
    fi
    
    read -s -p "$(echo -e "${BOLD}Enter password: ${NC}")" password
    echo
    if [ -z "$password" ]; then
        echo -e "${RED}❌ Password cannot be empty${NC}"
        return 1
    fi
    
    read -p "$(echo -e "${BOLD}Enter description (optional): ${NC}")" description
    description="${description:-Account for $domain}"
    
    # Check if domain already exists
    if grep -q "^$domain|" "$CREDENTIALS_FILE" 2>/dev/null; then
        echo -e "\n${YELLOW}⚠️  Credentials for domain '$domain' already exist.${NC}"
        read -p "$(echo -e "${PURPLE}Do you want to update them? (y/n): ${NC}")" update_choice
        case "$update_choice" in
            [Yy]|[Yy][Ee][Ss])
                # Remove existing entry
                grep -v "^$domain|" "$CREDENTIALS_FILE" > "$CREDENTIALS_FILE.tmp" && mv "$CREDENTIALS_FILE.tmp" "$CREDENTIALS_FILE"
                echo -e "${BLUE}Updated existing credentials for $domain${NC}"
                ;;
            *)
                echo -e "${YELLOW}Cancelled - keeping existing credentials${NC}"
                return 0
                ;;
        esac
    fi
    
    # Add new credentials
    echo "$domain|$username|$password|$description" >> "$CREDENTIALS_FILE"
    echo -e "${GREEN}✓ Credentials saved for domain: ${BOLD}$domain${NC}"
}

# Function to load credentials from file for a domain
load_credentials_for_domain() {
    local domain="$1"
    local found_line=""
    
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        return 1
    fi
    
    # Search for domain in credentials file
    found_line=$(grep "^$domain|" "$CREDENTIALS_FILE" 2>/dev/null | head -1)
    
    if [ -n "$found_line" ]; then
        # Parse the line: domain|username|password|description
        USERNAME=$(echo "$found_line" | cut -d'|' -f2)
        PASSWORD=$(echo "$found_line" | cut -d'|' -f3)
        DESCRIPTION=$(echo "$found_line" | cut -d'|' -f4)
        
        if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
            echo -e "${GREEN}✓ Found credentials for domain: ${BOLD}$domain${NC}"
            echo -e "${BLUE}   Description: $DESCRIPTION${NC}"
            return 0
        fi
    fi
    
    return 1
}

# Function for credentials management submenu
credentials_management_menu() {
    while true; do
        echo -e "\n${BOLD}${PURPLE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${PURPLE}║                      CREDENTIALS MANAGEMENT                           ║${NC}"
        echo -e "${BOLD}${PURPLE}╚════════════════════════════════════════════════════════════════════════╝${NC}\n"
        
        echo -e "${BOLD}${CYAN}Choose an option:${NC}\n"
        echo -e "${GREEN}1)${NC} ${BOLD}List credentials file${NC}"
        echo -e "${GREEN}   ${NC}→ Show file details and contents\n"
        
        echo -e "${YELLOW}2)${NC} ${BOLD}Edit credentials file${NC}"
        echo -e "${YELLOW}   ${NC}→ Open file in text editor\n"
        
        echo -e "${BLUE}3)${NC} ${BOLD}Save new credentials${NC}"
        echo -e "${BLUE}   ${NC}→ Add credentials for a domain\n"
        
        echo -e "${RED}4)${NC} ${BOLD}Back to main menu${NC}\n"
        
        read -p "$(echo -e "${BOLD}Enter your choice (1-4): ${NC}")" creds_choice
        
        case $creds_choice in
            1)
                list_credentials
                echo -e "\n${PURPLE}Press Enter to continue...${NC}"
                read
                ;;
            2)
                edit_credentials
                echo -e "\n${PURPLE}Press Enter to continue...${NC}"
                read
                ;;
            3)
                save_credentials
                echo -e "\n${PURPLE}Press Enter to continue...${NC}"
                read
                ;;
            4)
                break
                ;;
            *)
                echo -e "\n${RED}❌ Invalid choice. Please enter 1, 2, 3, or 4.${NC}"
                ;;
        esac
    done
}

#================================================================================
# INTERACTIVE MENU
#================================================================================

# Function to display menu
show_menu() {
    echo -e "\n${BOLD}${PURPLE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${PURPLE}║                           MP4 DOWNLOADER MENU                          ║${NC}"
    echo -e "${BOLD}${PURPLE}╚════════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Display current settings status
    local verbose_status="${RED}●${NC}"  # Red circle for OFF
    local debug_status="${RED}●${NC}"    # Red circle for OFF
    
    if [ "$VERBOSE_MODE" = true ]; then
        verbose_status="${GREEN}●${NC}"  # Green circle for ON
    fi
    
    if [ "$DEBUG_MODE" = true ]; then
        debug_status="${GREEN}●${NC}"   # Green circle for ON
    fi
    
    echo -e "${BOLD}${CYAN}Status:${NC} Verbose $verbose_status | Debug $debug_status | Output: ${BOLD}$OUTPUT_DIR${NC}\n"
    
    echo -e "${BOLD}${CYAN}📥 Download Options:${NC}\n"
    echo -e "${GREEN}1)${NC} ${BOLD}Download WITHOUT Authentication${NC}"
    echo -e "${GREEN}   ${NC}→ For public pages that don't require login\n"
    
    echo -e "${YELLOW}2)${NC} ${BOLD}Download WITH Authentication${NC}"
    echo -e "${YELLOW}   ${NC}→ For protected pages requiring login\n"
    
    echo -e "${BLUE}3)${NC} ${BOLD}Multi-File Downloader${NC}"
    echo -e "${BLUE}   ${NC}→ Analyze pages for all file types\n"
    
    echo -e "${CYAN}4)${NC} ${BOLD}Analyze Existing HTML Files${NC}"
    echo -e "${CYAN}   ${NC}→ Scan downloaded HTML files in output directory\n"
    
    echo -e "${BOLD}${PURPLE}⚙️  Management Options:${NC}\n"
    echo -e "${PURPLE}5)${NC} ${BOLD}Credentials Management${NC}"
    echo -e "${PURPLE}   ${NC}→ Manage saved credentials file\n"
    
    echo -e "${BOLD}6)${NC} ${BOLD}Log Files Management${NC}"
    echo -e "${BOLD}   ${NC}→ View, search, and manage download logs\n"
    
    echo -e "${BOLD}7)${NC} ${BOLD}Verbose & Debug Settings${NC}"
    echo -e "${BOLD}   ${NC}→ Toggle verbose and debug modes\n"
    
    echo -e "${RED}8)${NC} ${BOLD}Exit${NC}\n"
}

# Function for authentication submenu
authentication_submenu() {
    echo -e "\n${BOLD}${YELLOW}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${YELLOW}║                       AUTHENTICATION OPTIONS                          ║${NC}"
    echo -e "${BOLD}${YELLOW}╚════════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BOLD}${CYAN}Choose authentication method:${NC}\n"
    echo -e "${GREEN}1)${NC} ${BOLD}Manually enter credentials${NC}"
    echo -e "${GREEN}   ${NC}→ Enter username/password for each domain\n"
    
    echo -e "${BLUE}2)${NC} ${BOLD}Use saved credentials file${NC}"
    echo -e "${BLUE}   ${NC}→ Load credentials from saved file"
    echo -e "${BLUE}   ${NC}→ File: $CREDENTIALS_FILE\n"
    
    echo -e "${RED}3)${NC} ${BOLD}Back to main menu${NC}\n"
    
    while true; do
        read -p "$(echo -e "${BOLD}Enter your choice (1-3): ${NC}")" auth_choice
        
        case $auth_choice in
            1)
                init_log_file "manual_auth"
                log_message "INFO" "Selected: Manual credential entry"
                # Clear any existing temp credentials to force manual entry
                rm -f /tmp/creds_*
                USE_AUTH=true
                MANUAL_CREDS=true
                collect_urls_with_auth
                return 0
                ;;
            2)
                init_log_file "saved_auth"
                log_message "INFO" "Selected: Use saved credentials file"
                if [ ! -f "$CREDENTIALS_FILE" ]; then
                    echo -e "${RED}❌ Credentials file not found: $CREDENTIALS_FILE${NC}"
                    echo -e "${YELLOW}💡 Please create it first using 'Credentials Management' option.${NC}"
                    echo -e "\n${PURPLE}Press Enter to continue...${NC}"
                    read
                    return 1
                fi
                USE_AUTH=true
                MANUAL_CREDS=false
                collect_urls_with_auth
                return 0
                ;;
            3)
                return 1
                ;;
            *)
                echo -e "${RED}❌ Invalid choice. Please enter 1, 2, or 3.${NC}"
                ;;
        esac
    done
}

# Function for multi-file downloader submenu
multifile_authentication_submenu() {
    echo -e "\n${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                    MULTI-FILE AUTHENTICATION OPTIONS                  ║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BOLD}${CYAN}Choose authentication method:${NC}\n"
    echo -e "${GREEN}1)${NC} ${BOLD}No Authentication${NC}"
    echo -e "${GREEN}   ${NC}→ For public pages that don't require login\n"
    
    echo -e "${YELLOW}2)${NC} ${BOLD}Manually enter credentials${NC}"
    echo -e "${YELLOW}   ${NC}→ Enter username/password for each domain\n"
    
    echo -e "${BLUE}3)${NC} ${BOLD}Use saved credentials file${NC}"
    echo -e "${BLUE}   ${NC}→ Load credentials from saved file"
    echo -e "${BLUE}   ${NC}→ File: $CREDENTIALS_FILE\n"
    
    echo -e "${RED}4)${NC} ${BOLD}Back to main menu${NC}\n"
    
    while true; do
        read -p "$(echo -e "${BOLD}Enter your choice (1-4): ${NC}")" multi_auth_choice
        
        case $multi_auth_choice in
            1)
                init_log_file "multifile_no_auth"
                log_message "INFO" "Selected: Multi-File No Authentication"
                USE_AUTH=false
                MANUAL_CREDS=false
                collect_urls_multifile
                return 0
                ;;
            2)
                init_log_file "multifile_manual_auth"
                log_message "INFO" "Selected: Multi-File Manual credential entry"
                # Clear any existing temp credentials to force manual entry
                rm -f /tmp/creds_*
                USE_AUTH=true
                MANUAL_CREDS=true
                collect_urls_multifile
                return 0
                ;;
            3)
                init_log_file "multifile_saved_auth"
                log_message "INFO" "Selected: Multi-File Use saved credentials file"
                if [ ! -f "$CREDENTIALS_FILE" ]; then
                    echo -e "${RED}❌ Credentials file not found: $CREDENTIALS_FILE${NC}"
                    echo -e "${YELLOW}💡 Please create it first using 'Credentials Management' option.${NC}"
                    echo -e "\n${PURPLE}Press Enter to continue...${NC}"
                    read
                    return 1
                fi
                USE_AUTH=true
                MANUAL_CREDS=false
                collect_urls_multifile
                return 0
                ;;
            4)
                return 1
                ;;
            *)
                echo -e "${RED}❌ Invalid choice. Please enter 1, 2, 3, or 4.${NC}"
                ;;
        esac
    done
}

# Function to analyze page for all file types
analyze_page_file_types() {
    local html_file="$1"
    local page_url="$2"
    
    echo -e "\n${BOLD}${CYAN}🔍 Analyzing Page for File Types${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
    
    # Comprehensive file extensions to search for
    declare -A file_extensions
    file_extensions=(
        ["Video"]="mp4 avi mov wmv flv mkv webm m4v 3gp mpg mpeg m2v m4p m4v asf asx divx f4v h264 h265 hevc m1v m2p m2t m2ts mts ogv qt rm rmvb swf ts vob vp8 vp9 webm xvid yuv 3g2 3gp2 amv drc dv dvr-ms f4p f4a f4b gif m4s mjpeg mjpg mng moov movie mp2 mp2v mp4v mpe mpg2 mpg4 mpv mpv2 mxf nsv ogg ogm ogx rec roq srt svi tod tp trp vfw vro y4m"
        ["Audio"]="mp3 wav flac aac ogg wma m4a opus aiff au ra ram aac ac3 amr ape au caf dts eac3 gsm it m3u m3u8 mid midi mka mp2 mpa mpc oga opus pls ra realaudio s3m spx tta voc vqf w64 wv xm mod 669 abc amf ams dbm digi dmf dsm far gdm imf it med mod mt2 mtm nst okt psm ptm s3m stm ult umx wow xm"
        ["Image"]="jpg jpeg png gif bmp tiff webp svg ico psd ai eps ps pdf tga pcx ppm pgm pbm xbm xpm dib rle sgi rgb rgba bgra tif emf wmf cgm dxf dwg pct pic pict hdr exr cr2 nef arw dng orf pef srw x3f raf rw2 rwl iiq 3fr fff dcr k25 kdc erf mef mos mrw nrw orf pef ptx r3d raf raw rw2 srw x3f heic heif avif jxl jp2 j2k jpf jpx jpm mj2 jxr hdp wdp"
        ["Document"]="pdf doc docx xls xlsx ppt pptx txt rtf odt ods odp odg odf odb pages numbers key epub mobi azw azw3 fb2 lit pdb prc djvu cbr cbz ps eps tex latex md markdown rst adoc asciidoc org wpd wps works sxw sxc sxi sxd sxg stw stc sti std stg xml html htm xhtml mhtml mht csv tsv"
        ["Archive"]="zip rar 7z tar gz bz2 xz lzma lz4 zst arj cab deb rpm dmg iso img bin cue nrg mdf mds ccd sub idx vcd ace alz apk jar war ear lha lzh z taz tbz tbz2 tgz tlz txz tzo ace sit sitx sea hqx uu uue b64 mime binhex arc zoo pak lbr pma sfx exe"
        ["Executable"]="exe msi deb rpm dmg pkg mpkg app run bin com scr bat cmd ps1 vbs js jar apk ipa crx xpi addon vsix nupkg gem whl egg pyz pex snap flatpak appimage"
    )
    
    declare -A found_files
    declare -A extension_counts
    
    # Search for each extension
    for category in "${!file_extensions[@]}"; do
        for ext in ${file_extensions[$category]}; do
            # Find files with this extension in href attributes
            local files_href=$(grep -oE 'href="[^"]*\.'$ext'[^"]*"' "$html_file" | sed 's/href="//g' | sed 's/"$//g' 2>/dev/null || true)
            local files_src=$(grep -oE 'src="[^"]*\.'$ext'[^"]*"' "$html_file" | sed 's/src="//g' | sed 's/"$//g' 2>/dev/null || true)
            local files_data=$(grep -oE 'data-src="[^"]*\.'$ext'[^"]*"' "$html_file" | sed 's/data-src="//g' | sed 's/"$//g' 2>/dev/null || true)
            
            # Combine all found files
            local all_files="$files_href"$'\n'"$files_src"$'\n'"$files_data"
            
            if [ -n "$all_files" ]; then
                local unique_files=$(echo "$all_files" | grep -E "\.$ext" | sort -u | grep -v '^$' || true)
                if [ -n "$unique_files" ]; then
                    local count=$(echo "$unique_files" | wc -l)
                    extension_counts[$ext]=$count
                    found_files[$ext]="$unique_files"
                fi
            fi
        done
    done
    
    # Display results by category
    local total_files=0
    echo -e "${BLUE}📄 Page: ${NC}$page_url"
    echo
    
    for category in "${!file_extensions[@]}"; do
        local category_found=false
        local category_total=0
        
        for ext in ${file_extensions[$category]}; do
            if [ -n "${extension_counts[$ext]:-}" ]; then
                if [ "$category_found" = false ]; then
                    echo -e "${BOLD}${YELLOW}📁 $category Files:${NC}"
                    category_found=true
                fi
                echo -e "${GREEN}   .$ext: ${BOLD}${extension_counts[$ext]}${NC}${GREEN} files${NC}"
                category_total=$((category_total + extension_counts[$ext]))
            fi
        done
        
        if [ "$category_found" = true ]; then
            total_files=$((total_files + category_total))
            echo
        fi
    done
    
    if [ $total_files -eq 0 ]; then
        echo -e "${RED}❌ No downloadable files found on this page${NC}"
        return 1
    else
        echo -e "${BOLD}${GREEN}📊 Total downloadable files found: $total_files${NC}\n"
        return 0
    fi
}

# Function to collect URLs for multi-file download
collect_urls_multifile() {
    if [ "$USE_AUTH" = "true" ]; then
        if [ "$MANUAL_CREDS" = "true" ]; then
            echo -e "${BOLD}${BLUE}🌐 Multi-File URL Collection (Manual Authentication)${NC}\n"
        else
            echo -e "${BOLD}${BLUE}🌐 Multi-File URL Collection (Saved Credentials)${NC}\n"
        fi
    else
        echo -e "${BOLD}${BLUE}🌐 Multi-File URL Collection (No Authentication)${NC}\n"
    fi
    
    echo -e "${YELLOW}Enter HTML page URLs one at a time for file analysis.${NC}\n"

    page_count=0

    while true; do
        echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
        read -p "$(echo -e "${BOLD}Enter HTML page URL: ${NC}")" url
        
        # Skip empty input
        if [ -z "$url" ]; then
            echo -e "\n${RED}❌ Empty URL provided. Please enter a valid URL.${NC}"
            continue
        fi
        
        # Validate URL format
        if ! validate_url "$url"; then
            echo -e "\n${RED}❌ Invalid URL format. Please enter a valid HTTP/HTTPS URL.${NC}"
            continue
        fi
        
        # Handle authentication if needed
        if [ "$USE_AUTH" = "true" ]; then
            # Extract domain from URL
            domain=$(extract_domain "$url")
            echo -e "\n${BLUE}🌍 Domain: ${BOLD}$domain${NC}"
            
            # Check if we already have credentials for this domain in temp storage
            cred_file="/tmp/creds_${domain//[^a-zA-Z0-9]/_}"
            if [ -f "$cred_file" ]; then
                echo -e "${GREEN}✓ Using existing credentials for domain: ${BOLD}$domain${NC}"
                username=$(head -1 "$cred_file")
                password=$(tail -1 "$cred_file")
            else
                if [ "$MANUAL_CREDS" = "true" ]; then
                    # Manual mode: Always prompt for credentials
                    echo -e "\n${YELLOW}🔐 Enter credentials for domain: ${BOLD}$domain${NC}"
                    read -p "$(echo -e "${BOLD}Username: ${NC}")" username
                    read -s -p "$(echo -e "${BOLD}Password: ${NC}")" password
                    echo
                    
                    # Validate credentials
                    if [ -z "$username" ] || [ -z "$password" ]; then
                        echo -e "${RED}❌ Username and password cannot be empty${NC}"
                        continue
                    fi
                    
                    # Save credentials for this domain in temp file
                    echo "$username" > "$cred_file"
                    echo "$password" >> "$cred_file"
                    echo -e "\n${GREEN}✓ Credentials saved for domain: ${BOLD}$domain${NC}"
                else
                    # Saved credentials mode: Try to load from saved file first
                    if load_credentials_for_domain "$domain"; then
                        username="$USERNAME"
                        password="$PASSWORD"
                        
                        # Save to temp file for reuse
                        echo "$username" > "$cred_file"
                        echo "$password" >> "$cred_file"
                    else
                        # Fall back to manual entry if not found in saved file
                        echo -e "${YELLOW}⚠️  No saved credentials found for domain: ${BOLD}$domain${NC}"
                        echo -e "${BLUE}💡 You can save credentials using 'Credentials Management' option.${NC}"
                        
                        echo -e "\n${YELLOW}🔐 Enter credentials for domain: ${BOLD}$domain${NC}"
                        read -p "$(echo -e "${BOLD}Username: ${NC}")" username
                        read -s -p "$(echo -e "${BOLD}Password: ${NC}")" password
                        echo
                        
                        # Validate credentials
                        if [ -z "$username" ] || [ -z "$password" ]; then
                            echo -e "${RED}❌ Username and password cannot be empty${NC}"
                            continue
                        fi
                        
                        # Save credentials for this domain in temp file
                        echo "$username" > "$cred_file"
                        echo "$password" >> "$cred_file"
                        echo -e "\n${GREEN}✓ Credentials saved for domain: ${BOLD}$domain${NC}"
                    fi
                fi
            fi
            
            # Add URL and credentials to list
            echo "$url|$username|$password" >> "$URLS_FILE"
        else
            # Add URL to list (no credentials needed)
            echo "$url||" >> "$URLS_FILE"
        fi
        
        # Update log filename with domain from first URL
        if [ "$page_count" -eq 0 ]; then
            # Determine the auth type for multifile
            local auth_type="multifile_no_auth"
            if [ "$USE_AUTH" = "true" ]; then
                if [ "$MANUAL_CREDS" = "true" ]; then
                    auth_type="multifile_manual_auth"
                else
                    auth_type="multifile_saved_auth"
                fi
            fi
            update_log_filename_with_domain "$url" "$auth_type"
        fi
        
        # Safety check for arithmetic
        if [[ "$page_count" =~ ^[0-9]+$ ]]; then
            page_count=$((page_count + 1))
        else
            page_count=1
        fi
        echo -e "${GREEN}✓ Added page ${BOLD}$page_count${NC}${GREEN}: $url${NC}"
        
        # Ask if user wants to add more pages
        echo
        while true; do
            read -p "$(echo -e "${PURPLE}Do you want to add another page? ${BOLD}(y/n): ${NC}")" add_more
            case "$add_more" in
                [Yy]|[Yy][Ee][Ss])
                    break
                    ;;
                [Nn]|[Nn][Oo])
                    break 2
                    ;;
                *)
                    echo -e "${RED}Please answer y (yes) or n (no)${NC}"
                    ;;
            esac
        done
    done
}

# Function to collect URLs without authentication
collect_urls_no_auth() {
    echo -e "${BOLD}${BLUE}🌐 URL Collection Phase (No Authentication)${NC}\n"
    echo -e "${YELLOW}Enter HTML page URLs one at a time.${NC}\n"

    page_count=0

    while true; do
        echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
        read -p "$(echo -e "${BOLD}Enter HTML page URL: ${NC}")" url
        
        # Skip empty input
        if [ -z "$url" ]; then
            echo -e "\n${RED}❌ Empty URL provided. Please enter a valid URL.${NC}"
            continue
        fi
        
        # Validate URL format
        if ! validate_url "$url"; then
            echo -e "\n${RED}❌ Invalid URL format. Please enter a valid HTTP/HTTPS URL.${NC}"
            continue
        fi
        
        # Add URL to list (no credentials needed)
        echo "$url||" >> "$URLS_FILE"
        
        # Update log filename with domain from first URL
        if [ "$page_count" -eq 0 ]; then
            update_log_filename_with_domain "$url" "no_auth"
        fi
        
        # Safety check for arithmetic
        if [[ "$page_count" =~ ^[0-9]+$ ]]; then
            page_count=$((page_count + 1))
        else
            page_count=1
        fi
        echo -e "${GREEN}✓ Added page ${BOLD}$page_count${NC}${GREEN}: $url${NC}"
        
        # Ask if user wants to add more pages
        echo
        while true; do
            read -p "$(echo -e "${PURPLE}Do you want to add another page? ${BOLD}(y/n): ${NC}")" add_more
            case "$add_more" in
                [Yy]|[Yy][Ee][Ss])
                    break
                    ;;
                [Nn]|[Nn][Oo])
                    break 2
                    ;;
                *)
                    echo -e "${RED}Please answer y (yes) or n (no)${NC}"
                    ;;
            esac
        done
    done
}

# Function to collect URLs with authentication
collect_urls_with_auth() {
    if [ "$MANUAL_CREDS" = "true" ]; then
        echo -e "${BOLD}${BLUE}🌐 URL Collection Phase (Manual Authentication)${NC}\n"
        echo -e "${YELLOW}Enter HTML page URLs one at a time. For pages on the same domain,${NC}"
        echo -e "${YELLOW}credentials will be reused automatically.${NC}\n"
    else
        echo -e "${BOLD}${BLUE}🌐 URL Collection Phase (Saved Credentials)${NC}\n"
        echo -e "${YELLOW}Enter HTML page URLs one at a time. Credentials will be loaded${NC}"
        echo -e "${YELLOW}from the saved file when available.${NC}\n"
    fi

    page_count=0

    # Arrays to store domain credentials (simulated with files)
    declare -A domain_credentials

    while true; do
        echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
        read -p "$(echo -e "${BOLD}Enter HTML page URL: ${NC}")" url
        
        # Skip empty input
        if [ -z "$url" ]; then
            echo -e "\n${RED}❌ Empty URL provided. Please enter a valid URL.${NC}"
            continue
        fi
        
        # Validate URL format
        if ! validate_url "$url"; then
            echo -e "\n${RED}❌ Invalid URL format. Please enter a valid HTTP/HTTPS URL.${NC}"
            continue
        fi
        
        # Extract domain from URL
        domain=$(extract_domain "$url")
        echo -e "\n${BLUE}🌍 Domain: ${BOLD}$domain${NC}"
        
        # Check if we already have credentials for this domain in temp storage
        cred_file="/tmp/creds_${domain//[^a-zA-Z0-9]/_}"
        if [ -f "$cred_file" ]; then
            echo -e "${GREEN}✓ Using existing credentials for domain: ${BOLD}$domain${NC}"
            username=$(head -1 "$cred_file")
            password=$(tail -1 "$cred_file")
        else
            if [ "$MANUAL_CREDS" = "true" ]; then
                # Manual mode: Always prompt for credentials
                echo -e "\n${YELLOW}🔐 Enter credentials for domain: ${BOLD}$domain${NC}"
                read -p "$(echo -e "${BOLD}Username: ${NC}")" username
                read -s -p "$(echo -e "${BOLD}Password: ${NC}")" password
                echo
                
                # Validate credentials
                if [ -z "$username" ] || [ -z "$password" ]; then
                    echo -e "${RED}❌ Username and password cannot be empty${NC}"
                    continue
                fi
                
                # Save credentials for this domain in temp file
                echo "$username" > "$cred_file"
                echo "$password" >> "$cred_file"
                echo -e "\n${GREEN}✓ Credentials saved for domain: ${BOLD}$domain${NC}"
                
                # Ask if user wants to save to permanent file
                read -p "$(echo -e "${PURPLE}Save these credentials to file for future use? ${BOLD}(y/n): ${NC}")" save_choice
                case "$save_choice" in
                    [Yy]|[Yy][Ee][Ss])
                        create_credentials_file
                        description="Account for $domain (manually saved)"
                        echo "$domain|$username|$password|$description" >> "$CREDENTIALS_FILE"
                        echo -e "${GREEN}✓ Credentials saved to file for future use${NC}"
                        ;;
                esac
            else
                # Saved credentials mode: Try to load from saved file first
                if load_credentials_for_domain "$domain"; then
                    username="$USERNAME"
                    password="$PASSWORD"
                    
                    # Save to temp file for reuse
                    echo "$username" > "$cred_file"
                    echo "$password" >> "$cred_file"
                else
                    # Fall back to manual entry if not found in saved file
                    echo -e "${YELLOW}⚠️  No saved credentials found for domain: ${BOLD}$domain${NC}"
                    echo -e "${BLUE}💡 You can save credentials using 'Credentials Management' option.${NC}"
                    
                    echo -e "\n${YELLOW}🔐 Enter credentials for domain: ${BOLD}$domain${NC}"
                    read -p "$(echo -e "${BOLD}Username: ${NC}")" username
                    read -s -p "$(echo -e "${BOLD}Password: ${NC}")" password
                    echo
                    
                    # Validate credentials
                    if [ -z "$username" ] || [ -z "$password" ]; then
                        echo -e "${RED}❌ Username and password cannot be empty${NC}"
                        continue
                    fi
                    
                    # Save credentials for this domain in temp file
                    echo "$username" > "$cred_file"
                    echo "$password" >> "$cred_file"
                    echo -e "\n${GREEN}✓ Credentials saved for domain: ${BOLD}$domain${NC}"
                fi
            fi
        fi
        
        # Add URL and credentials to list
        echo "$url|$username|$password" >> "$URLS_FILE"
        
        # Update log filename with domain from first URL
        if [ "$page_count" -eq 0 ]; then
            local auth_type="manual_auth"
            if [ "$MANUAL_CREDS" = "false" ]; then
                auth_type="saved_auth"
            fi
            update_log_filename_with_domain "$url" "$auth_type"
        fi
        
        # Safety check for arithmetic
        if [[ "$page_count" =~ ^[0-9]+$ ]]; then
            page_count=$((page_count + 1))
        else
            page_count=1
        fi
        echo -e "${GREEN}✓ Added page ${BOLD}$page_count${NC}${GREEN}: $url${NC}"
        
        # Ask if user wants to add more pages
        echo
        while true; do
            read -p "$(echo -e "${PURPLE}Do you want to add another page? ${BOLD}(y/n): ${NC}")" add_more
            case "$add_more" in
                [Yy]|[Yy][Ee][Ss])
                    break
                    ;;
                [Nn]|[Nn][Oo])
                    break 2
                    ;;
                *)
                    echo -e "${RED}Please answer y (yes) or n (no)${NC}"
                    ;;
            esac
        done
    done
}

    # Display menu and get user choice
    while true; do
        show_menu
        read -p "$(echo -e "${BOLD}Enter your choice (1-8): ${NC}")" choice
        
        case $choice in
            1)
                init_log_file "no_auth"
                log_message "INFO" "Selected: Download WITHOUT Authentication"
                USE_AUTH=false
                collect_urls_no_auth
                
                # Execute download process
                if [ "$page_count" -gt 0 ]; then
                    # Confirmation prompt before starting download
                    echo -e "\n${BOLD}${CYAN}📋 Download Summary${NC}"
                    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
                    echo -e "${BLUE}📄 Pages to download: ${BOLD}$page_count${NC}"
                    echo -e "${BLUE}🔐 Authentication: ${BOLD}No${NC}"
                    echo -e "${BLUE}📁 Output directory: ${BOLD}$OUTPUT_DIR${NC}\n"
                    
                    while true; do
                        read -p "$(echo -e "${BOLD}${YELLOW}Do you want to proceed with the download? ${BOLD}(y/n): ${NC}")" confirm_download
                        case "$confirm_download" in
                            [Yy]|[Yy][Ee][Ss])
                                execute_download_process
                                # After download completion, return to main menu
                                echo -e "\n${PURPLE}Press Enter to return to main menu...${NC}"
                                read
                                main_menu
                                ;;
                            [Nn]|[Nn][Oo])
                                echo -e "\n${YELLOW}Download cancelled. Returning to main menu.${NC}"
                                main_menu
                                ;;
                            *)
                                echo -e "${RED}Please answer y (yes) or n (no)${NC}"
                                ;;
                        esac
                    done
                fi
                ;;
            2)
                if authentication_submenu; then
                    # Execute download process
                    if [ "$page_count" -gt 0 ]; then
                        # Confirmation prompt before starting download
                        auth_mode_text="Manual Entry"
                        if [ "$MANUAL_CREDS" = "false" ]; then
                            auth_mode_text="Saved Credentials"
                        fi
                        
                        echo -e "\n${BOLD}${CYAN}📋 Download Summary${NC}"
                        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
                        echo -e "${BLUE}📄 Pages to download: ${BOLD}$page_count${NC}"
                        echo -e "${BLUE}🔐 Authentication: ${BOLD}Yes ($auth_mode_text)${NC}"
                        echo -e "${BLUE}📁 Output directory: ${BOLD}$OUTPUT_DIR${NC}\n"
                        
                        while true; do
                            read -p "$(echo -e "${BOLD}${YELLOW}Do you want to proceed with the download? ${BOLD}(y/n): ${NC}")" confirm_download
                            case "$confirm_download" in
                                [Yy]|[Yy][Ee][Ss])
                                    execute_download_process
                                    # After download completion, return to main menu
                                    echo -e "\n${PURPLE}Press Enter to return to main menu...${NC}"
                                    read
                                    main_menu
                                    ;;
                                [Nn]|[Nn][Oo])
                                    echo -e "\n${YELLOW}Download cancelled. Returning to main menu.${NC}"
                                    break
                                    ;;
                                *)
                                    echo -e "${RED}Please answer y (yes) or n (no)${NC}"
                                    ;;
                            esac
                        done
                    fi
                fi
                # If authentication_submenu returns 1 (back to main menu), continue loop
                ;;
            3)
                if multifile_authentication_submenu; then
                    # Execute multi-file analysis and download
                    if [ "$page_count" -gt 0 ]; then
                        execute_multifile_process
                        # After completion, return to main menu
                        echo -e "\n${PURPLE}Press Enter to return to main menu...${NC}"
                        read
                        main_menu
                    fi
                fi
                ;;
            4)
                init_log_file "analyze_existing"
                log_message "INFO" "Selected: Analyze Existing HTML Files"
                analyze_existing_html_files
                ;;
            5)
                credentials_management_menu
                # After credentials management, return to main menu
                ;;
            6)
                log_files_management_menu
                # After log management, return to main menu
                ;;
            7)
                verbose_debug_settings_menu
                # After settings, return to main menu
                ;;
            8)
                log_message "INFO" "User exiting application"
                echo -e "\n${RED}👋 Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}❌ Invalid choice. Please enter 1, 2, 3, 4, 5, 6, 7, or 8.${NC}"
                ;;
        esac
    done
}

# Function to execute the download process
execute_download_process() {
    if [ "$page_count" -eq 0 ]; then
        echo -e "\n${RED}❌ No URLs provided.${NC}"
        rm -f "$URLS_FILE"
        return 1
    fi

#================================================================================
# PAGE PROCESSING AND DOWNLOAD PHASE
#================================================================================

log_message "INFO" "Starting Download Process"
log_message "INFO" "Pages to process: $page_count"
debug_log "Output directory: $OUTPUT_DIR"
debug_log "Authentication enabled: $USE_AUTH"

echo -e "\n\n${BOLD}${GREEN}🚀 Starting Download Process${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}📄 Pages to process: ${BOLD}$page_count${NC}\n"

# Process each URL
page_num=0
total_mp4_count=0

while IFS='|' read -r url username password; do
    # Safety check for arithmetic
    if [[ "$page_num" =~ ^[0-9]+$ ]]; then
        page_num=$((page_num + 1))
    else
        page_num=1
    fi
    
    echo -e "\n${BOLD}${BLUE}📄 [$page_num/$page_count] Processing Page${NC}"
    log_message "Processing page $page_num/$page_count: $url"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}🔗 URL: ${NC}$url"
    if [ "$USE_AUTH" = "true" ]; then
        echo -e "${BLUE}👤 Username: ${BOLD}$username${NC}\n"
    else
        echo -e "${BLUE}🌐 Mode: ${BOLD}No Authentication${NC}\n"
    fi
    
    # Download the HTML page 
    HTML_FILE="$OUTPUT_DIR/page${page_num}.html"
    
    if [ "$USE_AUTH" = "true" ]; then
        # Download WITH authentication
        COOKIE_JAR="$OUTPUT_DIR/cookies_${page_num}.txt"
        
        echo -e "${YELLOW}🔐 Step 1: Session Authentication${NC}"
        
        # Step 1: Get the login page to extract any tokens/forms
        domain=$(extract_domain "$url")
        login_url="https://$domain/login.php"
        
        echo -e "${BLUE}   → Getting login page: ${NC}$login_url"
        local curl_cmd="curl -L --user-agent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36' --cookie-jar '$COOKIE_JAR' -s -o '/tmp/login_page.html' '$login_url'"
        log_curl "$curl_cmd" ""
        curl -L --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
             --cookie-jar "$COOKIE_JAR" \
             -s \
             -o "/tmp/login_page.html" \
             "$login_url"
        
        # Step 2: Try to login via POST (common forum login method)
        echo -e "${BLUE}   → Attempting login with credentials...${NC}"
        local login_cmd="curl -L --user-agent 'Mozilla/5.0...' --cookie-jar '$COOKIE_JAR' --cookie '$COOKIE_JAR' --data 'vb_login_username=***&vb_login_password=***&do=login&cookieuser=1' '$login_url'"
        log_curl "$login_cmd" ""
        login_result=$(curl -L \
             --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
             --cookie-jar "$COOKIE_JAR" \
             --cookie "$COOKIE_JAR" \
             --header "Content-Type: application/x-www-form-urlencoded" \
             --header "Referer: $login_url" \
             --data "vb_login_username=$username&vb_login_password=$password&do=login&cookieuser=1" \
             -w "LOGIN_STATUS:%{http_code}" \
             -s \
             "$login_url" 2>&1)
        
        if echo "$login_result" | grep -q "Thank you for logging in"; then
            echo -e "${GREEN}   ✓ Login successful!${NC}"
            write_to_log "CURL" "Login successful"
        else
            echo -e "${YELLOW}   ⚠ Login response received${NC}"
            write_to_log "CURL" "Login response: $(echo "$login_result" | head -n 1)"
        fi
        
        # Step 3: Now try to access the actual page with session cookies
        echo -e "\n${YELLOW}📥 Step 2: Downloading Page Content${NC}"
        local download_cmd="curl -L --user-agent 'Mozilla/5.0...' --cookie '$COOKIE_JAR' [headers] -o '$HTML_FILE' '$url'"
        log_curl "$download_cmd" ""
        curl_output=$(curl -L \
             --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
             --cookie "$COOKIE_JAR" \
             --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
             --header "Accept-Language: en-US,en;q=0.5" \
             --header "Accept-Encoding: gzip, deflate" \
             --header "Connection: keep-alive" \
             --header "Upgrade-Insecure-Requests: 1" \
             --header "Cache-Control: no-cache" \
             --header "Pragma: no-cache" \
             --header "Referer: https://$domain/" \
             --compressed \
             -v \
             -w "HTTP_STATUS:%{http_code}|SIZE:%{size_download}|TIME:%{time_total}" \
             -o "$HTML_FILE" \
             "$url" 2>&1)
    else
        # Download WITHOUT authentication
        echo -e "${YELLOW}📥 Downloading Page Content (No Auth)${NC}"
        curl_command="curl -L --user-agent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36' --header 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8' --header 'Accept-Language: en-US,en;q=0.5' --header 'Accept-Encoding: gzip, deflate' --header 'Connection: keep-alive' --header 'Upgrade-Insecure-Requests: 1' --compressed -v -w 'HTTP_STATUS:%{http_code}|SIZE:%{size_download}|TIME:%{time_total}' -o '$HTML_FILE' '$url'"
        curl_output=$(curl -L \
             --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
             --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
             --header "Accept-Language: en-US,en;q=0.5" \
             --header "Accept-Encoding: gzip, deflate" \
             --header "Connection: keep-alive" \
             --header "Upgrade-Insecure-Requests: 1" \
             --compressed \
             -v \
             -w "HTTP_STATUS:%{http_code}|SIZE:%{size_download}|TIME:%{time_total}" \
             -o "$HTML_FILE" \
             "$url" 2>&1)
        log_curl "$curl_command" "$curl_output"
    fi
    
    # Extract status info
    status_info=$(echo "$curl_output" | grep "HTTP_STATUS:" | tail -1)
    http_code=$(echo "$status_info" | cut -d'|' -f1 | cut -d':' -f2)
    size=$(echo "$status_info" | cut -d'|' -f2 | cut -d':' -f2)
    time_taken=$(echo "$status_info" | cut -d'|' -f3 | cut -d':' -f2)
    
    echo "HTTP Status: $http_code, Size: $size bytes, Time: ${time_taken}s"
    
    # Check if we got content
    if [ ! -s "$HTML_FILE" ]; then
        echo "✗ Error: Empty response from: $url"
        echo "Curl output:"
        echo "$curl_output"
        log_error "CURL" "Empty response from: $url - Curl output: $curl_output"
        continue
    fi
    
    actual_size=$(wc -c < "$HTML_FILE")
    echo -e "${GREEN}   ✓ Downloaded ${BOLD}$actual_size bytes${NC}${GREEN} to: page${page_num}.html${NC}"
    
    # Validate we got actual forum content, not just headers
    echo -e "\n${YELLOW}🔍 Step 3: Content Validation${NC}"
    if grep -q "showthread" "$HTML_FILE"; then
        echo -e "${GREEN}   ✓ Contains forum thread content${NC}"
    else
        echo -e "${RED}   ✗ Missing forum thread content${NC}"
    fi
    
    if grep -q "postbit" "$HTML_FILE" || grep -q "post_" "$HTML_FILE"; then
        echo -e "${GREEN}   ✓ Contains forum posts${NC}"
    else
        echo -e "${RED}   ✗ Missing forum posts - may be access restricted${NC}"
    fi
    
    # Extract .mp4 URLs from the HTML by finding href attributes that contain .mp4
    # First, find all href attributes that contain .mp4
    MP4_URLS_HREF=$(grep -oE 'href="[^"]*\.mp4[^"]*"' "$HTML_FILE" | sed 's/href="//g' | sed 's/"$//g' 2>/dev/null || true)
    MP4_URLS_HREF2=$(grep -oE "href='[^']*\.mp4[^']*'" "$HTML_FILE" | sed "s/href='//g" | sed "s/'$//g" 2>/dev/null || true)
    
    # Find src attributes that contain .mp4 (for video/source tags)
    MP4_URLS_SRC=$(grep -oE 'src="[^"]*\.mp4[^"]*"' "$HTML_FILE" | sed 's/src="//g' | sed 's/"$//g' 2>/dev/null || true)
    MP4_URLS_SRC2=$(grep -oE "src='[^']*\.mp4[^']*'" "$HTML_FILE" | sed "s/src='//g" | sed "s/'$//g" 2>/dev/null || true)
    
    # Find data-src attributes (lazy loading)
    MP4_URLS_DATASRC=$(grep -oE 'data-src="[^"]*\.mp4[^"]*"' "$HTML_FILE" | sed 's/data-src="//g' | sed 's/"$//g' 2>/dev/null || true)
    MP4_URLS_DATASRC2=$(grep -oE "data-src='[^']*\.mp4[^']*'" "$HTML_FILE" | sed "s/data-src='//g" | sed "s/'$//g" 2>/dev/null || true)
    
    # Find any direct .mp4 URLs (backup method)
    MP4_URLS_DIRECT=$(grep -oE 'https?://[^"'\''<> ]*\.mp4[^"'\''<> ]*' "$HTML_FILE" 2>/dev/null || true)
    
    # Additional method: Find complete <a> tags that contain .mp4 in href and extract the href value
    MP4_URLS_ATAG=$(grep -oE '<a[^>]*href="[^"]*\.mp4[^"]*"[^>]*>' "$HTML_FILE" | sed 's/.*href="//g' | sed 's/".*//g' 2>/dev/null || true)
    MP4_URLS_ATAG2=$(grep -oE "<a[^>]*href='[^']*\.mp4[^']*'[^>]*>" "$HTML_FILE" | sed "s/.*href='//g" | sed "s/'.*//g" 2>/dev/null || true)
    
    # Alternative comprehensive search: Find any string ending with .mp4 and look for its context
    echo "  Debug - Comprehensive search for .mp4 references:"
    # Find all .mp4 strings and their surrounding context
    grep -oE '.{0,50}\.mp4.{0,50}' "$HTML_FILE" | while read -r line; do
        echo "    Context: $line"
        # Extract potential URLs from this context
        echo "$line" | grep -oE 'https?://[^"'\''<> ]*\.mp4[^"'\''<> ]*' || true
        echo "$line" | grep -oE '"[^"]*\.mp4[^"]*"' | sed 's/"//g' || true
        echo "$line" | grep -oE "'[^']*\.mp4[^']*'" | sed "s/'//g" || true
    done
    echo
    
    # Combine all methods and remove duplicates
    ALL_URLS="$MP4_URLS_HREF
$MP4_URLS_HREF2
$MP4_URLS_SRC
$MP4_URLS_SRC2
$MP4_URLS_DATASRC
$MP4_URLS_DATASRC2
$MP4_URLS_ATAG
$MP4_URLS_ATAG2
$MP4_URLS_DIRECT"
    
    MP4_URLS=$(echo "$ALL_URLS" | grep -E '\.mp4' | sort -u | grep -v '^$' 2>/dev/null || true)
    
    # Debug: Show what was found by each method
    echo "  Debug - Href URLs: $(echo -e "$MP4_URLS_HREF\n$MP4_URLS_HREF2" | grep -c . 2>/dev/null || echo 0)"
    echo "  Debug - Src URLs: $(echo -e "$MP4_URLS_SRC\n$MP4_URLS_SRC2" | grep -c . 2>/dev/null || echo 0)"
    echo "  Debug - Data-src URLs: $(echo -e "$MP4_URLS_DATASRC\n$MP4_URLS_DATASRC2" | grep -c . 2>/dev/null || echo 0)"
    echo "  Debug - A-tag URLs: $(echo -e "$MP4_URLS_ATAG\n$MP4_URLS_ATAG2" | grep -c . 2>/dev/null || echo 0)"
    echo "  Debug - Direct URLs: $(echo "$MP4_URLS_DIRECT" | grep -c . 2>/dev/null || echo 0)"
    
    # Show sample of what we're searching in
    echo "  Debug - All lines containing 'mp4' in HTML:"
    grep -i mp4 "$HTML_FILE" || echo "    No mp4 references found in HTML"
    echo
    
    # Show all href attributes for inspection
    echo "  Debug - All href attributes in HTML:"
    grep -oE 'href="[^"]*"' "$HTML_FILE" | head -10 || echo "    No href attributes found"
    echo
    
    # Show actual found URLs for debugging
    if [ -n "$MP4_URLS" ]; then
        echo "  Debug - All found URLs:"
        echo "$MP4_URLS" | sed 's/^/    /'
    fi
    
    if [ -z "$MP4_URLS" ]; then
        echo -e "${RED}   ✗ No .mp4 files found on this page${NC}"
        continue
    fi
    
    mp4_count=$(echo "$MP4_URLS" | wc -l)
    # Safety check for arithmetic
    if [[ "$mp4_count" =~ ^[0-9]+$ ]] && [[ "$total_mp4_count" =~ ^[0-9]+$ ]]; then
        total_mp4_count=$((total_mp4_count + mp4_count))
    else
        echo "Warning: Invalid mp4_count or total_mp4_count values"
        mp4_count=0
        total_mp4_count=${total_mp4_count:-0}
    fi
    echo -e "\n${GREEN}🎬 Found ${BOLD}$mp4_count${NC}${GREEN} .mp4 file(s) on this page:${NC}"
    echo "$MP4_URLS" | sed 's/^/     → /'
    
    # Convert relative URLs to absolute URLs and download each .mp4 file
    file_num=0
    while IFS= read -r mp4_url; do
        # Safety check for arithmetic
        if [[ "$file_num" =~ ^[0-9]+$ ]]; then
            file_num=$((file_num + 1))
        else
            file_num=1
        fi
        
        # Convert relative URL to absolute URL
        absolute_url=$(make_absolute_url "$url" "$mp4_url")
        
        filename=$(basename "$absolute_url" | cut -d'?' -f1)
        
        # If filename is empty or doesn't end with .mp4, generate one
        if [ -z "$filename" ] || [[ ! "$filename" =~ \.mp4$ ]]; then
            filename="page${page_num}_video_${file_num}.mp4"
        else
            # Add page prefix to avoid filename conflicts
            filename="page${page_num}_${filename}"
        fi
        
        output_path="$OUTPUT_DIR/$filename"
        
        echo -e "\n${YELLOW}⬇️  [$file_num/$mp4_count] Downloading: ${BOLD}$filename${NC}"
        echo -e "${BLUE}     URL: ${NC}$absolute_url"
        
        # Use wget to download the .mp4 file
        wget_cmd="wget '$absolute_url' -O '$output_path' --progress=bar:force"
        
        # Download with progress bar, capture only stderr for logging (without progress noise)
        if wget_result=$(wget "$absolute_url" -O "$output_path" --progress=bar:force 2>&1); then
            echo -e "${GREEN}     ✓ Downloaded: ${BOLD}$filename${NC}"
            # Get file size for logging
            if [ -f "$output_path" ]; then
                local file_size=$(du -h "$output_path" | cut -f1)
                log_download "$filename" "$file_size" "$absolute_url"
            fi
            log_wget "$wget_cmd" "SUCCESS - File downloaded successfully"
        else
            echo -e "${RED}     ✗ Failed to download: $absolute_url${NC}"
            # For failures, log the actual error (which won't have progress bar noise)
            log_error "WGET" "Failed to download: $absolute_url"
            log_wget "$wget_cmd" "FAILED: $wget_result"
        fi
    done <<< "$MP4_URLS"
    
    # Keep HTML file for inspection - don't delete it
    echo "  ✓ Saved HTML file: page${page_num}.html"
    echo "  Completed page $page_num"
    echo
done < "$URLS_FILE"

# Clean up URLs file and credential files
rm -f "$URLS_FILE"

# Clean up credential files
for cred_file in /tmp/creds_*; do
    if [ -f "$cred_file" ]; then
        rm -f "$cred_file"
    fi
done

#================================================================================
# SUMMARY AND POST-PROCESSING
#================================================================================

echo -e "\n\n${BOLD}${GREEN}📊 Download Summary${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}📄 Pages processed: ${BOLD}$page_count${NC}"
echo -e "${CYAN}🎬 Total MP4 files found: ${BOLD}$total_mp4_count${NC}"
echo -e "${CYAN}📁 Files saved to: ${BOLD}$OUTPUT_DIR${NC}\n"
log_message "MP4 download process completed: $page_count pages processed, $total_mp4_count MP4 files found"

# Rename files to remove page prefix
echo -e "${BOLD}${PURPLE}🏷️  File Renaming Phase${NC}"
echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════${NC}"
if ls "$OUTPUT_DIR"/page*_*.mp4 >/dev/null 2>&1; then
    echo -e "${YELLOW}Removing page prefixes from filenames...${NC}\n"
    
    for file in "$OUTPUT_DIR"/page*_*.mp4; do
        if [ -f "$file" ]; then
            # Extract filename without path
            basename_file=$(basename "$file")
            
            # Remove page<number>_ prefix using sed
            new_name=$(echo "$basename_file" | sed 's/^page[0-9]*_//')
            
            # Full path for new filename
            new_path="$OUTPUT_DIR/$new_name"
            
            # Rename the file
            if mv "$file" "$new_path"; then
                echo -e "${GREEN}  ✓ Renamed: ${BOLD}$basename_file${NC}${GREEN} → ${BOLD}$new_name${NC}"
            else
                echo -e "${RED}  ✗ Failed to rename: $basename_file${NC}"
            fi
        fi
    done
    echo
else
    echo -e "${YELLOW}No files with page prefixes found to rename${NC}\n"
fi

# Clean up HTML and cookie files
echo -e "${BOLD}${RED}🧹 Cleanup Phase${NC}"
echo -e "${RED}═══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Removing temporary HTML and cookie files...${NC}\n"

# Remove HTML files
if ls "$OUTPUT_DIR"/page*.html >/dev/null 2>&1; then
    for html_file in "$OUTPUT_DIR"/page*.html; do
        if rm -f "$html_file"; then
            echo -e "${GREEN}  ✓ Deleted: ${BOLD}$(basename "$html_file")${NC}"
        else
            echo -e "${RED}  ✗ Failed to delete: $(basename "$html_file")${NC}"
        fi
    done
else
    echo -e "${YELLOW}  No HTML files found to delete${NC}"
fi

# Remove cookie files (only if authentication was used)
if [ "$USE_AUTH" = "true" ]; then
    if ls "$OUTPUT_DIR"/cookies_*.txt >/dev/null 2>&1; then
        for cookie_file in "$OUTPUT_DIR"/cookies_*.txt; do
            if rm -f "$cookie_file"; then
                echo -e "${GREEN}  ✓ Deleted: ${BOLD}$(basename "$cookie_file")${NC}"
            else
                echo -e "${RED}  ✗ Failed to delete: $(basename "$cookie_file")${NC}"
            fi
        done
    else
        echo -e "${YELLOW}  No cookie files found to delete${NC}"
    fi
else
    echo -e "${BLUE}  No cookie files to delete (no authentication used)${NC}"
fi

echo -e "\n${GREEN}✨ Cleanup complete - only .mp4 files remain${NC}\n"

#================================================================================
# FINAL RESULTS
#================================================================================

echo -e "${BOLD}${CYAN}🎉 Final Results${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"

# Show final downloaded files
if ls "$OUTPUT_DIR"/*.mp4 >/dev/null 2>&1; then
    echo -e "${GREEN}📁 Successfully downloaded files:${NC}\n"
    ls -lh "$OUTPUT_DIR"/*.mp4 | while read -r line; do
        filename=$(echo "$line" | awk '{print $NF}')
        size=$(echo "$line" | awk '{print $5}')
        echo -e "${CYAN}  🎬 ${BOLD}$(basename "$filename")${NC}${CYAN} (${size})${NC}"
    done
    
    file_count=$(ls "$OUTPUT_DIR"/*.mp4 | wc -l)
    echo -e "\n${BOLD}${GREEN}🎊 SUCCESS! Downloaded $file_count MP4 files to: $OUTPUT_DIR${NC}"
else
    echo -e "${RED}❌ No files downloaded successfully${NC}"
fi

echo -e "\n${BOLD}${PURPLE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${PURPLE}║                            DOWNLOAD COMPLETE                          ║${NC}"
echo -e "${BOLD}${PURPLE}╚════════════════════════════════════════════════════════════════════════╝${NC}\n"

# Complete logging session
complete_log_session

# Clean up URLs file
rm -f "$URLS_FILE"
}

# Function to execute the multi-file analysis and download process
execute_multifile_process() {
    if [ "$page_count" -eq 0 ]; then
        echo -e "\n${RED}❌ No URLs provided.${NC}"
        rm -f "$URLS_FILE"
        return 1
    fi

    #================================================================================
    # MULTI-FILE ANALYSIS AND DOWNLOAD PHASE
    #================================================================================

    echo -e "\n\n${BOLD}${BLUE}🔍 Starting Multi-File Analysis${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📄 Pages to analyze: ${BOLD}$page_count${NC}\n"

    # Process each URL and analyze file types
    page_num=0
    declare -A all_found_files
    declare -A all_extension_counts
    declare -A page_files

    while IFS='|' read -r url username password; do
        # Safety check for arithmetic
        if [[ "$page_num" =~ ^[0-9]+$ ]]; then
            page_num=$((page_num + 1))
        else
            page_num=1
        fi
        
        echo -e "\n${BOLD}${BLUE}📄 [$page_num/$page_count] Analyzing Page${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${BLUE}🔗 URL: ${NC}$url"
        
        if [ "$USE_AUTH" = "true" ]; then
            echo -e "${BLUE}👤 Username: ${BOLD}$username${NC}\n"
        else
            echo -e "${BLUE}🌐 Mode: ${BOLD}No Authentication${NC}\n"
        fi
        
        # Download the HTML page using the same logic as the original download function
        HTML_FILE="$OUTPUT_DIR/analysis_page${page_num}.html"
        
        if [ "$USE_AUTH" = "true" ]; then
            # Download WITH authentication (reuse existing logic)
            COOKIE_JAR="$OUTPUT_DIR/analysis_cookies_${page_num}.txt"
            
            echo -e "${YELLOW}🔐 Step 1: Session Authentication${NC}"
            domain=$(extract_domain "$url")
            login_url="https://$domain/login.php"
            
            echo -e "${BLUE}   → Getting login page: ${NC}$login_url"
            curl_cmd="curl -L --user-agent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36' --cookie-jar '$COOKIE_JAR' -s -o '/tmp/login_page.html' '$login_url'"
            curl -L --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
                 --cookie-jar "$COOKIE_JAR" \
                 -s \
                 -o "/tmp/login_page.html" \
                 "$login_url"
            log_curl "$curl_cmd" ""
            
            echo -e "${BLUE}   → Attempting login with credentials...${NC}"
            login_cmd="curl -L --user-agent 'Mozilla/5.0...' --cookie-jar '$COOKIE_JAR' --cookie '$COOKIE_JAR' --data 'vb_login_username=***&vb_login_password=***&do=login&cookieuser=1' '$login_url'"
            login_result=$(curl -L \
                 --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
                 --cookie-jar "$COOKIE_JAR" \
                 --cookie "$COOKIE_JAR" \
                 --header "Content-Type: application/x-www-form-urlencoded" \
                 --header "Referer: $login_url" \
                 --data "vb_login_username=$username&vb_login_password=$password&do=login&cookieuser=1" \
                 -w "LOGIN_STATUS:%{http_code}" \
                 -s \
                 "$login_url" 2>&1)
            log_curl "$login_cmd" "$login_result"
            
            if echo "$login_result" | grep -q "Thank you for logging in"; then
                echo -e "${GREEN}   ✓ Login successful!${NC}"
            else
                echo -e "${YELLOW}   ⚠ Login response received${NC}"
            fi
            
            echo -e "\n${YELLOW}📥 Step 2: Downloading Page Content${NC}"
            download_cmd="curl -L --user-agent 'Mozilla/5.0...' --cookie '$COOKIE_JAR' [headers] -o '$HTML_FILE' '$url'"
            curl_output=$(curl -L \
                 --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
                 --cookie "$COOKIE_JAR" \
                 --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
                 --header "Accept-Language: en-US,en;q=0.5" \
                 --header "Accept-Encoding: gzip, deflate" \
                 --header "Connection: keep-alive" \
                 --header "Upgrade-Insecure-Requests: 1" \
                 --header "Cache-Control: no-cache" \
                 --header "Pragma: no-cache" \
                 --header "Referer: https://$domain/" \
                 --compressed \
                 -s \
                 -w "HTTP_STATUS:%{http_code}|SIZE:%{size_download}|TIME:%{time_total}" \
                 -o "$HTML_FILE" \
                 "$url" 2>&1)
            log_curl "$download_cmd" "$curl_output"
        else
            # Download WITHOUT authentication
            echo -e "${YELLOW}📥 Downloading Page Content (No Auth)${NC}"
            curl_command="curl -L --user-agent 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36' --header 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8' --header 'Accept-Language: en-US,en;q=0.5' --header 'Accept-Encoding: gzip, deflate' --header 'Connection: keep-alive' --header 'Upgrade-Insecure-Requests: 1' --compressed -s -w 'HTTP_STATUS:%{http_code}|SIZE:%{size_download}|TIME:%{time_total}' -o '$HTML_FILE' '$url'"
            curl_output=$(curl -L \
                 --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" \
                 --header "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
                 --header "Accept-Language: en-US,en;q=0.5" \
                 --header "Accept-Encoding: gzip, deflate" \
                 --header "Connection: keep-alive" \
                 --header "Upgrade-Insecure-Requests: 1" \
                 --compressed \
                 -s \
                 -w "HTTP_STATUS:%{http_code}|SIZE:%{size_download}|TIME:%{time_total}" \
                 -o "$HTML_FILE" \
                 "$url" 2>&1)
            log_curl "$curl_command" "$curl_output"
        fi
        
        # Extract status info
        status_info=$(echo "$curl_output" | grep "HTTP_STATUS:" | tail -1)
        http_code=$(echo "$status_info" | cut -d'|' -f1 | cut -d':' -f2)
        size=$(echo "$status_info" | cut -d'|' -f2 | cut -d':' -f2)
        time_taken=$(echo "$status_info" | cut -d'|' -f3 | cut -d':' -f2)
        
        echo -e "HTTP Status: $http_code, Size: $size bytes, Time: ${time_taken}s"
        
        # Check if we got content
        if [ ! -s "$HTML_FILE" ]; then
            echo -e "${RED}✗ Error: Empty response from: $url${NC}"
            log_error "CURL" "Empty response from: $url"
            continue
        fi
        
        actual_size=$(wc -c < "$HTML_FILE")
        echo -e "${GREEN}   ✓ Downloaded ${BOLD}$actual_size bytes${NC}${GREEN} for analysis${NC}"
        
        # Analyze the page for file types
        if analyze_page_file_types "$HTML_FILE" "$url"; then
            page_files[$page_num]="$HTML_FILE"
        fi
        
    done < "$URLS_FILE"
    
    # Now prompt user for which file types to download
    echo -e "\n${BOLD}${PURPLE}🎯 File Type Selection${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Choose which file types to download:${NC}\n"
    
    echo -e "${GREEN}1)${NC} ${BOLD}All files${NC} - Download everything found"
    echo -e "${BLUE}2)${NC} ${BOLD}Specific extensions${NC} - Choose specific file types"
    echo -e "${RED}3)${NC} ${BOLD}Cancel${NC} - Return to main menu"
    echo
    
    while true; do
        read -p "$(echo -e "${BOLD}Enter your choice (1-3): ${NC}")" file_choice
        
        case $file_choice in
            1)
                echo -e "\n${GREEN}✓ Selected: Download all files${NC}"
                download_selected_files "all"
                break
                ;;
            2)
                echo -e "\n${BLUE}✓ Selected: Specific extensions${NC}"
                select_specific_extensions
                break
                ;;
            3)
                echo -e "\n${RED}Download cancelled. Cleaning up...${NC}"
                # Clean up analysis files
                rm -f "$OUTPUT_DIR"/analysis_page*.html
                rm -f "$OUTPUT_DIR"/analysis_cookies_*.txt
                return 0
                ;;
            *)
                echo -e "${RED}❌ Invalid choice. Please enter 1, 2, or 3.${NC}"
                ;;
        esac
    done
    
    # Clean up analysis files
    rm -f "$OUTPUT_DIR"/analysis_page*.html
    rm -f "$OUTPUT_DIR"/analysis_cookies_*.txt
    rm -f "$URLS_FILE"
}

# Function to generate comprehensive extension regex pattern
generate_extension_pattern() {
    # Combine all extensions from the file_extensions array
    local all_extensions=""
    declare -A file_extensions_temp
    file_extensions_temp=(
        ["Video"]="mp4 avi mov wmv flv mkv webm m4v 3gp mpg mpeg m2v m4p asf asx divx f4v h264 h265 hevc m1v m2p m2t m2ts mts ogv qt rm rmvb swf ts vob vp8 vp9 xvid yuv 3g2 3gp2 amv drc dv dvr-ms f4p f4a f4b gif m4s mjpeg mjpg mng moov movie mp2 mp2v mp4v mpe mpg2 mpg4 mpv mpv2 mxf nsv ogg ogm ogx rec roq srt svi tod tp trp vfw vro y4m"
        ["Audio"]="mp3 wav flac aac ogg wma m4a opus aiff au ra ram ac3 amr ape caf dts eac3 gsm it m3u m3u8 mid midi mka mp2 mpa mpc oga pls realaudio s3m spx tta voc vqf w64 wv xm mod 669 abc amf ams dbm digi dmf dsm far gdm imf med mt2 mtm nst okt psm ptm stm ult umx wow"
        ["Image"]="jpg jpeg png gif bmp tiff webp svg ico psd ai eps ps pdf tga pcx ppm pgm pbm xbm xpm dib rle sgi rgb rgba bgra tif emf wmf cgm dxf dwg pct pic pict hdr exr cr2 nef arw dng orf pef srw x3f raf rw2 rwl iiq 3fr fff dcr k25 kdc erf mef mos mrw nrw ptx r3d raw heic heif avif jxl jp2 j2k jpf jpx jpm mj2 jxr hdp wdp"
        ["Document"]="pdf doc docx xls xlsx ppt pptx txt rtf odt ods odp odg odf odb pages numbers key epub mobi azw azw3 fb2 lit pdb prc djvu cbr cbz ps eps tex latex md markdown rst adoc asciidoc org wpd wps works sxw sxc sxi sxd sxg stw stc sti std stg xml html htm xhtml mhtml mht csv tsv"
        ["Archive"]="zip rar 7z tar gz bz2 xz lzma lz4 zst arj cab iso img bin cue nrg mdf mds ccd sub idx vcd ace alz apk jar war ear lha lzh z taz tbz tbz2 tgz tlz txz tzo sit sitx sea hqx uu uue b64 mime binhex arc zoo pak lbr pma sfx"
        ["Executable"]="exe msi deb rpm dmg pkg mpkg app run bin com scr bat cmd ps1 vbs js ipa crx xpi addon vsix nupkg gem whl egg pyz pex snap flatpak appimage"
    )
    
    for category in "${!file_extensions_temp[@]}"; do
        if [ -n "$all_extensions" ]; then
            all_extensions="$all_extensions|"
        fi
        all_extensions="$all_extensions$(echo "${file_extensions_temp[$category]}" | tr ' ' '|')"
    done
    
    echo "$all_extensions"
}

# Function to select specific file extensions
select_specific_extensions() {
    echo -e "\n${BOLD}${BLUE}📝 Specify File Extensions${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}Enter file extensions separated by spaces (e.g., mp4 jpg pdf):${NC}"
    echo -e "${YELLOW}Or type 'list' to see all available extensions${NC}\n"
    
    while true; do
        read -p "$(echo -e "${BOLD}Extensions: ${NC}")" extensions_input
        
        if [ -z "$extensions_input" ]; then
            echo -e "${RED}❌ Please enter at least one extension${NC}"
            continue
        fi
        
        if [ "$extensions_input" = "list" ]; then
            echo -e "\n${CYAN}Available extensions found:${NC}"
            # Show all extensions found across all pages using comprehensive pattern
            local ext_pattern=$(generate_extension_pattern)
            for page_html in "$OUTPUT_DIR"/analysis_page*.html; do
                if [ -f "$page_html" ]; then
                    grep -oE '\.('$ext_pattern')' "$page_html" | sort -u | sed 's/^\./ /'
                fi
            done | sort -u
            echo
            continue
        fi
        
        # Validate and process extensions
        extensions_list=$(echo "$extensions_input" | tr ' ' '\n' | sed 's/^\.*//' | sort -u)
        download_selected_files "$extensions_list"
        break
    done
}

# Function to download selected file types
download_selected_files() {
    local selection="$1"
    
    echo -e "\n${BOLD}${GREEN}⬇️  Starting File Downloads${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════${NC}"
    
    local total_downloaded=0
    
    # Process each analyzed page
    for page_html in "$OUTPUT_DIR"/analysis_page*.html; do
        if [ ! -f "$page_html" ]; then
            continue
        fi
        
        local page_num=$(echo "$page_html" | grep -oE '[0-9]+')
        echo -e "\n${BLUE}📄 Processing page $page_num files...${NC}"
        log_message "Processing files from page $page_num HTML file: $page_html"
        
        # Get all file URLs based on selection
        local file_urls=""
        
        if [ "$selection" = "all" ]; then
            # Get all file types using comprehensive pattern
            local ext_pattern=$(generate_extension_pattern)
            file_urls=$(grep -oE '(href|src|data-src)="[^"]*\.('$ext_pattern')[^"]*"' "$page_html" | sed 's/.*="//' | sed 's/"$//' | sort -u)
        else
            # Get specific extensions
            local ext_pattern=$(echo "$selection" | tr '\n' '|' | sed 's/|$//')
            file_urls=$(grep -oE '(href|src|data-src)="[^"]*\.('$ext_pattern')[^"]*"' "$page_html" | sed 's/.*="//' | sed 's/"$//' | sort -u)
        fi
        
        if [ -n "$file_urls" ]; then
            local file_count=$(echo "$file_urls" | wc -l)
            echo -e "${GREEN}   Found $file_count files to download${NC}"
            
            local file_num=0
            while IFS= read -r file_url; do
                if [ -n "$file_url" ]; then
                    file_num=$((file_num + 1))
                    
                    # Convert relative URL to absolute if needed
                    local absolute_url
                    if [[ "$file_url" =~ ^https?:// ]]; then
                        absolute_url="$file_url"
                    else
                        # Get the base URL from the original page URL
                        local base_url=$(sed -n "${page_num}p" <<< "$(cut -d'|' -f1 < "$URLS_FILE")")
                        absolute_url=$(make_absolute_url "$base_url" "$file_url")
                    fi
                    
                    local filename=$(basename "$absolute_url" | cut -d'?' -f1)
                    if [ -z "$filename" ] || [[ ! "$filename" =~ \. ]]; then
                        filename="page${page_num}_file_${file_num}"
                    else
                        filename="page${page_num}_${filename}"
                    fi
                    
                    local output_path="$OUTPUT_DIR/$filename"
                    
                    echo -e "\n${YELLOW}⬇️  [$file_num/$file_count] Downloading: ${BOLD}$filename${NC}"
                    echo -e "${BLUE}     URL: ${NC}$absolute_url"
                    
                    # Use wget to download the file
                    wget_cmd="wget '$absolute_url' -O '$output_path' --progress=bar:force"
                    if wget_result=$(wget "$absolute_url" -O "$output_path" --progress=bar:force 2>&1); then
                        echo -e "${GREEN}     ✓ Downloaded: ${BOLD}$filename${NC}"
                        total_downloaded=$((total_downloaded + 1))
                        # Get file size for logging
                        if [ -f "$output_path" ]; then
                            local file_size=$(du -h "$output_path" | cut -f1)
                            log_download "$filename" "$file_size" "$absolute_url"
                        fi
                        log_wget "$wget_cmd" "SUCCESS - File downloaded successfully"
                    else
                        echo -e "${RED}     ✗ Failed to download: $absolute_url${NC}"
                        log_error "WGET" "Failed to download: $absolute_url"
                        # For failures, log the actual error
                        log_wget "$wget_cmd" "FAILED: $wget_result"
                    fi
                fi
            done <<< "$file_urls"
        else
            echo -e "${YELLOW}   No matching files found on this page${NC}"
        fi
    done
    
    echo -e "\n${BOLD}${GREEN}📊 Multi-File Download Summary${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}📄 Pages analyzed: ${BOLD}$page_count${NC}"
    echo -e "${CYAN}📁 Total files downloaded: ${BOLD}$total_downloaded${NC}"
    echo -e "${CYAN}📂 Files saved to: ${BOLD}$OUTPUT_DIR${NC}\n"
    log_message "Multi-file download process completed: $page_count pages analyzed, $total_downloaded files downloaded"
    
    # Rename files to remove page prefix
    if [ $total_downloaded -gt 0 ]; then
        echo -e "${BOLD}${PURPLE}🏷️  File Renaming Phase${NC}"
        echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════${NC}"
        
        if ls "$OUTPUT_DIR"/page*_* >/dev/null 2>&1; then
            echo -e "${YELLOW}Removing page prefixes from filenames...${NC}\n"
            
            for file in "$OUTPUT_DIR"/page*_*; do
                if [ -f "$file" ]; then
                    basename_file=$(basename "$file")
                    new_name=$(echo "$basename_file" | sed 's/^page[0-9]*_//')
                    new_path="$OUTPUT_DIR/$new_name"
                    
                    if mv "$file" "$new_path"; then
                        echo -e "${GREEN}  ✓ Renamed: ${BOLD}$basename_file${NC}${GREEN} → ${BOLD}$new_name${NC}"
                    else
                        echo -e "${RED}  ✗ Failed to rename: $basename_file${NC}"
                    fi
                fi
            done
        fi
    fi
    
    echo -e "\n${BOLD}${PURPLE}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${PURPLE}║                       MULTI-FILE DOWNLOAD COMPLETE                    ║${NC}"
    echo -e "${BOLD}${PURPLE}╚════════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    # Complete logging session
    complete_log_session
}

# Function to analyze existing HTML files in the output directory
analyze_existing_html_files() {
    echo -e "\n${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                   ANALYZE EXISTING HTML FILES                         ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${BLUE}📁 Scanning directory: ${BOLD}$OUTPUT_DIR${NC}"
    
    # Check if output directory exists
    if [ ! -d "$OUTPUT_DIR" ]; then
        echo -e "${RED}❌ Output directory does not exist: $OUTPUT_DIR${NC}"
        echo -e "${YELLOW}💡 Create the directory or run other download options first.${NC}"
        echo -e "\n${PURPLE}Press Enter to return to main menu...${NC}"
        read
        main_menu
        return
    fi
    
    # Find HTML files in the output directory - handle files with newlines in names
    local html_files=()
    while IFS= read -r -d '' file; do
        html_files+=("$file")
    done < <(find "$OUTPUT_DIR" -maxdepth 1 -name "*.html" -type f -print0 2>/dev/null | sort -z)
    
    if [ ${#html_files[@]} -eq 0 ]; then
        echo -e "\n${RED}❌ No HTML files found in $OUTPUT_DIR${NC}"
        echo -e "${YELLOW}💡 Download some pages first using other options.${NC}"
        echo -e "\n${PURPLE}Press Enter to return to main menu...${NC}"
        read
        main_menu
        return
    fi
    
    echo -e "\n${GREEN}✓ Found ${BOLD}${#html_files[@]}${NC}${GREEN} HTML files${NC}\n"
    
    # Display found HTML files
    echo -e "${BOLD}${YELLOW}📄 Available HTML Files:${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════${NC}"
    for i in "${!html_files[@]}"; do
        local file_path="${html_files[$i]}"
        local file_basename=$(basename "$file_path")
        # Clean the basename to handle files with newlines
        file_basename=$(echo "$file_basename" | tr -d '\n\r' | sed 's/[[:space:]]*$//')
        
        # Get file info safely
        if [ -f "$file_path" ]; then
            local file_size=$(stat -c%s "$file_path" 2>/dev/null | numfmt --to=iec 2>/dev/null || echo "unknown")
            local file_date=$(stat -c%y "$file_path" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
            echo -e "${GREEN}$(($i + 1)))${NC} ${BOLD}$file_basename${NC} ${BLUE}($file_size)${NC} ${PURPLE}$file_date${NC}"
        else
            echo -e "${GREEN}$(($i + 1)))${NC} ${BOLD}$file_basename${NC} ${RED}(file not accessible)${NC}"
        fi
    done
    
    # Analyze each HTML file for file types
    echo -e "\n${BOLD}${CYAN}🔍 Analyzing Files for Downloadable Content${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    local total_files_found=0
    declare -A all_found_extensions
    declare -A file_analysis_results
    
    for i in "${!html_files[@]}"; do
        local html_file="${html_files[$i]}"
        local file_basename=$(basename "$html_file")
        # Clean the basename to handle files with newlines
        file_basename=$(echo "$file_basename" | tr -d '\n\r' | sed 's/[[:space:]]*$//')
        
        echo -e "${BLUE}📄 Analyzing: ${BOLD}$file_basename${NC}"
        
        # Use the existing analyze_page_file_types function logic with absolute path
        analyze_html_file_types "$html_file" "$file_basename"
        local analysis_result=$?
        
        if [ $analysis_result -eq 0 ]; then
            file_analysis_results["$i"]="success"
        else
            file_analysis_results["$i"]="no_files"
        fi
        
        echo
    done
    
    # Ask user what to do next
    echo -e "\n${BOLD}${PURPLE}📋 Analysis Complete${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${BOLD}${CYAN}What would you like to do?${NC}\n"
    echo -e "${GREEN}1)${NC} ${BOLD}Download files from specific HTML file${NC}"
    echo -e "${GREEN}   ${NC}→ Choose one HTML file and select extensions\n"
    
    echo -e "${YELLOW}2)${NC} ${BOLD}Download files from all HTML files${NC}"
    echo -e "${YELLOW}   ${NC}→ Batch download from all analyzed files\n"
    
    echo -e "${RED}3)${NC} ${BOLD}Return to main menu${NC}\n"
    
    while true; do
        read -p "$(echo -e "${BOLD}Enter your choice (1-3): ${NC}")" analysis_choice
        
        case $analysis_choice in
            1)
                select_and_download_from_single_html "${html_files[@]}"
                break
                ;;
            2)
                download_from_all_html_files "${html_files[@]}"
                break
                ;;
            3)
                echo -e "\n${PURPLE}Returning to main menu...${NC}"
                main_menu
                return
                ;;
            *)
                echo -e "${RED}❌ Invalid choice. Please enter 1, 2, or 3.${NC}"
                ;;
        esac
    done
}

# Function to analyze a single HTML file for file types (similar to analyze_page_file_types)
analyze_html_file_types() {
    local html_file="$1"
    local display_name="$2"
    
    # Use the same comprehensive extensions as the main analyzer
    declare -A file_extensions
    file_extensions=(
        ["Video"]="mp4 avi mov wmv flv mkv webm m4v 3gp mpg mpeg m2v m4p asf asx divx f4v h264 h265 hevc m1v m2p m2t m2ts mts ogv qt rm rmvb swf ts vob vp8 vp9 xvid yuv 3g2 3gp2 amv drc dv dvr-ms f4p f4a f4b gif m4s mjpeg mjpg mng moov movie mp2 mp2v mp4v mpe mpg2 mpg4 mpv mpv2 mxf nsv ogg ogm ogx rec roq srt svi tod tp trp vfw vro y4m"
        ["Audio"]="mp3 wav flac aac ogg wma m4a opus aiff au ra ram ac3 amr ape caf dts eac3 gsm it m3u m3u8 mid midi mka mp2 mpa mpc oga pls realaudio s3m spx tta voc vqf w64 wv xm mod 669 abc amf ams dbm digi dmf dsm far gdm imf med mt2 mtm nst okt psm ptm stm ult umx wow"
        ["Image"]="jpg jpeg png gif bmp tiff webp svg ico psd ai eps ps pdf tga pcx ppm pgm pbm xbm xpm dib rle sgi rgb rgba bgra tif emf wmf cgm dxf dwg pct pic pict hdr exr cr2 nef arw dng orf pef srw x3f raf rw2 rwl iiq 3fr fff dcr k25 kdc erf mef mos mrw nrw ptx r3d raw heic heif avif jxl jp2 j2k jpf jpx jpm mj2 jxr hdp wdp"
        ["Document"]="pdf doc docx xls xlsx ppt pptx txt rtf odt ods odp odg odf odb pages numbers key epub mobi azw azw3 fb2 lit pdb prc djvu cbr cbz ps eps tex latex md markdown rst adoc asciidoc org wpd wps works sxw sxc sxi sxd sxg stw stc sti std stg xml html htm xhtml mhtml mht csv tsv"
        ["Archive"]="zip rar 7z tar gz bz2 xz lzma lz4 zst arj cab iso img bin cue nrg mdf mds ccd sub idx vcd ace alz apk jar war ear lha lzh z taz tbz tbz2 tgz tlz txz tzo sit sitx sea hqx uu uue b64 mime binhex arc zoo pak lbr pma sfx"
        ["Executable"]="exe msi deb rpm dmg pkg mpkg app run bin com scr bat cmd ps1 vbs js ipa crx xpi addon vsix nupkg gem whl egg pyz pex snap flatpak appimage"
    )
    
    declare -A found_files
    declare -A extension_counts
    
    # Search for each extension
    for category in "${!file_extensions[@]}"; do
        for ext in ${file_extensions[$category]}; do
            # Find files with this extension in href, src, and data-src attributes
            # Handle files with unusual names by checking if file exists first
            if [ ! -f "$html_file" ]; then
                continue
            fi
            
            local files_href=$(grep -oE 'href="[^"]*\.'$ext'[^"]*"' "$html_file" 2>/dev/null | sed 's/href="//g' | sed 's/"$//g' || true)
            local files_src=$(grep -oE 'src="[^"]*\.'$ext'[^"]*"' "$html_file" 2>/dev/null | sed 's/src="//g' | sed 's/"$//g' || true)
            local files_data=$(grep -oE 'data-src="[^"]*\.'$ext'[^"]*"' "$html_file" 2>/dev/null | sed 's/data-src="//g' | sed 's/"$//g' || true)
            
            # Combine all found files
            local all_files="$files_href"$'\n'"$files_src"$'\n'"$files_data"
            
            if [ -n "$all_files" ]; then
                local unique_files=$(echo "$all_files" | grep -E "\.$ext" | sort -u | grep -v '^$' || true)
                if [ -n "$unique_files" ]; then
                    local count=$(echo "$unique_files" | wc -l)
                    extension_counts[$ext]=$count
                    found_files[$ext]="$unique_files"
                fi
            fi
        done
    done
    
    # Display results by category
    local total_files=0
    echo -e "${BLUE}   📄 File: ${NC}$display_name"
    
    for category in "${!file_extensions[@]}"; do
        local category_found=false
        local category_total=0
        
        for ext in ${file_extensions[$category]}; do
            if [ -n "${extension_counts[$ext]:-}" ]; then
                if [ "$category_found" = false ]; then
                    echo -e "${BOLD}${YELLOW}   📁 $category Files:${NC}"
                    category_found=true
                fi
                echo -e "${GREEN}      .$ext: ${BOLD}${extension_counts[$ext]}${NC}${GREEN} files${NC}"
                category_total=$((category_total + extension_counts[$ext]))
            fi
        done
        
        if [ "$category_found" = true ]; then
            total_files=$((total_files + category_total))
        fi
    done
    
    if [ $total_files -eq 0 ]; then
        echo -e "${RED}   ❌ No downloadable files found in this HTML file${NC}"
        return 1
    else
        echo -e "${BOLD}${GREEN}   📊 Total downloadable files found: $total_files${NC}"
        return 0
    fi
}

# Function to select and download from a single HTML file
select_and_download_from_single_html() {
    local html_files=("$@")
    
    echo -e "\n${BOLD}${GREEN}📄 Select HTML File to Download From${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${CYAN}Available HTML files:${NC}"
    for i in "${!html_files[@]}"; do
        local file_basename=$(basename "${html_files[$i]}")
        echo -e "${GREEN}$(($i + 1)))${NC} ${BOLD}$file_basename${NC}"
    done
    echo
    
    while true; do
        read -p "$(echo -e "${BOLD}Select HTML file (1-${#html_files[@]}): ${NC}")" file_choice
        
        if [[ "$file_choice" =~ ^[0-9]+$ ]] && [ "$file_choice" -ge 1 ] && [ "$file_choice" -le "${#html_files[@]}" ]; then
            local selected_file="${html_files[$((file_choice - 1))]}"
            local file_basename=$(basename "$selected_file")
            
            echo -e "\n${GREEN}✓ Selected: ${BOLD}$file_basename${NC}"
            
            # Set up for single file download
            rm -f "$OUTPUT_DIR"/analysis_page*.html
            cp "$selected_file" "$OUTPUT_DIR/analysis_page1.html"
            
            # Use existing download selection logic
            select_download_type_existing
            break
        else
            echo -e "${RED}❌ Invalid choice. Please enter a number between 1 and ${#html_files[@]}.${NC}"
        fi
    done
}

# Function to download from all HTML files
download_from_all_html_files() {
    local html_files=("$@")
    
    echo -e "\n${BOLD}${YELLOW}📄 Download from All HTML Files${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${BLUE}This will process ${BOLD}${#html_files[@]}${NC}${BLUE} HTML files${NC}"
    
    # Set up analysis files
    rm -f "$OUTPUT_DIR"/analysis_page*.html
    for i in "${!html_files[@]}"; do
        cp "${html_files[$i]}" "$OUTPUT_DIR/analysis_page$((i + 1)).html"
    done
    
    # Use existing download selection logic
    select_download_type_existing
}

# Function to handle download type selection for existing files
select_download_type_existing() {
    echo -e "\n${BOLD}${PURPLE}📋 Download Selection${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${BOLD}${CYAN}What would you like to download?${NC}\n"
    echo -e "${GREEN}1)${NC} ${BOLD}Download all files${NC}"
    echo -e "${GREEN}   ${NC}→ Download all supported file types\n"
    
    echo -e "${BLUE}2)${NC} ${BOLD}Download specific extensions${NC}"
    echo -e "${BLUE}   ${NC}→ Choose specific file extensions\n"
    
    echo -e "${RED}3)${NC} ${BOLD}Cancel and return to main menu${NC}\n"
    
    while true; do
        read -p "$(echo -e "${BOLD}Enter your choice (1-3): ${NC}")" download_choice
        
        case $download_choice in
            1)
                echo -e "\n${GREEN}✓ Selected: Download all files${NC}"
                download_selected_files "all"
                echo -e "\n${PURPLE}Press Enter to return to main menu...${NC}"
                read
                main_menu
                break
                ;;
            2)
                echo -e "\n${BLUE}✓ Selected: Specific extensions${NC}"
                select_specific_extensions
                echo -e "\n${PURPLE}Press Enter to return to main menu...${NC}"
                read
                main_menu
                break
                ;;
            3)
                echo -e "\n${RED}Download cancelled. Returning to main menu.${NC}"
                rm -f "$OUTPUT_DIR"/analysis_page*.html
                main_menu
                break
                ;;
            *)
                echo -e "${RED}❌ Invalid choice. Please enter 1, 2, or 3.${NC}"
                ;;
        esac
    done
}

# Start the main menu
main_menu
