# Linux System Guardian — Complete Testing & Proof Guide
### Live Hands-On Terminal Verification Commands

This document contains **every single manual and automated terminal command** to test and demonstrate that **Linux System Guardian v1.0** is 100% dynamic, interacts live with the Linux kernel, modifies real filesystem inodes, and safely protects user data.

---

## ⚡ Option A: Run the Complete 10-Step Automated Proof Suite in 1 Command

We have packaged all tests into an executable script: [`run_all_proof_tests.sh`](file:///d:/OS-MICROPROJECT/run_all_proof_tests.sh).

```bash
chmod +x run_all_proof_tests.sh
./run_all_proof_tests.sh
```

**What this automatically proves:**
1. ✅ Runs the internal 12-point self-test suite.
2. ✅ Proves live dynamic CPU timeslices from `/proc/stat` and RAM states from `/proc/meminfo`.
3. ✅ Physically creates demo files on disk and confirms they exist.
4. ✅ Creates a custom test file with spaces in the filename and proves the scanner finds it without breaking.
5. ✅ Creates a real `777` file on disk, audits it, and hardens the inode to `600`.
6. ✅ Proves Dry-Run preview does NOT delete candidate files.
7. ✅ Proves Confirmed Cleanup deletes `.tmp` files while preserving `.bak`, `.log`, and `.txt` files.
8. ✅ Validates storage quotas, root partition capacity, and 80% threshold alarms.
9. ✅ Generates an audit report and verifies zero ANSI escape corruption (`\x1B[`).
10. ✅ Verifies real-time chronological event recording in `activity.log`.

---

## 🛠️ Option B: Step-by-Step Manual Commands (For Presentation & Viva)

You can copy-paste each command below into your Kali Linux terminal to demonstrate each feature live to your professor or examiner.

---

### Test 1: Prove Live Kernel Telemetry (Module 1)

```bash
# 1. Run Module 1 directly:
./linux_system_guardian.sh --module 1

# 2. Check the real kernel files it reads:
cat /proc/stat | head -n 1
cat /proc/meminfo | head -n 5
df -h /
```
**Proof**: The numbers in Guardian match your operating system's live kernel counters.

---

### Test 2: Prove Physical File Creation & Directory Tree (Module 2)

```bash
# 1. Launch Guardian and generate demo files:
./linux_system_guardian.sh
# -> Press 02 (Workspace Manager)
# -> Press 2 (Generate Synthetic Demonstration Files)
# -> Press 0 (Return)
# -> Press 00 (Exit)

# 2. Verify files physically exist on your real disk:
ls -la ~/linux_system_guardian_workspace/temp/
ls -la ~/linux_system_guardian_workspace/archive/
ls -la ~/linux_system_guardian_workspace/logs/
```
**Proof**: You will see real files (`session_cache_01.tmp`, `credentials_draft.txt`, `system_config.bak`, `service_mock.log`) on your hard drive.

---

### Test 3: Test Dynamic Scanner & Filenames with Spaces (Module 3)

```bash
# 1. Create a custom file with spaces and a 200 KB test payload:
echo "Custom Content" > "$HOME/linux_system_guardian_workspace/temp/my confidential space test.tmp"
head -c 204800 /dev/zero > "$HOME/linux_system_guardian_workspace/temp/large_blob.tmp"

# 2. Run the scanner:
./linux_system_guardian.sh --module 3
# -> Enter threshold: 100
```
**Proof**: Guardian will dynamically discover `my confidential space test.tmp` (handling spaces safely) and flag `large_blob.tmp` as exceeding the 100 KiB threshold.

```bash
# Clean up the test files:
rm -f "$HOME/linux_system_guardian_workspace/temp/my confidential space test.tmp" "$HOME/linux_system_guardian_workspace/temp/large_blob.tmp"
```

---

### Test 4: Prove Inode Permission Auditing & Hardening (Module 4)

```bash
# 1. Create a file and give it dangerous world-writable 777 permissions:
echo "DATABASE_PASSWORD=secret" > "$HOME/linux_system_guardian_workspace/temp/hack_target.txt"
chmod 777 "$HOME/linux_system_guardian_workspace/temp/hack_target.txt"

# 2. Verify its initial mode in Linux:
stat -c "%a %A %n" "$HOME/linux_system_guardian_workspace/temp/hack_target.txt"
# Output will be: 777 -rwxrwxrwx ...

# 3. Open Guardian to audit and harden it:
./linux_system_guardian.sh
# -> Select [04] (File Permission Security Auditor)
# -> Notice 'hack_target.txt' is highlighted in RED as CRITICAL (777)!
# -> Enter its number and press Enter
# -> Type 'y' to confirm chmod 600 hardening

# 4. Verify in terminal that the inode was genuinely hardened:
stat -c "%a %A %n" "$HOME/linux_system_guardian_workspace/temp/hack_target.txt"
# Output is now: 600 -rw------- ... (Owner read/write only, zero access for group/others!)
```

```bash
# Clean up test target:
rm -f "$HOME/linux_system_guardian_workspace/temp/hack_target.txt"
```

---

### Test 5: Prove Stage A Dry-Run Deletes NOTHING (Module 5)

```bash
# 1. Create a dummy .tmp file:
echo "IMPORTANT_DATA" > "$HOME/linux_system_guardian_workspace/temp/do_not_delete_yet.tmp"

# 2. Run Cleanup Module and cancel:
./linux_system_guardian.sh --module 5
# -> Notice the Dry-Run preview lists the file and reclaimable bytes.
# -> When asked to type 'DELETE', just press Enter (or type 'no').

# 3. Verify the file is still safely on your disk:
ls -l "$HOME/linux_system_guardian_workspace/temp/do_not_delete_yet.tmp"
```
**Proof**: The file is completely untouched. Dry-run never deletes anything.

---

### Test 6: Prove Stage B Deletes ONLY .tmp & Preserves All Other Files (Module 5)

```bash
# 1. Create a .tmp file, a .bak file, and a .log file:
echo "TEMP_DATA" > "$HOME/linux_system_guardian_workspace/temp/delete_me.tmp"
echo "BACKUP_DATA" > "$HOME/linux_system_guardian_workspace/archive/preserve_me.bak"
echo "LOG_DATA" > "$HOME/linux_system_guardian_workspace/logs/preserve_me.log"

# 2. Run Cleanup Module and confirm deletion:
./linux_system_guardian.sh --module 5
# -> When prompted, type 'DELETE' in capital letters and press Enter.

# 3. Verify the result:
ls -l "$HOME/linux_system_guardian_workspace/temp/delete_me.tmp"       # File is GONE!
ls -l "$HOME/linux_system_guardian_workspace/archive/preserve_me.bak" # File SURVIVED!
ls -l "$HOME/linux_system_guardian_workspace/logs/preserve_me.log"    # File SURVIVED!
```
**Proof**: Only the eligible `.tmp` file was unlinked. `.bak` and `.log` files were strictly preserved.

---

### Test 7: Prove Storage Analysis & Disk Partition Quota (Module 6)

```bash
# 1. Run Storage Analysis:
./linux_system_guardian.sh --module 6

# 2. Compare against native Linux du and df:
df -h /
du -sh ~/linux_system_guardian_workspace/*
```
**Proof**: Guardian's breakdown matches the exact byte allocation reported by `du` and `df`.

---

### Test 8: Prove Clean Report Generation & ANSI Escape Code Sanitization (Module 7)

```bash
# 1. Generate a fresh report:
./linux_system_guardian.sh
# -> Select [07]
# -> Select [2] (Generate Report)
# -> Select [00] (Exit)

# 2. Find the generated report:
LATEST_REPORT=$(find ~/linux_system_guardian_workspace/reports -name "guardian_report_*.txt" | sort -r | head -n 1)
echo "Generated report: $LATEST_REPORT"

# 3. View the report with cat or less:
cat "$LATEST_REPORT"

# 4. Prove that ANSI color codes did NOT corrupt the text file:
grep -P '\x1B\[' "$LATEST_REPORT" && echo "Corrupted with ANSI!" || echo "Clean pure plaintext (Zero ANSI codes)!"
```

---

### Test 9: Prove Asynchronous Signal Trap Handling (Ctrl+C)

```bash
# 1. Launch Guardian:
./linux_system_guardian.sh

# 2. At any menu prompt, press Ctrl+C (SIGINT)
# -> Notice Guardian catches the interrupt gracefully:
#    "[!] Operation interrupted by user signal (SIGINT). Returning safely..."
# -> It logs the interrupt and does not crash the terminal!

# 3. Check the log entry:
tail -n 2 ~/linux_system_guardian_workspace/logs/activity.log
```

---

### Test 10: Prove Non-Root Safe Execution

```bash
# Run Guardian as normal user:
whoami
./linux_system_guardian.sh --test
```
**Proof**: Every test passes with exit code `0` without ever asking for `sudo` or root privileges.

---

### Test 11: Prove Custom Workspace Operation

```bash
# 1. Create a custom test directory anywhere with sample files:
mkdir -p /tmp/my_custom_project/src
echo "int main() { return 0; }" > /tmp/my_custom_project/src/main.c
echo "dummy temporary data" > /tmp/my_custom_project/cache.tmp

# 2. Run Guardian pointed specifically to your custom workspace:
./linux_system_guardian.sh --workspace /tmp/my_custom_project --module 2

# Or launch the interactive console on your custom workspace:
./linux_system_guardian.sh -w /tmp/my_custom_project
```
**Proof**: The tree display, inventory, permission auditing, file scans, and logs are all bound specifically to `/tmp/my_custom_project` without altering other directories.

