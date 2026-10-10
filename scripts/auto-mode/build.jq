# build.jq — the bundled settings.json `autoMode` block: Claude Code's default
# auto-mode rules with this bundle's own rules applied.
#
# Usage:
#   claude auto-mode defaults > defaults.json
#   jq -n --slurpfile defaults defaults.json --slurpfile own scripts/auto-mode/own-rules.json \
#       -f scripts/auto-mode/build.jq
#
# A custom `allow` or `environment` list REPLACES Claude Code's own, so the
# bundle carries the defaults and adds to them:
#
#   * allow: every default rule, then the bundle's own rules (own-rules.json
#     `allow`), in that order.
#   * environment: every default entry, except that an own entry with the same
#     key (the bold `**Key**` it starts with) replaces it; own entries with a
#     new key follow the defaults. Left out when own-rules.json has none.
#
# hard_deny and soft_deny are not set, so Claude Code's own apply.

def key: (capture("^\\*\\*(?<k>[^*]+)\\*\\*") // {k: .}).k;

$defaults[0] as $d
| $own[0] as $o
| ($o.environment // []) as $oe
| ($oe | map({key: key, value: .}) | from_entries) as $ov
| ($d.environment | map(key)) as $dk
| {
    allow: ($d.allow + ($o.allow // [])),
    environment: (
        ($d.environment | map(key as $k | $ov[$k] // .))
        + ($oe | map(select(key as $k | $dk | index($k) | not)))
    )
  }
| if ($oe | length) == 0 then del(.environment) else . end
