# Rival lab calibration data (2017 to 2026)

Compiled 2026-11-11 to calibrate the rival "boss" labs in AI Lab Tycoon. The tables are sparse on purpose: a missing cell means no public figure was found.

## How to read this

**Label** column:
- **reported**: stated by the company (announcement, filing, earnings call, exec on record) or a primary document such as a tech report.
- **estimate**: produced by an analyst or tracker (Epoch AI, SemiAnalysis, Sensor Tower, QuestMobile, UBS) or derived from public facts.
- **rumor/leak**: anonymous sources, a single unconfirmed outlet, or figures that conflict with other reports.
- **extrapolated**: my own arithmetic from other rows (used rarely and always marked).

**Epoch** means Epoch AI. Model FLOP figures come from Epoch's AI Models database ([hub](https://epoch.ai/data/ai-models), CSV `https://epoch.ai/data/all_ai_models.csv`, downloaded 2026-11-11). Epoch rates each figure Confident, Likely or Speculative, and that rating is shown in brackets. Data-center H100-equivalent (H100e) and power figures come from Epoch's Frontier Data Centers hub ([hub](https://epoch.ai/data/data-centers), CSVs `data_centers.csv` and `data_center_timelines.csv`, downloaded 2026-11-11). Those are satellite and permit-based **estimates**. They cover only about 96 large sites, so they undercount small, leased and overseas capacity.

**Tier** is a game-design capability tier, not an industry standard. It is my own judgement, used only to rank releases:
- T0: research or narrow system (games, protein folding)
- T1: GPT-2 class
- T2: GPT-3 class
- T3: ChatGPT / GPT-3.5 class
- T4: GPT-4 class
- T5: reasoning frontier (2024 to 2025: o1, GPT-5, Claude 4, Gemini 2.5/3, Grok 4)
- T6: 2026 frontier (GPT-6, Claude Mythos/Fable 5, Gemini 4)

Within a year, "frontier" means the best that year. A T4 model released in 2025 is behind the frontier.

**Big caveats before using any number:**
1. Labs almost never disclose GPU counts. Most compute rows are estimates or partner announcements (Amazon, Microsoft, Nvidia), and capacity is often shared or leased between labs. For example, Anthropic has leased SpaceX/xAI's Colossus 1 since May 2026.
2. "Users" metrics differ: ChatGPT reports weekly actives, Gemini and Meta AI report monthly actives, and Meta AI and Grok count people who meet the assistant inside other apps. They are not directly comparable.
3. Revenue is mostly *annualized run-rate* (one month × 12), not recognized revenue. 2026 run-rate reports for OpenAI and Anthropic conflict heavily.
4. Many 2026 items come from secondary coverage. Wherever I couldn't confirm a primary source, I say so.

---

## 1. OpenAI

| Year | Metric | Value | Label | Date of figure | Source |
|---|---|---|---|---|---|
| 2018 | Model | GPT-1, ~1.8e19 FLOP, 8 GPUs (T0/T1) | estimate (Epoch, Likely) | Jun 2018 | [OpenAI blog](https://openai.com/blog/language-unsupervised/), Epoch DB |
| 2019 | Model | GPT-2 1.5B, ~1.9e21 FLOP (T1) | estimate (Epoch, Speculative) | Feb 2019 | [paper](https://cdn.openai.com/better-language-models/language_models_are_unsupervised_multitask_learners.pdf), Epoch DB |
| 2019 | Compute / model | OpenAI Five trained on 1,536 P100 GPUs, 6.7e22 FLOP (T0) | reported (paper) | Dec 2019 | [arXiv 1912.06680](https://arxiv.org/abs/1912.06680) |
| 2020 | Compute | Microsoft-built Azure supercomputer for OpenAI: 10,000 GPUs, 285k CPU cores | reported (Microsoft) | May 2020 | [The Register](https://www.theregister.com/2020/05/20/microsoft_openai_supercomputer/) |
| 2020 | Model | GPT-3 175B, 3.1e23 FLOP, ~10,000 V100 (T2) | estimate (Epoch, Confident) | May 2020 | [arXiv 2005.14165](https://arxiv.org/abs/2005.14165), Epoch DB |
| 2021 | Model | Codex (Jul), DALL-E / CLIP (Jan) | reported | 2021 | [Codex blog](https://openai.com/blog/openai-codex/) |
| 2022 | Model | GPT-3.5 (davinci-002), ~2.6e24 FLOP; ChatGPT launched 30 Nov 2022 (T3) | estimate (Epoch, Speculative) | Mar/Nov 2022 | Epoch DB |
| 2022 | Compute | GPT-4 training cluster ~25,000 A100 (~7.9k H100e, ~21 MW) | estimate (Epoch, Likely; based on leaks) | 2022 | Epoch GPU-clusters data, [Epoch hub](https://epoch.ai/data/ai-models) |
| 2023 | Users | ~100M monthly actives in Jan 2023 (two months after launch) | estimate (UBS / Similarweb, via Reuters) | Jan 2023 | [Engadget summarizing Reuters](https://www.engadget.com/chatgpt-100-million-users-january-130619073.html) |
| 2023 | Model | GPT-4, ~2.1e25 FLOP (T4) | estimate (Epoch, Likely) | Mar 2023 | [arXiv 2303.08774](https://arxiv.org/abs/2303.08774), Epoch DB |
| 2023 | Users | 100M weekly active users | reported (Altman, DevDay) | 6 Nov 2023 | [TechCrunch](https://techcrunch.com/2023/11/06/openais-chatgpt-now-has-100-million-weekly-active-users) |
| 2023 | Revenue | ARR >$2B (FT); The Information says $1.6B for Dec (conflict) | rumor/leak (sources) | Dec 2023 | [Irish Times / FT](https://www.irishtimes.com/business/2024/02/09/openai-on-track-to-hit-2bn-revenue-milestone-as-growth-rockets), [Tekedia](https://www.tekedia.com/chatgpts-openai-hits-2-billion-revenue-milestone/) |
| 2023 | Power | ~0.2 GW of compute | reported (CFO Sarah Friar) | end 2023 | [DCD](https://datacenterdynamics.com/en/news/openai-cfo-says-company-ended-2025-with-19gw-of-compute-scaled-revenue-at-same-speed/), [eWeek](https://www.eweek.com/news/openai-revenue-compute-climbs/) |
| 2024 | Model | GPT-4o (May), o1-preview (Sep), o1 (Dec) (T4 to T5) | reported | 2024 | [GPT-4o](https://openai.com/index/hello-gpt-4o/), [o1-preview](https://openai.com/index/introducing-openai-o1-preview/) |
| 2024 | Compute | Microsoft Goodyear AZ cluster ~100k H100 for OpenAI | estimate (Epoch, Likely) | Oct 2024 | Epoch GPU-clusters data |
| 2024 | Power | ~0.6 GW of compute | reported (Friar) | end 2024 | [DCD](https://datacenterdynamics.com/en/news/openai-cfo-says-company-ended-2025-with-19gw-of-compute-scaled-revenue-at-same-speed/) |
| 2024 | Revenue | ARR ~$5.5B | rumor/leak (Reuters sources) | Dec 2024 | [DealStreetAsia/Reuters](https://media.dealstreetasia.com/stories/openais-annualised-revenue-445200) |
| 2025 | Users | 400M WAU (Feb), 500M (end Mar), ~700M (Aug) | reported | Feb to Aug 2025 | [TechCrunch](https://techcrunch.com/2025/03/06/chatgpt-doubled-its-weekly-active-users-in-under-6-months-thanks-to-new-releases), [TechRepublic](https://www.techrepublic.com/article/news-chatgpt-700-million-weekly-users/) |
| 2025 | Users | 800M WAU | reported (Altman, DevDay) | 6 Oct 2025 | [TechCrunch](https://techcrunch.com/2025/10/06/sam-altman-says-chatgpt-has-hit-800m-weekly-active-users/) |
| 2025 | Revenue | ARR ~$10B | rumor/leak (Reuters sources) | Jun 2025 | [DealStreetAsia/Reuters](https://media.dealstreetasia.com/stories/openais-annualised-revenue-445200) |
| 2025 | Revenue | ARR >$20B (Reuters elsewhere cites $21.4B) | reported (CFO) | end 2025 | [Yahoo/Reuters](https://finance.yahoo.com/news/openai-cfo-says-annualized-revenue-173519097.html) |
| 2025 | Model | GPT-4.5 (Feb), ~3.8e26 FLOP, the largest pre-training run then (T4.5) | estimate (Epoch, Likely) | Feb 2025 | [OpenAI](https://openai.com/index/introducing-gpt-4-5/), Epoch DB |
| 2025 | Model | GPT-5 (Aug), ~6.6e25 FLOP (T5); GPT-5.1 (Nov); GPT-5.2 (Dec) | estimate (Epoch, Speculative) | Aug to Dec 2025 | [GPT-5 system card](https://cdn.openai.com/gpt-5-system-card.pdf), [GPT-5.2](https://openai.com/index/introducing-gpt-5-2/) |
| 2025 | Power | ~1.9 GW of compute | reported (Friar) | end 2025 | [SiliconANGLE](https://siliconangle.com/2026/01/19/openai-reveals-data-center-capacity-tripled-1-9gw-2025/) |
| 2025 | Compute | Epoch-tracked sites with OpenAI as confident/likely user: ~0.9M H100e, ~1.1 GW (~1.2M / 1.5 GW including speculative sites) | estimate (Epoch) | end 2025 | [Epoch data centers](https://epoch.ai/data/data-centers) |
| 2026 | Users | 900M WAU, 50M paid subscribers | reported (secondary coverage) | Feb 2026 | [getpanto](https://www.getpanto.ai/blog/openai-statistics) |
| 2026 | Users | 1B WAU (Aug), 1.2B WAU (2 Nov, consumer lead Adam Fry) | reported | Aug and Nov 2026 | [TNW](https://thenextweb.com/news/chatgpt-1-billion-weekly-active-users-openai-target), [Sacra](https://sacra.com/research/openai) |
| 2026 | Revenue | ARR ~$25B | rumor/leak (The Information) | Feb 2026 | [The Standard HK](https://www.thestandard.com.hk/innovation/article/325931/OpenAI-tops-US25-billion-in-annualized-revenue-The-Information-reports) |
| 2026 | Revenue | Ads business alone ~$1B ARR | reported (OpenAI) | 31 Aug 2026 | [SiliconANGLE](https://siliconangle.com/2026/08/31/openai-says-its-ad-business-has-already-hit-1b-in-annualized-revenue/) |
| 2026 | Revenue | ARR "nears $70B" (single Reuters source; FT questioned it; an Aug Bloomberg comparison put OpenAI ~$40B) | rumor/leak (conflicting) | late Sep 2026 | [KSL/Reuters](https://www.ksl.com/article/51630023/openai-annualized-recurring-revenue-nears-70-billion-source-says), [ROIC/FT doubts](https://www.roic.ai/news/openais-revenue-run-rate-nears-70b-but-ft-report-raises-doubts-on-sustainability-10-08-2026), [Channel Insider](https://www.channelinsider.com/news-and-trends/news-anthropic-revenue-run-rate-outpaces-openai/) |
| 2026 | Model | GPT-5.4 (Mar), GPT-5.5 "Spud" (23 Apr), GPT-5.6 Sol/Terra/Luna (9 Jul) (T5+) | reported | 2026 | [GPT-5.5](https://openai.com/index/introducing-gpt-5-5/), [GPT-5.6](https://openai.com/index/gpt-5-6/) |
| 2026 | Model | GPT-6 Astra (3 Sep), ~9.4e26 FLOP (CI ~5e26 to 2e27), trained on ≥100,000 GB200 at Stargate Abilene (T6) | estimate (Epoch, Likely); hardware count reported by OpenAI/Nvidia per Epoch notes | Sep 2026 | Epoch DB entry "GPT-6 Astra" |
| 2026 | Model | GPT-6 Sol and Luna (22 Sep) | reported | Sep 2026 | [TechCrunch](https://techcrunch.com/2026/09/22/openai-launches-gpt-6-sol-and-luna/) |
| 2026 | Compute / power | Stargate Abilene ~1.02M H100e, ~0.82 GW IT (~1.15 GW total) | estimate (Epoch) | Nov 2026 | [Epoch data centers](https://epoch.ai/data/data-centers) |
| 2026 | Compute / power | All Epoch-tracked sites with OpenAI as confident/likely user: ~2.7M H100e, ~3.1 GW (~3.35M / 3.9 GW including speculative) | estimate (Epoch) | Nov 2026 | [Epoch data centers](https://epoch.ai/data/data-centers) |
| 2026 | Power (contracted) | "Secured" 10 GW of US capacity (contracted, not live) | reported (OpenAI) | 2026 | [DCD](https://www.datacenterdynamics.com/en/news/openai-claims-to-have-secured-10gw-of-ai-infrastructure-capacity-ahead-of-2029-target/) |

---

## 2. Anthropic

Founded 2021. No public products before 2023.

| Year | Metric | Value | Label | Date of figure | Source |
|---|---|---|---|---|---|
| 2023 | Model | Claude 1 (Mar 2023) (T3) | reported | 14 Mar 2023 | [Anthropic](https://www.anthropic.com/index/introducing-claude) |
| 2023 | Model | Claude 2, ~3.9e24 FLOP (T3/T4) | estimate (Epoch, Speculative) | Jul 2023 | [Anthropic](https://www.anthropic.com/index/claude-2), Epoch DB |
| 2024 | Model | Claude 3 family (Mar); Claude 3.5 Sonnet (Jun) ~2.7e25 FLOP (T4) | estimate (Epoch, Speculative) | Mar and Jun 2024 | [Claude 3 model card](https://www-cdn.anthropic.com/de8ba9b01c9ab7cbabf5c33b80b7bbc618857627/Model_Card_Claude_3.pdf), Epoch DB |
| 2024 | Revenue | ARR ~$1B | rumor/leak (Reuters sources) | Dec 2024 | [The Star/Reuters](https://www.thestar.com.my/tech/tech-news/2025/05/31/exclusive-anthropic-hits-3-billion-in-annualized-revenue-on-business-demand-for-ai) |
| 2025 | Model | Claude 3.7 Sonnet (Feb) ~3.4e25 FLOP (T5); Claude 4 (May); Opus 4.1 (Aug); Sonnet 4.5 (Sep); Opus 4.5 (24 Nov) (T5) | estimate (Epoch, Likely) for the FLOP; releases reported | 2025 | [3.7 Sonnet](https://www.anthropic.com/news/claude-3-7-sonnet), [Claude 4](https://www.anthropic.com/news/claude-4), [Opus 4.5](https://www.anthropic.com/news/claude-opus-4-5) |
| 2025 | Revenue | ARR ~$2B (end Mar), ~$3B (May) | rumor/leak (Reuters sources) | Mar to May 2025 | [The Star/Reuters](https://www.thestar.com.my/tech/tech-news/2025/05/31/exclusive-anthropic-hits-3-billion-in-annualized-revenue-on-business-demand-for-ai) |
| 2025 | Revenue | ARR >$5B (Aug), ~$7B (Oct), ~$9B (end 2025) | reported (company statements to Reuters; end-2025 figure from Anthropic's Apr 2026 post) | Aug 2025 to Dec 2025 | [Yahoo/Reuters](https://finance.yahoo.com/news/exclusive-anthropic-aims-nearly-triple-170234463.html), [Anthropic](https://www.anthropic.com/news/google-broadcom-partnership-compute) |
| 2025 | Compute | Project Rainier live: ~500,000 Trainium2 chips; plan for >1M Trainium2 by end 2025 | reported (Amazon) | 29 Oct 2025 | [The Star/Reuters](https://www.thestar.com.my/tech/tech-news/2025/10/29/amazon-launches-ai-infrastructure-project-to-power-anthropic039s-claude-model) |
| 2025 | Compute | Google deal for up to 1M TPUs, "well over a gigawatt" online in 2026 | reported | Oct 2025 | [TechInformed](https://techinformed.com/anthropic-expands-google-deal-for-million-tpu/) |
| 2025 | Compute | Microsoft/Nvidia deal: $30B Azure commitment plus up to 1 GW of Grace Blackwell/Vera Rubin capacity | reported | 18 Nov 2025 | [Constellation Research](https://www.constellationr.com/insights/news/anthropic-microsoft-azure-nvidia-ink-30-billion-compute-pact) |
| 2025 | Compute / power | New Carlisle, IN (Rainier) ~471k H100e, ~0.75 GW | estimate (Epoch) | end 2025 | [Epoch data centers](https://epoch.ai/data/data-centers) |
| 2026 | Revenue | Run-rate >$30B | reported (Anthropic) | Apr 2026 | [Anthropic](https://www.anthropic.com/news/google-broadcom-partnership-compute) |
| 2026 | Revenue | Run-rate ~$47B (Series H) | reported (secondary coverage) | May 2026 | [Lets Data Science](https://letsdatascience.com/news/anthropic-hits-50-billion-annual-revenue-f1e10978) |
| 2026 | Revenue | Run-rate >$65B (investor update) | rumor/leak (Bloomberg and Reuters sources) | end Jul 2026 | [The Star/Reuters](https://www.thestar.com.my/tech/tech-news/2026/08/18/anthropic-revenue-run-rate-tops-65-billion-source-says), [Bloomberg Gov](https://news.bgov.com/financial-accounting/anthropic-revenue-run-rate-surpasses-65-billion-ahead-of-ipo) |
| 2026 | Revenue | Run-rate >$80B (Oct) vs ">$100B" (NYT, 18 Sep). The two conflict. | rumor/leak | Sep to Oct 2026 | [Crypto Briefing](https://cryptobriefing.com/anthropic-revenue-run-rate-80-billion-ipo/), [Enterprise DNA](https://enterprisedna.co/resources/news/anthropic-100-billion-revenue-run-rate-ipo-november-2026) |
| 2026 | Revenue (recognized) | S-1 (filed ~26 Oct 2026): H1 2026 revenue $16.3B vs $1.16B in H1 2025 | reported (S-1, via secondary analysis; not checked on EDGAR) | Oct 2026 | [Luminix](https://www.useluminix.com/reports/company-overviews/anthropic-revenue-and-burn-rate/source/1) |
| 2026 | Users | ~245M monthly users across web and mobile. Anthropic has never published a count, and other trackers say 56M to 271M. | estimate (Sensor Tower, via aggregator; low confidence) | May 2026 | [Panto](https://www.getpanto.ai/blog/anthropic-ai-statistics) |
| 2026 | Compute | Google/Broadcom: ~3.5 GW of next-gen TPU capacity starting 2027 | reported (Anthropic), size via press | 6 Apr 2026 | [Anthropic](https://www.anthropic.com/news/google-broadcom-partnership-compute), [TNW](https://thenextweb.com/news/anthropic-google-broadcom-compute-deal) |
| 2026 | Compute | Leases all of Colossus 1 (300+ MW, >220k Nvidia GPUs) from SpaceX/xAI; expanded to Colossus 2 GB200s on 20 May | reported (xAI/Anthropic); payment terms are rumor | 6 May 2026 | [xAI](https://x.ai/news/anthropic-compute-partnership), [TechRepublic](https://techrepublic.com/article/news-anthropic-spacex-claude-compute-colossus-1) |
| 2026 | Compute / power | Epoch-tracked Anthropic sites: New Carlisle ~818k H100e/1.24 GW + Lake Mariner ~293k/0.25 GW + Colossus 1 ~276k/0.43 GW ≈ **1.4M H100e, ~1.9 GW**, plus an unknown share of Colossus 2 and Google TPUs in Google's own facilities | estimate (Epoch; the sum is mine) | Nov 2026 | [Epoch data centers](https://epoch.ai/data/data-centers) |
| 2026 | Model | Claude Mythos Preview (7 Apr, restricted); Opus 4.7 (16 Apr); Opus 4.8 (28 May) | reported | Apr to May 2026 | [Opus 4.7](https://www.anthropic.com/news/claude-opus-4-7), [Opus 4.8](https://www.anthropic.com/news/claude-opus-4-8) |
| 2026 | Model | Claude Fable 5 + Mythos 5 (9 Jun; new tier above Opus) (T6); Sonnet 5 (30 Jun); Opus 5 (24 Jul); Fable 5.1 (1 Sep); Opus 5.5 (22 Sep); Sonnet 5.5 (28 Sep) | reported | Jun to Sep 2026 | [Fable/Mythos 5](https://www.anthropic.com/news/claude-fable-5-mythos-5), [Opus 5 (SiliconANGLE)](https://siliconangle.com/2026/07/24/anthropic-launches-claude-opus-5-efficiency-safety-improvements/), [Opus 5.5](https://www.anthropic.com/claude-opus-5-5) |
| any | Training FLOP | No Epoch estimate for any Claude model after 3.7 Sonnet | (gap) | | |

---

## 3. Google DeepMind (incl. Google Brain before the 2023 merger)

Google never breaks out DeepMind or Gemini revenue. TPU fleet size is not disclosed, and Google's capacity also serves Search, Cloud customers and Anthropic.

| Year | Metric | Value | Label | Date of figure | Source |
|---|---|---|---|---|---|
| 2017 | Model | Transformer paper (8 P100s, ~7e18 FLOP) (T0) | estimate (Epoch, Confident) | Jun 2017 | [NeurIPS paper](https://proceedings.neurips.cc/paper/2017/file/3f5ee243547dee91fbd053c1c4a845aa-Paper.pdf) |
| 2017 | Model / compute | AlphaGo Zero (Oct, ~6.5e20 FLOP); AlphaZero (Dec, ~5,064 TPUs, ~1.1e20 FLOP) (T0) | estimate (Epoch) | Oct and Dec 2017 | [Nature](https://www.nature.com/articles/nature24270), [arXiv 1712.01815](https://arxiv.org/abs/1712.01815) |
| 2018 | Model | BERT-Large, 64 TPUv2 (T0/T1) | reported (paper) | Oct 2018 | [arXiv 1810.04805](https://arxiv.org/abs/1810.04805) |
| 2019 | Model | AlphaStar, 384 TPUv3, ~1.1e23 FLOP (T0) | estimate (Epoch, Confident) | Oct 2019 | [DeepMind](https://www.deepmind.com/blog/alphastar-grandmaster-level-in-starcraft-ii-using-multi-agent-reinforcement-learning) |
| 2020 | Model | Meena (1,024 TPUv3, 1.1e23); AlphaFold 2 (Nov) (T0/T2) | estimate (Epoch) | 2020 | [arXiv 2001.09977](https://arxiv.org/abs/2001.09977), [Nature](https://www.nature.com/articles/s41586-021-03819-2) |
| 2021 | Model | Gopher 280B, 4,096 TPUv3, ~6.3e23 FLOP (T2) | estimate (Epoch, Confident) | Dec 2021 | [arXiv 2112.11446](https://arxiv.org/abs/2112.11446) |
| 2022 | Model | PaLM 540B, 6,144 TPUv4, ~2.5e24 FLOP (T3); Chinchilla (Mar) | estimate (Epoch, Confident) | Apr 2022 | [arXiv 2204.02311](https://arxiv.org/abs/2204.02311) |
| 2023 | Model | Bard (Mar); PaLM 2 (May) ~7.3e24 FLOP (T3) | estimate (Epoch, Likely) | 2023 | Epoch DB |
| 2023 | Model / compute | Gemini 1.0 Ultra, ~5e25 FLOP, ~57,000 TPUv4 (T4) | estimate (Epoch, Speculative) | Dec 2023 | [Gemini report](https://storage.googleapis.com/deepmind-media/gemini/gemini_1_report.pdf), Epoch DB |
| 2024 | Model | Gemini 1.5 Pro (Feb), Gemini 2.0 (Dec) (T4) | reported | 2024 | [Gemini 1.5 report](https://storage.googleapis.com/deepmind-media/gemini/gemini_v1_5_report.pdf) |
| 2024 | Users | Gemini app ~90M MAU | reported (court documents) | Oct 2024 | [9to5Google](https://9to5google.com/2025/10/29/gemini-app-650-million-users/) |
| 2024 | Compute / power | Google-owned Epoch-tracked sites (all Google uses): ~0.48M H100e, ~1.2 GW | estimate (Epoch) | end 2024 | [Epoch data centers](https://epoch.ai/data/data-centers) |
| 2025 | Users | Gemini app 350M MAU (Mar, court docs), ~450M (Jul), 650M (Oct, Q3 call), 750M (Q4 call) | reported | Mar 2025 to Feb 2026 | [9to5Google](https://9to5google.com/2025/10/29/gemini-app-650-million-users/), [ContentGrip](https://www.contentgrip.com/google-gemini-ai-growth/) |
| 2025 | Model | Gemini 2.5 Pro (Mar) (T5); Gemini 3 Pro + Deep Think (18 Nov) (T5, top of field at launch) | reported | 2025 | [Gemini 2.5](https://blog.google/technology/google-deepmind/gemini-model-thinking-updates-march-2025/), [Gemini 3](https://blog.google/products/gemini/gemini-3/) |
| 2025 | Compute / power | Google-owned Epoch-tracked sites: ~1.7M H100e, ~2.4 GW | estimate (Epoch) | end 2025 | [Epoch data centers](https://epoch.ai/data/data-centers) |
| 2026 | Users | Gemini app 950M MAU (Q2 call, 22 Jul); >1B MAU (11 Aug; "1B+" in Q3 deck) | reported | Jul to Oct 2026 | [TechRepublic](https://www.techrepublic.com/article/news-google-gemini-950-million-monthly-users-alphabet-earnings/), [SiliconANGLE](https://siliconangle.com/2026/08/11/googles-gemini-ai-app-passes-1-billion-monthly-active-users/), [PPC Land](https://ppc.land/gemini-app-gains-350m-users-in-a-year-to-pass-1bn-alphabet-says/) |
| 2026 | Revenue (proxy only) | Google Cloud Q3 2026 revenue $30.7B (+103% y/y), with TPU system sales a "meaningful contributor". Not DeepMind revenue. | reported (earnings) | 28 Oct 2026 | [CRN Asia](https://www.crnasia.com/news-network/2026/google-cloud-sales-explode-103-percent-as-ceo-touts-tpu-extraordinary-demand) |
| 2026 | Capex | Alphabet 2026 capex guidance $195B to $205B; 2027 "significantly" higher | reported (earnings) | Oct 2026 | [Q3 2026 transcript](https://s206.q4cdn.com/479360582/files/doc_events/2026/Oct/28/2026_Q3_Earnings_Transcript.pdf), [Mezha](https://mezha.net/eng/bukvy/9dc288bc_alphabet_raises_2026/) |
| 2026 | Compute / power | Google-owned Epoch-tracked sites: ~3.7M H100e, ~3.9 GW (all Google uses; DeepMind's share unknown) | estimate (Epoch) | Nov 2026 | [Epoch data centers](https://epoch.ai/data/data-centers) |
| 2026 | Model | Gemini 3.1 Pro (Feb); 3.5 Flash (19 May, I/O); 3.6 Flash (21 Jul); 3.5 Pro delayed past June after missing quality bar | reported (delay via Bloomberg) | 2026 | [TechCrunch](https://techcrunch.com/2026/07/21/google-releases-three-new-gemini-models-but-no-3-5-pro/), [eWeek](https://eweek.com/news/google-gemini-3-5-pro-delay) |
| 2026 | Model | Gemini 4 Argon (30 Sep; claims 12 of 18 benchmark wins vs GPT-6 Astra / Opus 5.5) (T6); Gemini 4 Carbon (28 Oct) | reported (benchmarks are Google's own) | Sep to Oct 2026 | [Google blog](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-4-argon/), [Constellation](https://www.constellationr.com/insights/news/google-launches-gemini-4-argon) |
| any | Training FLOP | No public estimate for any Gemini model after 1.0 Ultra | (gap) | | |

---

## 4. Meta (FAIR → GenAI → Meta Superintelligence Labs)

Meta reports no AI-specific revenue: its AI pays off through ads, and Llama was given away.

| Year | Metric | Value | Label | Date of figure | Source |
|---|---|---|---|---|---|
| 2022 | Compute | Research SuperCluster (RSC) ~16,000 A100 at full build-out | reported (Epoch: Confirmed) | 2022 to May 2023 | Epoch GPU-clusters data |
| 2022 | Model | OPT-175B, 1,024 A100, ~4.3e23 FLOP (T2) | estimate (Epoch, Confident) | May 2022 | [arXiv 2205.01068](https://arxiv.org/abs/2205.01068) |
| 2023 | Model | LLaMA-65B (Feb) 5.5e23 on 2,048 A100; Llama 2-70B (Jul) 8.1e23 (T3) | estimate (Epoch, Confident) | 2023 | [arXiv 2302.13971](https://arxiv.org/abs/2302.13971), [Llama 2](https://ai.meta.com/research/publications/llama-2-open-foundation-and-fine-tuned-chat-models/) |
| 2023 | Compute | ~150,000 Nvidia H100s procured in 2023 | estimate (Omdia) | 2023 | [Tom's Hardware](https://www.tomshardware.com/tech-industry/meta-will-have-350000-of-nvidias-fastest-ai-gpus-by-end-of-year-buying-amds-mi300-too) |
| 2024 | Compute | Two 24,576-H100 training clusters | reported (Epoch: Confirmed) | Mar 2024 | Epoch GPU-clusters data |
| 2024 | Compute | ~350,000 H100 / ~600,000 H100-equivalents by end of 2024 | reported (Zuckerberg) | target stated Jan 2024 | [SiliconANGLE](https://siliconangle.com/2024/01/18/meta-plans-buy-350k-nvidia-gpus-build-artificial-general-intelligence/) |
| 2024 | Model | Llama 3 (Apr); Llama 3.1-405B (Jul), 16,384 H100, ~3.8e25 FLOP (T4) | estimate (Epoch, Confident; paper figures) | Jul 2024 | [Llama 3 herd paper](https://ai.meta.com/research/publications/the-llama-3-herd-of-models/) |
| 2024 | Users | Meta AI ~500M MAU | reported | Sep 2024 | [TechCrunch](https://techcrunch.com/2025/05/29/meta-ai-now-has-1b-monthly-active-users/) |
| 2025 | Users | Meta AI 1B MAU across apps | reported (Zuckerberg, shareholder meeting) | 28 May 2025 | [TechCrunch](https://techcrunch.com/2025/05/29/meta-ai-now-has-1b-monthly-active-users/) |
| 2025 | Model | Llama 4 Scout/Maverick (Apr; Maverick ~2.2e24, T4, weak reception); Behemoth preview ~5.2e25, ~32k H100 | estimate (Epoch, Likely) | Apr 2025 | [Meta blog](https://ai.meta.com/blog/llama-4-multimodal-intelligence/), Epoch DB |
| 2025 | Compute / power | Plan: >1.3M GPUs and ~1 GW online by end 2025 | reported (Zuckerberg; plan, not confirmed actual) | Jan 2025 | [DCD](https://datacenterdynamics.com/en/news/meta-plans-60-65bn-capex-on-ai-data-center-boom-will-bring-1gw-of-compute-online-this-year) |
| 2025 | Power | Prometheus (OH) 1 GW for 2026; Hyperion (LA) 2 GW by 2030, scaling to 5 GW | reported (Zuckerberg) | Jul 2025 | [TechRadar](https://www.techradar.com/pro/meta-unveils-new-plans-for-multi-gigawatt-datacenter-clusters-the-size-of-manhattan) |
| 2025 | Capex | $72.2B | reported | FY2025 | [Fintool](https://fintool.com/news/meta-q4-earnings-135-billion-ai-capex) |
| 2025 | Compute / power | Meta-owned Epoch-tracked sites: ~0.54M H100e, ~0.72 GW (Epoch undercounts older general-purpose DCs) | estimate (Epoch) | end 2025 | [Epoch data centers](https://epoch.ai/data/data-centers) |
| 2026 | Capex | 2026 guidance $115B to $135B (Jan), raised to $130B to $145B (Jul) | reported (earnings) | Jan and Jul 2026 | [Fintool](https://fintool.com/news/meta-q4-earnings-135-billion-ai-capex), [Webull](https://www.webull.com/news/15330428912493568) |
| 2026 | Model | Muse Spark (8 Apr): first MSL model and first closed-weights Meta frontier model; AA Intelligence Index 52, top 5 (T5) | reported | Apr 2026 | [Meta](https://ai.meta.com/blog/introducing-muse-spark-msl/), [The Decoder](https://the-decoder.com/metas-muse-spark-is-its-first-frontier-model-and-its-first-without-open-weights/) |
| 2026 | Model | Muse Spark 1.2 (5 Aug), 1.3 (2 Sep), Muse Wonder (12 Oct) | reported | Aug to Oct 2026 | [Muse Wonder](https://research.meta.ai/blog/muse-wonder) |
| 2026 | Users | No new MAU figure. Daily Meta AI users rose ~60% after the Muse Spark rebuild (Q2 call). | reported (qualitative) | 29 Jul 2026 | [Nasdaq](https://www.nasdaq.com/articles/meta-platforms-q2-earnings-call-highlights) |
| 2026 | Compute / power | Meta-owned Epoch-tracked sites: ~2.6M H100e, ~3.1 GW; Prometheus alone ~536k H100e / ~0.6 GW | estimate (Epoch) | Nov 2026 | [Epoch data centers](https://epoch.ai/data/data-centers) |
| any | Training FLOP | No estimate for the Muse models | (gap) | | |

---

## 5. xAI (part of SpaceX since 2 Feb 2026; Epoch calls it "SpaceXAI")

Founded Mar 2023. SpaceX completed its acquisition of xAI on 2 Feb 2026 at a reported $1.25T combined valuation ([Yahoo Finance](https://finance.yahoo.com/news/elon-musk-spacex-officially-acquires-222157679.html)).

| Year | Metric | Value | Label | Date of figure | Source |
|---|---|---|---|---|---|
| 2023 | Model | Grok-1, ~2.9e24 FLOP (T3) | estimate (Epoch, Likely) | Nov 2023 | [xAI](https://x.ai/blog/grok-os), Epoch DB |
| 2024 | Model | Grok-1.5 (Mar, ~9.3e24, Speculative); Grok-2 (Aug), ~3.0e25 FLOP (T4) | estimate (Epoch) | 2024 | [Grok-2](https://x.ai/blog/grok-2), Epoch DB |
| 2024 | Compute / power | Colossus (Memphis): 100,000 H100 online, built in 122 days; ~150 MW | reported (Musk); power is estimate | Sep 2024 | [Tom's Hardware](https://www.tomshardware.com/tech-industry/artificial-intelligence/xai-colossus-supercomputer-with-100k-h100-gpus-comes-online-musk-lays-out-plans-to-double-gpu-count-to-200k-with-50k-h100-and-50k-h200) |
| 2025 | Compute | Colossus ~200k GPUs (Feb); ~230k (150k H100 + 50k H200 + 30k GB200) by mid-2025 | reported (Musk) / estimate (Epoch, secondary) | Feb to Jul 2025 | Epoch GPU-clusters data, [Introl](https://introl.com/blog/xai-memphis-colossus-100000-gpu-supercomputer-infrastructure) |
| 2025 | Model | Grok 3 (Feb), ~3.5e26 FLOP on ~80k H100 (T5); first model Epoch puts above 1e26 | estimate (Epoch, Likely) | Feb 2025 | [xAI](https://x.ai/blog/grok-3), Epoch DB |
| 2025 | Model | Grok 4 (Jul), ~5e26 FLOP, ~246M H100-hours, ~200k GPUs: the largest known training run at the time (T5) | estimate (Epoch, Speculative) | Jul 2025 | [Epoch](https://epoch.ai/data-insights/grok-4-training-resources), [xAI](https://x.ai/news/grok-4) |
| 2025 | Model | Grok 4.1 (17 Nov) | reported | Nov 2025 | [xAI](https://x.ai/news/grok-4-1) |
| 2025 | Users | Grok 64M monthly users | reported (xAI) | Sep 2025 | [Gradually](https://www.gradually.ai/en/grok-statistics/) |
| 2025 | Revenue | ~$3.2B revenue in FY2025 *including X*; $6.4B operating loss | reported (SpaceX S-1) | FY2025 | [TechCrunch](https://techcrunch.com/2026/05/20/xai-burned-6-4b-last-year-spacexs-ipo-filing-shows-why-the-spending-is-far-from-over/) |
| 2025 | Compute | Colossus I + II: ">1 million H100 GPU equivalents" by end 2025 | reported (xAI Series E) | end 2025 (stated 6 Jan 2026) | [xAI](https://x.ai/news/series-e) |
| 2026 | Power | Colossus 2 described as the first gigawatt-scale training cluster; ~555k GB200/GB300 GPUs planned, ~2 GW across the complex | reported (Musk); counts via press | Jan 2026 | [Interesting Engineering](https://interestingengineering.com/ai-robotics/elon-musk-xai-gigawatt-scale-ai-training-cluster), [Introl](https://introl.com/blog/xai-colossus-2-gigawatt-expansion-555k-gpus-january-2026) |
| 2026 | Compute / power | Colossus 2 ~1.11M H100e, ~0.95 GW IT (~1.28 GW total). All SpaceXAI-owned tracked sites ~1.4M H100e / ~1.7 GW, but Colossus 1 is leased to Anthropic and part of Colossus 2 to Anthropic and Cursor. | estimate (Epoch) | Nov 2026 | [Epoch data centers](https://epoch.ai/data/data-centers) |
| 2026 | Users | Grok 117M MAU (of 550M combined X + Grok MAU); ~1.9M paying subscribers | reported (SpaceX S-1, via secondary) | Mar 2026 | [Pulse 2.0](https://pulse2.com/spacex-grok-reaches-117-million-users-as-ai-push-accelerates/amp/) |
| 2026 | Revenue | AI-only ARR ~$500M; target $2B for 2026 | estimate / rumor | Jul 2026 | [StartupHub](https://www.startuphub.ai/news/figure-elon-musk-spacexai-financial-breakdown-2026-07-09) |
| 2026 | Model | Grok 4.20 (17 Feb); Grok 4.5 (8 Jul, ~1.5T-param MoE, co-trained with Cursor); Grok 4.7 (21 Sep) (T5+) | reported (4.5 parameter count via press) | 2026 | [Bloomberg Gov](https://news.bgov.com/artificial-intelligence/spacexai-cursor-unveil-grok-ai-model-for-coding-finance-tasks), [xAI 4.7](https://x.ai/news/grok-4-7) |
| 2026 | Model | Grok 5 in training on Colossus 2 since ~Jan 2026 (rumored ~6T params); not released as of the latest sources found (Aug/Sep 2026); repeatedly delayed | reported (in training) / rumor (specs) | 2026 | [xAI Series E](https://x.ai/news/series-e), [NxCode](https://www.nxcode.io/resources/news/grok-5-release-date-latest-news-2026) |

---

## 6. DeepSeek (chosen over Mistral: better compute and FLOP data; Mistral has better revenue data, see 6b)

A spin-out of the quant fund High-Flyer, founded Jul 2023. No revenue or user data is published.

| Year | Metric | Value | Label | Date of figure | Source |
|---|---|---|---|---|---|
| 2021 | Compute | High-Flyer bought ~10,000 A100s before US export controls | estimate (SemiAnalysis, via press) | 2021 | [Tom's Hardware](https://www.tomshardware.com/tech-industry/artificial-intelligence/deepseek-might-not-be-as-disruptive-as-claimed-firm-reportedly-has-50-000-nvidia-gpus-and-spent-usd1-6-billion-on-buildouts) |
| 2023 | Model | DeepSeek Coder 33B (Nov), ~4e23 FLOP (T2/T3) | estimate (Epoch, Likely) | Nov 2023 | Epoch DB |
| 2024 | Model | DeepSeek LLM 67B (Jan, 8e23); V2 (May, 1e24); V2.5 (Sep, 1.8e24) (T3/T4) | estimate (Epoch, Confident) | 2024 | Epoch DB, [V2.5](https://huggingface.co/deepseek-ai/DeepSeek-V2.5) |
| 2024 | Model / compute | DeepSeek-V3: 2,048 H800, 2.788M H800-hours (~$5.6M at $2/hr, final run only), ~3.3e24 FLOP (T4) | reported (paper); FLOP estimate (Epoch, Confident) | Dec 2024 | [arXiv 2412.19437](https://arxiv.org/abs/2412.19437) |
| 2025 | Compute | ~50,000 Hopper GPUs of access (≈10k H800 + 10k H100 + H20s), ~$1.6B hardware spend, shared with High-Flyer | estimate (SemiAnalysis) | Jan 2025 | [SemiAnalysis](https://newsletter.semianalysis.com/p/deepseek-debates), [Tom's Hardware](https://www.tomshardware.com/tech-industry/artificial-intelligence/deepseek-might-not-be-as-disruptive-as-claimed-firm-reportedly-has-50-000-nvidia-gpus-and-spent-usd1-6-billion-on-buildouts) |
| 2025 | Model | DeepSeek-R1 (20 Jan): open reasoning model built on V3, ~3.3e24 FLOP; topped app stores (T5-lite) | reported; FLOP estimate (Epoch) | Jan 2025 | [DeepSeek](https://api-docs.deepseek.com/news/news250120) |
| 2025 | Users | 22.2M DAU (China, 11 Jan); ~97M MAU global (Apr). Longterm Wiki flags the MAU figure as unverifiable. | estimate (trackers, via aggregators) | Jan and Apr 2025 | [Backlinko](https://backlinko.com/deepseek-stats) |
| 2025 | Model | V3.1 (Aug, 3.6e24); V3.2 (Dec, 4.2e24) (T4/T5) | estimate (Epoch) | 2025 | Epoch DB |
| 2026 | Model | DeepSeek-V4 Pro (1.6T params) + Flash (284B), 24 Apr 2026 (preview); V4-Pro ~9.7e24 FLOP (T5) | reported; FLOP estimate (Epoch, Likely) | Apr 2026 | [Tech report](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro/blob/main/DeepSeek_V4.pdf), [The Register](https://www.theregister.com/2026/04/24/deepseek_v4/) |
| 2026 | Compute | V4 hardware disputed: Nvidia for pre-training, plus Huawei Ascend for RL/inference; delay blamed on the Ascend migration and compute shortage | rumor/leak (conflicting reports) | 2026 | [ChinaTalk](https://www.chinatalk.media/p/deepseek-v4), [The Register](https://www.theregister.com/2026/04/24/deepseek_v4/) |
| 2026 | Users | DeepSeek app 129M MAU in China (3rd after Doubao and Qwen) | estimate (QuestMobile, via aggregator) | Jun 2026 | [Gradually](https://www.gradually.ai/en/deepseek-statistics/) |
| 2026 | Model | V4.1 Flash (9 Sep), ~4.3e24 FLOP | estimate (Epoch, Likely) | Sep 2026 | [Tech report](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash/blob/main/DeepSeek_V41_Tech_Report.pdf) |
| any | Revenue / power | Not public | (gap) | | |

### 6b. Mistral (backup "small lab" data)

| Year | Metric | Value | Label | Date | Source |
|---|---|---|---|---|---|
| 2023 | Model | Mixtral 8x7B, ~7.7e23 FLOP (T3) | estimate (Epoch, Speculative) | Dec 2023 | [Mistral](https://mistral.ai/news/mixtral-of-experts/) |
| 2026 | Revenue | ARR >$400M (Mensch to FT); company target >$1B by end 2026 | reported | Feb 2026 | [Sacra](https://sacra.com/research/mistral), [HL](https://www.hl.co.uk/shares/stock-market-news/company--news/mistral-invests-in-swedish-infrastructure-as-annual-revenues-top-$400m) |
| 2026 | Compute / power | Own data center at Bruyères-le-Châtel: 13,800 GB300, 44 MW, $830M debt-financed; 200 MW in Europe planned by end 2027 | reported | Mar 2026 | [TNW](https://thenextweb.com/news/mistral-ai-830m-debt-data-centre-paris) |
| 2026 | Model | Mistral Large 4 (6 Oct): 3,840 GB200, 45 days, ~1.24e25 FLOP (T4/T5) | reported (tech report); FLOP estimate (Epoch, Confident) | Oct 2026 | [Mistral](https://mistral.ai/news/mistral-large-4/) |

---

## Calibration notes

### Order-of-magnitude ladder (what actually happened)

| Rung | GPUs (H100e) | Power | Real-world anchor |
|---|---|---|---|
| 0 | 1 GPU | ~0.7 kW | the player's start |
| 1 | 8 | ~10 kW (one server) | Transformer paper, 2017 (8 P100) |
| 2 | ~10² to 10³ | ~0.1 to 1 MW | AlphaStar 384 TPUs (2019), OpenAI Five 1,536 GPUs (2019), V3's 2,048 H800 (2024) |
| 3 | ~10⁴ | ~10 to 20 MW | GPT-3 on 10k V100 (2020), GPT-4 on ~25k A100 (2022), Llama 3.1 on 16k H100 (2024), Mistral 2026 |
| 4 | ~10⁵ | ~150 MW | xAI Colossus 100k H100 (Sep 2024), Meta/OpenAI 100k clusters (late 2024) |
| 5 | ~10⁶ | ~1 to 1.5 GW | xAI ">1M H100e" (end 2025); OpenAI 1.9 GW (end 2025); Abilene / Colossus 2 / New Carlisle single sites (2026) |
| 6 | ~3×10⁶ | ~3 to 4 GW | Each of OpenAI, Anthropic, Google, Meta in Nov 2026 (Epoch-tracked) |
| 7 | ~10⁷ | ~10 GW | OpenAI's "secured" 10 GW, Meta Hyperion 5 GW, Alphabet 2027 capex: contracted, not live (2027 to 2029) |

That is about 6.5 orders of magnitude from 1 GPU to a 2026 frontier lab.

Growth rates useful for boss curves:
- OpenAI power roughly tripled each year: 0.2 GW (2023), 0.6 GW (2024), 1.9 GW (2025).
- Epoch's long-run trend is frontier *training compute* growing ~4 to 5× per year.

**Flagship training FLOP ladder:**
- GPT-1: 1.8e19 (2018)
- GPT-2: 1.9e21 (2019)
- GPT-3: 3e23 (2020)
- PaLM: 2.5e24 (2022)
- GPT-4: 2e25 (2023)
- Gemini 1.0 Ultra: 5e25 (2023)
- Grok 3: 3.5e26 (2025)
- Grok 4: 5e26 (2025)
- GPT-6 Astra: ~9e26 (2026, estimate)

That is roughly 10²⁷ / 10¹⁹ = 8 orders of magnitude in 8 years. Efficiency outliers are a nice "underdog" mechanic: DeepSeek V3/R1 reached near-frontier quality at ~3e24 (2025), and V4 at ~1e25 (2026).

**Revenue (ARR) ladder:**
- OpenAI: ~$2B (end 2023), $5.5B (end 2024), $20B (end 2025), $25B (Feb 2026), then disputed $40B to $70B (H2 2026). That is about 3 to 4× per year.
- Anthropic: ~$1B (end 2024), $9B (end 2025), $30B (Apr 2026), $65B (Jul 2026), then $80B+ rumored. That is ~9× in 2025 and ~7× in the first 7 months of 2026, the steepest curve in the set.
- Mistral: ~$0.4B (2026), a good "mid-tier boss".
- xAI: AI-only ~$0.5B.

**Users ladder:**
- ChatGPT: 100M MAU (Jan 2023), 100M WAU (Nov 2023), 400M (Feb 2025), 800M (Oct 2025), 1.2B WAU (Nov 2026)
- Gemini: 90M MAU (Oct 2024), 1B+ (Aug 2026)
- Meta AI: 1B MAU (May 2025), but distribution-driven
- Grok: 117M (Mar 2026)
- DeepSeek: ~130M MAU in China (2026)
- Claude: ~250M estimated, the weakest consumer number in the set

### Suggested game-milestone anchors (design suggestion, not data)

1. **Garage (1 to 8 GPUs, 2017):** "Attention Is All You Need" era. Unlock: first Transformer.
2. **Research lab (~1k GPUs, ~1 MW, 2019):** OpenAI Five / AlphaStar class. Unlock: game-playing agents, GPT-2-class model (T1).
3. **First big cluster (~10k GPUs, ~10 MW, 2020):** GPT-3 (3e23 FLOP, T2). Bosses: early OpenAI, Google Brain.
4. **Chatbot launch (~25k GPUs, ~20 MW, 2022 to 2023):** ChatGPT moment. Unlock the Users stat, with 100M MAU as the "viral" milestone. ARR jumps from ~0 to ~$1 to 2B.
5. **100k cluster (~150 MW, 2024):** Colossus moment, the "built in 122 days" boss gimmick. GPT-4-class (2e25) is the entry ticket. ARR ~$1 to 5B.
6. **Gigawatt lab (~1M H100e, ~1 to 2 GW, 2025):** reasoning-model era (T5), training runs of 3 to 5e26. ARR ~$10 to 20B, 500M to 800M weekly users.
7. **Multi-gigawatt (~3M H100e, ~3 to 4 GW, 2026):** T6 frontier (GPT-6 / Mythos / Gemini 4), ~1e27 runs. ARR $50 to 80B+, 1B+ users. All four US majors sit within ~1.5× of each other here, which is good for a close end-game race.
8. **10 GW / 10⁷ GPUs (2027 to 2029, contracted not built):** post-2026 speculative end-game. A natural spot for "fictional" content such as orbital datacenters, which SpaceX/xAI and Anthropic are publicly discussing.

### Boss personality hints from the data

- **OpenAI parody:** largest consumer user base, fastest compute ramp, huge contracted capacity. Disputed revenue suggests a "hype" stat.
- **Anthropic parody:** few consumers, explosive enterprise revenue, rents compute from everyone (Amazon, Google, Microsoft and even its rival xAI). A "compute-borrower" mechanic.
- **Google DeepMind parody:** most owned compute (TPUs) and the deepest history (2017 to 2022 dominance), but slower to ship (3.5 Pro delays). Monetizes through its cloud.
- **Meta parody:** massive owned capex, gave models away (open-weights phase), then pivoted to closed Muse in 2026. Users are "free" through existing apps.
- **xAI parody:** fastest builder (122 days), biggest single-run FLOP in 2025, low revenue, missed launch dates (Grok 5). Later absorbed by a rocket company and leases its cluster to a rival.
- **DeepSeek parody:** 10 to 50× less compute but efficient (V3 trained for ~$5.6M in the final run). Export-control constraints make a good "sanctions" event.

### Biggest data gaps

- Exact GPU or TPU counts for any lab, and especially anything for Google DeepMind's share of Google's fleet.
- Training FLOP for nearly all 2025 to 2026 flagships: Claude 4 and later, Gemini 2.5 and later, Muse, Grok 4.x and 5, and all GPT-5.x except the Epoch GPT-5 / GPT-6 Astra estimates.
- Revenue for Google DeepMind, Meta and DeepSeek (not reported). xAI's AI-only revenue is unclear because X is bundled in.
- Claude consumer user counts (never published).
- The pre-2022 power draw of any lab.
- OpenAI and Anthropic H2 2026 run-rates, where reports conflict by up to 2×.
