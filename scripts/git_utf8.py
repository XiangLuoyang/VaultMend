#!/usr/bin/env python3
"""
git_utf8.py — UTF-8 safe git wrapper for Windows.

Root cause (治本): PowerShell 5.1's `& git <args>` invocation layer does ANSI
codepage conversion on argument strings AND stdout, even with [Console]::OutputEncoding.
This corrupts Chinese paths and stdout content.

Solution: route git operations through Python subprocess which preserves UTF-8 bytes
end-to-end (when stdin/stdout piped, not bound to console).

Usage:
    python git_utf8.py show HEAD -- <relative_path>
    python git_utf8.py grep -n TODO <relative_path>
    python git_utf8.py log --oneline -10

Output: UTF-8 clean text to stdout. Exit code mirrors git.
"""

import subprocess
import sys


def run_git(repo, *args):
    """Run git with UTF-8 args. Pipe stdout/stderr to capture, decode as UTF-8."""
    cmd = ['git', '-c', 'core.autocrlf=false', '-c', 'i18n.logOutputEncoding=utf-8',
           '-c', 'core.quotepath=false', '-C', repo] + list(args)
    try:
        result = subprocess.run(cmd, capture_output=True)
        sys.stdout.buffer.write(result.stdout)
        sys.stderr.buffer.write(result.stderr)
        return result.returncode
    except FileNotFoundError:
        sys.stderr.write("git not found in PATH\n")
        return 127


def main():
    if len(sys.argv) < 3:
        sys.stderr.write("Usage: git_utf8.py <repo> <git-args...>\n")
        return 1
    repo = sys.argv[1]
    args = sys.argv[2:]
    return run_git(repo, *args)


if __name__ == '__main__':
    sys.exit(main())
