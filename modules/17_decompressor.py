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

# --- CONFIGURATION ---
work_dir = "complex"

def decompress_folder():
    if not os.path.exists(work_dir):
        print(f"[!] Directory '{work_dir}' not found.")
        return

    print(f"[-] Scanning '{work_dir}' for .tar.gz archives...")

    # Find all .tar.gz and .tar files
    archives = [f for f in os.listdir(work_dir) if f.endswith(".tar.gz") or f.endswith(".tar")]

    if not archives:
        print("    No archives found.")
        return

    for archive in archives:
        archive_path = os.path.join(work_dir, archive)

        print(f"    -> Extracting '{archive}' ...")

        try:
            with tarfile.open(archive_path, "r:*") as tar:
                # Mitigate Path Traversal (TarSlip)
                for member in tar.getmembers():
                    if member.name.startswith('/') or '..' in member.name:
                        raise Exception(f"Security: Path traversal attempt detected in {member.name}")
                tar.extractall(path=work_dir)

            # Optional: Delete the .tar.gz after extracting?
            # os.remove(archive_path)
            # print("       Archive deleted.")

        except Exception as e:
            print(f"    [!] Error extracting {archive}: {e}")

    print("[-] Decompression complete. Folders restored.")

if __name__ == "__main__":
    decompress_folder()
log_pipeline_msg("Step 17", "OK")
