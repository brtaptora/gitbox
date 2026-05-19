import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent))
import todo


@pytest.fixture(autouse=True)
def tmp_data(tmp_path, monkeypatch):
    monkeypatch.setattr(todo, "DATA_FILE", tmp_path / "data.json")


def test_add_creates_item():
    todo.add("buy milk")
    items = todo.load()
    assert len(items) == 1
    assert items[0]["text"] == "buy milk"
    assert items[0]["done"] is False


def test_done_marks_item():
    todo.add("buy milk")
    todo.done(1)
    assert todo.load()[0]["done"] is True


def test_delete_removes_item():
    todo.add("buy milk")
    todo.delete(1)
    assert todo.load() == []


def test_list_empty(capsys):
    todo.list_items()
    assert "no items" in capsys.readouterr().out
