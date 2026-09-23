# SMS/A2P provider comparison

Pricing snapshot as of September 2026, US-only, focused on **toll-free** numbers (the path Rellm is currently on) since that's what avoids 10DLC brand/campaign registration — in theory. "Per-message cost" is the outbound SMS segment rate *plus* the typical carrier passthrough surcharge that every provider bills as a separate line item (AT&T/T-Mobile/Verizon charge this industry-wide; no provider can absorb it). Where a number's exact monthly rental isn't published (enterprise/"contact sales" pricing), that's noted rather than guessed.

## All-in-one comparison

"N msgs/mo" = toll-free number rental + (all-in per-message rate × N), recurring monthly costs only. One-time registration/verification fees are *not* amortized into these columns — see the Fees column and Notes.

| Provider | Toll-free number/mo | Per-message cost (all-in) | Fees | 10 msgs/mo | 100 msgs/mo | 1,000 msgs/mo | 10,000 msgs/mo |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Twilio** | $2.00/mo | ~$0.011 ($0.0083 base + ~$0.003 carrier surcharge) | Toll-Free Verification: free to submit, but slow/opaque review and rejections are common with little support to resolve them | $2.11 | $3.10 | $13.00 | $112.00 |
| **Telnyx** | $1.00/mo | ~$0.007 ($0.004 base + ~$0.003 carrier surcharge, both passed at cost) | TFV: free to submit; API-driven resubmission; real support on rejections | $1.07 | $1.70 | $8.00 | $71.00 |
| **Plivo** | $1.00/mo | ~$0.011 ($0.0077 base + ~$0.0035 carrier surcharge) | TFV: free to submit; 10DLC brand ($4.50)/campaign ($15 + $10/mo) fees are *local-number-only*, not applicable to toll-free | $1.11 | $2.13 | $12.30 | $114.00 |
| **Bandwidth** | *Not published — enterprise/contact-sales* | ~$0.0095 ($0.0065 base + ~$0.003 carrier surcharge) | TFV: free to submit; direct carrier-tier relationship (fewer resellers in the chain) | n/a* | n/a* | n/a* | n/a* |
| **Signal House** | $1.00/mo | ~$0.010 (quoted all-in, $0.008–$0.012 range) | TFV: free to submit; reviewers report 24–48hr turnaround vs. Twilio's multi-day; real support included | $1.10 | $2.00 | $11.00 | $101.00 |
| **Sinch** (SMS API) | $0/mo *(1 TFN included with account)* | ~$0.0115 ($0.0085 base + ~$0.003 carrier surcharge) | TFV: free to submit; carrier fees passed at cost, no markup. *Sinch Engage (higher-level inbox/campaign product) adds a $49+/mo platform fee on top — not needed for plain API use* | $0.12 | $1.15 | $11.50 | $115.00 |
| **Vonage** | *Not published — enterprise/contact-sales* | ~$0.008 ($0.00809 outbound only, inbound $0.00649) | TFV process exists but pricing is discretionary/sales-gated across the board | n/a* | n/a* | n/a* | n/a* |
| **Bird** (formerly MessageBird) | $2.00/mo | ~$0.0075 ($0.0035 base + ~$0.004 carrier surcharge, verified per-carrier on Bird's own fee page) | TFV: free ("free of charge" per Bird's own docs); 10DLC brand ($4.50)/campaign ($15 + $1.50–$30/mo) fees are *local-number-only*, not applicable to toll-free; pure pay-as-you-go, no platform fee | $2.08 | $2.75 | $9.50 | $77.00 |

\* Bandwidth and Vonage don't publish toll-free number rental rates; both require a sales conversation to get a number price, which makes them hard to compare apples-to-apples against the self-serve providers above.

## Notes

- **Toll-free avoids 10DLC brand/campaign registration and its fees ($4.50–$44 one-time brand + $15 one-time + $2–10/mo recurring campaign fee), but doesn't avoid review** — that's the trap: Toll-Free Verification (TFV) is free everywhere, but it's a manual carrier-adjacent review with no SLA, and Twilio in particular has a reputation for rejecting submissions (e.g. on business registration number / EIN mismatches) without giving actionable feedback on how to fix it.
- If a TFV submission is rejected for a missing/invalid business registration number, the fix across all these providers is the same: upload a **CP-575 (EIN confirmation letter)** or **IRS Letter 147C** as proof of EIN. This isn't a provider-specific requirement — it's a carrier/TCR-level requirement that flows through whichever provider you use.
- **Telnyx and Signal House** are the two most commonly recommended migration targets specifically *because* of Twilio TFV pain — both are API-driven for registration and both are reported to have actual humans to talk to when a submission is stuck, unlike Twilio's ticket queue.
- **Sinch and Vonage** are the "enterprise" options in this set — better carrier relationships and support SLAs at volume, but pricing and number provisioning both go through a sales process rather than a self-serve dashboard, which matters less at Rellm's scale.
- 10DLC (local number, not toll-free) is the other path entirely: cheaper per-number ($0.50–$1/mo) and often faster to get approved, but caps daily throughput per campaign far below a verified toll-free number, and carries the brand+campaign fees noted above. Worth considering as a stopgap if toll-free verification keeps stalling, since 10DLC review tends to be faster and more predictable than TFV.

## Caveats

- Carrier surcharges (the ~$0.003–$0.005/message passthrough) fluctuate and vary slightly by destination carrier (AT&T vs. T-Mobile vs. Verizon); the figures above use the commonly-quoted ~$0.003 average. Actual bills will show this as a separate line item, not folded into the base rate.
- These are outbound SMS rates only. MMS, international numbers/messages, two-way conversation pricing, and voice are all priced separately and not reflected here.
- "Per-message cost" assumes single-segment messages (≤160 GSM-7 chars); longer messages split into multiple segments, each billed at the same per-segment rate.
- Signal House and Telnyx figures are sourced from their own marketing/help-center pages, which may understate real-world all-in cost the way independent reviews suggest Twilio's advertised rate does; treat all figures here as directional, not a quote.
