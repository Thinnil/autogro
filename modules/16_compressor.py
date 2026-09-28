import subprocess
_orig_run = subprocess.run
def _safe_run(*args, **kwargs):
    kwargs.setdefault("check", True)
    return _orig_run(*args, **kwargs)
subprocess.run = _safe_run

def log_pipeline_msg(step_name, msg, is_error=False):
    import os
    with open("../pipeline_report.txt" if os.path.basename(os.getcwd()) == "complex" else "pipeline_report.txt", "a") as log_f:
        prefix = "[ERROR]" if is_error else "[INFO]"
        log_f.write(f"{prefix} {step_name}: {msg}\n")
import os
import tarfile
import shutil

# --- CONFIGURATION ---
work_dir = "complex"

# --- HELPER: GET FOLDER SIZE ---
def _get_size(path):
    total = 0
    with os.scandir(path) as it:
        for entry in it:
            if entry.is_file(follow_symlinks=False):
                total += entry.stat(follow_symlinks=False).st_size
            elif entry.is_dir(follow_symlinks=False):
                total += _get_size(entry.path)
    return total

def get_size_mb(path):
    """Calculates size of file or folder in Megabytes."""
    if os.path.isfile(path):
        return os.path.getsize(path) / (1024 * 1024)
    elif os.path.isdir(path):
        return _get_size(path) / (1024 * 1024)
    return 0

# --- MAIN SCRIPT ---
def compress_folder():
    if not os.path.exists(work_dir):
        print(f"[!] Directory '{work_dir}' not found.")
        return

    print(f"[-] Scanning '{work_dir}' for subfolders to compress...")

    subfolders = [f for f in os.listdir(work_dir) if os.path.isdir(os.path.join(work_dir, f))]

    if not subfolders:
        print("    No subfolders found. Have you organized the folder yet?")
        print("    (Run 15_organize_folder.py first)")
        return

    total_saved = 0

    for folder in subfolders:
        folder_path = os.path.join(work_dir, folder)
        # SKIP Analysis/Results (but compress replicas inside them!)
        if "Results" in folder or "Analysis" in folder:
            print(f"    [SKIP] Preserving '{folder}', but checking for replicas inside...")
            # Compress replicas inside Results
            res_folders = [
                f for f in os.listdir(folder_path)
                if os.path.isdir(os.path.join(folder_path, f)) and f.startswith("replica_")
            ]
            for res_f in res_folders:
                rep_path = os.path.join(folder_path, res_f)
                arc_name = os.path.join(folder_path, f"{res_f}.tar")
                orig_s = get_size_mb(rep_path)

                # Move .pdb and .xtc OUT of the replica folder so they aren't hidden in the zip!
                os.makedirs(os.path.join(folder_path, "Ensemble"), exist_ok=True)
                for file_in_rep in os.listdir(rep_path):
                    if file_in_rep.endswith(".pdb") or file_in_rep.endswith(".xtc"):
                        os.rename(
                            os.path.join(rep_path, file_in_rep),
                            os.path.join(folder_path, "Ensemble", file_in_rep)
                        )

                # Now compress the heavy stuff left behind
                print(f"    -> Compressing '{res_f}' ({orig_s:.1f} MB)...")
                try:
                    with tarfile.open(arc_name, "w") as tar:
                        tar.add(rep_path, arcname=res_f)
                    comp_s = get_size_mb(arc_name)
                    saved = orig_s - comp_s
                    total_saved += saved
                    print(f"       Done. Saved {saved:.1f} MB")
                    shutil.rmtree(rep_path)
                except Exception as e:
                    print(f"    [!] Error compressing {res_f}: {e}")
            continue

        archive_name = os.path.join(work_dir, f"{folder}.tar")

        # 1. Measure Original Size
        original_size = get_size_mb(folder_path)

        print(f"    -> Compressing '{folder}' ({original_size:.1f} MB)...")

        try:
            # 2. Compress
            with tarfile.open(archive_name, "w") as tar:
                tar.add(folder_path, arcname=folder)

            # 3. Measure Compressed Size
            compressed_size = get_size_mb(archive_name)

            # 4. Calculate Savings
            saved = original_size - compressed_size
            percent = (saved / original_size) * 100 if original_size > 0 else 0
            total_saved += saved

            print(f"       Done. Size: {compressed_size:.1f} MB (Saved {saved:.1f} MB / {percent:.0f}%)")

            # 5. Delete Original
            shutil.rmtree(folder_path)

        except Exception as e:
            print(f"    [!] Error compressing {folder}: {e}")

    # Clean up huge .trr files if they are loose in the root
    for f in os.listdir(work_dir):
        if f.endswith(".trr"):
            print(f"    [TIP] Loose heavy file found: '{f}'. Delete manually if not needed.")

    print("-" * 40)
    print(f"[-] Compression complete.")
    print(f"[-] TOTAL SPACE SAVED: {total_saved:.1f} MB")

if __name__ == "__main__":
    compress_folder()
log_pipeline_msg("Step 16", "OK")
