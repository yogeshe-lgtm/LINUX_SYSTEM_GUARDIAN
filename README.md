# Linux System Guardian v1.0
### Workspace Management & Security Auditor
**Academic Operating Systems Microproject**  
*Target Environment: Kali Linux, Ubuntu, Debian & Compatible POSIX Systems*

---

## 🛡️ Project Overview

**Linux System Guardian** is a lightweight, dependency-free terminal application built in Bash for Linux environments (specifically tested on Kali Linux, Debian, and Ubuntu). It serves as an academic demonstration of core Operating System principles, including:
- **Filesystem Hierarchy & Inode Auditing**: Scanning, attribute inspection, and directory isolation.
- **POSIX Access Control**: Permission analysis (octal masks vs symbolic notations) and controlled hardening.
- **System Telemetry & Virtual Memory**: Dynamic CPU sampling via `/proc/stat` and RAM analysis via `/proc/meminfo` & `free`.
- **Defensive Automation**: Safe two-stage cleanup (Dry-run preview before irreversible deletion).
- **Signal Handling & Process Traps**: Graceful recovery from asynchronous interrupts (`SIGINT`/`SIGTERM`).
- **Audit Logging**: Plain-text operational logs and sanitized, ANSI-free administrative reports.

---

## 🚀 Quick Start on Kali Linux / Ubuntu

### 1. Make the Script Executable
```bash
chmod +x linux_system_guardian.sh
```

*(Optional: If transferred from a Windows machine with CRLF line endings, normalize with `dos2unix linux_system_guardian.sh` or `sed -i 's/\r$//' linux_system_guardian.sh`)*

### 2. Run Interactive Console
```bash
./linux_system_guardian.sh
```

### 3. Run Automated Self-Test Verification Suite
```bash
./linux_system_guardian.sh --test
```

### 4. Run Any Module Directly
```bash
./linux_system_guardian.sh --module 1   # System Overview & Telemetry
./linux_system_guardian.sh --module 2   # Workspace Manager & Demo Files
./linux_system_guardian.sh --module 3   # Temporary & Large-File Scanner
./linux_system_guardian.sh --module 4   # File Permission Security Auditor
./linux_system_guardian.sh --module 5   # Safe Cleanup Center
./linux_system_guardian.sh --module 6   # Storage Analysis & Quotas
./linux_system_guardian.sh --module 7   # Reports & Activity Audit Trail
./linux_system_guardian.sh --module 8   # Academic Help & OS Concepts
```

### 5. Use with a Custom Workspace / Folder
By default, Guardian manages `~/linux_system_guardian_workspace/`. You can point it to **any custom workspace or project directory** using any of these 3 methods:

- **Method 1: Command-Line Flag (`--workspace` or `-w`)**
  ```bash
  # Launch interactive console pointing to your custom folder:
  ./linux_system_guardian.sh --workspace /path/to/my/workspace

  # Or run a specific module directly on your custom folder:
  ./linux_system_guardian.sh -w /path/to/my/workspace --module 3
  ```

- **Method 2: Environment Variable (`GUARDIAN_WORKSPACE`)**
  ```bash
  GUARDIAN_WORKSPACE=/path/to/my/workspace ./linux_system_guardian.sh
  ```

- **Method 3: Inside the Interactive Menu**
  Launch `./linux_system_guardian.sh` -> Select `[02]` (Workspace Manager) -> Choose `[4]` (Switch / Set Custom Workspace Directory) -> Type the folder path.


---

## 📁 Workspace Isolation Model

All file creations, scans, permission adjustments, and cleanup actions are strictly quarantined inside a dedicated directory in the user's home path:

```
$HOME/linux_system_guardian_workspace/
├── logs/
│   └── activity.log          # Sanitized operational audit trail
├── temp/                     # Quarantine directory for temporary .tmp files
├── archive/                  # Long-term backups and .bak files
└── reports/                  # Generated plain-text audit reports (.txt)
```

### 🔒 Safety Guarantees
- **No Root Required**: Operates strictly within user privileges.
- **Zero Outside Impact**: Deletion routines will never touch `/`, `/home`, `/tmp`, or any parent system partition.
- **Symlink Immunity**: All traversal commands reject symbolic links (`-P`), preventing directory traversal attacks.
- **Two-Stage Deletion**: Stage A is always a dry-run preview; Stage B requires typing `DELETE` in capital letters.

---

## 📊 Modules Summary

| Module | Name | OS Concept Demonstrated | Key Commands Used |
|---|---|---|---|
| **01** | System Overview | Process load, Virtual Memory, Kernel telemetry | `uname`, `hostname`, `free`, `/proc/stat`, `/proc/meminfo` |
| **02** | Workspace Manager | Directory hierarchies, File tree traversal | `find`, `stat`, `du`, `mkdir` |
| **03** | Temp & Large File Scanner | Inode filtering, Safe null-delimited processing | `find -print0`, `stat -c %s` |
| **04** | Permission Security Auditor | POSIX access masks (rwx), Hardening to 600 | `stat -c %a %A`, `chmod 600` |
| **05** | Safe Cleanup Center | Atomic unlinking, Revalidation before delete | `find -maxdepth 1`, `rm -f --`, test flags |
| **06** | Storage Analysis | Mount points, Disk utilization thresholds | `df -Pk`, `du -sh`, `sort -nr` |
| **07** | Reports & Activity Logs | Stream sanitization, Audit trails | `strip_ansi`, `sed`, `date`, `tail` |
| **08** | Help & OS Viva Guide | Architectural documentation & Academic theory | In-app help screens |

---

## 🧪 Self-Test Verification

Guardian includes a built-in headless verification suite:
```
$ ./linux_system_guardian.sh --test
================================================================
   LINUX SYSTEM GUARDIAN — AUTOMATED SELF-TEST SUITE            
================================================================
Running automated headless test verification on current environment...

  Testing: Environment dependencies...                          [PASS]
  Testing: Workspace directory initialization...                [PASS]
  Testing: Workspace path boundary isolation...                 [PASS]
  Testing: Activity log logging...                              [PASS]
  Testing: Demo file generation (no overwrite)...               [PASS]
  Testing: POSIX stat permission retrieval...                   [PASS]
  Testing: Permission hardening (chmod 600)...                  [PASS]
  Testing: Dry-run preserves temporary candidate...             [PASS]
  Testing: Cleanup removal of eligible file...                  [PASS]
  Testing: Preservation of .bak in archive...                   [PASS]
  Testing: ANSI escape sequence stripping...                    [PASS]
  Testing: Plaintext audit report generation...                 [PASS]

----------------------------------------------------------------
Self-Test Results: 12 Passed, 0 Failed
----------------------------------------------------------------
[+] All system verification tests passed successfully!
```
