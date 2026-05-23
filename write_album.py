import sys
import json
import os
import re
from mutagen.flac import FLAC

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def ensure_list(value):
    if value is None:
        return []

    if isinstance(value, list):
        return [str(x).strip() for x in value if str(x).strip()]

    if isinstance(value, str):
        value = value.strip()
        return [value] if value else []

    return [str(value).strip()]


def safe_filename(name):
    name = re.sub(r'[\\/:*?"<>|]', "-", name)
    name = name.strip()
    name = name.rstrip(". ")
    return name


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


def main():
    if len(sys.argv) < 2:
        print("Usage: python write_album.py <album_output_json>")
        sys.exit(1)

    json_file = sys.argv[1]

    if not os.path.exists(json_file):
        print(f"ERROR: JSON file not found: {json_file}")
        sys.exit(1)

    with open(json_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    tracks = get_tracks(data)

    for track in tracks:
        file_path = track.get("file", "")

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
        tracknumber = str(track.get("tracknumber", "")).strip()

        if not title:
            title = "Unknown Title"

        if not tracknumber:
            tracknumber = "01"

        if "/" in tracknumber:
            tracknumber = tracknumber.split("/", 1)[0]

        tracknumber = tracknumber.zfill(2)

        audio = FLAC(file_path)

        audio["composer"] = composer
        audio["artist"] = artist
        audio["albumartist"] = albumartist
        audio["title"] = [title]
        audio["tracknumber"] = [tracknumber]

        # Optional: write album if AI returns it
        if "album" in track:
            album_value = str(track.get("album", "")).strip()
            if album_value:
                audio["album"] = [album_value]

        audio.save()

        print(f"Metadata written: {file_path}")

        # Rename file
        directory = os.path.dirname(file_path)
        new_name = f"{tracknumber} - {safe_filename(title)}.flac"
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