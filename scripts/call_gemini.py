"""
call_gemini.py
--------------
Drop-in replacement for the Copilot CLI call in run_album.ps1 Step 3.

Usage:
    python call_gemini.py <task_file_path>

Output:
    Prints the Gemini response to stdout (same as copilot -sp did).
    Exits with code 1 on error so PowerShell can detect failure via $LASTEXITCODE.

Requirements:
    pip install google-genai

API key lookup order:
    1. .env file in the project root  (GEMINI_API_KEY=xxx)
    2. System / user environment variable  (fallback)
"""

import sys
import os
from pathlib import Path

# Force UTF-8 stdout so Chinese/accented characters in JSON
# are not mangled by Windows cp950 default encoding.
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    import io
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")


def load_dotenv_manual(env_path: Path) -> None:
    """
    Load a .env file into os.environ without requiring python-dotenv.
    Only sets variables not already present (env vars take precedence).
    """
    if not env_path.is_file():
        return
    with open(env_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip()
            if len(value) >= 2 and value[0] in ('"', "'") and value[-1] == value[0]:
                value = value[1:-1]
            if key and key not in os.environ:
                os.environ[key] = value


def find_dotenv(start: Path) -> Path | None:
    """Walk up from `start` looking for a .env file."""
    current = start.resolve()
    while True:
        candidate = current / ".env"
        if candidate.is_file():
            return candidate
        parent = current.parent
        if parent == current:
            return None
        current = parent


def main():
    # ----------------------------------------------------------------
    # 1. Validate arguments
    # ----------------------------------------------------------------
    if len(sys.argv) < 2:
        print("ERROR: call_gemini.py requires one argument: <task_file_path>", file=sys.stderr)
        sys.exit(1)

    task_file = sys.argv[1]

    if not os.path.isfile(task_file):
        print(f"ERROR: Task file not found: {task_file}", file=sys.stderr)
        sys.exit(1)

    # ----------------------------------------------------------------
    # 2. Load .env
    # ----------------------------------------------------------------
    script_dir = Path(__file__).parent
    dotenv_path = find_dotenv(script_dir)

    if dotenv_path:
        load_dotenv_manual(dotenv_path)
        print(f"[call_gemini] Loaded .env from: {dotenv_path}", file=sys.stderr)
    else:
        print("[call_gemini] No .env file found; relying on system environment variable.", file=sys.stderr)

    # ----------------------------------------------------------------
    # 3. Read API key
    # ----------------------------------------------------------------
    api_key = os.environ.get("GEMINI_API_KEY", "").strip()

    if not api_key:
        print(
            "ERROR: GEMINI_API_KEY is not set.\n"
            "Either create a .env file in the project root with:\n"
            "    GEMINI_API_KEY=your_key_here\n"
            "or set a system/user environment variable.",
            file=sys.stderr,
        )
        sys.exit(1)

    # ----------------------------------------------------------------
    # 4. Read task file — always UTF-8
    # ----------------------------------------------------------------
    try:
        with open(task_file, "r", encoding="utf-8") as f:
            prompt_text = f.read()
    except Exception as e:
        print(f"ERROR: Cannot read task file: {e}", file=sys.stderr)
        sys.exit(1)

    # ----------------------------------------------------------------
    # 5. Call Gemini API  (new google-genai SDK)
    # ----------------------------------------------------------------
    try:
        from google import genai
        from google.genai import types
    except ImportError:
        print(
            "ERROR: google-genai is not installed.\n"
            "Run:  pip install google-genai",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        client = genai.Client(api_key=api_key)

        response = client.models.generate_content(
            model="gemini-3.1-flash-lite",
            contents=prompt_text,
            config=types.GenerateContentConfig(
                temperature=0.0,
                max_output_tokens=64000,
                response_mime_type="application/json",
                thinking_config=types.ThinkingConfig(
                    thinking_level="MEDIUM"
                ),
            ),
        )

        print(response.text)

    except Exception as e:
        print(f"ERROR: Gemini API call failed: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
