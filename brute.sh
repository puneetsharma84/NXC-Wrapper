#!/bin/bash

# === Colors ===
GREEN='\033[1;32m'
ORANGE='\033[38;5;208m'
RESET='\033[0m'

# === Log Setup ===
LOGFILE="nxc.log"
mkdir -p "$(dirname "$LOGFILE")"

# === Handle Ctrl+C ===
trap ctrl_c INT
function ctrl_c() {
    echo -e "\n\n🛑 Interrupted. Saving log to ${GREEN}$LOGFILE${RESET}"
    echo "------ Scan interrupted by user ------" >> "$LOGFILE"
    exit 0
}

# === Default paths ===
DEFAULT_USERS="users.txt"
DEFAULT_PASSWORDS="pass.txt"
DEFAULT_TARGETS="targets.txt"

# === Input prompts ===
echo "📁 Using defaults: users.txt, pass.txt, targets.txt (in current directory)"

read -p "Use a different users file? (default: users.txt) [y/N]: " CHOOSE_USERS
[[ "$CHOOSE_USERS" =~ ^[Yy]$ ]] && read -p "Enter full path to users file: " USERS || USERS="./$DEFAULT_USERS"

read -p "Use a different passwords file? (default: pass.txt) [y/N]: " CHOOSE_PASS
[[ "$CHOOSE_PASS" =~ ^[Yy]$ ]] && read -p "Enter full path to password file: " PASSWORDS || PASSWORDS="./$DEFAULT_PASSWORDS"

read -p "Use a different targets file? (default: targets.txt) [y/N]: " CHOOSE_TARGETS
[[ "$CHOOSE_TARGETS" =~ ^[Yy]$ ]] && read -p "Enter full path to targets file: " TARGETS || TARGETS="./$DEFAULT_TARGETS"

read -p "Enter the DOMAIN (for Kerberos auth): " DOMAIN

# === Validate files ===
for file in "$USERS" "$PASSWORDS" "$TARGETS"; do
    [[ ! -f "$file" ]] && echo "❌ File not found: $file" && exit 1
done

# === Init log ===
echo -e "🔐 NXC Full Scan Log - $(date)\n" > "$LOGFILE"
echo "Users: $USERS | Passwords: $PASSWORDS | Targets: $TARGETS | Domain: $DOMAIN" >> "$LOGFILE"
echo "------------------------------------------------------------" >> "$LOGFILE"

mapfile -t TARGET_LIST < "$TARGETS"
TOTAL=${#TARGET_LIST[@]}
PROTOCOLS=("smb" "rdp" "ssh" "winrm")

# === Function: Run Scan ===
run_scan() {
    local proto=$1
    local target=$2
    local kerb_args=$3
    local label=$4

    TMP_OUTPUT=$(mktemp)

    echo -e "\n[$(date +'%F %T')] $label $proto → $target" >> "$LOGFILE"
    echo "--- Running: nxc $proto $target -u $USERS -p $PASSWORDS $kerb_args" >> "$LOGFILE"

    stdbuf -oL -eL nxc "$proto" "$target" -u "$USERS" -p "$PASSWORDS" $kerb_args --continue-on-success > "$TMP_OUTPUT" 2>&1

    cat "$TMP_OUTPUT" >> "$LOGFILE"
    echo "------------------------------------------------------------" >> "$LOGFILE"

    # Show banner line
    banner=$(grep '^\[\*\]' "$TMP_OUTPUT" | head -n1)
    [[ -n "$banner" ]] && echo -e "$banner"

    # Show unique [+] hits
    grep '\[+\]' "$TMP_OUTPUT" | sort -u | while read -r line; do
        pre=$(echo "$line" | sed -E 's/\(Pwn3d!\)//')
        has_pwned=$(echo "$line" | grep '(Pwn3d!)')
        if [[ -n "$has_pwned" ]]; then
            echo -e "${GREEN}${pre}${ORANGE}(Pwn3d!)${RESET}"
        else
            echo -e "${GREEN}$line${RESET}"
        fi
    done

    rm "$TMP_OUTPUT"
}

# === LOCAL AUTH ===
echo ""
echo "🔍 Starting LOCAL authentication..."
echo ""

for proto in "${PROTOCOLS[@]}"; do
    i=0
    for target in "${TARGET_LIST[@]}"; do
        ((i++))
        percent=$(( i * 100 / TOTAL ))
        printf "\n[LOCAL] %-5s | Target: %-15s | %3d%% complete\n" "$proto" "$target" "$percent"
        run_scan "$proto" "$target" "" "LOCAL"
    done
done

# === Prompt for Kerberos ===
echo ""
read -p "Do you want to continue with Kerberos authentication? (y/n): " DO_KERB

if [[ "$DO_KERB" =~ ^[Yy]$ ]]; then
    echo ""
    echo "🔐 Starting DOMAIN (Kerberos) authentication..."
    echo ""

    for proto in "${PROTOCOLS[@]}"; do
        i=0
        for target in "${TARGET_LIST[@]}"; do
            ((i++))
            percent=$(( i * 100 / TOTAL ))
            printf "\n[KERB ] %-5s | Target: %-15s | %3d%% complete\n" "$proto" "$target" "$percent"
            run_scan "$proto" "$target" "-d $DOMAIN --kerberos" "KERB"
        done
    done
else
    echo -e "\n🛑 Skipping Kerberos authentication."
fi

echo -e "\n✅ All scans complete. Log saved to ${GREEN}$LOGFILE${RESET}"
