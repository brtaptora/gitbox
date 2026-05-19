import json
import os
import sys
from pathlib import Path

DATA_FILE = Path.home() / ".todoapp_data.json"


def load() -> list[dict]:
    if not DATA_FILE.exists():
        return []
    return json.loads(DATA_FILE.read_text())


def save(items: list[dict]) -> None:
    DATA_FILE.write_text(json.dumps(items, indent=2))


def add(text: str) -> None:
    items = load()
    items.append({"id": len(items) + 1, "text": text, "done": False})
    save(items)
    print(f"added: {text}")


def done(item_id: int) -> None:
    items = load()
    for item in items:
        if item["id"] == item_id:
            item["done"] = True
            save(items)
            print(f"done: {item['text']}")
            return
    print(f"not found: {item_id}")


def list_items() -> None:
    items = load()
    if not items:
        print("no items")
        return
    for item in items:
        mark = "x" if item["done"] else " "
        print(f"[{mark}] {item['id']}. {item['text']}")


def delete(item_id: int) -> None:
    items = load()
    before = len(items)
    items = [i for i in items if i["id"] != item_id]
    if len(items) == before:
        print(f"not found: {item_id}")
        return
    save(items)
    print(f"deleted: {item_id}")


USAGE = """todo <command> [args]
  add <text>    add a todo item
  done <id>     mark item done
  list          list all items
  delete <id>   remove item
"""


def main() -> None:
    args = sys.argv[1:]
    if not args:
        print(USAGE)
        return
    cmd = args[0]
    if cmd == "add" and len(args) > 1:
        add(" ".join(args[1:]))
    elif cmd == "done" and len(args) == 2:
        done(int(args[1]))
    elif cmd == "list":
        list_items()
    elif cmd == "delete" and len(args) == 2:
        delete(int(args[1]))
    else:
        print(USAGE)


if __name__ == "__main__":
    main()
