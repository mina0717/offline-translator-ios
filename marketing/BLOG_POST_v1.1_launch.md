# Why I Spent 6 Months Building a Translator That Doesn't Collect Your Data

*By @mina0717 · 2026-04-21 · Taipei, Taiwan*

I'm writing this from a coffee shop in Taipei at 2 AM. My iPhone battery is at 38%. Airplane mode is on. I'm translating a Japanese menu from last week's trip into Chinese to figure out what I actually ate.

The translation takes 200ms on a 3-year-old iPhone. No network. No data collection. No "we value your privacy" banner. Just the translated words.

This is the simplest thing in the world. It's also almost impossible to find in an App Store.

## The problem

Open the App Store. Search "translator". Every one of the top 10 apps will:

1. Ship your input text to a server (theirs or Google's or DeepL's or Microsoft's).
2. Show you ads, or demand a subscription, or log behavior for "personalization".
3. Bury what actually happens in a 40-page privacy policy.
4. Technically be "compliant" because you tapped "agree" on first launch.

You know what's in your typical translator input? Travel medical phrases. Contract terms. Arguments with your partner. Text messages from your ex. Menus for foods you're embarrassed you don't recognize. Names. Addresses. "How do I say 'I'm lost near the embassy' in Thai?"

That's a lot of your life going through someone else's pipeline.

## What I wanted

A translator that:

- Works on the airplane.
- Never makes a network call for translation.
- Doesn't ship analytics, crash reports, or any events to anyone.
- Has an offline dictionary big enough to cover real language (not just 3000 common words).
- Can translate a photo (because the menu and the sign and the manual and the prescription).
- Can take voice input and give you the result out loud (because your hands are on luggage and your eyes are on traffic).
- Is free and has no ads, because what's the point otherwise.

Nothing like this existed. So I built it.

## What it actually does

**Offline Translator** has four modes:

1. **Text** — type or paste. Live character count (5000 cap). One-tap copy, save, retry.
2. **Voice** — hold to speak. Release to translate. Haptic feedback. On-device speech recognition.
3. **Photo** — point the camera at a sign, menu, receipt, prescription. Vision framework finds text. Apple Translation translates it. You see both.
4. **Dictionary** — 170,000-word offline English-Chinese dictionary with parts of speech, examples, and one-tap save.

In v1.1 I added:

- **Vocabulary Notebook** — a little wordbook that remembers everything you saved, groups by date, exports to CSV.
- **Share Extension** — select text in Safari, share → Offline Translator → translated.
- **Siri Shortcut** — "Hey Siri, translate clipboard."
- **TipKit onboarding** — four gentle tips for first-time users.
- **Dark mode palette** — hand-tuned, not just inverted.

Everything runs on your iPhone. Apple's Translation framework (iOS 17.4+) does the heavy lifting. For users on iOS 17.0-17.3, there's an MLKit fallback.

## The part I'm most proud of

I didn't add analytics.

I didn't add crash reporting.

I didn't add a "sign in" screen.

I didn't add a single third-party SDK that makes network calls.

You can read the source. It's MIT-licensed: https://github.com/mina0717/offline-translator-ios

Search the repo for `URLSession`. You'll find exactly zero results in the translation path. You'll find exactly zero instances of analytics SDK imports. The `PrivacyInfo.xcprivacy` manifest declares an empty array for "collected data types" — not by omission, but because the array is genuinely empty.

If you turn on airplane mode on your iPhone before opening the app, it still works. That's the test.

## What I learned

### 1. Privacy as a constraint is creative, not limiting

I kept running into design decisions where adding analytics would've made a feature "easier to iterate on". I resisted every single one. The result: the UI is simpler than it would have been if I'd been optimizing metrics. I trust my users' taste more than I trust a dashboard.

### 2. Apple's Translation framework is genuinely good

It's not perfect — it's tuned for everyday phrases, not literary translation — but it runs on a 3-year-old iPhone in 200ms and doesn't require a network. That's a massive gift from Apple that not enough indie devs have used yet.

### 3. Shipping alone is faster than you think

6 months from idea to App Store. That includes:
- 50+ tracked tasks (see my progress report in the repo)
- 4 translation modes fully functional
- 170K-word dictionary ingestion pipeline
- Share Extension + Siri integration
- TipKit onboarding
- 5 IG launch cards + multi-platform launch copy
- Privacy policy + landing page + GitHub Pages
- Unit tests + E2E mock mode
- Brand identity (icon, colors, guidelines)

The secret wasn't heroic effort. It was *ruthlessly* saying no to anything that wasn't on the shipping path. No "what if I also added...". No "maybe I should support...". Ship v1.0. Then v1.1. Learn. Iterate.

### 4. Marketing is not optional

I spent almost as much time on the launch assets as on the code in the last 2 weeks. Product Hunt post, IG cards, X thread, Hacker News post, Reddit, LinkedIn, Press Kit — all of it needed to exist before launch day, because on launch day you're answering replies, not writing.

### 5. You can be paranoid about privacy and still have a polished app

People assume privacy-preserving = ugly. Offline Translator has:
- Custom branded app icon
- Hand-tuned dark mode
- Haptic feedback on every interaction
- TipKit onboarding that doesn't feel like onboarding
- Dynamic Type support
- VoiceOver labels

You can care about your users' data *and* your users' eyes.

## What's next

v1.2 ideas I'm noodling on:
- Home Screen Widget (translate clipboard from Home Screen)
- iPad split-view with dual-column translation
- Apple Watch with microphone + live captions
- iCloud Keychain sync for vocabulary notebook
- SharePlay — live bilingual captions in FaceTime calls

If any of these sound interesting to you, tell me which. [@mina0717](https://twitter.com/mina0717).

## If you try it

Offline Translator is free on the App Store (as soon as Apple approves — expected within 72 hours of this post).

- **App Store**: TBD
- **Landing page**: <https://mina0717.github.io/offline-translator-ios/>
- **Source**: <https://github.com/mina0717/offline-translator-ios>

Turn on airplane mode before opening. Translate something. That's the best possible first experience.

---

*If this post resonates, sharing it is the best thanks. I'll be in the replies.*

— @mina0717

<!-- This post is CC-BY 4.0. Quote it, syndicate it, share it. -->
