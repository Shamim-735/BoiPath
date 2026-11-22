# BoiPath

**Every textbook. Every classroom. One platform.**

BoiPath is an independent digital textbook library and classroom reader for Bangladesh. Students browse the public library as guests. Teachers can present and annotate PDFs privately and use a teacher account to share the current textbook page with a class.

The starter catalog covers the general NCTB curriculum for Classes 1–12. It contains 269 class-group and version entries for 136 titles, including the 2026 Class 1–10 listings and the five published HSC entries from the official 2025–26 listing. Classes 9–10 and 11–12 share listings. Each can be browsed through either class filter. Each starter entry has a book-specific **Download PDF** action in search results and on the book details page. The catalog prefers Government Cloud Drive where available, with Google Drive links for the remaining entries. The provider may ask for confirmation on some files. The official class listing remains accessible from book details. An administrator can publish in-app reading after reviewing and verifying a direct PDF URL. English Version is the NCTB curriculum in its designated version.

Catalog coverage follows the NCTB [primary listings](https://nctb.gov.bd/pages/static-pages/695b9b7cc4774958d7b70a12), [secondary listings](https://nctb.gov.bd/pages/static-pages/695b98afc4774958d7b7044c), and [HSC 2025–26 listing](https://nctb.gov.bd/pages/static-pages/6922e145933eb65569e2b37b). The subject inventory and version labels were cross-checked against the [EducationBD class-by-class index](https://educationbd.org/nctb-book-download/) and [Somadhan catalog](https://somadhan.app/nctb-books).

## Run locally in VS Code

Install Python 3.12 or newer, [Flutter stable](https://docs.flutter.dev/install) with Dart 3.10 or newer, and Chrome. For Android, install Android Studio and its SDK. For iOS, use a Mac with Xcode and follow Flutter's iOS setup.

Open the extracted `boipath` folder in VS Code. In a terminal, start the API with its local SQLite database.

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m boipath.cli seed
$env:BOIPATH_ORIGINS = "http://localhost:8080"
.\.venv\Scripts\python.exe -m uvicorn boipath.app:app --host 127.0.0.1 --port 8000
```

On macOS or Linux, run these commands from the repository root.

```bash
cd backend
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m boipath.cli seed
BOIPATH_ORIGINS=http://localhost:8080 .venv/bin/python -m uvicorn boipath.app:app --host 127.0.0.1 --port 8000
```

In a second terminal at the repository root, generate the native and web project shells and launch Flutter. The bootstrap uses the installed SDK's templates and keeps the app source under `apps/flutter_app/lib`.

```text
python scripts/configure_flutter.py
cd apps/flutter_app
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 8080 --dart-define=API_BASE_URL=http://localhost:8000
```

Open the [Flutter app](http://localhost:8080), [API documentation](http://localhost:8000/docs), or [admin sign-in](http://localhost:8080/#/admin). The web app uses hash routing for direct links on static hosts.

### Android, iOS, and web builds

For an Android Studio emulator, select the device shown by `flutter devices` and use the Android emulator's address for the host API. To test a physical phone with a debug build, run the API on your development computer's LAN interface and substitute that computer's LAN IP. Use an HTTPS API for signed production builds.

```text
flutter devices
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8000
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com --dart-define=PUBLIC_APP_URL=https://books.example.com
flutter build web --release --dart-define=API_BASE_URL=https://api.example.com --dart-define=PUBLIC_APP_URL=https://books.example.com
```

On a Mac, set your signing team and bundle ID in the generated Xcode project. Run against an HTTPS API.

```text
flutter run -d <ios-device-id> --dart-define=API_BASE_URL=https://api.example.com
flutter build ipa --release --dart-define=API_BASE_URL=https://api.example.com --dart-define=PUBLIC_APP_URL=https://books.example.com
```

Build outputs are under `apps/flutter_app/build/`. For web, publish `build/web` and configure the API's allowed origin to the exact app origin. Replace the example domains before building. `PUBLIC_APP_URL` enables shareable lesson links and QR codes from mobile.

## Update an existing installation

Copy the updated `backend` and `apps/flutter_app` files into the existing project. Keep the existing database. Restart FastAPI to apply the catalog migrations and attach the book-specific download links. Seed installation leaves existing book records and their publication status in place. Restart Flutter so it loads the updated frontend and starter catalog.

### Textbook covers

BoiPath draws its textbook illustrations locally in the grid, list, and detail view. Each book has a consistent design based on its title, subject, and catalog ID. The artwork is available offline as soon as the card appears.

## Configure PostgreSQL

Copy `.env.example` to `.env`. Set `POSTGRES_PASSWORD` to a unique URL-safe password. A generated hex value works with both the PostgreSQL container and connection URI. Start the API and PostgreSQL with Docker Compose.

```text
python -c "import secrets; print(secrets.token_hex(24))"
docker compose up --build -d
docker compose exec api python -m boipath.cli seed
docker compose exec api python -m boipath.cli create-admin --email admin@example.com
docker compose exec api python -m boipath.cli create-teacher --email teacher@example.com
```

For local SQLite, run the same commands after replacing `docker compose exec api python` with the Python interpreter from the local venv. Both account commands prompt for a password. Teacher self-registration is disabled by default and guests can join an active classroom without an account.

## Publish a textbook

1. Open the source page on [NCTB](https://nctb.gov.bd/) and check the title, academic year, class, track, edition, and version.
2. Review whether the direct PDF link is suitable for linking and guest download. Add a reviewed content hostname to `OFFICIAL_PDF_HOSTS` if necessary, then restart the API.
3. Sign in to `/#/admin`. Add a pending record or edit the matching starter entry. Enter the direct HTTPS file URL and the corresponding official NCTB source page.
4. Select **Verify and publish**. The validator requires an approved HTTPS host, a public address, and a PDF signature. It checks that the selected record did not change while verification was in progress.
5. Reload the guest catalog and test both in-app reading and the source link. Test the direct PDF separately in Chrome and on a device, because a host can serve public files while limiting browser fetch access.

Pending and unavailable records display their official source page. Draft and archived records are accessible to authorized administrators. The app links to official PDF sources and stores user-initiated local copies on mobile. BoiPath is independent of NCTB.

## Repository and checks

| Path | Contents |
| --- | --- |
| `apps/flutter_app` | Flutter catalog, reader, Teacher Mode, classroom client, and admin interface |
| `backend` | FastAPI, SQL migrations, account CLI, source metadata seed, and API tests |
| `scripts` | Flutter platform setup and a two-page PDF generator for QA |
| `docs` | Architecture, API and deployment notes, and manual QA |
| `.github/workflows` | SQLite and PostgreSQL backend checks, Flutter analysis and tests, and a web build |

```text
cd backend
python -m unittest discover -s tests -v
cd ../apps/flutter_app
flutter analyze lib test
flutter test
```

Seventeen backend tests passed on SQLite in the development workspace. The suite includes controlled fixture verification, admin publication, rate-limited API features, and classroom page updates received through the WebSocket. PostgreSQL and Flutter checks are configured in CI and still require a run. The Flutter SDK and platform build tools were unavailable in the development workspace.

## Current limits

- The seed covers the general curriculum. Madrasa, vocational, and ethnic-language editions are listed separately by NCTB. All bundled entries have a cloud download link. In-app online reading still uses an admin-verified PDF URL.
- Mobile downloads run in the foreground and support progress, cancellation, retry, and deletion. Pause and resume of partial bytes, storage capacity reporting, and background transfers remain open.
- Web downloads use the browser's own PDF controls. Persistent in-app PDF storage and offline web app installation remain open. Upload-free local PDF opening is available in Teacher Mode.
- Reader text matching depends on searchable text in the file. Thumbnails and one-page snap layout are pending. Native immersive display depends on OS support.
- Teacher notes, annotations, and bookmarks stay on the device or browser profile. Cloud synchronization and cross-device student annotations are pending.
- Classroom clients receive page changes and can opt out of following. Shared ink, production load tests, native client tests, and a hosted two-client acceptance test are pending.

See [architecture](docs/architecture.md) and [manual QA](docs/manual-qa.md).
