# Extraction test: 50 real saves → "the thing inside"

2026-11-20. Sample from Ariel's 1,415 saves on the connector: 20 with a transcript (legacy Gemini pass),
15 recent caption-only, 15 older caption-only. Read by hand (Claude, in session); no API calls.
Question: if the back end turned each save into the thing inside it, what would come out, how sure
would we be, and where would it go?

Kinds used: **technique** (how to do something), **resource** (a named tool, repo, paper, list),
**place**, **media** (song/film/book), **nothing** (entertainment, news, opinion, meme),
**teaser** (the content is behind "comment X" / a DM / a signup), **can't tell** (needs the video).

| # | Author | Has transcript | Kind | What's inside | Confidence | Would go to |
|---|---|---|---|---|---|---|
| 1 | dalto.ca | yes | technique | House bass: Diva → stock basses → "MK Bass TriSaw Seq", turn reverb wet down | high | Production notebook |
| 2 | macro_quant_rick | yes | resource | GDELT: free global news-sentiment database, updates every 15 min | high | Quant resources |
| 3 | millee.md | yes | resource | 3 sites/libraries that fix "AI slop" design in Claude Code apps | high (names in full transcript) | Claude tips |
| 4 | matfinog | yes | resource | Paper: "151 Trading Strategies" (2018) | high | Quant reading list |
| 5 | squad.by.triangle | yes (Hebrew) | technique | Vocal chops: Pultec EQ for the highs, Pro-C2 to even dynamics | medium | Production notebook |
| 6 | nugget | yes | resource | Strawberry: "self-driving" browser with AI companions (launch promo) | medium | AI tools |
| 7 | thehoffather (X) | yes | nothing | Political clip | high | dropped |
| 8 | stockmarkethomie | yes | resource | Quantum ETFs list (QTUM, …) | medium | Finance notes |
| 9 | notyourdad.co | yes | technique | Overnight vs intraday returns anomaly (Micron example, a paper is cited) | medium | Quant notes |
| 10 | macro_quant_rick | yes | technique | Grid search over MA lengths for backtests | medium | Quant notes |
| 11 | eyal.gelberg | yes | nothing | Voice-over demo | high | dropped |
| 12 | macro_quant_rick | yes | technique + teaser | "3000 papers tested: MA crossover and absolute momentum hold up"; the strategy itself is behind "comment TF" | medium | Quant notes |
| 13 | maayanloeub | yes | nothing | Political clip | high | dropped |
| 14 | marc.kaz | yes | resource | CuPy: GPU drop-in for NumPy/SciPy | high | Dev tools |
| 15 | josholdmixon | yes | teaser | HFT-on-FPGA course walkthrough; files behind signup | low | dropped |
| 16 | petergriffin.ai | yes | resource | 5 Claude Code plugins for design quality | high (names in full transcript) | Claude tips |
| 17 | macro_quant_rick | yes | technique | Don't use ML in finance before understanding degrees of freedom; a book is recommended | medium | Quant notes |
| 18 | macro_quant_rick | yes | technique | Mean reversion: works on 15 min–1 h with higher-timeframe alignment | medium | Quant notes |
| 19 | edward.builds | yes | nothing | AI video news (faster than real time) | medium | dropped |
| 20 | vince.quant | yes | technique | Almgren–Chriss optimal execution: impact vs timing risk | high | Quant / interview notes |
| 21 | lyricalemonade | no | nothing | Michael Jackson photos | high | dropped |
| 22 | charles.unemployed | no | can't tell | Caption is only hashtags | — | needs video |
| 23 | Vladic_ETH (X) | no | technique | Polymarket "BTC up/down" vs Deribit options: price with N(d2) | high | **pmbot project** (strategy ideas) |
| 24 | ukgdrop | no | nothing | Meme | high | dropped |
| 25 | gannonbreslin | no | technique | Short-form growth playbook ("format arbitrage") | low | needs video |
| 26 | manuel.ermachenko | no | nothing | Chess meme | high | dropped |
| 27 | gregpr07 (X) | no | resource | "The harness used" + a link | low | needs the link opened |
| 28 | amichai.ai | no | teaser | "Comment for the tools list" | high | dropped |
| 29 | solesontech | no | resource | Startups paying higher base than big tech | low | needs video |
| 30 | kaithevibecoder | no | teaser | Ad | medium | dropped |
| 31 | parthknowsai | no | resource | A Google paper on self-updating weights (no title in caption) | low | needs video |
| 32 | cgtwts (X) | no | nothing | Anthropic/OpenAI news meme | high | dropped |
| 33 | loopsy.store | no | nothing | Preset pack promo | medium | dropped |
| 34 | chrislakin (X) | no | can't tell | Link only | — | needs the link opened |
| 35 | chrispathway | no (slides text) | resource | 5 GitHub repos for quant finance (Awesome-Quant, …) | high | Quant resources |
| 36 | hangrybynature | no | place | Little Tokyo, Düsseldorf | high | Places |
| 37 | amir___hetsroni | no | nothing | Opinion post | high | dropped |
| 38 | bluesteel.wav | no | technique | Recreating the "Please Please Please" preset | low | needs video |
| 39 | jadenskyfall | no | nothing | Motivation clip | medium | dropped (or Keep close) |
| 40 | marketrypro | no | resource | Website: sketch → mock-up (name not in the caption) | low | needs video |
| 41 | moonnstones | no | can't tell | Caption is one emoji | — | needs video |
| 42 | bluesteel.wav | no | technique | Omnisphere preset behind a Rich the Kid sound | low | needs video |
| 43 | edward.builds | no | technique | Compare a YouTuber's start date with Google Trends | medium | Creator notes |
| 44 | zanderwhitehurst | no | resource | 3 Figma plugins (propstar, Alphabet profile, …) | high | Design tools |
| 45 | prod.by.iiinfinite | no | can't tell | Q&A prompt | — | needs video |
| 46 | abhi0x01 | no | resource | Reverse-engineering tools: IDA, Ghidra, Binary Ninja, Immunity Debugger, OllyDbg | high | Dev tools |
| 47 | catia_plus | no | nothing | Topology images | medium | dropped |
| 48 | drillbants | no | media | Song: "Je M'appelle" – Benzz | high | Listen later |
| 49 | isaac.horner | no | technique | Pluggnb melodies tutorial with presets | low | needs video |
| 50 | artistconnect.de | no | nothing | Meme | high | dropped |

## Tally
| | With transcript (20) | Caption only (30) |
|---|---|---|
| Something usable, as is | 15 | 7 |
| Something there, but needs the video / link | 0 | 8 |
| Teaser (content is elsewhere) | 1 (+1 partial) | 2 |
| Nothing worth keeping | 4 | 9 |
| Can't tell | 0 | 4 |

## What it says
1. **The transcript decides it.** With a transcript, 15 of 20 gave a usable object. From captions alone, 7 of 30 did, and 12 more need the video before anything can be said.
2. **About a third is "nothing"** (13 of 50) and a few more are teasers. Dropping these automatically removes a large share of the pile.
3. **Ariel's saves are techniques and resources, not recipes and places.** 50 saves: 1 place, 0 recipes, 1 song. The consumer destinations (Groceries, Maps) barely apply here; domain notebooks do: music production, quant, AI/dev tools, design tools.
4. **Lists of named things are the best case** (tools, repos, plugins, papers): easy to extract, easy to check, useful as one line each.
5. **Some saves belong to a live project.** #23 is a strategy idea for the prediction-market bot. Routing to a project is more valuable than any list.
6. **Following links matters** for X: two bookmarks are just a link.
7. Limits of this test: one reader, 50 saves, transcripts read as excerpts; "confidence" is judgment, not measured.
