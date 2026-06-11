# Known Issues

## Pinned Chrome windows can flicker when focus moves away

Status: root cause identified from `~/Library/Logs/WinPin/app.log`.

Observed with commit `4043873` plus the current uncommitted changes.

High-reproduction steps:

1. Open three Google Chrome windows.
2. Pin two of those Chrome windows with WinPin.
3. Focus the third, unpinned Chrome window.
4. Switch to another app, reproduced with Zed.

Observed behavior:

- The two pinned Chrome windows can visibly flicker.
- The flicker was observed at the yellow border between the two pinned windows when they occupied the left and right halves of the screen.
- The flicker appears after switching to another app.

Pinned windows in the reproduced case:

- `title="$title1 - Google Chrome - $username"`
- `title="$title2 - Google Chrome - $username"`

Log evidence:

- Chrome process PID was `31709`.
- Zed process PID was `14007`.
- While Chrome was frontmost, both pinned Chrome windows were skipped with `pin_raise_skipped reason=frontmost_application`.
- After switching to Zed, WinPin repeatedly raised both pinned Chrome windows with `AXRaise`.
- The repeated maintenance sequence was:
  1. Raise the Airbnb Chrome window.
  2. Raise the BI Dashboard Chrome window.
  3. Repeat on the next maintenance tick.
- The sampled log contained `1188` maintenance raise attempts and `1188` maintenance raise successes.
- Each of the two pinned Chrome windows had `594` maintenance raise attempts.

Root cause:

- WinPin does not have a public macOS always-on-top API for existing windows owned by another app.
- To approximate pinning, WinPin periodically calls `AXRaise`.
- With multiple pinned windows, the current maintenance loop raises more than one pinned window in sequence.
- When another app is frontmost, this creates repeated foreground-order churn between the pinned windows.
- In the reproduced left/right Chrome layout, the churn is visible as flicker at the shared border.

Concerns:

- Detailed success logs in a 0.10 second maintenance loop can grow `app.log` quickly.
- Repeated successful `AXRaise` calls can waste CPU and window-server work.
- Repeatedly raising multiple pinned windows can cause visible foreground-order flicker.

Implemented mitigation:

- Do not keep high-frequency success logging enabled during normal use.
- Avoid raising every pinned window on every maintenance tick.
- Use a stateful maintenance loop that backs off after three repeated identical successful multi-window raise sequences.
- Resume the backoff after a meaningful trigger such as frontmost-app change, pin order change, new pin, unpin, window snapshot change, refresh failure, or raise failure.
- Consider limiting maintenance raising to a single effective top pinned window if multiple pinned windows cannot be kept stable without churn.

Remaining possible mitigation:

- Add log rotation or a size cap for `~/Library/Logs/WinPin/app.log`.
