#!/bin/bash
# Backup Verification Script for macOS
# Checks Time Machine and cloud sync status

SCRIPT_NAME="BackupVerification"
LOG_FILE="$HOME/Library/Logs/${SCRIPT_NAME}.log"
REPORT_FILE="$HOME/Library/Logs/${SCRIPT_NAME}-report.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

# Create log directory if needed
mkdir -p "$(dirname "$LOG_FILE")"

log "=== Backup Verification Started ==="

# Initialize counters
ISSUES=0
WARNINGS=0
PASSED=0

# Function to check Time Machine
check_time_machine() {
    log "Checking Time Machine status..."
    
    # Check if Time Machine is enabled
    TM_STATUS=$(tmutil status 2>/dev/null | grep -c "Running = 1" || echo "0")
    
    if [ "$TM_STATUS" = "1" ]; then
        log_success "Time Machine is currently running"
    else
        # Check last backup
        LAST_BACKUP=$(tmutil latestbackup 2>/dev/null | xargs -I {} stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" {} 2>/dev/null || echo "")
        
        if [ -z "$LAST_BACKUP" ]; then
            log_error "Time Machine has never completed a backup!"
            ((ISSUES++))
        else
            # Calculate days since last backup
            LAST_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$LAST_BACKUP" +%s 2>/dev/null || echo "0")
            CURRENT_EPOCH=$(date +%s)
            DAYS_SINCE=$(( (CURRENT_EPOCH - LAST_EPOCH) / 86400 ))
            
            if [ $DAYS_SINCE -gt 7 ]; then
                log_error "Time Machine backup is $DAYS_SINCE days old (Last: $LAST_BACKUP)"
                ((ISSUES++))
            elif [ $DAYS_SINCE -gt 3 ]; then
                log_warning "Time Machine backup is $DAYS_SINCE days old (Last: $LAST_BACKUP)"
                ((WARNINGS++))
            else
                log_success "Time Machine backup current (Last: $LAST_BACKUP, $DAYS_SINCE days ago)"
                ((PASSED++))
            fi
        fi
    fi
    
    # Check Time Machine destination
    TM_DEST=$(tmutil destinationinfo 2>/dev/null | grep "Name" | head -1 | cut -d: -f2 | xargs || echo "")
    if [ -z "$TM_DEST" ]; then
        log_error "No Time Machine destination configured!"
        ((ISSUES++))
    else
        log "Time Machine destination: $TM_DEST"
    fi
}

# Function to check iCloud Drive sync
check_icloud() {
    log "Checking iCloud Drive status..."
    
    # Check if iCloud Drive is enabled
    ICLOUD_STATUS=$(defaults read MobileMeAccounts Accounts 2>/dev/null | grep -c "accountDescription" || echo "0")
    
    if [ "$ICLOUD_STATUS" = "0" ]; then
        log_warning "iCloud Drive not configured"
        return
    fi
    
    # Check for stuck uploads/downloads using brctl
    if command -v brctl &> /dev/null; then
        BRCTL_STATUS=$(brctl status 2>&1)
        
        # Look for stuck items
        if echo "$BRCTL_STATUS" | grep -q "down:" || echo "$BRCTL_STATUS" | grep -q "up:"; then
            PENDING_UPLOADS=$(echo "$BRCTL_STATUS" | grep "up:" | grep -o '[0-9]\+' | head -1 || echo "0")
            PENDING_DOWNLOADS=$(echo "$BRCTL_STATUS" | grep "down:" | grep -o '[0-9]\+' | head -1 || echo "0")
            
            if [ "$PENDING_UPLOADS" -gt 100 ] || [ "$PENDING_DOWNLOADS" -gt 100 ]; then
                log_warning "iCloud has $PENDING_UPLOADS uploads and $PENDING_DOWNLOADS downloads pending"
                ((WARNINGS++))
            else
                log_success "iCloud sync appears healthy"
                ((PASSED++))
            fi
        else
            log_success "iCloud Drive enabled and accessible"
            ((PASSED++))
        fi
    fi
}

# Function to check specific cloud services
check_cloud_services() {
    log "Checking cloud sync services..."
    
    # Check if Dropbox is running
    if pgrep -x "Dropbox" > /dev/null; then
        log_success "Dropbox is running"
        ((PASSED++))
    fi
    
    # Check if Google Drive is running
    if pgrep -f "Google Drive" > /dev/null || pgrep -x "GoogleDrive" > /dev/null; then
        log_success "Google Drive is running"
        ((PASSED++))
    fi
    
    # Check if OneDrive is running
    if pgrep -x "OneDrive" > /dev/null; then
        log_success "OneDrive is running"
        ((PASSED++))
    fi
    
    # Check if Box is running
    if pgrep -x "Box" > /dev/null; then
        log_success "Box Drive is running"
        ((PASSED++))
    fi
}

# Function to check disk space on backup drives
check_backup_drives() {
    log "Checking backup drive space..."
    
    # Get Time Machine destination
    TM_DEST_INFO=$(tmutil destinationinfo 2>/dev/null)
    
    if [ -n "$TM_DEST_INFO" ]; then
        # Extract mount point or network URL
        MOUNT_POINT=$(echo "$TM_DEST_INFO" | grep "Mount Point" | cut -d: -f2 | xargs || echo "")
        
        if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
            # Check available space
            DISK_INFO=$(df -h "$MOUNT_POINT" 2>/dev/null | tail -1)
            AVAILABLE=$(echo "$DISK_INFO" | awk '{print $4}')
            USE_PERCENT=$(echo "$DISK_INFO" | awk '{print $5}' | tr -d '%')
            
            if [ "$USE_PERCENT" -gt 90 ]; then
                log_error "Backup drive is ${USE_PERCENT}% full (Only $AVAILABLE available)"
                ((ISSUES++))
            elif [ "$USE_PERCENT" -gt 80 ]; then
                log_warning "Backup drive is ${USE_PERCENT}% full ($AVAILABLE available)"
                ((WARNINGS++))
            else
                log_success "Backup drive has $AVAILABLE available (${USE_PERCENT}% used)"
                ((PASSED++))
            fi
        fi
    fi
}

# Function to check important file backups
check_critical_files() {
    log "Checking critical files are backed up..."
    
    CRITICAL_PATHS=(
        "$HOME/Documents"
        "$HOME/Desktop"
        "$HOME/Pictures"
    )
    
    for path in "${CRITICAL_PATHS[@]}"; do
        if [ -d "$path" ]; then
            # Check if path is excluded from Time Machine
            EXCLUDED=$(tmutil isexcluded "$path" 2>/dev/null | grep -c "\[Excluded\]" || echo "0")
            
            if [ "$EXCLUDED" = "1" ]; then
                log_warning "$path is EXCLUDED from Time Machine backups"
                ((WARNINGS++))
            else
                log_success "$path is included in backups"
                ((PASSED++))
            fi
        fi
    done
}

# Generate summary report
generate_report() {
    log "=== Backup Verification Summary ==="
    log "Passed: $PASSED"
    log "Warnings: $WARNINGS"
    log "Issues: $ISSUES"
    
    # Create report file
    cat > "$REPORT_FILE" << EOF
Backup Verification Report
==========================
Generated: $(date)
Computer: $(scutil --get ComputerName 2>/dev/null || echo "Unknown")

Summary:
- Passed: $PASSED
- Warnings: $WARNINGS  
- Issues: $ISSUES

Status: $(if [ $ISSUES -gt 0 ]; then echo "CRITICAL - Action Required"; elif [ $WARNINGS -gt 0 ]; then echo "WARNING - Review Needed"; else echo "HEALTHY"; fi)

Detailed log: $LOG_FILE
EOF
    
    log "Report saved to: $REPORT_FILE"
}

# Main execution
main() {
    check_time_machine
    check_icloud
    check_cloud_services
    check_backup_drives
    check_critical_files
    generate_report
    
    log "=== Backup Verification Completed ==="
    
    # Exit with appropriate code
    if [ $ISSUES -gt 0 ]; then
        exit 1
    elif [ $WARNINGS -gt 0 ]; then
        exit 2
    else
        exit 0
    fi
}

# Run main function
main