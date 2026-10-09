# missing-plugins.jq — every enabled plugin with its install path, so the
# caller can tell which ones Claude Code has not installed.
#
# Usage: jq -rn --slurpfile settings <settings.json> \
#                --slurpfile installed <installed_plugins.json> -f missing-plugins.jq
#   (pass `--slurpfile installed /dev/null` when the file does not exist yet)
#
# post-create.sh skips the plugin bootstrap for 24h after a run, to keep
# container starts fast and offline-tolerant. That window must not hide a
# plugin the roster enables but the cache lacks (a plugin added to the bundle,
# or a wiped cache): Claude Code then reports it "not cached". One line per
# enabled plugin: "<name>\t<installPath>", the path empty when the plugin is
# not recorded as installed. The caller checks that the path exists, since a
# recorded install whose folder is gone is just as broken.

($settings[0].enabledPlugins // {})
| to_entries
| map(select(.value == true) | .key)
| .[]
| . as $name
| "\($name)\t\(((($installed[0] // {}).plugins // {})[$name] // [])[0].installPath // "")"
