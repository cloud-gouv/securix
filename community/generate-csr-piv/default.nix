# SPDX-FileCopyrightText: 2026 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.securix.programs.generate-csr-piv;
  inherit (config.securix.self) user;

  script = pkgs.writeShellApplication {
    name = "generate-csr-piv";

    runtimeInputs = [
      pkgs.curl
      pkgs.jq
      pkgs.openssl
      pkgs.yubikey-manager
    ];

    runtimeEnv = {
      DEFAULT_USERNAME = toString user.username;
      DEFAULT_EMAIL = toString user.email;
      DEFAULT_ALGO = cfg.algorithm;
      SUBJ_OU = cfg.subject.organizationalUnit;
      SUBJ_O = cfg.subject.organization;
      SUBJ_C = cfg.subject.country;
      GRIST_URL = toString cfg.grist.url;
      GRIST_TABLE = cfg.grist.table;
      GRIST_COL_USERNAME = cfg.grist.col.username;
      GRIST_COL_CSR = cfg.grist.col.csr;
      OPENSSL_MODULES = "${pkgs.pkcs11-provider}/lib/ossl-modules";
      PKCS11_PROVIDER_MODULE = "${pkgs.yubico-piv-tool}/lib/libykcs11.so";
    };

    text = ''
      usage() {
        cat <<EOF
      Usage : generate-csr-piv [-u NOM] [-e EMAIL] [-a ALGO]
        -u  Nom d'utilisateur (défaut : ''${DEFAULT_USERNAME:-aucun})
        -e  Email du SAN (défaut : ''${DEFAULT_EMAIL:-aucun})
        -a  Algorithme de la clé si le slot 9a est vide (défaut : $DEFAULT_ALGO)
      EOF
      }

      username="$DEFAULT_USERNAME"
      email="$DEFAULT_EMAIL"
      algo="$DEFAULT_ALGO"

      while getopts "u:e:a:h" opt; do
        case "$opt" in
          u) username="$OPTARG" ;;
          e) email="$OPTARG" ;;
          a) algo="$OPTARG" ;;
          h) usage; exit 0 ;;
          *) usage; exit 2 ;;
        esac
      done

      # Sur un installateur générique, l'utilisateur n'est pas connu
      [ -n "$username" ] || read -rp "Nom d'utilisateur : " username
      [ -n "$email" ] || read -rp "Adresse email : " email

      if [ -z "$username" ] || [ -z "$email" ] || [[ "$username$email" == *[$'\n'=]* ]]; then
        echo "Nom d'utilisateur ou email invalide." >&2
        exit 2
      fi

      out="$HOME/Documents/$username-9a-$(date +%d-%m-%Y)-SAN.csr"
      conf="$(mktemp)"
      jar="$(mktemp)"

      cleanup() {
        code=$?
        rm -f "$conf" "$jar"
        [ "$code" -ne 0 ] && echo ">> Échec (code $code)."
        read -rsn1 -p "Appuyez sur une touche pour fermer..." _ || true
        echo
      }
      trap cleanup EXIT

      mkdir -p "$(dirname "$out")"

      if ! ykman piv keys info 9a &>/dev/null; then
        echo ">> Aucune clé sur le slot 9a : génération d'une clé $algo..."
        gen=(ykman piv keys generate --pin-policy ALWAYS --touch-policy NEVER -a "$algo" 9a /dev/null)
        if ykman piv info | grep -q 'Using default Management key!'; then
          echo "" | "''${gen[@]}"
        else
          echo ">> Saisissez votre clé de management :"
          "''${gen[@]}"
        fi
      fi

      cat >"$conf" <<EOF
      [req]
      distinguished_name = dn
      req_extensions = ext
      prompt = no
      utf8 = yes
      string_mask = utf8only
      [dn]
      CN = $username.0002
      OU = $SUBJ_OU
      O = $SUBJ_O
      C = $SUBJ_C
      [ext]
      subjectAltName = email:$email
      EOF

      RED='\033[0;31m'
      BOLD='\033[1m'
      YELLOW='\033[1;33m'
      NC='\033[0m'
      echo
      echo -e "''${YELLOW}''${BOLD}╔═══════════════════════════════════════════════╗''${NC}"
      echo -e "''${YELLOW}''${BOLD}║  ACTION REQUISE : GÉNÉRATION DU CERTIFICAT    ║''${NC}"
      echo -e "''${YELLOW}''${BOLD}╚═══════════════════════════════════════════════╝''${NC}"
      echo -e "''${BOLD}Saisissez votre code PIN pour la passphrase et le PIN.''${NC}"
      echo -e "''${RED}''${BOLD}Il ne s'affiche pas : utilisez MAJ + chiffre.''${NC}"
      echo

      openssl req \
        -provider-path "$OPENSSL_MODULES" -provider default -provider pkcs11 \
        -new -key "pkcs11:id=%01;type=private" \
        -out "$out" -config "$conf" -extensions ext

      echo ">> CSR générée : $out"

      [ -n "$GRIST_URL" ] || exit 0

      echo ">> Envoi de la CSR vers Grist..."
      att_id=$(curl -sS -c "$jar" -X POST "$GRIST_URL/attachments" \
        -H "X-Requested-With: XMLHttpRequest" -F "upload=@$out" | jq -r '.[0]')
      if [ -z "$att_id" ] || [ "$att_id" = "null" ]; then
        echo "Échec de l'upload de la pièce jointe." >&2
        exit 1
      fi

      payload=$(jq -n \
        --arg cu "$GRIST_COL_USERNAME" --arg cc "$GRIST_COL_CSR" \
        --arg u "$username" --argjson a "$att_id" \
        '{records:[{fields:{($cu):$u,($cc):["L",$a]}}]}')

      http_code=$(curl -sS -b "$jar" -o /dev/null -w "%{http_code}" -X POST \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$GRIST_URL/tables/$GRIST_TABLE/records") || true

      case "$http_code" in
        200 | 201) echo ">> Enregistrement Grist terminé." ;;
        *) echo "Échec de l'enregistrement Grist (HTTP $http_code)." >&2; exit 1 ;;
      esac

      rm -f "$out"
    '';
  };
in
{
  options.securix.programs.generate-csr-piv = {
    enable = lib.mkEnableOption "la génération de CSR depuis le slot PIV 9a d'une YubiKey";

    algorithm = lib.mkOption {
      type = lib.types.str;
      default = "RSA3072";
      description = "Algorithme par défaut. Surchargeable avec `-a`.";
    };

    subject = {
      organizationalUnit = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Attribut OU du DN.";
      };
      organization = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Attribut O du DN.";
      };
      country = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Attribut C du DN.";
      };
    };

    grist = {
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://grist.numerique.gouv.fr/o/docs/api/s/<id>";
        description = "URL de partage de l'API Grist. `null` : la CSR est seulement écrite dans ~/Documents.";
      };
      table = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Nom de la table Grist.";
      };
      col = {
        username = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Colonne Grist recevant le nom d'utilisateur.";
        };
        csr = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Colonne Grist (pièce jointe) recevant la CSR.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable { environment.systemPackages = [ script ]; };
}
