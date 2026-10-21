# SPDX-FileCopyrightText: 2026 Pauline Legrand <pauline.legrand@numerique.gouv.fr>
# SPDX-FileContributor: 2026 Fabien VANEENOO <fabien.vaneenoo.ext@numerique.gouv.fr>
# SPDX-FileContributor: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>
# SPDX-FileContributor: 2026 Xavier Maso <xavier.maso.ext@numerique.gouv.fr>
# SPDX-FileContributor: 2026 Lucas Desgouilles <lucas.desgouilles@numerique.gouv.fr>
#
# SPDX-License-Identifier: MIT

set -o errexit -o nounset -o pipefail

log_journal() {
  echo "[$(date -Iseconds)] [$1] $2"
  logger -t securix-telemetry-report -p "user.$1" "$2" 2>/dev/null || true
}

: "${DRY_RUN=0}"

declare -A fields=()

set -o xtrace +o errexit +o pipefail

fields["currentDate"]=$( date -Iseconds )

fields["user"]=$( getent group video | cut -d ':' -f 4 )
fields["hostName"]=$( hostname )

fields["chassisSerial"]=$( dmidecode --string chassis-serial-number || dmidecode --string system-serial-number )
fields["chassisFamily"]=$( dmidecode --string system-family || dmidecode --string system-version )

fields["energyCapacity"]=$( acpi --battery --details | grep "Battery 0:" | tail -n 1 )

fields["displayResolution"]=$( cat /sys/class/drm/card*-eDP-*/modes | sort --numeric-sort --reverse | uniq | head -n 1 )

current_gen=$( nixos-rebuild list-generations --json | jq '.[] | select(.current == true)' )

fields["nixosBuildDate"]=$( jq -r '.date' <<< "$current_gen" )
fields["nixosVersion"]=$( jq -r '.nixosVersion' <<< "$current_gen" )
fields["kernelVersion"]=$( jq -r '.kernelVersion' <<< "$current_gen" )

fields["generationCount"]=$( nixos-rebuild list-generations --json | jq 'length' )

fields["bootTime"]=$( systemctl show -p KernelTimestamp --value )

fields["rootfsCapacity"]=$( df -h --output=size / | tail -n+2 )
fields["rootfsUse"]=$( df -h --output=used,pcent / | tail -n+2 )
fields["espCapacity"]=$( df -h --output=size /boot | tail -n+2 )
fields["espUse"]=$( df -h --output=used,pcent /boot | tail -n+2 )

fields["secureBoot"]=$( sbctl status --json | jq -r '
  if .secure_boot and .installed and (.setup_mode | not) then
    "OK"
  else
    del(.guid, .firmware_quirks) | @json | gsub("[\"{}]"; "")
  end
' )

set +o xtrace -o errexit -o pipefail

args=()
for key in "${!fields[@]}"; do
  args+=(--arg "$key" "${fields[$key]}")
done

PAYLOAD=$(jq -n  '{ records: [{ fields: $ARGS.named }]}' "${args[@]}")

if [ "$DRY_RUN" = 1 ]; then
  echo "$PAYLOAD"
  exit 0
fi

if [ -z ${GRIST_URL+x} ]; then
  log_journal "err" "Échec : Vous n'avez pas fourni l'URL pour enregistrer dans Grist"
  exit 1
fi

log_journal "info" "Envoi vers Grist"

if ! [ -z ${HTTPS_PROXY+x} ]; then
  log_journal "info" "Proxy détecté : $HTTPS_PROXY"
  exit 1
fi

RESPONSE=$(curl --silent --fail --write-out "\n%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$GRIST_URL" || echo -e "\n000")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
  log_journal "info" "Succès : Enregistrement Grist terminé (HTTP $HTTP_CODE)."
elif [ "$HTTP_CODE" -eq 0 ]; then
  log_journal "err" "Échec de l'enregistrement Grist. La commande curl a échoué : $RESPONSE"
  exit 1
else
  log_journal "err" "Échec de l'enregistrement Grist. Code HTTP : $HTTP_CODE. Réponse : $BODY"
  exit 1
fi
