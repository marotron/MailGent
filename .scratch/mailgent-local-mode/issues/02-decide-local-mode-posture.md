# Decide Local-Mode Product Posture

Type: grilling
Blocked by: 01
Status: claimed

## Question

After research: keep the proposed **poll → analyze → copy-paste** loop as (a) a temporary bridge until OAuth, (b) a lasting offline/fallback feature, or (c) do not ship?

## Context

The proposed loop reads Apple Mail's `~/Library/Mail` on a cadence, maintains a local message list, and on new `.emlx` reads and analyzes for MailGent search/read. Outbound is copy-paste only (no Mail-store writes). This is a companion posture, not a replacement client.

## Grilling criteria

- Does the read path hold after ticket 01's findings on TCC, format stability, and completeness?
- Is copy-paste a sufficient outbound path for v1 users, or does it break the value proposition?
- Temporary bridge vs lasting fallback: different maintenance cost and UX implications — which fits v1 better?
- Does this require any v1 spec amendments? If so, which sections?
- Are there scenarios where this should simply not ship (risk, effort, poor fit)?

## Inputs

- [01 · Research ArchMail and Apple Mail On-Disk Viability](01-research-archmail-ondisk-viability.md) — must be resolved first.

## Answer

_(to be written after ticket 01 is resolved)_
