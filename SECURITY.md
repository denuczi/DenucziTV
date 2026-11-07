# Security policy

DenucziTV is in early development. Do not use untrusted provider endpoints with valuable account credentials while security review is incomplete.

Report vulnerabilities privately to the repository maintainer, Ignacio Sanguina. Do not publish secrets, playlist links or sample URLs containing credentials in issues or test fixtures.

Credentials are stored using the operating system's secret service. The personal-library SQLite database never stores passwords, streaming tokens or complete stream URLs. Its files remain local to the user profile and are not encrypted by the application. Protect your OS account and disk accordingly.

Exported M3U files and copied stream URLs may contain provider credentials. HTTPS-to-HTTP redirects can reveal URL tokens if explicitly allowed in settings. Filesystem permissions and network boundaries should be reviewed before release.
