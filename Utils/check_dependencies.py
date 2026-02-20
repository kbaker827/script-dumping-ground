#!/usr/bin/env python3
"""
Script Dependency Checker
Checks all scripts for outdated modules and dependencies
"""

import json
import os
import sys
import subprocess
import re
from pathlib import Path
from datetime import datetime

class DependencyChecker:
    def __init__(self, repo_path='.'):
        self.repo_path = Path(repo_path)
        self.dependencies = {}
        self.outdated = []
        self.missing = []
        
    def scan_scripts(self):
        """Scan all scripts for imports/requires"""
        for ext in ['*.py', '*.ps1', '*.sh']:
            for script in self.repo_path.rglob(ext):
                if '.git' not in str(script):
                    self.analyze_script(script)
    
    def analyze_script(self, script_path):
        """Analyze a single script for dependencies"""
        try:
            with open(script_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            ext = script_path.suffix
            
            if ext == '.py':
                self.extract_python_imports(script_path, content)
            elif ext == '.ps1':
                self.extract_powershell_modules(script_path, content)
            elif ext == '.sh':
                self.extract_shell_commands(script_path, content)
                
        except Exception as e:
            print(f"Error reading {script_path}: {e}")
    
    def extract_python_imports(self, path, content):
        """Extract Python imports"""
        # Match import statements
        imports = re.findall(r'^(?:from|import)\s+([a-zA-Z_][a-zA-Z0-9_]*)', content, re.MULTILINE)
        
        for module in set(imports):
            # Skip standard library modules
            if module not in ['os', 'sys', 'json', 're', 'datetime', 'pathlib', 'subprocess', 'urllib']:
                if 'python' not in self.dependencies:
                    self.dependencies['python'] = {}
                if module not in self.dependencies['python']:
                    self.dependencies['python'][module] = {'scripts': [], 'latest': None, 'current': None}
                self.dependencies['python'][module]['scripts'].append(str(path))
    
    def extract_powershell_modules(self, path, content):
        """Extract PowerShell module requirements"""
        # Match Import-Module
        modules = re.findall(r'Import-Module\s+["\']?([^"\'\n]+)["\']?', content)
        
        for module in set(modules):
            if 'powershell' not in self.dependencies:
                self.dependencies['powershell'] = {}
            if module not in self.dependencies['powershell']:
                self.dependencies['powershell'][module] = {'scripts': [], 'installed': False}
            self.dependencies['powershell'][module]['scripts'].append(str(path))
    
    def extract_shell_commands(self, path, content):
        """Extract shell command dependencies"""
        commands = re.findall(r'^(?:command\s+-v|which)\s+(\w+)|^(?:brew|apt|yum|pip|npm)\s+', content, re.MULTILINE)
        
        for cmd in set([c for c in commands if c]):
            if 'shell' not in self.dependencies:
                self.dependencies['shell'] = {}
            if cmd not in self.dependencies['shell']:
                self.dependencies['shell'][cmd] = {'scripts': [], 'installed': False}
            self.dependencies['shell'][cmd]['scripts'].append(str(path))
    
    def check_python_packages(self):
        """Check Python packages for updates"""
        if 'python' not in self.dependencies:
            return
        
        print("\n📦 Checking Python packages...")
        
        for package in self.dependencies['python']:
            try:
                # Get currently installed version
                result = subprocess.run(
                    [sys.executable, '-m', 'pip', 'show', package],
                    capture_output=True,
                    text=True
                )
                
                if result.returncode == 0:
                    # Package is installed
                    version_match = re.search(r'Version:\s*(.+)', result.stdout)
                    if version_match:
                        current_version = version_match.group(1).strip()
                        self.dependencies['python'][package]['current'] = current_version
                        
                        # Check for updates
                        check_result = subprocess.run(
                            [sys.executable, '-m', 'pip', 'index', 'versions', package],
                            capture_output=True,
                            text=True
                        )
                        
                        if check_result.returncode == 0:
                            latest_match = re.search(r'Available versions:\s*(.+)', check_result.stdout)
                            if latest_match:
                                latest = latest_match.group(1).split(',')[0].strip()
                                self.dependencies['python'][package]['latest'] = latest
                                
                                if latest != current_version:
                                    self.outdated.append({
                                        'type': 'python',
                                        'package': package,
                                        'current': current_version,
                                        'latest': latest,
                                        'scripts': self.dependencies['python'][package]['scripts']
                                    })
                                    print(f"  ⚠️  {package}: {current_version} → {latest}")
                                else:
                                    print(f"  ✅ {package}: {current_version} (up to date)")
                else:
                    # Package not installed
                    self.missing.append({
                        'type': 'python',
                        'package': package,
                        'scripts': self.dependencies['python'][package]['scripts']
                    })
                    print(f"  ❌ {package}: Not installed")
                    
            except Exception as e:
                print(f"  ⚠️  Could not check {package}: {e}")
    
    def check_shell_commands(self):
        """Check if shell commands are available"""
        if 'shell' not in self.dependencies:
            return
        
        print("\n🔧 Checking shell commands...")
        
        for cmd in self.dependencies['shell']:
            result = subprocess.run(
                ['which', cmd],
                capture_output=True
            )
            
            if result.returncode == 0:
                self.dependencies['shell'][cmd]['installed'] = True
                print(f"  ✅ {cmd}: Found")
            else:
                self.dependencies['shell'][cmd]['installed'] = False
                self.missing.append({
                    'type': 'shell',
                    'command': cmd,
                    'scripts': self.dependencies['shell'][cmd]['scripts']
                })
                print(f"  ❌ {cmd}: Not found")
    
    def generate_report(self):
        """Generate dependency report"""
        print("\n" + "="*60)
        print("📊 DEPENDENCY CHECK REPORT")
        print("="*60)
        
        print(f"\nTotal outdated packages: {len(self.outdated)}")
        print(f"Total missing dependencies: {len(self.missing)}")
        
        if self.outdated:
            print("\n⚠️  OUTDATED PACKAGES:")
            print("-" * 60)
            for item in self.outdated:
                print(f"\n{item['package']} ({item['type']})")
                print(f"  Current: {item['current']}")
                print(f"  Latest:  {item['latest']}")
                print(f"  Used in: {', '.join(item['scripts'][:3])}")
                print(f"  Update:  pip install --upgrade {item['package']}")
        
        if self.missing:
            print("\n❌ MISSING DEPENDENCIES:")
            print("-" * 60)
            for item in self.missing:
                if item['type'] == 'python':
                    print(f"\n{item['package']} (Python)")
                    print(f"  Install: pip install {item['package']}")
                elif item['type'] == 'shell':
                    print(f"\n{item['command']} (Shell)")
                    print(f"  Install with: brew/apt/yum install {item['command']}")
                print(f"  Required by: {', '.join(item['scripts'][:3])}")
        
        # Generate update script
        if self.outdated:
            print("\n📝 QUICK UPDATE SCRIPT:")
            print("-" * 60)
            print("#!/bin/bash")
            print("# Update all outdated Python packages")
            for item in self.outdated:
                if item['type'] == 'python':
                    print(f"pip install --upgrade {item['package']}")
        
        # Save report to file
        report_file = self.repo_path / "dependency_report.txt"
        with open(report_file, 'w') as f:
            f.write(f"Dependency Check Report - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("="*60 + "\n\n")
            f.write(f"Outdated: {len(self.outdated)}\n")
            f.write(f"Missing: {len(self.missing)}\n\n")
            
            if self.outdated:
                f.write("Outdated Packages:\n")
                for item in self.outdated:
                    f.write(f"  {item['package']}: {item['current']} → {item['latest']}\n")
            
            if self.missing:
                f.write("\nMissing Dependencies:\n")
                for item in self.missing:
                    f.write(f"  {item.get('package', item.get('command'))}\n")
        
        print(f"\n💾 Report saved to: {report_file}")
    
    def run(self):
        """Main execution"""
        print("🔍 Scanning repository for dependencies...")
        self.scan_scripts()
        
        print(f"Found {len(self.dependencies)} dependency categories")
        
        self.check_python_packages()
        self.check_shell_commands()
        
        self.generate_report()
        
        # Exit with error code if issues found
        if self.outdated or self.missing:
            print("\n⚠️  Dependency issues found!")
            return 1
        else:
            print("\n✅ All dependencies up to date!")
            return 0


if __name__ == "__main__":
    repo_path = sys.argv[1] if len(sys.argv) > 1 else '.'
    
    checker = DependencyChecker(repo_path)
    sys.exit(checker.run())