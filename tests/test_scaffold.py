from pathlib import Path


def test_project_scaffold_exists():
    assert Path("pyproject.toml").exists()
    assert Path("app").is_dir()
    assert Path("tests").is_dir()
