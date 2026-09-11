# GrammarFixer

A native replacement for Raycast's "Fix Spelling and Grammar" command. Select
some text, press `⇧⌃⌥⌘G`, read the corrected version and put it back. The
provider and the model are yours to choose, and what you spend is counted on
your own machine.

The whole round trip works today: the shortcut takes your selection, sends it
to a model and shows the corrected text in a panel. From there `⏎` pastes it
back, `⌘⏎` puts it in the clipboard and `Esc` closes without doing anything.
The provider, model, key, prompt and theme are changed in a settings window and
take effect from the very next press of the shortcut. Every round is counted,
and the menu says what the month has cost so far.

The prototype findings the round trip rests on are in
[docs/round-trip-findings.md](docs/round-trip-findings.md).

## How it works

Select text in any app and press the shortcut. The app sends a synthetic `⌘C`,
waits for a confirmed change to the clipboard, and sends the text to a model.
The answer appears in the panel, and `⏎` puts it back where it came from with a
synthetic `⌘V`. The clipboard is restored afterwards with every type it held.

There is not one silent failure left. Nothing selected, or a selection that did
not arrive as text: a beep, and nothing more. A window would explain to someone
what they can already see, and cost them an action to dismiss. Accessibility
access revoked: the access screen again. Secure input on, meaning a password
field is active somewhere: a message that says so. Focus that never came back
to the source app: no paste at all, so the text cannot land in a stranger's
window. No answer from the model, a refused key, a dropped connection: the
reason is written in the panel, and `⏎` sends the request again. A round
already running: the same beep, because a round with a model takes seconds and
silence in reply reads as a broken app.

## The result panel

The panel appears in the middle of whichever screen the cursor is on, and shows
the answer as it arrives. Until the first piece lands it shows that it is
waiting: a round with a model takes seconds, and an empty window for all that
time reads as a breakage.

- `⏎` pastes the result back where the text came from.
- `⌘⏎` puts the result in the clipboard and pastes nothing. What was in the
  clipboard before is not put back: taking the clipboard over is the whole of
  what was asked for.
- `Esc` closes the panel having pasted nothing. The clipboard goes back to what
  it was, but only if nobody touched it while the panel stood open: somebody's
  own fresh copy is worth more than our snapshot.

The text shown is the text as it arrives; the text pasted is the one that came
whole and was cleaned up. The difference is rarely visible, because a preamble
or a pair of quotes can only be recognised in a finished answer.

Closing the panel also stops the request. An answer nobody will read is still
paid for.

The footer names the model and counts characters, words and changes.

### What the model changed

Once the whole answer has arrived, the words the model touched are tinted green,
the way a diff has always shown what was added, and the footer says how many
places it touched. A text it left alone is shown plain,
with "no changes" in the footer, which is the answer somebody checking their own
writing wants to see.

The comparison is by whole words rather than by characters. Fixing grammar
mostly means adding a comma or a letter, and a character comparison tints the
comma alone: a mark floating between two untouched words tells nobody anything,
while "Привет," tinted whole reads at a glance. Words next to each other that
both changed are tinted as one stretch, and a word the model removed leaves its
mark on the gap where it stood — or on the surviving word beside the hole, when
the removal was at the very start or the very end and there is no gap there at
all. The number in the footer always has something on screen behind it.

Highlighting waits for the whole answer on purpose. A half-arrived answer has
nothing to compare against — the words still to come would look like words the
model deleted — so the text streams plain and the tinting appears once.

The tinting is for looking at. What `⏎` pastes and what `⌘⏎` copies is the
answer itself, with nothing of the highlighting in it.

Above the answer, and only when the month is worth mentioning, a line says
where the spending stands. It appears at eighty per cent of the monthly limit
and again past it, and it never stands in the way: the correction below it is
finished and `⏎` still pastes it.

## Provider and key

The `Settings…` menu item opens the settings window. The provider is picked
from a list, the model is typed in, and the key is pasted into a field and goes
to the Keychain. Everything applies the moment it is changed: the next press of
the shortcut already goes to the new provider, with nothing to restart. There
is deliberately no Save button, or there would be a second, half-applied state
to reason about, and the button that checks the key would not know which of the
two it was checking.

The presets are OpenAI, Anthropic, DeepSeek, OpenRouter, Groq, and an entry for
your own OpenAI-compatible address, which covers everything else: another
provider, or a model running on this very machine. A preset supplies the
address and the adapter. The model field stays free to type in: providers
rename models far more often than this app is released.

The key and the model name are kept separately for each provider. A week on
DeepSeek should not cost you your OpenAI key, and a model name belongs to the
provider it was typed for: `claude-haiku` sent to DeepSeek is refused, and the
refusal blames the key rather than the model, so you would go and fix the wrong
thing.

Keys live in the Keychain, one `generic password` entry per provider, under the
service `com.badta5te.GrammarFixer`. There is no key in
`defaults read com.badta5te.GrammarFixer`, and there never will be.

The key field sits above the model field, because the list of models cannot be
loaded without a key. The `Check` button follows the same order: while no model
has been chosen it proves the key by asking for the list of models, which is an
authenticated request like any other, and hands the list straight to the menu
beside the field. Once a model is chosen it sends a short correction instead,
cut off at the first piece of the answer so the rest is never paid for. It
answers either "the key works" or with the provider's own refusal: a wrong key
and a wrong model name look different and are fixed differently.

The app knows no model names and wants to know none. Any list written into it
goes stale the day a provider renames something, and keeping it current by hand
would fall to exactly the person who started all this to avoid such work. The
button beside the field asks the provider, with the key already entered, sorts
the newest first, cuts the list to fifty and drops the models that plainly
cannot write text: transcription, speech, images, embeddings. The field stays
free to type in, so a mistake in that filter breaks nothing.

An answer cut off part way through counts as a refusal, not as an answer. With
Anthropic the ceiling on the answer is set by this app, with everyone else by
the provider, but the outcome is the same: half a correction pasted over a
selection would eat the tail of somebody's own text. So `stop_reason:
max_tokens` and `finish_reason: length` raise an error, and the selection is
left alone.

There are two adapters and no need for a third. The OpenAI-compatible
`/chat/completions` covers OpenAI, DeepSeek, OpenRouter, Groq and local
servers. Anthropic has its own `/v1/messages`: the key goes in a header of its
own, a ceiling on the answer is mandatory and is worked out from the length of
the request, and token usage arrives in two events, how much was read at the
start and how much written at the end. Both numbers are added up and handed
over at once, or the spending counter would get only the last one and the
amount read would be zeroed.

Not every OpenAI-compatible server understands the optional fields of the
request, and some refuse the whole call over one of them. The app survives that
by itself, retrying without them. Anthropic gets no retry: there is nothing to
drop, because the ceiling on the answer is mandatory.

The environment variables `GRAMMARFIXER_API_KEY`, `GRAMMARFIXER_MODEL`,
`GRAMMARFIXER_BASE_URL` and `GRAMMARFIXER_PROVIDER` still override everything
else, which is handy when launching from a terminal. A field that has been
overridden is shown disabled, with a note naming the variable that took it
over: a window showing one thing while requests go out with another is worse
than no window at all.

The file `~/.config/grammar-fixer/config.json` from ticket 04 is no longer read
on every round. On the first launch after that its contents are carried over
into the settings and the Keychain, once, and a line about it appears in the
log. The file itself is neither changed nor removed: it holds somebody's key,
and this app has no business with it.

The prompt is kept whole and ends with the anchor `Rewritten text:`. The anchor
does real work: it suppresses "Here is the corrected text:" in weaker models.
Whatever a model adds beyond the text anyway, a preamble, quotes, code fences,
is stripped when the answer is parsed, but only if it was not in the original.

The prompt is edited in the settings, and a button brings the original back.
`{selection}` is replaced with the selected text. A template that has lost that
placeholder would send the model a request with no text in it at all, and the
answer to that would take the place of somebody's selection, so such a template
is not used: the original stands in, and the window says so while it is being
typed. Going back to the original does not store a copy of it but forgets the
setting, so an improved prompt in a later version reaches everybody who never
changed theirs.

The Keychain entry is created and read by the app itself, so a release signed
with a stable certificate is never asked about it. During development the
password prompt does appear: a self-signed certificate is untrusted, the system
cannot check the signature against a chain and remembers the exact binary
instead, and every rebuild produces a new one. To stop it, mark the
`GrammarFixer Dev` certificate as Always Trust for Code Signing in Keychain
Access, once.

## Permissions

The app needs Accessibility access, and it needs it in order to send events
rather than to read anything. The shortcut registers and fires without it, but
`⌘C` and `⌘V` are not delivered.

The access screen appears on the first launch and from the `Accessibility
Access…` menu item. Access is checked before every round, so a revocation is
noticed at once and needs no restart.

## Settings

The window opens from the `Settings…` menu item. The theme, light, dark or
whatever the system is doing, applies to windows that are already open,
because it is set on the application rather than on each window. The theme is a
setting rather than decoration: this app's windows appear over other people's
and stay for seconds, and a permanently light panel over a dark editor is hard
on the eyes.

Two of the paste switches are repeated in the menu, because reaching them
without opening a window is sometimes easier. The same things can be switched
from a terminal:

```
defaults write com.badta5te.GrammarFixer RestoreClipboardAfterPaste -bool false
defaults write com.badta5te.GrammarFixer PasteMethod typing
defaults write com.badta5te.GrammarFixer WriteLog -bool false
defaults write com.badta5te.GrammarFixer Theme dark
defaults write com.badta5te.GrammarFixer Provider anthropic
defaults write com.badta5te.GrammarFixer Model.anthropic claude-haiku-4-5-20251001
defaults write com.badta5te.GrammarFixer MonthlyLimit -float 5
```

- `RestoreClipboardAfterPaste` — whether to put the clipboard back after
  pasting. Restoring is never complete: promised and lazy clipboard types
  cannot be deep-copied, because they hold no data yet. The switch exists for
  anybody who finds that unacceptable.
- `PasteMethod` — `clipboard` pastes with `⌘V`, `typing` types the text out as
  events and never touches the clipboard.
- `WriteLog` — the round's log in `~/Library/Logs/GrammarFixer.log`. What was
  selected never reaches it, only how long it was.
- `Theme` — `system`, `light` or `dark`.
- `MonthlyLimit` — dollars a month before the app starts saying so. Zero means
  no limit. `Prices` holds only the price rows that were typed by hand, and is
  easier to change in the window than as encoded data.
- `Provider`, `Model.<provider>`, `BaseURL`, `RequestUsage`, `Reasoning` — the
  same things as in the window. There is no key among them: it is in the
  Keychain.

## Spending

Every round is recorded: which provider, which model, how many tokens in and
out. The menu carries the month's total and the limit beside it, and the
settings window holds the limit, the prices and the last few rounds.

The limit is soft, three dollars a month to start with. The correction is
always sent. Past eighty per cent of the limit the result panel says where the
month stands, and past the limit itself the menu bar icon turns red. Zero means
no limit at all.

Every amount is approximate and is shown that way, with the word "about" in
front of it. The prices come from [models.dev](https://models.dev), a published
list, and not from anybody's invoice. The window names the source and says when
it was last fetched, because this is a figure about your own money and you are
entitled to know whose list it rests on.

Tokens are the part that is not guesswork. They come from the provider, so the
menu and the window show them beside the money: rounds, tokens in, tokens out.
When more than one provider was used in a month, each gets a line of its own.
Which of them the money went to is the question behind trying several.

No prices are compiled into the app. A table written into the source is wrong
the moment a provider changes a figure, exactly as a list of model names would
be. The catalogue is fetched at launch, at most once a day, and cached in a
file, so a launch with no network still knows what a round costs. Nothing waits
on it: a correction never holds still for a price list. It is the only request
this app makes that does not go to your own provider, and it carries nothing of
yours: no key, no prompt, not even which model you use.

A price typed in by hand wins over the fetched one, for anybody running a model
on their own machine or paying something other than the list price. Only the
typed rows are stored.

What is stored in the history is tokens, never dollars. Money is worked out on
the way out, from the prices as they stand at that moment, so a price that
arrives later counts the rounds that already went through at that rate. A model
nothing can price is left out of the total and said to be left out, rather than
counted as free: a round nobody has a price for was not free, and counting it
as free is the one answer that is certainly wrong. A pair of zeros in the
catalogue is treated as a gap for the same reason, because several paid models
are listed there at nothing at all.

The month is the calendar one in the local time zone and turns at midnight on
the first. Rounds older than thirteen months are forgotten: the app lives in
the background for months and nobody ever cleans the file up.

Token counts come from the provider. All four presets report them. When one
does not — the request for usage is switched off, or a server refused it and
the round was sent again without it — the tokens are guessed from the text,
that round is marked as an estimate, and the month's total is shown as a floor
rather than a sum. Cyrillic is guessed at a smaller number of characters per
token than Latin, because the common tokenizers split it far more finely.

The history and the fetched prices are files of their own:

```
~/Library/Application Support/GrammarFixer/usage.json
~/Library/Application Support/GrammarFixer/prices.json
```

## Requirements

- macOS 14 or newer
- Swift 6, which ships with the Command Line Tools
- Xcode to run the tests: XCTest is not part of the Command Line Tools

A full Xcode is needed only by the tests. The app builds and runs on the
Command Line Tools alone. There is no need to switch `xcode-select`: `make`
points at Xcode's toolchain through an environment variable when Xcode is
installed.

## Building and running

```
make run      # build, bundle, sign and launch
make bundle   # build the bundle only
make release  # the same in the release configuration
make verify   # show what the bundle is signed with and its entitlements
make test     # run the tests
make clean
```

The finished app is at `build/GrammarFixer.app`.

## Signing

macOS ties granted Accessibility access to the pair of path and signature. With
an ad-hoc signature the code hash changes from build to build, so access has to
be granted again after every build. A permanent self-signed certificate stops
that. It is made once, by hand:

1. Open Keychain Access.
2. Menu `Keychain Access` → `Certificate Assistant` → `Create a Certificate…`
   That is the application menu at the very top of the screen, next to the
   apple.
3. Fill the dialog in:
   - `Name`: `GrammarFixer Dev`
   - `Identity Type`: `Self Signed Root`
   - `Certificate Type`: `Code Signing`
   - leave `Let me override defaults` unchecked
4. `Create`, then `Continue` past the warning about a self-signed certificate,
   then `Done`.
5. Build again with `make run`. The output should end with the line
   `Signed with: GrammarFixer Dev`.

The certificate counts as untrusted, and `security find-identity -v` will not
list it. That is normal and needs nothing done about it as far as signing goes:
local signing needs no trust and `codesign` works with it. Marking it Always
Trust is worth doing only to stop the Keychain asking for a password on every
rebuild, as described above.

Check the result with `make verify`: it should show `Authority=GrammarFixer
Dev` instead of `Signature=adhoc`.

The code hash still changes from build to build, as soon as a source file is
touched. Access survives a rebuild not because of the hash but because the
designated requirement of a signed bundle points at the identifier and the
certificate:

```
designated => identifier "com.badta5te.GrammarFixer"
               and certificate leaf = H"..."
```

Found by experiment; the details are in
[docs/round-trip-findings.md](docs/round-trip-findings.md).

For a different certificate, pass its name through an environment variable:

```
SIGN_IDENTITY="My certificate name" make run
```

Without a certificate the build does not fail. It prints a warning and signs
ad-hoc, which is enough for development, except that access has to be granted
more often.

## How the project is laid out

```
Sources/GrammarFixer/       the entry point, nothing else
Sources/GrammarFixerCore/   all of the app's code
  App/                      the delegate, the menu bar, the round trip
  Hotkey/                   the global shortcut, through Carbon
  TextIO/                   capture, paste, the clipboard, permissions
  LLM/                      the prompt, two provider adapters, parsing answers
  Billing/                  what a round cost, the prices, the month, the limit
  Diff/                     which words the model changed
  Settings/                 settings over UserDefaults, keys in the Keychain
  UI/                       the windows of an agent app
  Support/                  the log
Resources/Info.plist        the bundle description, written by hand, not Xcode
scripts/bundle.sh           assembling the .app and signing it
Tests/                      the tests
docs/                       prototype findings
```

The code is split into an executable target and a library not for elegance: a
module with an entry point cannot be imported from tests, so the executable
target holds nothing but the launch.

The app is marked as an agent in `Info.plist`, so it appears neither in the
Dock nor in the app switcher. App Sandbox is deliberately off: it breaks both
reading selected text in other apps and sending events.
