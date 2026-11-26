#!/usr/bin/env bash
#MISE hide=true
#USAGE arg "<file>" var=#true help="SOPS files to check"
set -euo pipefail

# Lists the values and comments sops should have encrypted but are plain
# text, e.g. a key added to an encrypted file without sops. Like sops, a value
# is in scope when any key on its path matches the document's
# encrypted_regex or encrypted_suffix, or when none matches unencrypted_regex
# or unencrypted_suffix (default "_unencrypted"). Suffixes are literal strings,
# quoted as \Q...\E with QE re-adding any "\E" they contain. Comments belong
# to the enclosing map or list, and sops writes them as #ENC[...]. With
# encrypted_comment_regex or unencrypted_comment_regex the comments decide, so
# those documents are skipped. sops leaves empty strings and nulls as they
# are. A document without metadata is listed by its number. Each step after a
# select starts from "." because yq emits a literal or [...] even when the
# select matched nothing.
read -r -d '' plaintext <<'EOF' || true
select(tag == "!!map" and (has("sops") | not)) | "document " + (document_index + 1 | tostring)
,
select(tag == "!!map" and has("sops"))
| .sops as $sops | del(.sops)
| ($sops.encrypted_regex // "") as $er
| ($sops.unencrypted_regex // "") as $ur
| ($sops.encrypted_suffix // "") as $es
| ($sops.unencrypted_suffix // "") as $us
| select(($sops.encrypted_comment_regex // "") + ($sops.unencrypted_comment_regex // "") == "")
| (if $er != "" then $er
   elif $ur != "" then $ur
   else "\\Q" + ((if $es != "" then $es elif $us != "" then $us else "_unencrypted" end) | split("\\E") | join(strenv(QE))) + "\\E$"
   end) as $re
| ($er + $es != "") as $match
| (if document_index == 0 then "" else "document " + (document_index + 1 | tostring) + ": " end) as $doc
| (
    (.. | select(tag != "!!map" and tag != "!!seq" and tag != "!!null" and . != "")
      | select(if tag == "!!str" then (test("^ENC\[") | not) else true end)
      | path
      | select((map(select(tag == "!!str")) | any_c(test($re))) == $match)
      | map(if tag == "!!int" then "[" + tostring + "]" elif test("^[A-Za-z0-9_-]+$") then "." + . else "[\"" + . + "\"]" end) | join("")),
    (... | select((head_comment + "\n" + line_comment + "\n" + foot_comment) | split("\n") | map(select(test("^#? ?(ENC\[.*)?$") | not)) | length > 0)
      | (if tag == "!!map" then path elif tag == "!!seq" then path else path | .[:-1] end)
      | select((map(select(tag == "!!str")) | any_c(test($re))) == $match)
      | map(if tag == "!!int" then "[" + tostring + "]" elif test("^[A-Za-z0-9_-]+$") then "." + . else "[\"" + . + "\"]" end) | join("")
      | sub("^[.]"; "") | sub("^$"; "document root") | sub("^"; "comment in "))
  )
| sub("^[.]"; "") | sub("^"; $doc)
EOF

# sops metadata alone does not mean the values are encrypted: a file without
# data/stringData gets metadata and a MAC but no other ENC[] value.
rc=0
for f in "$@"; do
    if ! sops filestatus "$f" 2>/dev/null | jq --exit-status '.encrypted == true' >/dev/null; then
        mise run //:log error "File is not encrypted" file "$f"
        rc=1
    elif ! awk '/ENC\[/ && !/^[[:space:]]*"?(sops_)?mac"?[[:space:]]*[:=]/ { found = 1; exit } END { exit !found }' < "$f"; then
        mise run //:log error "File has no encrypted values, only data and stringData are encrypted" file "$f"
        rc=1
    elif [[ "$f" =~ \.(ya?ml|json)$ ]]; then
        if ! leaks="$(QE='\E\\E\Q' yq --no-doc --unwrapScalar "$plaintext" "$f" | awk '!seen[$0]++')"; then
            mise run //:log error "Failed to parse file" file "$f"
            rc=1
        elif [[ -n "$leaks" ]]; then
            mise run //:log error "File has plain text values, remove them from the file and add them again with sops edit" file "$f" values "${leaks//$'\n'/, }"
            rc=1
        fi
    fi
done
exit "$rc"
