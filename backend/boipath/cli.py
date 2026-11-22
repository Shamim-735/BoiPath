import argparse
import getpass

from .app import create_user
from .catalog import seed_catalog
from .db import default_database
from .schemas import Credentials


def main():
    parser = argparse.ArgumentParser(description="BoiPath catalog and account setup")
    parser.add_argument("action", choices=("migrate", "seed", "create-admin", "create-teacher"))
    parser.add_argument("--email")
    args = parser.parse_args()
    db = default_database()
    db.migrate()
    if args.action == "seed":
        total = seed_catalog(db)
        print(f"Checked {total} NCTB catalog entries. Existing books were preserved.")
    elif args.action.startswith("create-"):
        password = getpass.getpass("Password (at least 12 characters): ")
        if len(password) < 12 or password != getpass.getpass("Repeat password: "):
            parser.error("Use matching passwords of at least 12 characters.")
        credentials = Credentials(email=args.email or input("Email: "), password=password)
        print(create_user(db, credentials, args.action.removeprefix("create-")))


if __name__ == "__main__":
    main()
