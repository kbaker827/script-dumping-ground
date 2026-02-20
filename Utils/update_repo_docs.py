#!/usr/bin/env python3
"""
GitHub Repository Auto-Documentation
Scans repos and updates README files with latest info
"""

import json
import os
import sys
import subprocess
import re
from datetime import datetime
from pathlib import Path

class RepoDocumenter:
    def __init__(self, repo_path='.'):
        self.repo_path = Path(repo_path)
        self.script_info = []
        
    def scan_directory(self, directory='.'):
        """Scan directory for scripts and gather info"""
        base_path = self.repo_path / directory
        
        if not base_path.exists():
            return
        
        for item in base_path.iterdir():
            if item.is_dir() and not item.name.startswith('.') and item.name not in ['node_modules', '__pycache__']:
                # Recursively scan subdirectories
                self.scan_directory(str(item.relative_to(self.repo_path)))
            elif item.suffix in ['.ps1', '.py', '.sh', '.bash']:
                self.analyze_script(item)
    
    def analyze_script(self, script_path):
        """Extract information from a script file"""
        try:
            with open(script_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            info = {
                'name': script_path.name,
                'path': str(script_path.relative_to(self.repo_path)),
                'type': script_path.suffix,
                'description': self.extract_description(content, script_path.suffix),
                'parameters': self.extract_parameters(content, script_path.suffix),
                'examples': self.extract_examples(content)
            }
            
            self.script_info.append(info)
            
        except Exception as e:
            print(f"Error analyzing {script_path}: {e}")
    
    def extract_description(self, content, file_type):
        """Extract script description from comments"""
        if file_type == '.ps1':
            # PowerShell help
            match = re.search(r'\.DESCRIPTION\s+([^\n]+(?:\n[^#\n]+)*)', content)
            if match:
                return match.group(1).strip().replace('\n', ' ')
        elif file_type in ['.py', '.sh']:
            # Python/Shell docstrings/comments
            lines = content.split('\n')
            description = []
            in_docstring = False
            
            for line in lines[:30]:  # Check first 30 lines
                if '"""' in line or "'''" in line or '# ' in line:
                    in_docstring = True
                    text = line.split('"""')[-1].split("'''")[-1].split('# ')[-1]
                    if text and not text.startswith('#'):
                        description.append(text)
                elif in_docstring and line.strip():
                    if line.strip().startswith('#'):
                        description.append(line.strip().lstrip('#').strip())
                    else:
                        break
            
            return ' '.join(description[:3])  # First 3 lines
        
        return "No description available"
    
    def extract_parameters(self, content, file_type):
        """Extract script parameters"""
        params = []
        
        if file_type == '.ps1':
            # PowerShell parameters
            matches = re.findall(r'\[Parameter[^\]]*\][^\n]*\n\s*\[([^\]]+)\]\s*\$([^\s,=\[]+)', content)
            for match in matches[:5]:  # Limit to first 5
                param_type = match[0]
                param_name = match[1]
                params.append(f"[{param_type}]${param_name}")
        
        return params[:5]  # Limit to 5 params
    
    def extract_examples(self, content):
        """Extract usage examples from comments"""
        examples = []
        
        # Look for EXAMPLE sections
        matches = re.findall(r'\.EXAMPLE\s+([^\n]+(?:\n[^#\n\.]+)*)', content)
        for match in matches[:3]:  # First 3 examples
            examples.append(match.strip())
        
        return examples
    
    def generate_table_of_contents(self):
        """Generate TOC from scanned scripts"""
        toc = []
        
        # Group by directory
        by_dir = {}
        for info in self.script_info:
            dir_name = str(Path(info['path']).parent)
            if dir_name not in by_dir:
                by_dir[dir_name] = []
            by_dir[dir_name].append(info)
        
        for dir_name, scripts in sorted(by_dir.items()):
            if dir_name == '.':
                toc.append("\n### Root Directory")
            else:
                toc.append(f"\n### {dir_name}/")
            
            toc.append("")
            for script in scripts:
                toc.append(f"- **{script['name']}** - {script['description'][:80]}")
            
            toc.append("")
        
        return '\n'.join(toc)
    
    def update_readme(self):
        """Update main README.md with auto-generated content"""
        readme_path = self.repo_path / "README.md"
        
        if not readme_path.exists():
            print("README.md not found, creating new one")
            readme_content = self.create_new_readme()
        else:
            with open(readme_path, 'r') as f:
                readme_content = f.read()
            
            # Update the auto-generated section
            readme_content = self.update_auto_generated_section(readme_content)
        
        with open(readme_path, 'w') as f:
            f.write(readme_content)
        
        print(f"Updated {readme_path}")
    
    def create_new_readme(self):
        """Create a new README from template"""
        toc = self.generate_table_of_contents()
        
        return f"""# Script Repository

Auto-generated documentation for script collection.

Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## Table of Contents

{toc}

## Quick Start

See individual script README files for detailed usage instructions.

---

*This README is auto-generated. Do not edit the Table of Contents section manually.*
"""
    
    def update_auto_generated_section(self, content):
        """Update only the auto-generated portion of README"""
        # Find and replace the TOC section
        pattern = r'(## Table of Contents\n)(.*?)(\n## |\n--- |\Z)'
        
        toc = self.generate_table_of_contents()
        
        replacement = f"""## Table of Contents

{toc}

## Quick Start
"""
        
        # Simple replacement
        if '## Table of Contents' in content:
            parts = content.split('## Table of Contents')
            before = parts[0]
            after = parts[1].split('## Quick Start')[1] if '## Quick Start' in parts[1] else ''
            return before + replacement + after
        else:
            # Insert before first ## heading
            lines = content.split('\n')
            first_heading = 0
            for i, line in enumerate(lines):
                if line.startswith('# ') and i > 0:
                    first_heading = i
                    break
            
            return '\n'.join(lines[:first_heading]) + '\n' + replacement + '\n' + '\n'.join(lines[first_heading:])
    
    def run(self):
        """Main execution"""
        print("🔍 Scanning repository for scripts...")
        self.scan_directory()
        
        print(f"Found {len(self.script_info)} scripts")
        
        print("📝 Updating README.md...")
        self.update_readme()
        
        print("✅ Documentation updated!")


if __name__ == "__main__":
    repo_path = sys.argv[1] if len(sys.argv) > 1 else '.'
    
    documenter = RepoDocumenter(repo_path)
    documenter.run()