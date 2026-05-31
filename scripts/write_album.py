import sys
import json
import os
import re
from mutagen.flac import FLAC


# ============================================================
# Settings
# ============================================================

FILENAME_MAX_LENGTH = 100


# ============================================================
# Console UTF-8
# ============================================================

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass


# ============================================================
# Path helpers
# ============================================================

def normalize_path(path):
    r"""
    Remove Windows extended path prefix if present.

    Example:
    \\?\D:\Music -> D:\Music
    \\?\UNC\server\share -> \\server\share
    """
    if not path:
        return path

    if path.startswith("\\\\?\\UNC\\"):
        return "\\\\" + path[8:]

    if path.startswith("\\\\?\\"):
        return path[4:]

    return path


# ============================================================
# Data helpers
# ============================================================

def ensure_list(value):
    """
    Ensure Mutagen multi-value fields are always written as list[str].
    """
    if value is None:
        return []

    if isinstance(value, list):
        return [str(x).strip() for x in value if str(x).strip()]

    if isinstance(value, str):
        value = value.strip()
        return [value] if value else []

    return [str(value).strip()]


def get_tracks(data):
    """
    Accept either:
    1. { "tracks": [ ... ] }
    2. [ ... ]
    """
    if isinstance(data, dict) and "tracks" in data:
        return data["tracks"]

    if isinstance(data, list):
        return data

    raise ValueError("Output JSON must be either an array or an object with a 'tracks' array.")


def normalize_tracknumber(value):
    """
    Convert:
    "1"    -> "01"
    "01"   -> "01"
    "1/12" -> "01"
    """
    value = str(value or "").strip()

    if not value:
        return "01"

    if "/" in value:
        value = value.split("/", 1)[0]

    try:
        return str(int(value)).zfill(2)
    except Exception:
        return value.zfill(2)


# ============================================================
# Filename helpers
# ============================================================

def safe_filename(name):
    """
    Remove characters illegal in Windows filenames.
    """
    if not name:
        return "Unknown"

    name = str(name)

    # Replace Windows-illegal filename characters
    name = re.sub(r'[\\/:*?"<>|]', "-", name)

    # Normalize repeated whitespace
    name = re.sub(r"\s+", " ", name)

    # Avoid trailing dots/spaces on Windows
    name = name.strip().rstrip(". ")

    return name if name else "Unknown"


def truncate_filename(filename, max_length=FILENAME_MAX_LENGTH):
    """
    Limit filename length while preserving extension.
    """
    if len(filename) <= max_length:
        return filename

    base, ext = os.path.splitext(filename)
    allowed = max_length - len(ext)

    if allowed < 20:
        allowed = 20

    base = base[:allowed].rstrip(". -_")

    return base + ext


def looks_like_ensemble(name):
    """
    Detect orchestra / ensemble / group names.
    These names should not be shortened to surname.
    """
    if not name:
        return False

    lower = name.lower()

    keywords = [
        "orchestra",
        "philharmonic",
        "philharmoniker",
        "symphony",
        "ensemble",
        "quartet",
        "quintet",
        "trio",
        "choir",
        "chorus",
        "consort",
        "players",
        "academy",
        "kapelle",
        "staatskapelle",
        "orchester",
        "sinfonia",
        "cappella",
        "capella"
    ]

    return any(k in lower for k in keywords)


def extract_surname(name):
    """
    Extract surname from a personal name.

    Examples:
    Maria Callas -> Callas
    Giuseppe Di Stefano -> Di Stefano
    Herbert von Karajan -> Karajan
    Ludwig van Beethoven -> Beethoven
    """
    name = str(name or "").strip()

    if not name:
        return "Unknown"

    title_prefixes = [
        "Sir ",
        "Dame ",
        "Dr. ",
        "Dr ",
        "Lord ",
        "Lady "
    ]

    for prefix in title_prefixes:
        if name.startswith(prefix):
            name = name[len(prefix):].strip()

    parts = name.split()

    if not parts:
        return "Unknown"

    if len(parts) >= 2:
        particle = parts[-2].lower()

        compound_particles = {
            "di",
            "de",
            "del",
            "della",
            "da",
            "du"
        }

        if particle in compound_particles:
            return parts[-2] + " " + parts[-1]

    return parts[-1]


def get_short_albumartist(albumartist_list, max_names=3):
    """
    Convert albumartist list to filename-friendly short form.

    Examples:
    ["Arturo Benedetti Michelangeli"] -> "Michelangeli"
    ["Maria Callas", "Giuseppe Di Stefano", "Tullio Serafin"]
        -> "Callas, Di Stefano, Serafin"

    Ensembles / orchestras are kept as full names:
    ["Wiener Philharmoniker"] -> "Wiener Philharmoniker"
    """
    values = ensure_list(albumartist_list)

    if not values:
        return "Unknown"

    short_names = []

    for name in values[:max_names]:
        name = str(name).strip()

        if not name:
            continue

        if looks_like_ensemble(name):
            short_names.append(name)
        else:
            short_names.append(extract_surname(name))

    if not short_names:
        return "Unknown"

    return ", ".join(short_names)


def build_filename(tracknumber, albumartist, title, max_length=FILENAME_MAX_LENGTH):
    """
    Filename format:
    01 - Michelangeli - Images, Book 1 - I. Reflets dans l'eau.flac
    """
    short_albumartist = get_short_albumartist(albumartist)

    filename_title = str(title or "Unknown Title").strip()

    # Metadata title may contain colon.
    # Filename uses hyphen for readability and Windows compatibility.
    filename_title = filename_title.replace(": ", " - ")
    filename_title = filename_title.replace(":", " -")

    raw_name = f"{tracknumber} {short_albumartist} - {filename_title}.flac"

    clean_name = safe_filename(raw_name)

    return truncate_filename(clean_name, max_length=max_length)


# ============================================================
# Main
# ============================================================

def main():
    if len(sys.argv) < 2:
        print("Usage: python write_album.py <album_output_json>")
        sys.exit(1)

    json_file = normalize_path(sys.argv[1])

    if not os.path.exists(json_file):
        print(f"ERROR: JSON file not found: {json_file}")
        sys.exit(1)

    with open(json_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    tracks = get_tracks(data)

    for track in tracks:
        file_path = normalize_path(track.get("file", ""))

        if not file_path:
            print("WARNING: Track missing file path, skipping.")
            continue

        if not os.path.exists(file_path):
            print(f"WARNING: FLAC file not found, skipping: {file_path}")
            continue

        composer = ensure_list(track.get("composer", []))
        artist = ensure_list(track.get("artist", []))
        albumartist = ensure_list(track.get("albumartist", []))

        title = str(track.get("title", "")).strip()
        tracknumber = normalize_tracknumber(track.get("tracknumber", ""))

        if not title:
            title = ""

        # Fallback rules
        if not composer and artist:
            composer = [artist[0]]

        if not artist and composer:
            artist = composer.copy()

        if not albumartist:
            if len(artist) >= 2:
                albumartist = [artist[1]]
            elif artist:
                albumartist = [artist[0]]
            else:
                albumartist = []

        audio = FLAC(file_path)

        # Optional album tag from AI output
        if "album" in track and str(track.get("album", "")).strip():
            audio["album"] = [str(track.get("album", "")).strip()]
        elif isinstance(data, dict) and str(data.get("album", "")).strip():
            audio["album"] = [str(data.get("album", "")).strip()]

        audio["composer"] = composer
        audio["artist"] = artist
        audio["albumartist"] = albumartist
        audio["title"] = [title]
        audio["tracknumber"] = [tracknumber]

        audio.save()

        print(f"Metadata written: {file_path}")
        print(f"  composer: {composer}")
        print(f"  artist: {artist}")
        print(f"  albumartist: {albumartist}")
        print(f"  title: {title}")
        print(f"  tracknumber: {tracknumber}")

        # Rename file
        directory = os.path.dirname(file_path)

        new_name = build_filename(
            tracknumber=tracknumber,
            albumartist=albumartist,
            title=title,
            max_length=FILENAME_MAX_LENGTH
        )

        new_path = os.path.join(directory, new_name)

        if os.path.abspath(file_path) != os.path.abspath(new_path):
            if os.path.exists(new_path):
                print(f"WARNING: Target exists, rename skipped: {new_path}")
            else:
                os.rename(file_path, new_path)
                print(f"Renamed to: {new_name}")
        else:
            print("Filename already correct.")

    print("Album write completed.")


if __name__ == "__main__":
    main()