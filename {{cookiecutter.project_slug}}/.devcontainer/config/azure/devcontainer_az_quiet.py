"""Drop Azure CLI's "altered by the following extension" warning.

The image installs the containerapp extension, which overrides the built-in
`az containerapp` commands, so every such call printed that warning. Only this
one message is filtered; every other warning and error still prints.
Installed into az's own Python by post-create.sh, with a .pth file that
imports it.
"""

import logging


class _DropExtensionOverride(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        return not str(record.msg).startswith("The behavior of this command has been altered by")


logging.getLogger("cli.azure.cli.core.commands").addFilter(_DropExtensionOverride())
