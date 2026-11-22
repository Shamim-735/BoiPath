# Manual QA

Generate a small synthetic file for the reader smoke test from the repository root.

```text
python scripts/make_reader_fixture.py
```

Use **Teacher Mode → Open PDF from device** to load `BoiPath_Reader_Test.pdf`. It has two pages of selectable text. The generator does not publish a guest catalog entry.

| Flow | What to verify |
| --- | --- |
| Guest browsing | Start without signing in. Search for English for Today. Filter Classes 1 and 2, then switch versions. Click **Download PDF** from Class 10 Physics in each version and confirm the two intended files. Open the official listing from book details. |
| Book publication | Add an approved official PDF URL from an NCTB listing. Verify and publish. Refresh the guest app. Check that the new PDF opens in-app and via the official source. |
| Offline mobile | Download a verified file. Switch to airplane mode, close the app, launch it, and open the file from Downloads. |
| Bookmarks and progress | Bookmark the second page of the synthetic file. Close the view, reopen the same file, and check page restoration and the bookmark list. |
| Teacher mode | Draw on the first page and highlight on the second. Undo and redo. Zoom and rotate the device. Check stroke alignment and that notes persist when reopening the file. |
| Live classroom | In one session sign in as a teacher, open a verified book, then start a classroom. In a private browser window join with the code. Turn pages, toggle follow mode, disconnect and reconnect, and end the session. |
| Broken source | Use a controlled test environment with a reviewed host returning a broken response. Confirm verification rejects it. For a source that fails after verification, confirm the reader or download reports an error and offers recovery. |
| Layout and accessibility | Exercise desktop, tablet and 360-pixel mobile widths. Switch to Bangla, use Ctrl+K or Command+K to focus search, enable dark theme and raise text scaling. Check filter selections, catalog counts, pending-book actions, and teacher controls. |

For portfolio screenshots, capture the catalog at 1440 × 900 and 390 × 844. Capture the reader with the generated fixture and the annotation toolbar visible. Use a development account and synthetic reports for admin screenshots. Omit live student session codes.
