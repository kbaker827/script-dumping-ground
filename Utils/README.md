# Utility Scripts

General utility scripts for repository and script management.

## Scripts

### `update_repo_docs.py`
Auto-generates repository documentation by scanning scripts.

**Features:**
- Scans all scripts for descriptions
- Extracts parameters and examples
- Generates Table of Contents
- Updates README.md automatically
- Groups scripts by directory

**Usage:**
```bash
# Update current repository
python3 update_repo_docs.py

# Update specific repository
python3 update_repo_docs.py /path/to/repo
```

**Extracts:**
- Script descriptions from comments/docstrings
- Parameter lists
- Usage examples
- File organization

---

### `check_dependencies.py`
Checks all scripts for outdated dependencies.

**Features:**
- Scans Python imports
- Checks PowerShell module requirements
- Identifies shell command dependencies
- Compares installed vs latest versions
- Generates update commands

**Usage:**
```bash
# Check current repository
python3 check_dependencies.py

# Check specific repository
python3 check_dependencies.py /path/to/repo
```

**Supported Languages:**
- Python (pip packages)
- PowerShell (modules)
- Bash/Shell (commands)

**Output:**
- Outdated packages list
- Missing dependencies
- Update commands
- Report file: `dependency_report.txt`

## Requirements

- Python 3.6+
- Internet connection (for version checking)
- pip (for Python package checking)
