import 'package:flutter/widgets.dart';

import 'l10n_ext.dart';

/// Translates known internal errors at the presentation boundary.
///
/// Unknown provider messages remain unchanged rather than being guessed.
String localizeAppError(BuildContext context, String message) {
  final l10n = context.l10n;
  final translations = <String, String>{
    "Cancelled": l10n.downloadStatusCancelled,
    "Reconnecting to resume saved bytes...": l10n.downloadReconnecting,
    "Resuming saved partial transfer...": l10n.downloadResumingPartial,
    "Resuming saved download...": l10n.downloadResuming,
    "Finalizing download...": l10n.downloadFinalizing,
    "The server interrupted the connection.": l10n.downloadServerInterrupted,
    "The network connection was interrupted.": l10n.downloadNetworkInterrupted,
    "The server ended the transfer early.": l10n.downloadTransferEndedEarly,
    "The download timed out.": l10n.downloadTimedOut,
    "Cancelled. The downloaded portion has been kept.":
        l10n.downloadCancelledPartialKept,
    "Download cancelled. Partial data was kept.":
        l10n.downloadCancelledPartialDataKept,
    "The download failed unexpectedly.": l10n.downloadUnexpectedFailure,
    "The download could not be completed.": l10n.downloadCouldNotComplete,
    "Network error. Check the connection and try again.":
        l10n.downloadNetworkError,
    "The provider refused access. Verify the account and subscription.":
        l10n.downloadProviderDenied,
    "The media file is no longer available.": l10n.downloadMediaUnavailable,
    "The provider rejected the requested byte range.":
        l10n.downloadRangeRejected,
    "Interrupted when the application closed. Start a new download from the catalog.":
        l10n.downloadInterruptedOnClose,
    "Cannot access the partial file. Check disk space and folder permissions.":
        l10n.downloadPartialFileAccessFailed,
    "Saved successfully": l10n.savedSuccessfully,
    "Download cancelled.": l10n.downloadStatusCancelled,
    "Enter a valid protected HTTP or HTTPS link.": l10n.protectedInvalidUrl,
    "The protected link returned an invalid Xtream destination.":
        l10n.protectedInvalidTarget,
    "Enter a permanent protected link, not an Xtream destination.":
        l10n.protectedPermanentRequired,
    "The protected link returned an invalid expiration.":
        l10n.protectedInvalidExpiration,
    "The protected link contains a redirect loop.": l10n.protectedRedirectLoop,
    "The protected link exceeded four redirects.":
        l10n.protectedTooManyRedirects,
    "The protected link returned an invalid redirect.":
        l10n.protectedInvalidRedirect,
    "The protected link is unavailable or did not redirect.":
        l10n.protectedUnavailable,
    "The protected link was not found.": l10n.protectedNotFound,
    "Access to the protected link was denied.": l10n.protectedDenied,
    "The protected link check timed out.": l10n.protectedTimeout,
    "Could not contact the protected link securely.":
        l10n.protectedContactFailed,
    "Protected account storage is unavailable.": l10n.protectedStorageFailed,
    "A protected account name is required.": l10n.accountNameRequired,
    "The protected account is no longer available.":
        l10n.protectedAccountUnavailable,
    "The protected account check was cancelled.": l10n.protectedCancelled,
    "Please wait before checking the protected link again.": l10n.protectedWait,
    "The protected link has expired.": l10n.protectedExpired,
    "The protected link has expired. Secure credential cleanup will be retried.":
        l10n.protectedExpiredCleanup,
    "Protected accounts do not allow sharing links or playlists.":
        l10n.protectedSharingDenied,
    "Protected accounts must use their permanent link.":
        l10n.protectedPermanentRequired,
    "The protected link must be checked before connecting.":
        l10n.protectedCheckRequired,
    "The protected account could not be checked.": l10n.protectedCheckFailed,
    "This content is unavailable in the current account source.":
        l10n.contentUnavailable,

    'Network preferences could not be restored.':
        l10n.networkPreferencesRestoreFailed,
    'Pending credential cleanup could not be completed.':
        l10n.pendingCredentialCleanupFailed,
    'Saved accounts could not be read.': l10n.savedAccountsRestoreFailed,
    'The last selected account could not be restored.':
        l10n.preferredAccountRestoreFailed,
    'Account metadata could not be restored.':
        l10n.accountMetadataRestoreFailed,
    'Appearance preferences could not be restored.':
        l10n.appearanceRestoreFailed,
    'Language preferences could not be restored.': l10n.languageRestoreFailed,
    'Download button preference could not be restored.':
        l10n.downloadControlsRestoreFailed,
    'Copy-link preference could not be restored.': l10n.copyLinkRestoreFailed,
    'M3U export preference could not be restored.':
        l10n.exportPreferenceRestoreFailed,
    'Download redirect preferences could not be restored.':
        l10n.redirectPreferenceRestoreFailed,
    'Download history could not be restored.':
        l10n.downloadHistoryRestoreFailed,
    'Personal library storage could not be opened.':
        l10n.personalLibraryRestoreFailed,
    'Username and password are required.': l10n.credentialsRequiredError,
    'The personal library could not be loaded.': l10n.personalLibraryOpenError,
    'Connected, but the account selection could not be saved.':
        l10n.preferredAccountSaveError,
    'Could not save or connect the account.': l10n.accountConnectError,
    'Could not read the saved account credentials.':
        l10n.savedCredentialsReadError,
    'Account removed, but local library cleanup failed.':
        l10n.accountRemovalCleanupError,
    'Could not finish deleting the saved account.': l10n.accountRemovalError,
    'The catalog could not be loaded.': l10n.catalogLoadError,
    'Disconnected, but the saved selection could not be cleared.':
        l10n.preferredAccountClearError,
    'Connection timed out. Check the server and try again.':
        l10n.connectionTimeoutError,
    'The server TLS certificate is invalid.': l10n.tlsCertificateError,
    'Could not connect to the server.': l10n.serverConnectionError,
    'The request was cancelled.': l10n.requestCancelledError,
    'The server returned an unexpected response.': l10n.unexpectedResponseError,
    'An unexpected error occurred.': l10n.unexpectedError,
    'The provider redirected the API request. Verify the server URL.':
        l10n.apiRedirectError,
    'The server did not return valid account information.':
        l10n.invalidAccountResponseError,
    'The server did not return user information.': l10n.missingUserInfoError,
    'Account access is denied or inactive.': l10n.accountAccessDeniedError,
    'The account has expired.': l10n.accountExpiredError,
    'The provider returned an invalid category list.':
        l10n.invalidCategoriesError,
    'The provider returned an invalid catalog.': l10n.invalidCatalogError,
    'The provider returned invalid series information.':
        l10n.invalidSeriesInfoError,
    'The provider returned invalid movie details.': l10n.invalidMovieInfoError,
    'Saved account information is corrupted.': l10n.corruptSavedAccountError,
    'No stored password is available for this account.':
        l10n.missingSavedPasswordError,
    'Enter an absolute HTTP or HTTPS server URL.': l10n.urlRequiredError,
    'Server URL contains an unsupported path.': l10n.unsupportedServerPathError,
    'User-Agent must contain 1 to 256 characters.': l10n.userAgentLengthError,
    'User-Agent must contain printable ASCII characters only.':
        l10n.userAgentAsciiError,
  };
  final translated = translations[message];
  if (translated != null) {
    return translated;
  }

  final httpStatus = RegExp(r'^The server returned HTTP ([1-5][0-9]{2})\.$')
      .firstMatch(message);
  if (httpStatus != null) {
    return l10n.serverHttpError(httpStatus.group(1)!);
  }

  // Startup may combine several independent recovery warnings.
  const startupWarnings = <String>[
    'Network preferences could not be restored.',
    'Pending credential cleanup could not be completed.',
    'Saved accounts could not be read.',
    'The last selected account could not be restored.',
    'Account metadata could not be restored.',
    'Appearance preferences could not be restored.',
    'Language preferences could not be restored.',
    'Download button preference could not be restored.',
    'Copy-link preference could not be restored.',
    'M3U export preference could not be restored.',
    'Download redirect preferences could not be restored.',
    'Download history could not be restored.',
    'Personal library storage could not be opened.',
  ];
  final warnings = <String>[];
  var pending = message;
  while (pending.isNotEmpty) {
    final warning = startupWarnings.where(pending.startsWith).firstOrNull;
    if (warning == null) {
      return message;
    }
    warnings.add(translations[warning]!);
    pending = pending.substring(warning.length);
    if (pending.startsWith(' ')) {
      pending = pending.substring(1);
    } else if (pending.isNotEmpty) {
      return message;
    }
  }
  return warnings.join(' ');
}
