import tkinter as tk
from tkinter import ttk, messagebox
import subprocess
import json
import os
import shutil
import time

class RootSession:
    """
    Gère un shell root persistent
    """
    def __init__(self):
        self.process = None

    def start(self):
        """Lance le shell root via pkexec. Bloquant tant que le mot de passe n'est pas saisi."""
        try:
            self.process = subprocess.Popen(
                ['pkexec', '/bin/sh'],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=0
            )

            return self.run("echo 'ROOT_ACCESS_OK'")
        except Exception as e:
            print(f"Erreur start root: {e}")
            self.stop()
            return False

    def run(self, cmd_str):
        """Exécute une commande dans le shell root existant et retourne le résultat."""
        if not self.process or self.process.poll() is not None:
            return False, "Shell root fermé", ""

        delimiter = "___CMD_DONE___"

        try:
            full_cmd = f"{cmd_str}; echo '{delimiter}'; echo $?\n"
            self.process.stdin.write(full_cmd)
            self.process.stdin.flush()

            output_lines = []
            return_code = -1

            while True:
                line = self.process.stdout.readline()
                if not line: break

                stripped = line.strip()

                if stripped == delimiter:
                    code_line = self.process.stdout.readline()
                    if code_line:
                        return_code = int(code_line.strip())
                    break
                else:
                    output_lines.append(stripped)

            stdout_str = "\n".join(output_lines)

            return (return_code == 0), stdout_str, ""

        except Exception as e:
            return False, "", str(e)

    def stop(self):
        """Tue le processus root."""
        if self.process:
            try:
                self.process.terminate()
                self.process.wait(timeout=1)
            except:
                pass
            self.process = None

class YubiKeyManager:
    def __init__(self, root):
        self.root = root
        self.root.title("Gestionnaire YubiKeys")
        self.root.geometry("1050x1000")

        style = ttk.Style()
        style.theme_use('clam')

        self.root_session = RootSession()
        self.admin_unlocked = False

        self.is_started_as_root = (os.geteuid() == 0)
        if self.is_started_as_root:
            messagebox.showinfo("Info", "Script lancé en root.\nLe système de verrouillage est désactivé.")
            self.admin_unlocked = True

        self.setup_ui()
        self.tab_control.bind("<<NotebookTabChanged>>", self.on_tab_changed)

        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

    def on_close(self):
        self.root_session.stop()
        self.root.destroy()

    def setup_ui(self):
        self.tab_control = ttk.Notebook(self.root)

        self.tab_user = ttk.Frame(self.tab_control)
        self.tab_admin = ttk.Frame(self.tab_control)

        self.tab_control.add(self.tab_user, text='Espace Utilisateur')
        self.tab_control.add(self.tab_admin, text='Espace Admin')
        self.tab_control.pack(expand=1, fill="both")

        self.build_user_tab()

        self.frame_admin_auth = ttk.Frame(self.tab_admin)
        self.frame_admin_auth.pack(fill="both", expand=True)

        self.frame_admin_tools = ttk.Frame(self.tab_admin)

        self.build_admin_auth_ui()
        self.build_admin_tools_ui()

        ttk.Separator(self.root, orient='horizontal').pack(fill='x', pady=5)
        self.log_text = tk.Text(self.root, height=7, state="disabled", bg="#f0f0f0", font=("Consolas", 9))
        self.log_text.pack(fill="x", padx=10, pady=(0, 10))

    def on_tab_changed(self, event):
        selected_tab = event.widget.select()
        tab_text = event.widget.tab(selected_tab, "text")

        if "Utilisateur" in tab_text:
            if not self.is_started_as_root and self.admin_unlocked:
                self.lock_admin()

    def lock_admin(self):
        self.admin_unlocked = False
        self.root_session.stop()
        self.log("Session Root fermée.")

        self.frame_admin_tools.pack_forget()
        self.frame_admin_auth.pack(fill="both", expand=True)
        self.tab_control.tab(1, text='Espace Admin')
        self.combo_disk.set('')
        self.combo_disk['values'] = []

    def unlock_admin(self):
        self.log("Demande d'accès Root (regardez les pop-ups)...")
        self.root.update()

        success, out, _ = self.root_session.start()

        if success and "ROOT_ACCESS_OK" in out:
            self.admin_unlocked = True
            self.frame_admin_auth.pack_forget()
            self.frame_admin_tools.pack(fill="both", expand=True)
            self.tab_control.tab(1, text='Espace Admin (Ouvert)')
            self.log("Accès Root.")

            self.refresh_disks()
        else:
            self.log("Échec authentification.")
            messagebox.showerror("Erreur", "Mot de passe incorrect ou annulé.")

    def create_pwd_entry(self, parent, label, row, col=1):
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="e", padx=5, pady=5)
        f = ttk.Frame(parent)
        f.grid(row=row, column=col, sticky="w", padx=5)
        e = ttk.Entry(f, show="*", width=22)
        e.pack(side="left")
        ttk.Button(f, text="voir", width=5, command=lambda: e.config(show="" if e['show']=="*" else "*")).pack(side="left")
        return e

    def build_user_tab(self):
        frame = ttk.LabelFrame(self.tab_user, text="Modification du code PIN Standard (FIDO + PIV)", padding=20)
        frame.pack(fill="both", expand=True, padx=20, pady=20)

        self.u_old = self.create_pwd_entry(frame, "Ancien PIN :", 1)
        self.u_new = self.create_pwd_entry(frame, "Nouveau PIN :", 2)
        self.u_conf = self.create_pwd_entry(frame, "Confirmer PIN :", 3)
        ttk.Button(frame, text="Valider", command=self.user_change_pin).grid(row=4, columnspan=2, pady=20)

    def build_admin_auth_ui(self):
        c = ttk.Frame(self.frame_admin_auth)
        c.place(relx=0.5, rely=0.5, anchor="center")
        tk.Label(c, text="!", font=("Arial", 60)).pack()
        ttk.Label(c, text="Zone Admin sécurisée.\nAuthentification requise.", justify="center").pack(pady=10)
        ttk.Button(c, text="Déverrouiller", command=self.unlock_admin).pack(ipadx=20, ipady=10)

    def build_admin_tools_ui(self):
        # --- Section 1: Enrôlement ---
        f1 = ttk.LabelFrame(self.frame_admin_tools, text="1. Disques & Chiffrement", padding=10)
        f1.pack(fill="x", padx=10, pady=5)

        # Sélection du disque
        d_frame = ttk.Frame(f1); d_frame.pack(fill="x", pady=(0, 10))
        self.combo_disk = ttk.Combobox(d_frame, state="readonly", width=80); self.combo_disk.pack(side="left")
        ttk.Button(d_frame, text="rafraichir", width=9, command=self.refresh_disks).pack(side="left", padx=5)

        # Choix Méthode d'autorisation
        auth_frame = ttk.LabelFrame(f1, text="Autorisation pour l'ajout", padding=5)
        auth_frame.pack(fill="x", pady=5)

        self.var_auth_method = tk.StringVar(value="password")

        # Radio 1 : Mot de passe
        r_pwd = ttk.Radiobutton(auth_frame, text="Mot de Passe Disque (Passphrase)", variable=self.var_auth_method, value="password", command=self.toggle_enroll_ui)
        r_pwd.grid(row=0, column=0, sticky="w", padx=5)

        # Champ mot de passe
        self.frame_enroll_pwd = ttk.Frame(auth_frame)
        self.frame_enroll_pwd.grid(row=0, column=1, sticky="w", padx=10)
        self.entry_enroll_pwd = ttk.Entry(self.frame_enroll_pwd, show="*", width=20)
        self.entry_enroll_pwd.pack(side="left")
        ttk.Button(self.frame_enroll_pwd, text="voir", width=4, command=lambda: self.entry_enroll_pwd.config(show="" if self.entry_enroll_pwd['show']=="*" else "*")).pack(side="left")

        # Radio 2 : YubiKey existante
        r_yubi = ttk.Radiobutton(auth_frame, text="YubiKey Déjà Enrôlée (Autorisation FIDO)", variable=self.var_auth_method, value="yubikey", command=self.toggle_enroll_ui)
        r_yubi.grid(row=1, column=0, columnspan=2, sticky="w", padx=5, pady=5)

        ttk.Button(f1, text="Enroller NOUVELLE YubiKey", command=self.admin_enroll).pack(pady=10)

        # --- Section 2: PIN ---
        f2 = ttk.LabelFrame(self.frame_admin_tools, text="2. PIN", padding=10)
        f2.pack(fill="x", padx=10, pady=5)

        c_frame = ttk.Frame(f2); c_frame.grid(row=0, columnspan=2, sticky="w")
        self.var_do_fido = tk.BooleanVar(value=True); ttk.Checkbutton(c_frame, text="FIDO2", variable=self.var_do_fido).pack(side="left")
        self.var_do_piv = tk.BooleanVar(value=True); ttk.Checkbutton(c_frame, text="PIV", variable=self.var_do_piv).pack(side="left", padx=10)
        self.var_def_pin = tk.BooleanVar(); ttk.Checkbutton(c_frame, text="Defaut (123456)", variable=self.var_def_pin, command=lambda: self.toggle_def(self.adm_old, "123456", self.var_def_pin)).pack(side="left", padx=20)

        self.adm_old = self.create_pwd_entry(f2, "Ancien :", 1)
        self.adm_new = self.create_pwd_entry(f2, "Nouveau :", 2)
        self.adm_conf = self.create_pwd_entry(f2, "Confirmer :", 3)
        ttk.Button(f2, text="Appliquer", command=self.admin_change_pin).grid(row=4, columnspan=2, pady=10)

        # --- Section 3: PUK ---
        f3 = ttk.LabelFrame(self.frame_admin_tools, text="3. PUK (Déblocage)", padding=10)
        f3.pack(fill="x", padx=10, pady=5)
        self.var_def_puk = tk.BooleanVar()
        ttk.Checkbutton(f3, text="Defaut (12345678)", variable=self.var_def_puk, command=lambda: self.toggle_def(self.puk_old, "12345678", self.var_def_puk)).grid(row=0, columnspan=2, sticky="w")

        self.puk_old = self.create_pwd_entry(f3, "Ancien PUK :", 1)
        self.puk_new = self.create_pwd_entry(f3, "Nouveau PUK :", 2)
        self.puk_conf = self.create_pwd_entry(f3, "Confirmer PUK :", 3)
        ttk.Button(f3, text="Changer PUK", command=self.admin_change_puk).grid(row=4, columnspan=2, pady=10)

    def toggle_enroll_ui(self):
        if self.var_auth_method.get() == "password":
            self.entry_enroll_pwd.config(state='normal')
            self.frame_enroll_pwd.grid()
        else:
            self.entry_enroll_pwd.delete(0, tk.END)
            self.frame_enroll_pwd.grid_remove()

    def toggle_def(self, entry, val, var):
        if var.get(): entry.delete(0, tk.END); entry.insert(0, val)
        else: entry.delete(0, tk.END)


    def log(self, msg):
        self.log_text.config(state="normal")
        self.log_text.insert(tk.END, f"> {msg}\n")
        self.log_text.see(tk.END)
        self.log_text.config(state="disabled")

    def run_user_cmd(self, cmd, input_str=None):
        try:
            p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            o, e = p.communicate(input=input_str)
            return p.returncode, o, e
        except Exception as ex: return -1, "", str(ex)

    def check_pin(self, p1, p2, type="PIN"):
        if len(p1) != 8 or not p1.isdigit(): return False, f"{type} invalide (8 chiffres requis)"
        if p1 != p2: return False, "Confirmation incorrecte"
        return True, ""

    def user_change_pin(self):
        old, new, conf = self.u_old.get(), self.u_new.get(), self.u_conf.get()
        ok, msg = self.check_pin(new, conf)
        if not ok: return messagebox.showwarning("Erreur", msg)

        self.log("--- Utilisateur : Update Global ---")
        c, o, e = self.run_user_cmd(["ykman", "fido", "access", "change-pin"], f"{old}\n{new}\n{new}\n")
        if c != 0: return messagebox.showerror("Echec FIDO", "Vérifiez l'ancien code.")

        c2, o2, e2 = self.run_user_cmd(["ykman", "piv", "access", "change-pin"], f"{old}\n{new}\n{new}\n")
        if c2 == 0:
            messagebox.showinfo("Succès", "PIN modifié partout.")
            self.u_old.delete(0, tk.END); self.u_new.delete(0, tk.END); self.u_conf.delete(0, tk.END)
        else: messagebox.showwarning("Partiel", "FIDO OK, mais erreur PIV.")

    # --- ADMIN ACTIONS VIA ROOT SESSION ---

    def refresh_disks(self):
        if not self.admin_unlocked: return
        self.log("Scan des disques (Root)...")

        cmd = "lsblk -J -a -o NAME,FSTYPE,PATH,MOUNTPOINT,LABEL,TYPE"
        success, json_str, err = self.root_session.run(cmd)

        if success:
            try:
                data = json.loads(json_str)
                items = []
                def scan(devs):
                    for d in devs:
                        path = d.get("path")
                        if not path or d.get("type") in ["loop", "rom"]: continue
                        fstype = d.get("fstype"); label = d.get("label"); mount = d.get("mountpoint")
                        desc = path
                        if fstype == "crypto_LUKS": desc += " [LUKS]"
                        elif fstype: desc += f" ({fstype})"
                        if label: desc += f" [{label}]"
                        if mount: desc += f" -> {mount}"
                        items.append(desc)
                        if "children" in d: scan(d["children"])
                scan(data.get("blockdevices", []))
                self.combo_disk['values'] = items
                if items: self.combo_disk.current(0)
                self.log(f"Disques trouvés: {len(items)}")
            except: self.log("Erreur parsing JSON disques.")
        else:
            self.log(f"Erreur lsblk: {err}")

    def admin_enroll(self):
        sel = self.combo_disk.get()
        if not sel: return
        dev = sel.split(" ")[0]

        auth_method = self.var_auth_method.get()

        cmd_base = f"systemd-cryptenroll {dev} --fido2-device=auto --fido2-with-client-pin=true --fido2-with-user-presence=true"

        if auth_method == "password":
            pwd = self.entry_enroll_pwd.get()
            if not pwd:
                return messagebox.showwarning("Erreur", "Veuillez saisir le mot de passe du disque.")

            self.log(f"Enrôlement sur {dev} avec Mot de Passe...")
            full_cmd = f"CRYPTENROLL_PASSWORD='{pwd}' {cmd_base}"

        else:
            self.log(f"Enrôlement sur {dev} avec AUTRE YUBIKEY...")
            self.log("ATTENTION : Touchez d'abord la clé DÉJÀ ENRÔLÉE (quand ça clignote)...")
            self.log("...puis touchez la NOUVELLE clé.")
            full_cmd = f"{cmd_base} --unlock-fido2-device=auto"

        success, out, err = self.root_session.run(full_cmd)

        if success:
            self.log("Enrôlement OK.")
            messagebox.showinfo("Succès", "Nouvelle YubiKey associée au disque.")
            self.entry_enroll_pwd.delete(0, tk.END)
        else:
            self.log(f"Erreur: {out}")
            messagebox.showerror("Erreur", "Échec enrôlement.\nVérifiez le mot de passe ou l'ordre des clés.")

    def admin_change_pin(self):
        if not (self.var_do_fido.get() or self.var_do_piv.get()): return
        old, new, conf = self.adm_old.get(), self.adm_new.get(), self.adm_conf.get()
        ok, msg = self.check_pin(new, conf)
        if not ok: return messagebox.showerror("Erreur", msg)

        if self.var_do_fido.get():
            cmd = f"printf '{old}\\n{new}\\n{new}\\n' | ykman fido access change-pin"
            s, o, e = self.root_session.run(cmd)
            if not s: return messagebox.showerror("Erreur FIDO", "Echec FIDO (Admin)")
            self.log("FIDO Modifié (Admin).")

        if self.var_do_piv.get():
            cmd = f"printf '{old}\\n{new}\\n{new}\\n' | ykman piv access change-pin"
            s, o, e = self.root_session.run(cmd)
            if not s: return messagebox.showerror("Erreur PIV", "Echec PIV (Admin)")
            self.log("PIV Modifié (Admin).")

        messagebox.showinfo("Succès", "OK.")
        self.adm_new.delete(0, tk.END); self.adm_conf.delete(0, tk.END)

    def admin_change_puk(self):
        old, new, conf = self.puk_old.get(), self.puk_new.get(), self.puk_conf.get()
        ok, msg = self.check_pin(new, conf, "PUK")
        if not ok: return messagebox.showerror("Erreur", msg)

        cmd = f"printf '{old}\\n{new}\\n{new}\\n' | ykman piv access change-puk"
        s, o, e = self.root_session.run(cmd)
        if s:
            self.log("PUK modifié.")
            messagebox.showinfo("Succès", "PUK changé.")
            self.puk_new.delete(0, tk.END); self.puk_conf.delete(0, tk.END)
        else:
            messagebox.showerror("Erreur", "Echec changement PUK.")

if __name__ == "__main__":
    root = tk.Tk()
    app = YubiKeyManager(root)
    root.mainloop()
