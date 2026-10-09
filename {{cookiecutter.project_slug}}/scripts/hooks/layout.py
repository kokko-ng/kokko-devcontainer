"""Where this project keeps its code, as the template generated it.

check_strictness.py reads these to know which paths the gates must keep covering.
If the layout moves, change it here and in pyproject.toml in the same commit.
"""

BACKEND_SRC_DIR = "{{ cookiecutter.backend_src_dir }}"
FRONTEND_DIR = "{{ cookiecutter.frontend_dir }}"
PACKAGE = "{{ cookiecutter.__package_name }}"
