import re
text = open("install.sh").read()
text = text.replace('print("\n[-] Launching Multi-Replica Ensemble MDRun in background...")', 'print("\\n[-] Launching Multi-Replica Ensemble MDRun in background...")')
open("install.sh", "w").write(text)
