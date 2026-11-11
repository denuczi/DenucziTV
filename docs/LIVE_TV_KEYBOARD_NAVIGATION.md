# Live TV keyboard navigation

The player supports channel changes while the video remains open, including
media_kit's separate fullscreen route. Movie and episode playback are unaffected.

## Controls

- `0`–`9`, including the numeric keypad: enter a channel number. Each key resets
  a five-second confirmation delay. `Enter` confirms immediately; `Backspace`
  corrects the pending number and `Escape` cancels it.
- `Arrow Up` or `W`: previous channel. `Arrow Down` or `S`: next channel.
  Navigation wraps at either end of the full provider list. Key repeats are
  ignored to avoid opening several streams from a held key.
- Other player shortcuts are not intercepted. In Live TV only, Up/Down
  replace the media_kit default volume shortcuts; volume remains available
  through the player controls.

Numbers match the stable provider ordering used by the Live TV catalog, **not**
`stream_id` or the current search/category results. The current channel's title
and number are shown at the video region's upper-left corner only after
number/direction input. The notice disappears automatically. Logos have a
high-contrast fallback, and long names are constrained to two lines.

## Architecture and failure behavior

- `LiveChannelDirectory` indexes valid channel numbers and IDs once. Lookup is
  O(1) and directional navigation is O(1) after the initial O(n log n) sort.
- `LiveChannelInputController` owns and cancels its five-second timer.
- `PlayerDialog` reuses one media_kit `Player`. Switching first stops the
  previous source and then opens the new source; it never creates a second
  player. Requests received during an asynchronous open coalesce to the latest
  channel rather than creating concurrent native opens.
- A previously loaded Live TV catalog is reused. When the player opens from
  saved favorites without a loaded catalog, it fetches the list only after the
  player opens, without changing the selected workspace.
- Invalid numbers, catalog failures, unavailable channels and switching errors
  preserve the current dialog and present localized feedback. A failed channel
  load retains the existing retry UI.
- Account/source-scope checks forbid cross-account navigation. Protected-access
  revocation cancels catalog loading, pending input and queued channel changes.
  Closing the dialog cancels timers and disposes the native player.

## QA acceptance criteria

1. From Live TV, select channel 15, enter `2`, then `0`; the overlay shows `20`
   and switches to channel 20 **five seconds after the final keypress**.
2. `Enter` switches immediately, and `Backspace` / `Escape` edit or cancel
   input without reopening streams.
3. `Up/W` and `Down/S` follow the full catalog, including wraparound, while
   remaining within the same player window and fullscreen route.
4. Logo failure, missing artwork, and very long channel titles remain legible.
5. The banner does not appear when opening a channel initially, when retrying,
   or when watching a movie or episode.
6. Very fast changes do not leave two native players running, and the last
   requested channel takes precedence.
7. A missing number leaves the current stream unchanged. Expired protected
   links and account switches cannot open channels from a different source.
8. Opening a live favorite without prior Live TV navigation fetches the catalog
   on demand, without altering the current My Library workspace.

The CI/unit tests cover mapping, bounded input, timers, shortcuts, and overlay.
Real-player behavior, including fullscreen focus and source teardown, still
requires smoke testing with an authorized provider on Linux and Windows.
