# Security policy

DenucziTV is in early development. Do not use untrusted provider endpoints with valuable account credentials while security review is incomplete.

Report vulnerabilities privately to the repository maintainer, Ignacio Sanguina. Do not publish secrets, playlist links or sample URLs containing credentials in issues or test fixtures.

Credentials are stored using the operating system's secret service. The personal-library SQLite database never stores passwords, streaming tokens or complete stream URLs. Its files remain local to the user profile and are not encrypted by the application. Protect your OS account and disk accordingly.

Exported M3U files and copied stream URLs may contain provider credentials. HTTPS-to-HTTP redirects can reveal URL tokens if explicitly allowed in settings. Filesystem permissions and network boundaries should be reviewed before release.

Protected Single Link accounts store their original link, resolved connection,
expiry, and installation UUID in the existing OS secure store. They cannot copy
playback links or export M3U through application operations. Their identifying
User-Agent is sent only to the initial permanent-link request. Subsequent hops
use ordinary headers, with automatic redirects disabled and no cookie forwarding.
Link expiry revokes sessions and transfers while retaining personal data and
files. See [Protected Single Link](docs/PROTECTED_SINGLE_LINK.md) for the redirect
contract, migration, clock assumptions, and verification limitations.

These are ordinary application privacy controls, not DRM. A person controlling
the OS or modifying this open-source client can inspect memory or bypass local
controls. The identifying User-Agent is spoofable. HTTP links and protocol
downgrades are supported and expose transport data to network observers.
