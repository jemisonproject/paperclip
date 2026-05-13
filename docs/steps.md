The repo has 9 docs total. They serve different audiences and stages. Here's the order:
For a brand-new teammate 

Read in this order:

README.md (1 min) — context, links to everything else
docs/TEAMMATE_ONBOARDING.md (5 min, then 30 min of action) — the master checklist. This is the only doc they MUST start with — it links them to all the others in the right order. Phase 1 is required, Phase 2 is optional.
docs/TAILSCALE_TEAM_SETUP.md — referenced from step 1.1 of onboarding. ~5 min of hands-on work.
docs/MCP_SETUP.md — referenced from step 1.7 of onboarding. ~15 min of hands-on work.
docs/OPENCLAW_SETUP.md (optional — only for Phase 2) — referenced from Phase 2 of onboarding. ~60 min, more advanced.

Read AFTER setup, for daily work:

CLAUDE.md — what each teammate's Claude does at session start
docs/TEAM_WORKFLOW.md — branching, PR conventions, how we use Paperclip day-to-day

Read WHEN debugging (reference, not sequential):

docs/UPSTREAM_BUGS.md — list of known Paperclip / OpenClaw bugs with workarounds; every troubleshooting case links here

For you (Juan / admin only)
You read everything plus two extra:

docs/NAS_DEPLOYMENT.md — how the NAS deploy works, what you do when something breaks
docs/AGENT_TUNING.md — timeout fix, future tuning playbook, credential-rotation list

Teammates don't need 9 or 10.
What to send each teammate in a DM
Literally one paragraph:

"Hey — onboarding to Koiomi's shared Paperclip AI workforce. Start at this single doc, it walks you through everything in order:
https://github.com/jemisonproject/paperclip/blob/main/docs/TEAMMATE_ONBOARDING.md
Required setup is Phase 1 (~30 min). Phase 2 (autonomous agent) is optional. Ping me on Step 1.3 (Tailscale invite) and Step 1.5 (Paperclip join approval) — those two need me on the admin side. Everything else you can do solo."

That's it. The doc handles the rest.
Quick correctness check before you send
Three places in the docs mention JuanPabloDelgado/paperclip or specific Tailscale hostnames. Make sure they all reflect your actual GitHub org (looks like jemisonproject/paperclip now) and tailnet:

README.md — has Tailscale URL placeholder
docs/TEAMMATE_ONBOARDING.md — has <TOKEN> placeholder
docs/MCP_SETUP.md — has <your-tailnet> and <your API key from Juan> placeholders

The placeholders are correct as-is — teammates fill them in. But the GitHub URLs in some doc text might still say JuanPabloDelgado if I missed an update. Worth a quick grep before sending:
powershellcd D:\Proyectos\Koiomi\paperclip
findstr /s /i "JuanPabloDelgado" docs\*.md *.md
If anything matches, swap for jemisonproject (or whatever the company GitHub org is now) and push.
After the push, you're done with docs. The remaining work — running the timeout patch and testing — is the operational task we've been talking about. Go run that, see Claudio actually complete a ticket, and you have your demo for tomorrow today.