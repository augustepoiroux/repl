import os

from rich.console import Console

__console = Console()

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REPL_DIR = ROOT_DIR


def build_repl():
    os.chdir(REPL_DIR)
    os.system("rm -rf .lake")
    os.system("lake exe cache get")
    os.system("lake build")


# check if lake is installed
if os.system("which lake") != 0:
    __console.print("Lake is not installed. Please install it: https://leanprover-community.github.io/get_started.html")
    exit(1)

# Check if we need to build the REPL, and if so, build it
if not os.path.exists(os.path.join(REPL_DIR, ".lake")):
    __console.log("Lean REPL not ready. Building it... (this may take a while)")
    build_repl()
