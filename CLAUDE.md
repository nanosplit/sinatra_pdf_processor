# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Sinatra web app for processing PDF files. Users upload a PDF, then edit it via a browser UI: remove pages, merge PDFs, and convert between PDF and JPG formats.

## Commands

```bash
# Install dependencies
bundle install

# Run the app (serves on http://localhost:4567)
ruby app.rb
```

Requires Ruby 3.1.2 and ImageMagick installed on the system (`apt-get install imagemagick` or `brew install imagemagick`). Uses Thin as the web server.

## Architecture

**Single-file app** — all routes and logic live in `app.rb`. No tests, no separate models or controllers.

### Key libraries
- **combine_pdf** — PDF manipulation (merge, split, page removal)
- **mini_magick** — PDF-to-JPG and JPG-to-PDF conversion (wraps ImageMagick)
- **rubyzip** — listed as dependency but zip is currently done via shell `zip` command

### Routes
| Route | Method | Purpose |
|-------|--------|---------|
| `/` | GET | Upload form |
| `/upload` | POST | Save PDF, store filename in session |
| `/edit` | GET | Edit page showing all operations |
| `/remove_pages` | POST | Remove specified pages (1-indexed, comma-separated) |
| `/add_pages` | POST | Merge another PDF at beginning/end/specific position |
| `/pdf_to_jpg` | POST | Convert current PDF pages to JPGs, zipped for download |
| `/download_jpg` | GET | Serve the generated JPG zip |
| `/jpg_to_pdf` | POST | Convert uploaded JPGs into a new PDF |
| `/download` | GET | Download the current working PDF |

### File storage
- `public/uploads/` — working PDFs (UUID-named), gitignored
- `public/processed/` — temporary output during operations, gitignored
- Files are identified by UUID filenames stored in `session[:current_pdf]`

### Views
ERB templates in `views/` with Bootstrap 5 styling via CDN. Layout (`layout.erb`) wraps `index.erb` (upload) and `edit.erb` (all editing operations).
