#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
# SPDX-License-Identifier: MIT

# Parse les fichiers .nix de securix pour extraire les options mkOption

import re
import json
import sys
from pathlib import Path

def parse_type(type_str):
    """Convertit une expression de type Nix en dict JSON."""
    t = type_str.strip()
    if t == "types.bool":
        return {"kind": "bool"}
    elif t == "types.str" or t == "types.nonEmptyStr":
        return {"kind": "str"}
    elif t == "types.int" or t == "types.ints.positive":
        return {"kind": "int"}
    elif t == "types.path":
        return {"kind": "path"}
    elif t == "types.package":
        return {"kind": "package"}
    elif t.startswith("types.nullOr"):
        inner = re.sub(r"^types\.nullOr\s*", "", t).strip()
        return {"kind": "nullable", "inner": parse_type(inner)}
    elif t.startswith("types.listOf"):
        inner = re.sub(r"^types\.listOf\s*", "", t).strip()
        if inner.startswith("("):
            inner = inner[1:-1].strip()
        return {"kind": "list", "inner": parse_type(inner)}
    elif t.startswith("types.enum"):
        m = re.search(r'\[([^\]]+)\]', t)
        if m:
            raw = m.group(1)
            values = re.findall(r'"([^"]+)"', raw)
            return {"kind": "enum", "values": values}
        return {"kind": "enum", "values": []}
    elif t.startswith("types.attrsOf"):
        return {"kind": "attrsOf"}
    elif t.startswith("types.submodule"):
        return {"kind": "submodule"}
    return {"kind": "str"}

def extract_options_from_file(filepath, module_prefix):
    """Extrait les mkOption d'un fichier .nix avec leur chemin complet."""
    content = Path(filepath).read_text(encoding="utf-8")
    options = []

    i = 0
    lines = content.split('\n')
    option_stack = []
    in_options_block = False
    
    for line_no, line in enumerate(lines):
        stripped = line.strip()
        
        if re.match(r'options\.(' + module_prefix + r'\.\S+)\s*=\s*\{', stripped) or \
           re.match(r'options\.(' + module_prefix + r')\s*=\s*\{', stripped):
            in_options_block = True
            m = re.match(r'options\.(\S+)\s*=', stripped)
            if m:
                option_stack = [m.group(1)]

        m_inline_enable = re.match(
            r'options\.(' + module_prefix + r'\.\S+)\s*=\s*(?:lib\.)?mkEnableOption\s*(.*)',
            stripped
        )
        m_inline_option = re.match(
            r'options\.(' + module_prefix + r'\.\S+)\s*=\s*(?:lib\.)?mkOption\s*\{',
            stripped
        )

        if m_inline_enable:
            full_path = m_inline_enable.group(1)
            desc_part = m_inline_enable.group(2).strip().strip(';')
            desc = None
            m_desc = re.match(r'^"([^"]+)"', desc_part)
            if m_desc:
                desc = m_desc.group(1)
            opt = {
                "path": full_path,
                "internal": False,
                "visible": True,
                "hasDefault": True,
                "default": False,
                "type": {"kind": "bool"},
                "description": desc,
                "example": None,
                "isEnable": True,
                "enableGroup": None,
            }
            options.append(opt)
            continue

        if m_inline_option:
            full_path = m_inline_option.group(1)
            block_lines = []
            depth = 1
            j = line_no + 1
            while j < len(lines) and depth > 0:
                l = lines[j]
                depth += l.count('{') - l.count('}')
                block_lines.append(l)
                j += 1
            block = '\n'.join(block_lines)

            opt = {"path": full_path, "internal": False, "visible": True, "hasDefault": False,
                   "isEnable": False, "enableGroup": None}

            m_type = re.search(r'type\s*=\s*((?:lib\.)?types\.[^;]+);', block)
            if m_type:
                type_str = m_type.group(1).strip().replace('lib.', '')
                opt["type"] = parse_type(type_str)
            else:
                opt["type"] = {"kind": "str"}

            m_desc2 = re.search(r'description\s*=\s*(?:lib\.mdDoc\s*)?(?:\'\'(.*?)\'\'|"([^"]+)")', block, re.DOTALL)
            if m_desc2:
                opt["description"] = (m_desc2.group(1) or m_desc2.group(2) or "").strip()
            else:
                opt["description"] = None

            m_ex = re.search(r'example\s*=\s*"([^"]+)"', block)
            opt["example"] = m_ex.group(1) if m_ex else None

            m_def = re.search(r'default\s*=\s*"([^"]+)"', block)
            if m_def:
                opt["default"] = m_def.group(1); opt["hasDefault"] = True
            elif re.search(r'default\s*=\s*null', block):
                opt["default"] = None; opt["hasDefault"] = True
            elif re.search(r'default\s*=\s*\[\s*\]', block):
                opt["default"] = []; opt["hasDefault"] = True
            elif re.search(r'default\s*=\s*true', block):
                opt["default"] = True; opt["hasDefault"] = True
            elif re.search(r'default\s*=\s*false', block):
                opt["default"] = False; opt["hasDefault"] = True
            else:
                opt["default"] = None

            if not opt["internal"] and opt["visible"]:
                options.append(opt)
            continue
        
        if not in_options_block:
            continue
            
        m_enable = re.match(r'(\w+)\s*=\s*(?:lib\.)?mkEnableOption\s*', stripped)
        m = re.match(r'(\w+)\s*=\s*(?:lib\.)?mkOption\s*\{', stripped)

        if m_enable and option_stack:
            opt_name = m_enable.group(1)
            full_path = ".".join(option_stack + [opt_name])
            opt = {
                "path": full_path,
                "internal": False,
                "visible": True,
                "hasDefault": True,
                "default": False,
                "type": {"kind": "bool"},
                "description": None,
                "example": None,
                "isEnable": True,
                "enableGroup": None,
            }
            m_desc = re.search(r'mkEnableOption\s+"([^"]+)"', stripped)
            if not m_desc:
                m_desc = re.search(r"mkEnableOption\s+''([^']+)''", stripped)
            if m_desc:
                opt["description"] = m_desc.group(1)
            if not opt["internal"] and opt["visible"]:
                options.append(opt)
            continue
        if m and option_stack:
            opt_name = m.group(1)
            full_path = ".".join(option_stack + [opt_name])
            
            block_lines = []
            depth = 1
            j = line_no + 1
            while j < len(lines) and depth > 0:
                l = lines[j]
                depth += l.count('{') - l.count('}')
                block_lines.append(l)
                j += 1
            block = '\n'.join(block_lines)
            
            opt = {"path": full_path, "internal": False, "visible": True, "hasDefault": False}
            
            m_type = re.search(r'type\s*=\s*(types\.[^;]+);', block)
            if m_type:
                opt["type"] = parse_type(m_type.group(1).strip())
            else:
                opt["type"] = {"kind": "str"}
            
            m_desc = re.search(r"description\s*=\s*(?:lib\.mdDoc\s*)?(?:''(.*?)''|\"([^\"]+)\")", block, re.DOTALL)
            if m_desc:
                opt["description"] = (m_desc.group(1) or m_desc.group(2) or "").strip()
            else:
                opt["description"] = None
            
            m_ex = re.search(r'example\s*=\s*"([^"]+)"', block)
            if m_ex:
                opt["example"] = m_ex.group(1)
            else:
                opt["example"] = None
            
            m_def = re.search(r'default\s*=\s*"([^"]+)"', block)
            if m_def:
                opt["default"] = m_def.group(1)
                opt["hasDefault"] = True
            elif re.search(r'default\s*=\s*null', block):
                opt["default"] = None
                opt["hasDefault"] = True
            elif re.search(r'default\s*=\s*\[\s*\]', block):
                opt["default"] = []
                opt["hasDefault"] = True
            elif re.search(r'default\s*=\s*true', block):
                opt["default"] = True
                opt["hasDefault"] = True
            elif re.search(r'default\s*=\s*false', block):
                opt["default"] = False
                opt["hasDefault"] = True
            else:
                opt["default"] = None
            
            if re.search(r'internal\s*=\s*true', block):
                opt["internal"] = True
            if re.search(r'visible\s*=\s*false', block):
                opt["visible"] = False
            
            if not opt["internal"] and opt["visible"]:
                options.append(opt)
    
    return options

def detect_enable_groups(options):
    """
    Détecte les groupes qui ont un .enable et marque les autres options du groupe.
    Ex: securix.yubikey-reset.enable → le groupe 'securix.yubikey-reset' a un enable.
    Retourne un set de préfixes de groupe qui ont un enable.
    """
    enable_groups = set()
    for opt in options:
        if opt["path"].endswith(".enable"):
            prefix = opt["path"][:-len(".enable")]
            enable_groups.add(prefix)
    return enable_groups


def detect_repo_prefix(repo_path):
    """
    Détecte dynamiquement le préfixe d'options utilisé dans un repo
    (ex: 'bureautix', 'monprojet', ...) en excluant 'securix' et 'nixos'.
    Retourne le préfixe le plus fréquent, ou None si introuvable.
    """
    counts = {}
    for nix_file in Path(repo_path).rglob("*.nix"):
        try:
            content = nix_file.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        for line in content.split('\n'):
            m = re.match(r'\s*options\.(\w+)\.', line)
            if m:
                prefix = m.group(1)
                if prefix not in ('securix', 'nixos', 'lib', 'config', 'pkgs'):
                    counts[prefix] = counts.get(prefix, 0) + 1
    if not counts:
        return None
    return max(counts, key=counts.get)


def main():
    securix_src = Path(sys.argv[1])
    repo_src = Path(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else None

    scan_dirs = [
        (securix_src / "modules",   "securix"),
        (securix_src / "community", "securix"),
    ]

    if repo_src and repo_src.exists():
        repo_prefix = detect_repo_prefix(repo_src)
        if repo_prefix:
            scan_dirs.append((repo_src, repo_prefix))

    all_options = []
    seen_paths = set()

    for scan_dir, prefix in scan_dirs:
        if not scan_dir.exists():
            continue
        for nix_file in sorted(scan_dir.rglob("*.nix")):
            content = nix_file.read_text(encoding="utf-8", errors="replace")
            has_mkoption = "mkOption" in content or "mkEnableOption" in content
            has_options = f"options.{prefix}" in content
            if not has_mkoption or not has_options:
                continue
            try:
                opts = extract_options_from_file(nix_file, prefix)
                for opt in opts:
                    if opt["path"] not in seen_paths:
                        seen_paths.add(opt["path"])
                        all_options.append(opt)
            except Exception as e:
                print(f"Warning: {nix_file}: {e}", file=sys.stderr)

    enable_groups = detect_enable_groups(all_options)
    for opt in all_options:
        group = ".".join(opt["path"].split(".")[:-1])
        opt["enableGroup"] = group if group in enable_groups else None
        opt["isEnable"] = opt["path"].endswith(".enable")

    result = {
        "schemaVersion": 1,
        "options": all_options,
        "enableGroups": sorted(enable_groups),
    }
    print(json.dumps(result, ensure_ascii=False, separators=(',', ':')))

if __name__ == "__main__":
    main()