#!/usr/bin/env python3
"""Apply DenucziTV icons to Flutter-generated Windows and Linux runners.

Run after ``flutter create --project-name denuczi_tv --platforms=linux,windows .``.
The script accepts Flutter's multiline GTK runner template and is idempotent.
"""
from pathlib import Path
import re
import shutil
import sys


# Flutter declares GtkWindow* window on two physical lines. The regex must
# accept that formatting and whitespace differences across SDK releases.
LINUX_WINDOW_DECLARATION = re.compile(
    r"GtkWindow\s*\*\s*window\s*=\s*GTK_WINDOW\s*\(\s*"
    r"gtk_application_window_new\s*\(\s*GTK_APPLICATION\s*\(\s*"
    r"application\s*\)\s*\)\s*\)\s*;",
)
MARKER = "  // DenucziTV native application icon (generated branding)."
ICON_SETUP = r'''

  // DenucziTV native application icon (generated branding).
  // Flutter copies declared assets to data/flutter_assets/ in the bundle.
  gchar* binary_path = g_file_read_link("/proc/self/exe", nullptr);
  if (binary_path != nullptr) {
    gchar* binary_dir = g_path_get_dirname(binary_path);
    gchar* icon_path = g_build_filename(binary_dir, "data", "flutter_assets",
                                        "assets", "branding", "denuczitv_app_icon.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_IS_REGULAR)) {
      gtk_window_set_icon_from_file(window, icon_path, nullptr);
    }
    g_free(icon_path);
    g_free(binary_dir);
    g_free(binary_path);
  }
'''


def apply_branding(root: Path) -> None:
    assets = root / 'assets' / 'branding'
    win = root / 'windows' / 'runner' / 'resources' / 'app_icon.ico'
    linux = root / 'linux' / 'runner' / 'my_application.cc'

    if not (assets / 'denuczitv.ico').is_file():
        raise FileNotFoundError('Missing DenucziTV Windows icon asset')
    if not (assets / 'denuczitv_app_icon.png').is_file():
        raise FileNotFoundError('Missing DenucziTV Linux icon asset')

    # Validate both target layouts before changing anything. An unexpected
    # Flutter template must not leave partially patched native assets.
    patched_linux = None
    if linux.is_file():
        source = linux.read_text(encoding='utf-8')
        if MARKER not in source:
            match = LINUX_WINDOW_DECLARATION.search(source)
            if match is None:
                raise ValueError(
                    'Unrecognized Linux runner layout; no native files were changed. '
                    'Check linux/runner/my_application.cc.'
                )
            patched_linux = source[:match.end()] + ICON_SETUP + source[match.end():]

    if win.parent.is_dir():
        shutil.copyfile(assets / 'denuczitv.ico', win)
        print(f'Windows application icon: {win.relative_to(root)}')
    else:
        print('Windows runner not generated; skipping native Windows icon.')

    if linux.is_file():
        if patched_linux is not None:
            linux.write_text(patched_linux, encoding='utf-8')
        print(f'Linux GTK window icon: {linux.relative_to(root)}')
    else:
        print('Linux runner not generated; skipping native Linux icon.')


if __name__ == '__main__':
    try:
        apply_branding(Path(__file__).resolve().parent.parent)
    except (OSError, ValueError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        sys.exit(1)
