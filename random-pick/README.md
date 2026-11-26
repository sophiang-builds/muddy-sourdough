# Pick for Me

A random picker for creative prompts. Choose up to three categories, tap Pick, and push any card one layer deeper.

- `build_db.py` holds the category tree as indented text. Edit it, then run `python3 build_db.py` to regenerate `categories.json`.
- `picker.py` picks from the command line using Python's `secrets`. Run `python3 picker.py --test` to check the picks are even.
- `index.html` is the phone app. It uses `crypto.getRandomValues` with rejection sampling, the browser's equivalent of `secrets`. Serve the folder (for example with GitHub Pages) and use Safari's Share > Add to Home Screen on iPhone.
