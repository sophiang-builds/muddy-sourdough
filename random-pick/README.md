# Try Your Luck

Tap Pick for me and up to three glass squares land on something random to do, picked from a fixed list of 123 categories and about 1,400 options.

- `build_db.py` holds the deep category tree; `more_categories.txt` adds the rest, one line per category. Run `python3 build_db.py` to regenerate `categories.json`.
- `picker.py` picks from the command line with Python's `secrets`. `python3 picker.py --test` checks the picks are even.
- `index.html` is the web app (Liquid Glass look, iPhone 15 frame on wider screens). It picks with `crypto.getRandomValues` and rejection sampling. Host the folder (for example GitHub Pages), open it in Safari and use Share > Add to Home Screen.
- `ios/TryYourLuck/` is the native SwiftUI app using Apple's real Liquid Glass APIs. See its README.
