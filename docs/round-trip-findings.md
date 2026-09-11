# Findings from the capture-and-paste prototype

The prototype from ticket 02. Its code was thrown out of `main` and kept apart;
what stays here are the answers it was written to get.

The machine it was checked on: macOS 15.7.7, a 1728×1079 screen,
Karabiner-Elements, Hidden Bar, Raycast.

One boundary applies to every finding below: the super key does not come from a
hardware keyboard. Karabiner maps Caps Lock to `⇧⌃⌥⌘`, so the modifiers are
produced by a virtual device. For this user that is what a normal invocation
looks like, so the sample is representative of the product. But a real chord of
four physically held keys was never tested, and if the trap does exist, that is
where it lives.

## The main question: what to do about held modifiers

**Neither waiting for the keys to be released nor a private event source is
needed.** It is enough to set `flags` explicitly on the `CGEvent` itself.

The plan stated the trap this way: when the shortcut fires all four modifiers
are held, so a synthetic `⌘C` will reach the app as `⇧⌃⌥⌘C` and be ignored. The
first half is true and confirmed by measurement:

```
modifiers when the shortcut fired: cmd+shift+alt+ctrl
```

The second half does not reproduce on macOS 15.7.7. Checked by working through
the strategies, each time with Caps Lock deliberately held for two seconds:

| Wait for release | Event source | Attempts | Succeeded | Clipboard changed, ms |
| --- | --- | --- | --- | --- |
| yes | `privateState` | 25 | 25 | 10–146 |
| no | `privateState` | 2 | 2 | 34, 103 |
| no | `hidSystemState` | 3 | 3 | 22, 23, 46 |

The sample without the wait is small, five attempts against twenty-five. It
cannot be read as proof of a difference in time. It proves something else, and
for that five attempts are enough: **all five succeeded with the modifiers
deliberately held for two seconds.** There was not one failure, and the trap
predicted failure in every case.

In every measurement `flags` were assigned explicitly on both events of the
down-up pair:

```swift
keyDown.flags = .maskCommand
keyUp.flags = .maskCommand
```

The negative case, without the explicit assignment, was not tried, so there are
no grounds for claiming that this line is what cures it. What the data supports
is narrower: on macOS 15.7.7, with flags set explicitly, held modifiers do not
get in the way of synthetic events.

Pasting was checked separately, because its risk profile is different: `⌘V`
goes out after `⏎` has been pressed, and the person may well be holding a
modifier at that moment. Checked with Shift held:

```
modifiers held before pasting: shift
round finished
```

The paste went through. So the finding covers both halves of the round trip
rather than capture alone.

**What this means for ticket 03:** do not wait for a release, on capture or on
paste. It fixes nothing and costs a noticeable delay: 29 measurements gave a
median of 192 ms with a spread from 108 to 1180 ms, because that is the time a
living person takes to lift a finger off a key. A fixed delay in its place is
even less defensible.

Keep `privateState` as the source: there is no difference in behaviour, but it
does not depend on the state of the physical keyboard, and that is cheap
insurance. The waiting code is on the prototype branch if the symptom does turn
up on another machine.

## A failed copy is detected by the clipboard's change count

Fully confirmed. Take `NSPasteboard.general.changeCount` before sending `⌘C`,
then poll until it increments or the wait runs out.

The order of operations matters more than the counter itself: **nothing is
written to the clipboard before a confirmed increment.** So "nothing is
selected" cannot turn into yesterday's clipboard being pasted into somebody
else's app. Checked in Ghostty: the count did not move, the beep sounded, the
panel did not open, and the clipboard was left untouched.

Times to the increment, all 30 from the session, across every app:

```
10 12 22 22 22 22 22 23 23 23 23 23 23 33 34
34 34 44 44 45 46 55 57 61 66 69 77 103 103 146
```

A median of 34 ms and a maximum of 146 ms.

**What this means for ticket 03:** the prototype's timeout was 1000 ms, and
that is far too long. An empty selection beeped only 1.2 seconds after the
shortcut, which reads as "the app did not react". With a maximum of 146 ms, a
sensible starting point is 400 ms.

But that is a direction rather than a finished number. The measurements were
taken on short selections, in a handful of apps, with no load. A large
selection or a stuttering app may well go past 400 ms, and the cost of being
wrong is not symmetrical: too short a timeout will quietly declare "nothing
selected" where there was text. Ticket 03 should settle the value on long texts
and perhaps tell "still waiting" apart from "definitely empty".

A separate case, found in Chrome: the count moved but there was no string in
the clipboard. The selection was not text. Both conditions have to be checked,
the increment and the presence of a non-empty string, or a nil travels onward.

## The panel: two mandatory properties, each found through a bug

At first the panel did not appear on screen at all, even though `isVisible` was
`true`, the coordinates were right, alpha was one, and it was listed among the
windows. It was not in the list of windows for the current space.

There were two causes, and both are mandatory:

1. **`hidesOnDeactivate = false`.** `NSPanel`, unlike `NSWindow`, hides itself
   by default when its app is inactive. An agent app is always inactive, so the
   panel hid itself immediately after being shown.
2. **`.nonactivatingPanel` in the `styleMask`.** This is the shape Spotlight
   and Raycast have: the panel takes keyboard input without the app becoming
   active. Without it, `NSApp.activate(ignoringOtherApps:)` on macOS 15 is
   simply ignored, `NSApp.isActive` stays `false`, and focus never arrives.

They were changed in one edit, so strictly speaking it is not proven that each
is necessary on its own. What is proven is that together they are sufficient,
and that before them neither raising the window level nor
`orderFrontRegardless()` helped.

Show it with `orderFrontRegardless()` rather than `makeKeyAndOrderFront`: from
an inactive app the latter does not bring the window to the current space.

Level `.popUpMenu`. `.floating`, at level three, would sit under the Dock at
twenty and under neighbours such as AlDente at twenty-four.

Dismissal on a click outside the panel is done with a global monitor,
`NSEvent.addGlobalMonitorForEvents`: such a monitor receives only the events
that went past our app, which is exactly the outside clicks.

## Returning focus turned out to be free

That is a direct consequence of `.nonactivatingPanel`: the source app never
stops being frontmost, not for a moment. In all ten measurements returning
focus took 0 ms and was confirmed at once.

Zero milliseconds means the early check, "the app we want is already in front",
fired every time, and the real path with its subscription to
`didActivateApplicationNotification` never ran. By the way it is built, the
panel accidentally removed the very trap the prototype was written for.

So the path was checked on its own: before pasting, focus is deliberately taken
away to Finder, and returning it has to do real work.

```
hook: focus taken to Finder in 15 ms, confirmed=yes
focus returned to Slack: 8 ms, confirmed=yes
```

Four measurements in Slack and Mail: away in 11–18 ms, back in 8–11 ms, the
confirmation arriving as a notification all four times, and the timeout never
firing. **The asynchronous branch works and goes to ticket 03 as proven.**

What follows from this:

- The trap has not disappeared, it has become cheaper. The panel still has to
  be taken away before pasting, or the keystroke goes into it rather than into
  the target app.
- The order is unchanged: take the panel away, confirm the app we want is in
  front, and only then send the paste.
- Keep confirming by observation. In the ordinary case it is free; where focus
  is genuinely lost it costs about 10 ms.

## Secure input: visible in advance, and mandatory to check

Checked on a password field in Safari. The result is unambiguous:

```
secure input: true
waiting for the modifiers to be released: 152 ms, released=yes
the clipboard count did not change in 1000 ms, so nothing was selected
```

- `IsSecureEventInputEnabled()` returns `true`, so the state is visible in
  advance and cheaply.
- The shortcut **still fires**, so the app is alive and can show an error.
- The synthetic `⌘C` is not delivered, silently. The clipboard count does not
  move.

Hence a direct requirement on ticket 03: **check the flag before capturing.**
Without that check, secure input is indistinguishable from an empty selection,
and the person is told "nothing is selected" where text is selected. That is
exactly the silent failure ticket 03 exists to remove.

## The clipboard: copying only the string will not do

Found through a bug on a live clipboard. The prototype at first saved only
`string(forType: .string)`, and a round run on top of a copied screenshot
destroyed the image for good.

A deep copy of every type solves it completely:

```swift
originalItems = (NSPasteboard.general.pasteboardItems ?? []).map { item in
    let copy = NSPasteboardItem()
    for type in item.types {
        if let data = item.data(forType: type) { copy.setData(data, forType: type) }
    }
    return copy
}
```

Checked on a screenshot carrying eight types at once, from `public.png` to TIFF
and BMP. After the round all eight were there, at the same sizes.

One catch: an `NSPasteboardItem` can be handed to the clipboard only once, so a
snapshot is unusable after being restored and has to be taken afresh on every
round.

## Pasting without the clipboard, and why it matters

A second way of pasting was tried: typing the text out as events through
`keyboardSetUnicodeString` instead of `⌘V`. Typing replaces the selection just
as ordinary typing does.

It works. Russian text went through without loss and the selection was
replaced.

The value is not in the paste itself but in what it removes: the only fixed
delay in the whole round. Pasting with `⌘V` means holding the clipboard busy
until the target app has read it, and there is no way to learn when that
happened: in the prototype an invented 300 ms sat there. When the text is typed
out, nobody needs the clipboard after capture and it is restored at once:

```
captured characters: 110
clipboard restored: true
clipboard restored immediately after capture
```

**Recommendation for ticket 03:** make the paste method switchable, with `⌘V`
as the default because it is faster and more predictable, and typing as the
fallback for anyone who cannot accept the clipboard being disturbed.

What was not checked about this method: long texts, how fast it is on them, and
how it behaves in apps other than Slack.

## What was left unchecked

- **Long texts.** Every selection in the session was between 12 and 412
  characters. Neither the clipboard timeout nor the speed of typing was
  measured on paragraphs.
- **Real emoji as characters.** The round with emoji was checked only in Slack,
  which substitutes shortcodes for them, see below. Typing was never checked
  through an app that hands over an emoji as a character.
- **The chord from a hardware keyboard.** See the boundary at the top of this
  document.

## Emoji travel through Slack as shortcodes, not characters

When copying, Slack hands over an emoji as the shortcode `:smile:` rather than
as a character. So the panel shows a shortcode: that is exactly what we were
given. On the way back Slack turns it into a picture again, so an emoji
survives the round.

For ticket 04 this is good news, on balance. The prompt's rule "Don't change
emojis" applies to ordinary text `:smile:`, which a model will not change. But
it is worth knowing: what the person sees as an emoji reaches the model as
text, and apps differ here.

## Where the round was checked end to end

The full round, replacing the selection with upper-case text: **Slack, Google
Chrome, Safari, Notes, Mail, HEY.**

Ghostty was used to check an empty selection, and Safari to check secure input.

## Accessibility access survives a rebuild

The main consequence of ticket 01, checked by experiment rather than theory
alone.

The designated requirement of a signed bundle holds no code hash:

```
designated => identifier "com.badta5te.GrammarFixer"
               and certificate leaf = H"3e7886e138c9c8b2c199f995291946ef4f64bb0d"
```

Access was granted once, and then the sources were changed and the bundle
rebuilt around ten times. The code hash did change,
`0512b39b3a5f17c4f49dddd709e2cca9cac081f0` before and
`e354f3816b1b2a7f1cd9157fbb7c46a45df8c00d` after. There was not one further
prompt, and `AXIsProcessTrusted()` returned `true` immediately after every
restart.

So access is tied to the pair of identifier and certificate rather than to the
hash, and is granted once for the whole of development. The onboarding in
ticket 03 can rely on that.

Carbon's `RegisterEventHotKey` needs no Accessibility access: the shortcut
registered and fired before the permission was granted. The permission is
needed only to send events.

## Conflicts worth remembering

The `⇧⌃⌥⌘G` shortcut was taken by the very Raycast command all this exists to
replace. What was observed: `RegisterEventHotKey` returned `noErr`, and our
shortcut fired. Whether Raycast's command fired as well was not checked; its
shortcut was turned off for the duration of the experiments.

The only thing that follows is that a successful registration does not
guarantee the combination is exclusive, and the return code cannot be relied on
as a conflict detector. The shortcut editor in ticket 09 should take that into
account.

## Where the prototype itself lives

The `spike/round-trip` branch, commits `bff93c7` and `793d4bf`. None of the
prototype's code is in `main`.
