import subprocess
_orig_run = subprocess.run
def _safe_run(*args, **kwargs):
    kwargs.setdefault("check", True)
    return _orig_run(*args, **kwargs)
subprocess.run = _safe_run

import os
import shutil

# --- CONFIGURATION ---
# Files/Extensions that must NEVER be deleted
safe_extensions = [".py", ".txt", ".sh", ".md"]
safe_files = [
    "ligand.itp", "ligand.gro",  # Basal inputs (if pre-generated)
    "complex.gro",               # Basal structure
    "topol.top"                  # Main topology (sometimes manual)
]

def is_safe(filename):
    """Returns True if the file is in our safe list or has a safe extension."""
    # 1. Check strict filename match
    if filename in safe_files:
        return True

    # 2. Check extension (Protects ALL python scripts automatically)
    for ext in safe_extensions:
        if filename.endswith(ext):
            return True

    # 3. Check for original input structures (usually .pdb or .mol2)
    # We assume basal inputs don't have underscores like "step5_..."
    if (filename.endswith(".pdb") or filename.endswith(".mol2")) and "step" not in filename:
        return True

    return False

def cleanup():
    print("[-] STARTING PROJECT RESET (Universal Safety Mode)")

    # 1. Clean 'complex' directory (The heavy simulation data)
    # We wipe this completely because it is 100% generated.
    print("[-] Cleaning 'complex' folder...")
    if os.path.exists("complex"):
        print("    Removing entire 'complex' directory...")
        shutil.rmtree("complex")
        os.makedirs("complex")

    # 2. Clean 'receptor' directory
    print("[-] Cleaning 'receptor' folder...")
    if os.path.exists("receptor"):
        for f in os.listdir("receptor"):
            f_path = os.path.join("receptor", f)
            # Delete intermediate processing files
            if f.endswith("_clean.pdb") or f == "protein_processed.gro" or f.startswith("step"):
                print(f"    Deleting: {f}")
                os.remove(f_path)

    # 3. Clean 'ligand' directory
    print("[-] Cleaning 'ligand' folder...")
    if os.path.exists("ligand"):
        # Extensions created by ACPYPE that are junk
        junk_exts = [".inpcrd", ".prmtop", ".frcmod", ".lib", ".div", ".log", ".out", ".ant", ".prm", ".rtf", ".inp"]

        for f in os.listdir("ligand"):
            f_path = os.path.join("ligand", f)

            # Remove ACPYPE directories
            if os.path.isdir(f_path) and (".acpype" in f or "MOL_AC" in f):
                shutil.rmtree(f_path)

            # Remove junk files
            elif os.path.isfile(f_path):
                _, ext = os.path.splitext(f)
                if ext in junk_exts or "sqm." in f:
                    print(f"    Deleting: {f}")
                    os.remove(f_path)

    # 4. Clean Main Directory (The Root)
    print("[-] Cleaning main directory...")
    for f in os.listdir("."):
        if os.path.isdir(f):
            continue # Skip folders (like 'receptor', 'ligand')

        # If it's a script or input, SKIP IT
        if is_safe(f):
            continue

        # Delete typical GROMACS junk
        if f.startswith("#") or f.startswith("step") or f == "mdout.mdp" or f.endswith(".log"):
            print(f"    Deleting: {f}")
            os.remove(f)

    print("[-] RESET COMPLETE. All Python scripts and Basal inputs preserved.")

if __name__ == "__main__":
    print("WARNING: This will delete ALL simulation data in 'complex/'.")
    print("It effectively factory-resets the project.")
    confirm = input("Are you sure? (yes/no): ")
    if confirm.lower() == "yes":
        cleanup()
    else:
        print("Aborted.")
