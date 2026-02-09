#!/bin/bash
#
# remove-office365.sh
# Completely removes Microsoft Office 365 apps and all related files from macOS
# Does NOT remove Microsoft Teams or OneDrive
#
# Usage: sudo ./remove-office365.sh
#

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

echo "=== Microsoft Office 365 Complete Removal Script ==="
echo "This will remove Word, Excel, PowerPoint, Outlook, and OneNote"
echo "Teams and OneDrive will NOT be touched"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Closing Office applications..."
pkill -f "Microsoft Word" 2>/dev/null || true
pkill -f "Microsoft Excel" 2>/dev/null || true
pkill -f "Microsoft PowerPoint" 2>/dev/null || true
pkill -f "Microsoft Outlook" 2>/dev/null || true
pkill -f "Microsoft OneNote" 2>/dev/null || true
sleep 2

echo "Removing Office applications..."
rm -rf "/Applications/Microsoft Word.app"
rm -rf "/Applications/Microsoft Excel.app"
rm -rf "/Applications/Microsoft PowerPoint.app"
rm -rf "/Applications/Microsoft Outlook.app"
rm -rf "/Applications/Microsoft OneNote.app"

echo "Removing Office preferences and caches..."
for user_home in /Users/*; do
    if [[ -d "$user_home" && "$user_home" != "/Users/Shared" ]]; then
        username=$(basename "$user_home")
        
        # Preferences
        rm -f "$user_home/Library/Preferences/com.microsoft.Word.plist" 2>/dev/null || true
        rm -f "$user_home/Library/Preferences/com.microsoft.Excel.plist" 2>/dev/null || true
        rm -f "$user_home/Library/Preferences/com.microsoft.Powerpoint.plist" 2>/dev/null || true
        rm -f "$user_home/Library/Preferences/com.microsoft.Outlook.plist" 2>/dev/null || true
        rm -f "$user_home/Library/Preferences/com.microsoft.onenote.mac.plist" 2>/dev/null || true
        rm -f "$user_home/Library/Preferences/com.microsoft.office.plist" 2>/dev/null || true
        rm -f "$user_home/Library/Preferences/com.microsoft.Office365.plist" 2>/dev/null || true
        rm -f "$user_home/Library/Preferences/com.microsoft.Office365ServiceV2.plist" 2>/dev/null || true
        rm -rf "$user_home/Library/Preferences/ByHost/com.microsoft"* 2>/dev/null || true
        
        # Containers
        rm -rf "$user_home/Library/Containers/com.microsoft.Word" 2>/dev/null || true
        rm -rf "$user_home/Library/Containers/com.microsoft.Excel" 2>/dev/null || true
        rm -rf "$user_home/Library/Containers/com.microsoft.Powerpoint" 2>/dev/null || true
        rm -rf "$user_home/Library/Containers/com.microsoft.Outlook" 2>/dev/null || true
        rm -rf "$user_home/Library/Containers/com.microsoft.onenote.mac" 2>/dev/null || true
        rm -rf "$user_home/Library/Containers/com.microsoft.Office365ServiceV2" 2>/dev/null || true
        rm -rf "$user_home/Library/Containers/com.microsoft.errorreporting" 2>/dev/null || true
        rm -rf "$user_home/Library/Containers/com.microsoft.netlib.shipassertprocess" 2>/dev/null || true
        rm -rf "$user_home/Library/Containers/com.microsoft.Office365.FinderSync" 2>/dev/null || true
        
        # Group Containers (shared Office data)
        rm -rf "$user_home/Library/Group Containers/UBF8T346G9.Office" 2>/dev/null || true
        rm -rf "$user_home/Library/Group Containers/UBF8T346G9.OfficeOsfWebHost" 2>/dev/null || true
        
        # Application Support
        rm -rf "$user_home/Library/Application Support/Microsoft/Office" 2>/dev/null || true
        rm -rf "$user_home/Library/Application Support/com.microsoft.Word" 2>/dev/null || true
        rm -rf "$user_home/Library/Application Support/com.microsoft.Excel" 2>/dev/null || true
        rm -rf "$user_home/Library/Application Support/com.microsoft.Powerpoint" 2>/dev/null || true
        rm -rf "$user_home/Library/Application Support/com.microsoft.Outlook" 2>/dev/null || true
        rm -rf "$user_home/Library/Application Support/com.microsoft.onenote.mac" 2>/dev/null || true
        
        # Caches
        rm -rf "$user_home/Library/Caches/com.microsoft.Word" 2>/dev/null || true
        rm -rf "$user_home/Library/Caches/com.microsoft.Excel" 2>/dev/null || true
        rm -rf "$user_home/Library/Caches/com.microsoft.Powerpoint" 2>/dev/null || true
        rm -rf "$user_home/Library/Caches/com.microsoft.Outlook" 2>/dev/null || true
        rm -rf "$user_home/Library/Caches/com.microsoft.onenote.mac" 2>/dev/null || true
        rm -rf "$user_home/Library/Caches/Microsoft Office" 2>/dev/null || true
        rm -rf "$user_home/Library/Caches/com.microsoft.office.licensingV2" 2>/dev/null || true
        
        # Logs
        rm -rf "$user_home/Library/Logs/Microsoft Office" 2>/dev/null || true
        
        # Saved Application State
        rm -rf "$user_home/Library/Saved Application State/com.microsoft.Word.savedState" 2>/dev/null || true
        rm -rf "$user_home/Library/Saved Application State/com.microsoft.Excel.savedState" 2>/dev/null || true
        rm -rf "$user_home/Library/Saved Application State/com.microsoft.Powerpoint.savedState" 2>/dev/null || true
        rm -rf "$user_home/Library/Saved Application State/com.microsoft.Outlook.savedState" 2>/dev/null || true
        rm -rf "$user_home/Library/Saved Application State/com.microsoft.onenote.mac.savedState" 2>/dev/null || true
        
        # Cookies
        rm -rf "$user_home/Library/Cookies/com.microsoft.Word.binarycookies" 2>/dev/null || true
        rm -rf "$user_home/Library/Cookies/com.microsoft.Excel.binarycookies" 2>/dev/null || true
        rm -rf "$user_home/Library/Cookies/com.microsoft.Powerpoint.binarycookies" 2>/dev/null || true
        rm -rf "$user_home/Library/Cookies/com.microsoft.Outlook.binarycookies" 2>/dev/null || true
        
        echo "  Cleaned user: $username"
    fi
done

echo "Removing system-level Office files..."

# Fonts
rm -rf "/Library/Fonts/Microsoft" 2>/dev/null || true

# Application Support (system-wide)
rm -rf "/Library/Application Support/Microsoft/Office" 2>/dev/null || true
rm -rf "/Library/Application Support/Microsoft/MAU2.0" 2>/dev/null || true
rm -rf "/Library/Application Support/Microsoft/MERP2.0" 2>/dev/null || true

# Preferences (system-wide)
rm -f "/Library/Preferences/com.microsoft.office.licensingV2.plist" 2>/dev/null || true

# LaunchAgents and LaunchDaemons
rm -f "/Library/LaunchAgents/com.microsoft.update.agent.plist" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/com.microsoft.office.licensingV2.helper.plist" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/com.microsoft.autoupdate.helper.plist" 2>/dev/null || true

# PrivilegedHelperTools
rm -f "/Library/PrivilegedHelperTools/com.microsoft.office.licensingV2.helper" 2>/dev/null || true
rm -f "/Library/PrivilegedHelperTools/com.microsoft.autoupdate.helper" 2>/dev/null || true

# Receipts
rm -rf /private/var/db/receipts/com.microsoft.package.Microsoft_Word.* 2>/dev/null || true
rm -rf /private/var/db/receipts/com.microsoft.package.Microsoft_Excel.* 2>/dev/null || true
rm -rf /private/var/db/receipts/com.microsoft.package.Microsoft_PowerPoint.* 2>/dev/null || true
rm -rf /private/var/db/receipts/com.microsoft.package.Microsoft_Outlook.* 2>/dev/null || true
rm -rf /private/var/db/receipts/com.microsoft.package.Microsoft_OneNote.* 2>/dev/null || true
rm -rf /private/var/db/receipts/com.microsoft.package.Microsoft_Office_* 2>/dev/null || true
rm -rf /private/var/db/receipts/com.microsoft.pkg.licensing* 2>/dev/null || true

echo "Removing Office installer files and downloads..."
for user_home in /Users/*; do
    if [[ -d "$user_home" && "$user_home" != "/Users/Shared" ]]; then
        # Downloads folder - installer packages
        find "$user_home/Downloads" -maxdepth 1 -name "*Microsoft*Office*.pkg" -delete 2>/dev/null || true
        find "$user_home/Downloads" -maxdepth 1 -name "*Microsoft*Office*.dmg" -delete 2>/dev/null || true
        find "$user_home/Downloads" -maxdepth 1 -name "Microsoft_Office*.pkg" -delete 2>/dev/null || true
        find "$user_home/Downloads" -maxdepth 1 -name "Microsoft_Office*.dmg" -delete 2>/dev/null || true
        
        # Trash (if accessible)
        find "$user_home/.Trash" -name "*Microsoft*Office*" -delete 2>/dev/null || true
    fi
done

# System temp and caches
rm -rf /private/var/folders/*/*/com.microsoft.Word 2>/dev/null || true
rm -rf /private/var/folders/*/*/com.microsoft.Excel 2>/dev/null || true
rm -rf /private/var/folders/*/*/com.microsoft.Powerpoint 2>/dev/null || true
rm -rf /private/var/folders/*/*/com.microsoft.Outlook 2>/dev/null || true

echo "Removing Microsoft AutoUpdate (if no other MS apps need it)..."
# Only remove MAU if Teams and OneDrive are the only remaining MS apps
if [[ ! -d "/Applications/Microsoft Teams.app" ]] && [[ ! -d "/Applications/OneDrive.app" ]]; then
    rm -rf "/Library/Application Support/Microsoft/MAU2.0" 2>/dev/null || true
    rm -rf "/Applications/Microsoft AutoUpdate.app" 2>/dev/null || true
    echo "  Removed Microsoft AutoUpdate"
else
    echo "  Keeping Microsoft AutoUpdate (Teams/OneDrive still installed)"
fi

echo "Clearing caches..."
# Force Finder to refresh
killall Finder 2>/dev/null || true

echo ""
echo "=== Office 365 removal complete! ==="
echo ""
echo "Removed:"
echo "  - Word, Excel, PowerPoint, Outlook, OneNote"
echo "  - All preferences, caches, and containers"
echo "  - License files and receipts"
echo "  - Installer files from Downloads"
echo ""
echo "NOT removed:"
echo "  - Microsoft Teams"
echo "  - OneDrive"
echo "  - Microsoft AutoUpdate (if Teams/OneDrive present)"
echo ""
echo "Recommendation: Restart your Mac to fully clear memory."
