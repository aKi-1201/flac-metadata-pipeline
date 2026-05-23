import os
import sys
import json
from mutagen.flac import FLAC

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def first_value(audio, tag):
    """
    Return the first value of a FLAC metadata tag.
    If the tag does not exist, return an empty string.
    """
    values = audio.get(tag, [])
    if not values:
        return ""
    return str(values[0])


def extract_track(file_path):
    """
    Extract metadata from one FLAC file.
    """
    audio = FLAC(file_path)

    return {
        "file": file_path,
        "filename": os.path.basename(file_path),
        "title": first_value(audio, "title"),
        "artist": audio.get("artist", []),
        "albumartist": audio.get("albumartist", []),
        "composer": audio.get("composer", []),
        "album": first_value(audio, "album"),
        "tracknumber": first_value(audio, "tracknumber"),
        "discnumber": first_value(audio, "discnumber"),
        "date": first_value(audio, "date"),
        "genre": first_value(audio, "genre")
    }


def parse_number(value):
    """
    Convert tracknumber/discnumber values such as:
    "01", "1", "1/12" into integer.
    """
    value = str(value or "").strip()

    if not value:
        return 0

    if "/" in value:
        value = value.split("/", 1)[0]

    try:
        return int(value)
    except Exception:
        return 0


def track_sort_key(track):
    """
    Sort by discnumber first, then tracknumber, then filename.
    If discnumber is missing, assume disc 1.
    """
    disc = parse_number(track.get("discnumber", ""))
    track_no = parse_number(track.get("tracknumber", ""))

    if disc == 0:
        disc = 1

    if track_no == 0:
        track_no = 9999

    return (disc, track_no, track.get("filename", ""))


def should_skip_folder(folder_path):
    """
    Skip debug or system folders.
    """
    folder_lower = folder_path.lower()

    skip_names = [
        "_debug_album",
        "_debug_json",
        "prompts",
        "prompts_album",
        "__pycache__"
    ]

    return any(name.lower() in folder_lower for name in skip_names)


def main():
    if len(sys.argv) < 2:
        print("Usage: python extract_album.py <album_folder>")
        sys.exit(1)

    album_folder = sys.argv[1]

    if not os.path.isdir(album_folder):
        print(f"ERROR: Album folder not found: {album_folder}")
        sys.exit(1)

    tracks = []

    # Recursive album extraction:
    # This supports nested folders such as CD1/CD2.
    for root, dirs, files in os.walk(album_folder):

        if should_skip_folder(root):
            continue

        for name in files:
            if name.lower().endswith(".flac"):
                full_path = os.path.join(root, name)
                tracks.append(extract_track(full_path))

    tracks.sort(key=track_sort_key)

    album_name = ""

    if tracks:
        # Pick the first non-empty album tag.
        for track in tracks:
            if track.get("album"):
                album_name = track.get("album")
                break

    output = {
        "album_folder": album_folder,
        "album": album_name,
        "track_count": len(tracks),
        "tracks": tracks
    }

    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()