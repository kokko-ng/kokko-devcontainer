from __future__ import annotations

from typing import TYPE_CHECKING

from {{ cookiecutter.__package_name }}.__main__ import PROJECT_NAME, main

if TYPE_CHECKING:
    import pytest


def test_main_prints_the_project_name(capsys: pytest.CaptureFixture[str]) -> None:
    assert main() == 0
    assert capsys.readouterr().out == f"{PROJECT_NAME}\n"
