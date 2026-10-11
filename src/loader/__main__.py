"""Allow `python -m loader` to invoke the CLI."""
from loader.cli import main

if __name__ == "__main__":
    raise SystemExit(main())